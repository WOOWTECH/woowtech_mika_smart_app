import json
import os
import plistlib
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from prepare_live_xctestrun import configure


class LiveRunnerConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.env = {"WOOW_MODEL_TEST_BASE_URL": "https://model.invalid/v1",
                    "WOOW_MODEL_TEST_MODEL": "fixture", "WOOW_MODEL_TEST_API_KEY": "fixture-not-a-key"}

    def test_v2_injects_only_ui_runner(self):
        unit = {"BlueprintName": "AssistantModelsTests"}
        ui = {"BlueprintName": "WoowAssistantUITests", "EnvironmentVariables": {"EXISTING": "keep"}}
        payload = {"TestConfigurations": [{"TestTargets": [unit, ui]}]}
        configure(payload, self.env)
        self.assertNotIn("EnvironmentVariables", unit)
        self.assertEqual(ui["EnvironmentVariables"]["WOOW_LIVE_API_KEY"], "fixture-not-a-key")
        self.assertEqual(ui["EnvironmentVariables"]["EXISTING"], "keep")

    def test_legacy_format(self):
        payload = {"WoowAssistantUITests": {}}
        configure(payload, self.env)
        self.assertEqual(len(payload["WoowAssistantUITests"]["EnvironmentVariables"]), 3)

    def test_clear_removes_only_live_values(self):
        payload = {"WoowAssistantUITests": {"EnvironmentVariables": {"EXISTING": "keep"}}}
        configure(payload, self.env)
        configure(payload, {}, clear=True)
        self.assertEqual(payload["WoowAssistantUITests"]["EnvironmentVariables"], {"EXISTING": "keep"})

    def test_missing_runner_rejected(self):
        with self.assertRaises(ValueError):
            configure({}, self.env)

    def test_mcp_configuration_never_injects_model_key(self):
        payload = {"WoowAssistantUITests": {}}
        configure(payload, {"WOOW_HA_MCP_TEST_URL": "https://mcp.example.invalid/private"}, service="mcp")
        self.assertEqual(payload["WoowAssistantUITests"]["EnvironmentVariables"],
                         {"WOOW_LIVE_MCP_URL": "https://mcp.example.invalid/private"})
        configure(payload, {}, clear=True, service="mcp")
        self.assertEqual(payload["WoowAssistantUITests"]["EnvironmentVariables"], {})

    def test_mcp_secret_is_injected_verbatim_through_plist(self):
        raw = "https://fixture.invalid/mcp/a%2Fb?token=x%2Fy+z&mode=read"
        payload = {"WoowAssistantUITests": {}}
        configure(payload, {"WOOW_HA_MCP_TEST_URL": raw}, service="mcp")
        restored = plistlib.loads(plistlib.dumps(payload))
        self.assertEqual(restored["WoowAssistantUITests"]["EnvironmentVariables"]["WOOW_LIVE_MCP_URL"], raw)

    def test_mcp_serialized_or_repaired_secret_rejected_before_mutation(self):
        raw = "https://fixture.invalid/mcp?token=fixture"
        for malformed in (json.dumps(raw), raw.replace("/", "\\/"), " " + raw, raw + "\\"):
            payload = {"WoowAssistantUITests": {}}
            with self.subTest(kind=len(malformed)):
                with self.assertRaisesRegex(ValueError, "^Invalid private MCP endpoint$"):
                    configure(payload, {"WOOW_HA_MCP_TEST_URL": malformed}, service="mcp")
                self.assertEqual(payload, {"WoowAssistantUITests": {}})

    def test_mcp_cli_writes_private_runner_and_clears_only_endpoint(self):
        raw = "https://fixture.invalid/mcp?token=fixture%2Fvalue&scope=read"
        script = Path(__file__).with_name("prepare_live_xctestrun.py")
        with tempfile.TemporaryDirectory() as directory:
            runner = Path(directory) / "synthetic.xctestrun"
            runner.write_bytes(plistlib.dumps({"WoowAssistantUITests": {
                "EnvironmentVariables": {"EXISTING": "keep"}}}))
            result = subprocess.run([sys.executable, str(script), str(runner), "--service", "mcp"],
                                    env={"WOOW_HA_MCP_TEST_URL": raw}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertNotIn(raw, result.stdout + result.stderr)
            self.assertEqual(stat.S_IMODE(os.stat(runner).st_mode), 0o600)
            variables = plistlib.loads(runner.read_bytes())["WoowAssistantUITests"]["EnvironmentVariables"]
            self.assertEqual(variables, {"EXISTING": "keep", "WOOW_LIVE_MCP_URL": raw})
            result = subprocess.run([sys.executable, str(script), str(runner), "--service", "mcp", "--clear"],
                                    env={}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0)
            self.assertEqual(plistlib.loads(runner.read_bytes())["WoowAssistantUITests"]["EnvironmentVariables"],
                             {"EXISTING": "keep"})

    def test_unknown_service_rejected(self):
        with self.assertRaises(ValueError):
            configure({}, {}, service="unknown")

    def test_combined_services_clear_independently(self):
        payload = {"WoowAssistantUITests": {}}
        configure(payload, self.env)
        configure(payload, {"WOOW_HA_MCP_TEST_URL": "https://mcp.example.invalid/private"}, service="mcp")
        variables = payload["WoowAssistantUITests"]["EnvironmentVariables"]
        self.assertEqual(len(variables), 4)
        configure(payload, {}, clear=True, service="mcp")
        self.assertNotIn("WOOW_LIVE_MCP_URL", variables)
        self.assertEqual(len(variables), 3)
        configure(payload, {}, clear=True)
        self.assertEqual(variables, {})

    def test_duplicate_runner_rejected(self):
        with self.assertRaises(ValueError):
            configure({"TestConfigurations": [{"TestTargets": [
                {"BlueprintName": "WoowAssistantUITests"}, {"BlueprintName": "WoowAssistantUITests"}]}]}, self.env)

    def test_missing_key_is_rejected_before_changes(self):
        payload = {"WoowAssistantUITests": {}}
        with self.assertRaises(ValueError):
            configure(payload, {})
        self.assertEqual(payload, {"WoowAssistantUITests": {}})
