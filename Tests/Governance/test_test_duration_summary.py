"""Telemetry-only per-test duration summary; never a merge gate."""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'Scripts/test-duration-summary.py'


class TestDurationSummaryTests(unittest.TestCase):
    def run_script(self, text=None):
        with tempfile.TemporaryDirectory() as td:
            log = Path(td) / 'tests.log'
            if text is not None:
                log.write_text(text)
            return subprocess.run([sys.executable, str(SCRIPT), str(log)],
                                  capture_output=True, text=True)

    def test_reports_slowest_and_over_threshold(self):
        result = self.run_script(
            "Test Case '-[CoolMalliOSUITests.HomeLoadTests testFast]' passed (12.500 seconds).\n"
            "Test Case '-[CoolMalliOSUITests.HomeLoadTests testSlow]' failed (61.250 seconds).\n"
            "Test Case '-[CoolMalliOSUITests.HomeLoadTests testEdge]' passed (45.000 seconds).\n"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('tests recorded: 3', result.stdout)
        self.assertIn('slowest: 61.250s', result.stdout)
        self.assertIn('testSlow(): 61.250s (failed)', result.stdout)
        self.assertIn('testEdge(): 45.000s (passed)', result.stdout)
        self.assertIn('at/over 45s: 2', result.stdout)

    def test_missing_log_is_an_error_but_empty_log_is_not(self):
        self.assertEqual(self.run_script().returncode, 2)
        result = self.run_script('no durations here\n')
        self.assertEqual(result.returncode, 0)
        self.assertIn('No XCTest/Swift Testing durations found', result.stdout)


if __name__ == '__main__':
    unittest.main()
