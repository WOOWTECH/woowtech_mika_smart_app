"""The downloadable relay CLI must pass Cloudflare's browser-integrity check."""

import email.message
import importlib.util
import io
import pathlib
import unittest


CLI = pathlib.Path(__file__).resolve().parents[1] / "downloads" / "apporo-relay-cli.py"
SPEC = importlib.util.spec_from_file_location("apporo_relay_cli", CLI)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RelayCliHeadersTest(unittest.TestCase):
    def test_api_request_identifies_the_cli_to_cloudflare(self):
        seen = []

        class Opener:
            def open(self, request, timeout):
                seen.append(request)
                response = io.BytesIO(b'{"api_version":1}')
                response.headers = email.message.Message()
                response.headers["Content-Type"] = "application/json"
                return response

        client = MODULE.Client("https://assistant-relay.apporo.ai/api/v1", "test-token")
        client.opener = Opener()
        self.assertEqual(client.request("GET"), {"api_version": 1})
        self.assertEqual(seen[0].get_header("User-agent"), "apporo-relay-cli/" + MODULE.VERSION)
        self.assertEqual(seen[0].get_header("Authorization"), "Bearer test-token")


if __name__ == "__main__":
    unittest.main()
