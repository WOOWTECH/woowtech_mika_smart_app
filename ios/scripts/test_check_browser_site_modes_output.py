import subprocess
import sys
import unittest

from check_browser_site_modes_app import parse_run_result


class SiteModesOutputTests(unittest.TestCase):
    def test_json_stdout_and_diagnostics_stderr(self):
        result = subprocess.run(
            [sys.executable, "-c", "import sys; print('{\"assertions\": 1}'); print('BROWSER_WEBSITE_REMOVAL phase=begin', file=sys.stderr)"],
            capture_output=True, check=True,
        )
        self.assertEqual(parse_run_result(result.stdout), {"assertions": 1})
        self.assertIn(b"BROWSER_WEBSITE_REMOVAL", result.stderr)

    def test_extra_stdout_and_non_object_are_rejected(self):
        for output in (b'BROWSER_WEBSITE_REMOVAL phase=begin\n{"assertions":1}\n',
                       b'{"assertions":1}\n{"assertions":2}', b'[]', b'not-json'):
            with self.subTest(output=output), self.assertRaises(ValueError):
                parse_run_result(output)


if __name__ == "__main__":
    unittest.main()
