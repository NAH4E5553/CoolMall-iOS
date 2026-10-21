import importlib.util
import json
import os
import signal
import sys
import time
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('banner_trace', ROOT / 'Scripts/with-banner-trace.py')
TRACE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(TRACE)


class BannerTraceTests(unittest.TestCase):
    def exercise(self, test_code=0, stream_code=None, events=True, start_error=False):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'trace.log'
            collector = Mock(pid=123, returncode=stream_code)
            collector.poll.return_value = stream_code
            test = Mock()
            test.wait.return_value = test_code
            test.poll.return_value = test_code
            def start(*args, **kwargs):
                if args[0] == ['test-command']:
                    return test
                if start_error:
                    raise OSError('no simulator')
                kwargs['stdout'].write('AUTOTRACE event=arm\n' if events else '')
                kwargs['stdout'].flush()
                return collector
            with patch.object(TRACE.subprocess, 'Popen', side_effect=start) as command:
                result = TRACE.run('SIM', output, ['test-command'])
            status = json.loads(output.with_suffix('.status.log').read_text())
            return result, status, collector, command

    def test_real_command_and_events_retained(self):
        code, status, collector, command = self.exercise()
        self.assertEqual(code, 0)
        self.assertTrue(status['eventsObserved'])
        self.assertEqual(command.call_args_list[-1].args[0], ['test-command'])
        collector.terminate.assert_called_once()
        collector.wait.assert_called_once_with(timeout=5)

    def test_original_business_failure_preserved(self):
        self.assertEqual(self.exercise(test_code=65)[0], 65)

    def test_dead_stream_cannot_report_success(self):
        code, status, collector, _ = self.exercise(stream_code=1)
        self.assertEqual(code, 65)
        self.assertEqual(status['state'], 'diagnostic-missing')
        collector.terminate.assert_not_called()
        self.assertEqual(self.exercise(test_code=42, stream_code=1)[0], 42)

    def test_start_failure_explicit_and_no_test_claim(self):
        code, status, _, command = self.exercise(start_error=True)
        self.assertEqual(code, 65)
        self.assertEqual(status['state'], 'diagnostic-missing')
        self.assertEqual(command.call_count, 1)

    def test_no_events_is_inconclusive(self):
        code, status, _, _ = self.exercise(events=False)
        self.assertEqual(code, 0)
        self.assertFalse(status['eventsObserved'])

    def test_cleanup_failure_preserves_business_failure(self):
        for test_code, expected in [(42, 42), (0, 65)]:
            with self.subTest(code=test_code), tempfile.TemporaryDirectory() as directory:
                collector = Mock(pid=1)
                collector.poll.return_value = None
                collector.terminate.side_effect = OSError('cleanup denied')
                test = Mock()
                test.wait.return_value = test_code
                test.poll.return_value = test_code
                with patch.object(TRACE.subprocess, 'Popen', side_effect=[collector, test]):
                    self.assertEqual(TRACE.run('SIM', Path(directory) / 'trace.log', ['test']), expected)

    def test_metadata_failure_preserves_business_failure(self):
        for test_code, expected in [(42, 42), (0, 65)]:
            with self.subTest(code=test_code), tempfile.TemporaryDirectory() as directory:
                collector = Mock(pid=1)
                collector.poll.return_value = None
                test = Mock()
                test.wait.return_value = test_code
                test.poll.return_value = test_code
                with patch.object(TRACE.subprocess, 'Popen', side_effect=[collector, test]), patch.object(
                    Path, 'write_text', side_effect=OSError('read only')):
                    self.assertEqual(TRACE.run('SIM', Path(directory) / 'trace.log', ['test']), expected)

    def test_real_wrapper_signals_clean_both_children(self):
        for sig in [signal.SIGINT, signal.SIGTERM]:
            with self.subTest(signal=sig), tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                fake = folder / 'xcrun'
                fake.write_text('#!' + sys.executable + '\nimport time\nprint("AUTOTRACE ready", flush=True)\nwhile True: time.sleep(1)\n')
                fake.chmod(0o755)
                pid_file = folder / 'child.pid'
                trace = folder / 'trace.log'
                command = [sys.executable, str(ROOT / 'Scripts/with-banner-trace.py'), 'SIM', str(trace), '--', sys.executable, '-c',
                           'import os,time,pathlib; pathlib.Path(' + repr(str(pid_file)) + ').write_text(str(os.getpid())); time.sleep(60)']
                process = subprocess.Popen(command, env={**os.environ, 'PATH': str(folder) + os.pathsep + os.environ['PATH']}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    deadline = time.monotonic() + 5
                    while not pid_file.exists() and time.monotonic() < deadline:
                        time.sleep(.02)
                    self.assertTrue(pid_file.exists())
                    status = json.loads(trace.with_suffix('.status.log').read_text())
                    children = [int(pid_file.read_text()), status['pid']]
                    process.send_signal(sig)
                    self.assertEqual(process.wait(timeout=12), 128 + sig)
                    status = json.loads(trace.with_suffix('.status.log').read_text())
                    self.assertEqual(status['exitCode'], 128 + sig)
                    for pid in children:
                        with self.assertRaises(ProcessLookupError):
                            os.kill(pid, 0)
                finally:
                    if process.poll() is None:
                        process.kill()
                        process.wait()

    def test_signalled_command_exit_preserved(self):
        self.assertEqual(self.exercise(test_code=-15)[0], 143)


if __name__ == '__main__':
    unittest.main()
