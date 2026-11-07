"""WOOWTECH fork: the CLI finds the WOOWTECH build (io.woowtech.agent) over ADB and names it over --url too.
Not part of upstream Mika."""

import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import unittest

from test_mika_cli import DISCOVERY, SCRIPT, TOKEN, api

WOOWTECH = "io.woowtech.agent"
FILES = "/sdcard/Android/data/%s/files/"

FAKE_ADB = r'''
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with open(os.environ["FAKE_ADB_LOG"], "a") as log:
    log.write(json.dumps(args) + "\n")
cfg = json.loads(Path(os.environ["FAKE_ADB_CONFIG"]).read_text())
if args[:1] == ["-s"]:
    args = args[2:]
if args == ["start-server"]:
    pass
elif args == ["devices"]:
    print("List of devices attached\nphone-a\tdevice\n")
elif args == ["get-state"]:
    print("device")
elif args[:3] == ["shell", "pm", "path"]:
    if args[3] not in cfg["installed"]:
        sys.exit(1)
    print("package:/data/app/~~test/" + args[3] + "-1/base.apk")
elif args[:2] == ["shell", "sh"]:
    sys.exit(0 if args[2].startswith(tuple(cfg["readable"])) else 1)
elif args[:2] == ["shell", "cat"]:
    if not args[2].startswith(tuple(cfg["readable"])):
        sys.exit(1)
    print(json.dumps({"api_version": 1, "token": cfg["token"], "port": 8765, "boot": "17"}))
elif args[:3] == ["shell", "settings", "get"]:
    print("17")
elif args[:2] == ["forward", "tcp:0"]:
    print(cfg["local_port"])
elif args[:2] == ["forward", "--remove"]:
    pass
else:
    sys.exit(1)
'''


class WoowtechPackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def adb(self, server, installed, readable):
        config = self.directory / "adb-config.json"
        config.write_text(json.dumps({"installed": installed, "readable": [FILES % p for p in readable],
                                      "token": TOKEN, "local_port": server.server_port}))
        log = self.directory / "adb-log.jsonl"
        log.write_text("")
        if os.name == "nt":
            script = self.directory / "fake_adb.py"
            script.write_text(FAKE_ADB)
            executable = self.directory / "fake-adb.cmd"
            executable.write_text('@"%s" "%s" %%*\r\n' % (sys.executable, script))
        else:
            executable = self.directory / "fake-adb"
            executable.write_text("#!" + sys.executable + "\n" + FAKE_ADB)
            executable.chmod(0o700)
        env = {"FAKE_ADB_CONFIG": str(config), "FAKE_ADB_LOG": str(log)}
        return executable, env, lambda: [json.loads(line) for line in log.read_text().splitlines()]

    def invoke(self, *args, env):
        process_env = {**os.environ, "PYTHONUTF8": "1", **env}
        process_env.pop("ANDROID_SERIAL", None)
        if "MIKA_ANDROID_PACKAGE" not in env:
            process_env.pop("MIKA_ANDROID_PACKAGE", None)
        result = subprocess.run([sys.executable, str(SCRIPT), "--json", *args], text=True, encoding="utf-8",
                                capture_output=True, cwd=self.directory, env=process_env, timeout=15)
        self.assertNotIn(TOKEN, result.stdout + result.stderr)
        return result, json.loads(result.stdout)

    def test_connect_uses_the_woowtech_build_when_installed(self):
        with api() as server:
            adb, env, calls = self.adb(server, installed=[WOOWTECH], readable=[WOOWTECH])
            result, body = self.invoke("connect", "--adb", str(adb), env=env)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn(["-s", "phone-a", "shell", "sh", FILES % WOOWTECH + "connect-computer.sh"], calls())
            self.assertIn(["-s", "phone-a", "shell", "cat", FILES % WOOWTECH + "mcp-usb.json"], calls())

    def test_messages_name_the_woowtech_build(self):
        with api() as server:
            adb, env, _ = self.adb(server, installed=[WOOWTECH], readable=[])
            result, body = self.invoke("doctor", "--adb", str(adb), env=env)
            self.assertEqual("connection_info", body["error"]["code"])
            self.assertIn("open woowtech agent once, then retry connect", body["error"]["message"])
            self.assertNotIn("Mika", body["error"]["message"])

    def test_upstream_build_is_the_fallback(self):
        with api() as server:
            adb, env, calls = self.adb(server, installed=["com.wangzan101.mika"], readable=["com.wangzan101.mika"])
            result, body = self.invoke("doctor", "--adb", str(adb), env=env)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertIn(["-s", "phone-a", "shell", "cat", FILES % "com.wangzan101.mika" + "mcp-usb.json"], calls())

    def test_environment_picks_the_package_without_probing(self):
        with api() as server:
            adb, env, calls = self.adb(server, installed=[WOOWTECH], readable=["com.example.mika"])
            result, body = self.invoke("doctor", "--adb", str(adb), env={**env, "MIKA_ANDROID_PACKAGE": "com.example.mika"})
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertFalse(any(c[2:4] == ["shell", "pm"] for c in calls()))

            result, body = self.invoke("doctor", "--adb", str(adb), env={**env, "MIKA_ANDROID_PACKAGE": "../etc"})
            self.assertEqual("arguments", body["error"]["code"])

    def over_url(self, port, *args, token=TOKEN):
        token_file = self.directory / "token"
        token_file.write_text(token)
        return self.invoke("--url", "http://127.0.0.1:%d" % port, "--token-file", str(token_file), *args, env={})

    def test_url_messages_name_the_woowtech_build_before_the_phone_answers(self):
        # Nothing listens on a port that was just released: the phone never answers, so its version is unknown.
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            closed = probe.getsockname()[1]
        result, body = self.over_url(closed, "doctor")
        self.assertEqual("connection", body["error"]["code"])
        self.assertIn("from woowtech agent", body["error"]["message"])
        self.assertIn("run mika connect", body["error"]["message"])
        self.assertNotIn("Mika", body["error"]["message"])

        result, body = self.over_url(closed, "doctor", token="not a token")
        self.assertEqual("credentials", body["error"]["code"])
        self.assertIn("reconnect to woowtech agent", body["error"]["message"])

    def test_url_names_the_app_by_the_version_it_reports(self):
        for version, name in [("0.1.37-woow.2", "woowtech agent"), ("0.1.37", "Mika")]:
            def respond(method, path, body, version=version):
                if path == "/api/v1":
                    return 200, {**DISCOVERY, "server_version": version}, {}
                return 200, {}, {}  # not a task snapshot
            with self.subTest(version=version), api(respond) as server:
                result, body = self.over_url(server.server_port, "task", "status", "t1")
                self.assertEqual("protocol", body["error"]["code"])
                self.assertEqual(name + " returned an invalid task snapshot.", body["error"]["message"])

    def test_package_adb_does_not_recognize_is_named_by_the_reported_version(self):
        def respond(method, path, body):
            if path == "/api/v1":
                return 200, {**DISCOVERY, "server_version": "0.1.37-woow.2"}, {}
            return 200, {}, {}
        with api(respond) as server:
            adb, env, _ = self.adb(server, installed=[], readable=["com.example.mika"])
            result, body = self.invoke("task", "status", "t1", "--adb", str(adb), env={**env, "MIKA_ANDROID_PACKAGE": "com.example.mika"})
            self.assertEqual("woowtech agent returned an invalid task snapshot.", body["error"]["message"])

    def test_help_names_the_woowtech_build(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--help"], text=True, encoding="utf-8", capture_output=True,
                                cwd=self.directory, env={**os.environ, "PYTHONUTF8": "1"}, timeout=15)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("woowtech agent", result.stdout)


if __name__ == "__main__":
    unittest.main()
