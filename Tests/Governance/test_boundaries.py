"""Exercise rejected manifest changes, including attempts to bypass the graph."""

import copy
from contextlib import redirect_stderr, redirect_stdout
import io
import json
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("boundaries", ROOT / "Scripts/check-boundaries.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class BoundariesTests(unittest.TestCase):
    def setUp(self):
        self.policy = CHECK.read_policy(ROOT / "ENGINEERING.md")
        self.manifest = {
            "name": self.policy["package"], "dependencies": [
                {"sourceControl": [{"identity": identity, "location": {"remote": [{"urlString": p["url"]}]}, "productFilter": None, "requirement": {"exact": [p["version"]]}, "traits": [{"name": "default"}]}]}
                for identity,p in self.policy["externalPackages"].items()],
            "platforms": [{"options": [], "platformName": "ios", "version": "17.0"}],
            "swiftLanguageVersions": ["6"],
            "targets": [
                {"name": name, "type": kind, "dependencies": [{"product": [d, "Nuke", None, None]} if d in ("Nuke", "NukeUI") else {"byName": [d, None]} for d in deps]}
                for group, kind in (("targets", "regular"), ("tests", "test"))
                for name, deps in self.policy[group].items()
            ],
            "products": [
                {"name": name, "targets": [name], "type": {"library": ["automatic"]}}
                for name in self.policy["targets"]
            ],
        }

    def target(self, name):
        return next(t for t in self.manifest["targets"] if t["name"] == name)

    def rejected(self, pattern):
        with self.assertRaisesRegex(CHECK.BoundaryError, pattern):
            CHECK.validate_manifest(self.manifest, self.policy)

    def test_language_baseline(self):
        self.manifest["swiftLanguageVersions"] = ["5"]
        self.rejected("MOD-06: Package language")

    def test_platform_baseline(self):
        self.manifest["platforms"][0]["version"] = "18.0"
        self.rejected("MOD-06: Package deployment")

    def test_exception_registry_fails_closed(self):
        handbook = (ROOT / "ENGINEERING.md").read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ENGINEERING.md"
            path.write_text(handbook.replace("| 无 | 无 | 当前没有生效中的例外 | — | — |", "| EX-1 | MOD-01 | expired | owner | 2020-01-01 |"), encoding="utf-8")
            with self.assertRaisesRegex(CHECK.BoundaryError, "MOD-06: active/unknown exceptions"):
                CHECK.read_policy(path)

    def test_allowed_graph(self):
        CHECK.validate_manifest(self.manifest, self.policy)

    def test_explicit_target_dependency_and_resources_allowed(self):
        self.target("MallData")["dependencies"] = [{"target": ["MallCore", None]}]
        self.target("CatalogFeature")["resources"] = [{"path": "Resources", "rule": {"process": {}}}]
        CHECK.validate_manifest(self.manifest, self.policy)

    def test_feature_to_feature_rejected(self):
        self.target("CatalogFeature")["dependencies"].append({"byName": ["CartFeature", None]})
        self.rejected("forbidden/missing dependency")

    def test_feature_to_data_rejected(self):
        self.target("CartFeature")["dependencies"].append({"byName": ["MallData", None]})
        self.rejected("forbidden/missing dependency")

    def test_test_dependency_cannot_mask_production_boundary(self):
        self.target("CatalogFeatureTests")["dependencies"].append({"byName": ["CartFeature", None]})
        self.rejected("forbidden/missing dependency")

    def test_missing_target_rejected(self):
        self.manifest["targets"].pop()
        self.rejected("target set mismatch")

    def test_undeclared_target_rejected(self):
        self.manifest["targets"].append({"name": "HiddenFeature", "type": "regular", "dependencies": []})
        self.rejected("target set mismatch")

    def test_duplicate_target_rejected(self):
        self.manifest["targets"].append(copy.deepcopy(self.manifest["targets"][0]))
        self.rejected("duplicate targets")

    def test_test_cannot_be_disguised_as_library(self):
        self.target("CartFeatureTests")["type"] = "regular"
        self.rejected("wrong target type")

    def test_source_layout_overrides_rejected(self):
        for key, value in (("path", "../Other"), ("sources", ["../Other.swift"]), ("exclude", ["Unwanted.swift"])):
            with self.subTest(key=key):
                self.target("CartFeature")[key] = value
                self.rejected("MOD-03")
                del self.target("CartFeature")[key]

    def test_unsafe_build_flags_rejected(self):
        self.target("CartFeature")["settings"] = [{"tool": "swift", "kind": {"unsafeFlags": {"_0": ["-I", "../Other"]}}}]
        self.rejected("unapproved settings")

    def test_plugin_rejected(self):
        self.target("CartFeature")["pluginUsages"] = [{"plugin": ["Generator", None]}]
        self.rejected("unapproved pluginUsages")

    def test_external_version_rejected(self):
        self.manifest["dependencies"][0]["sourceControl"][0]["requirement"] = {"exact": ["13.1.0"]}
        self.rejected("external packages")

    def test_external_url_rejected(self):
        self.manifest["dependencies"][0]["sourceControl"][0]["location"]["remote"][0]["urlString"] = "https://example.com/Nuke.git"
        self.rejected("external packages")

    def test_sdk_product_on_feature_rejected(self):
        self.target("CatalogFeature")["dependencies"].append({"product": ["Nuke", "Nuke", None, None]})
        self.rejected("forbidden/missing dependency")

    def test_external_package_rejected(self):
        self.manifest["dependencies"] = [{"sourceControl": ["unapproved"]}]
        self.rejected("external packages")

    def test_external_product_rejected(self):
        self.target("CartFeature")["dependencies"].append({"product": ["SDK", "sdk", None, None]})
        self.rejected("external product")

    def test_conditional_dependency_rejected(self):
        self.target("MallData")["dependencies"] = [{"byName": ["MallCore", {"platformNames": ["ios"]}]}]
        self.rejected("conditional dependency")

    def test_malformed_dependency_fails_closed(self):
        self.target("MallData")["dependencies"] = [{"unrecognized": []}]
        self.rejected("unknown dependency")

    def test_resource_escape_rejected(self):
        self.target("CatalogFeature")["resources"] = [{"path": "../CartFeature/Resources"}]
        self.rejected("resource escapes")

    def test_multi_target_product_rejected(self):
        self.manifest["products"][0]["targets"].append("CartFeature")
        self.rejected("own target only")

    def test_cycle_rejected_even_if_added_to_policy(self):
        with self.assertRaisesRegex(CHECK.BoundaryError, "dependency cycle"):
            CHECK.check_cycles({"A": ["B"], "B": ["A"]})

    def test_invalid_or_duplicate_policy_fails(self):
        handbook = (ROOT / "ENGINEERING.md").read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ENGINEERING.md"
            for content in (handbook + handbook, handbook.replace('"schemaVersion": 1', '"schemaVersion": 99')):
                path.write_text(content, encoding="utf-8")
                with self.assertRaises(CHECK.BoundaryError):
                    CHECK.read_policy(path)

    def test_missing_real_package_is_failure_not_skip(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "ENGINEERING.md").write_text((ROOT / "ENGINEERING.md").read_text(encoding="utf-8"), encoding="utf-8")
            result = subprocess.run([sys.executable, str(ROOT / "Scripts/check-boundaries.py"), "--root", directory], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn("F0 is incomplete", result.stderr)


class ManifestDiagnosticsTests(unittest.TestCase):
    def test_success_keeps_json_and_does_not_start_sampling(self):
        with mock.patch.object(CHECK.subprocess, 'Popen') as popen, \
             mock.patch.object(CHECK, 'ManifestSample') as sample, redirect_stderr(io.StringIO()):
            process = popen.return_value.__enter__.return_value
            process.returncode = 0
            process.communicate.return_value = ('{"name":"MallKit"}', 'compiler detail')
            result = CHECK.dump_manifest(Path('/fixture/MallKit'))
        self.assertEqual(result.stdout, '{"name":"MallKit"}')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(popen.call_args.args[0], [
            'xcrun', 'swift', 'package', '--package-path', '/fixture/MallKit', '--verbose', 'dump-package'])
        process.communicate.assert_called_once_with(timeout=50)
        sample.assert_not_called()

    def test_timeout_chunks_share_original_deadline_and_never_wait_for_child_pipes(self):
        now = [0]
        log = io.StringIO()
        with mock.patch.object(CHECK.time, 'monotonic', side_effect=lambda: now[0]), \
             mock.patch.object(CHECK.subprocess, 'Popen') as popen, \
             mock.patch.object(CHECK, 'ManifestSample') as factory, redirect_stderr(log):
            process = popen.return_value.__enter__.return_value
            sampler = factory.return_value
            sampler.deadline = 53
            def communicate(timeout):
                now[0] += timeout
                raise subprocess.TimeoutExpired(['xcrun'], timeout, output=b'partial-json', stderr=b'compiler-wait\xff')
            process.communicate.side_effect = communicate
            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                CHECK.dump_manifest(Path('/fixture/MallKit'))
        self.assertEqual(now[0], 60)
        self.assertEqual(caught.exception.timeout, 60)
        self.assertEqual([call.kwargs['timeout'] for call in process.communicate.call_args_list], [50, 3, 7])
        process.kill.assert_called_once_with()
        process.wait.assert_called_once_with()
        sampler.start.assert_called_once_with(60)
        self.assertEqual(sampler.finish.call_args_list, [mock.call('sample-window-ended', 60), mock.call('command-finished', 60)])
        self.assertIn('partial-json', log.getvalue())
        self.assertIn('compiler-wait', log.getvalue())
        self.assertIn('truncated=false', log.getvalue())

    def test_command_completion_interrupts_owned_sample_before_return(self):
        error = subprocess.TimeoutExpired(['xcrun'], 50)
        with mock.patch.object(CHECK.subprocess, 'Popen') as popen, \
             mock.patch.object(CHECK, 'ManifestSample') as factory, redirect_stderr(io.StringIO()):
            process = popen.return_value.__enter__.return_value
            process.returncode = 12
            process.communicate.side_effect = [error, ('{}', 'compiler failed')]
            factory.return_value.deadline = CHECK.time.monotonic() + 3
            result = CHECK.dump_manifest(Path('/fixture/MallKit'))
        self.assertEqual(result.returncode, 12)
        self.assertEqual(factory.return_value.finish.call_count, 1)
        self.assertEqual(factory.return_value.finish.call_args.args[0], 'command-finished')

    def test_start_failure_does_not_create_sampler(self):
        with mock.patch.object(CHECK.subprocess, 'Popen', side_effect=OSError('missing xcrun')), \
             mock.patch.object(CHECK, 'ManifestSample') as sample, redirect_stderr(io.StringIO()):
            with self.assertRaisesRegex(OSError, 'missing xcrun'):
                CHECK.dump_manifest(Path('/fixture/MallKit'))
        sample.assert_not_called()

    def test_snapshot_filters_unrelated_processes_and_keeps_complete_stack(self):
        processes = '100 1 S 00:50 0.0 - checker\n200 100 S 00:50 0.0 - swift-package\n201 200 S 00:49 0.0 - swift-frontend\n202 100 R 00:00 0.0 - /bin/ps\n900 1 S 01:00 0.0 - unrelated\n'
        log = io.StringIO()
        def launch(command, **kwargs):
            kwargs['stdout'].write(b'compiler stack wait')
            kwargs['stdout'].flush()
            process = mock.Mock(pid=300, returncode=0)
            process.poll.return_value = 0
            return process
        sample = CHECK.ManifestSample(200)
        with mock.patch.object(CHECK.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, processes, '')) as run, \
             mock.patch.object(CHECK.subprocess, 'Popen', side_effect=launch) as popen, \
             mock.patch.object(CHECK.os, 'killpg'), redirect_stderr(log):
            deadline = CHECK.time.monotonic() + 10
            sample.start(deadline)
            sample.finish('command-finished', deadline)
        self.assertNotIn('unrelated', log.getvalue())
        self.assertNotIn('202 100', log.getvalue())
        self.assertIn('compiler stack wait', log.getvalue())
        self.assertIn('sample state=complete', log.getvalue())
        self.assertIn('truncated=false', log.getvalue())
        self.assertLessEqual(run.call_args.kwargs['timeout'], 2)
        self.assertEqual(popen.call_args.args[0], ['/usr/bin/sample', '201', '1', '10', '-file', '/dev/stdout'])
        self.assertTrue(popen.call_args.kwargs['start_new_session'])
        self.assertIsNone(sample.process)
        self.assertIsNone(sample.stdout)

    def test_sample_cancellation_kills_reaps_and_keeps_partial_output(self):
        sample = CHECK.ManifestSample(200)
        sample.process = mock.Mock(pid=300, returncode=-9)
        sample.process.poll.return_value = None
        sample.stdout = tempfile.TemporaryFile()
        sample.stdout.write(b'partial stack before cancellation')
        sample.stdout.flush()
        owned = sample.process
        log = io.StringIO()
        with mock.patch.object(CHECK.os, 'killpg') as kill, redirect_stderr(log):
            sample.finish('command-finished', CHECK.time.monotonic() + 0.1)
            sample.finish('command-finished', CHECK.time.monotonic() + 0.1)
        kill.assert_called_once_with(300, CHECK.signal.SIGKILL)
        owned.wait.assert_called_once()
        self.assertLessEqual(owned.wait.call_args.kwargs['timeout'], 0.1)
        self.assertIn('state=interrupted', log.getvalue())
        self.assertIn('partial stack before cancellation', log.getvalue())
        self.assertIsNone(sample.process)
        self.assertIsNone(sample.stdout)

    def test_unreaped_sample_is_explicit_without_exceeding_deadline(self):
        sample = CHECK.ManifestSample(200)
        sample.process = mock.Mock(pid=300, returncode=None)
        sample.process.poll.return_value = None
        sample.process.wait.side_effect = subprocess.TimeoutExpired(['sample'], 0)
        owned = sample.process
        log = io.StringIO()
        with mock.patch.object(CHECK.os, 'killpg'), redirect_stderr(log):
            sample.finish('sample-window-ended', CHECK.time.monotonic() - 1)
        owned.wait.assert_called_once_with(timeout=0)
        self.assertIn('incomplete-unreaped', log.getvalue())
        self.assertIn('exit=None', log.getvalue())

    def test_no_live_command_is_explicit_and_does_not_sample_another_process(self):
        log = io.StringIO()
        with mock.patch.object(CHECK.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '900 1 S 00:50 0 - unrelated\n', '')), \
             mock.patch.object(CHECK.subprocess, 'Popen') as popen, redirect_stderr(log):
            CHECK.ManifestSample(200).start(CHECK.time.monotonic() + 10)
        popen.assert_not_called()
        self.assertIn('no live command process', log.getvalue())
        self.assertNotIn('unrelated', log.getvalue())

    def test_expired_command_deadline_starts_no_diagnostic(self):
        log = io.StringIO()
        with mock.patch.object(CHECK.subprocess, 'run') as run, redirect_stderr(log):
            CHECK.ManifestSample(200).start(CHECK.time.monotonic() - 1)
        run.assert_not_called()
        self.assertIn('command deadline reached', log.getvalue())

    def test_ps_error_retains_partial_output_and_is_disclosed(self):
        log = io.StringIO()
        error = subprocess.TimeoutExpired(['ps'], 2, output=b'200 100 S 00:50 0 - owned-ps-row\n900 1 S 00:50 0 - UNRELATED_PROCESS_SENTINEL\n', stderr=b'partial ps error')
        with mock.patch.object(CHECK.subprocess, 'run', side_effect=error), redirect_stderr(log):
            CHECK.ManifestSample(200).start(CHECK.time.monotonic() + 10)
        self.assertIn('state=unavailable', log.getvalue())
        self.assertIn('owned-ps-row', log.getvalue())
        self.assertNotIn('UNRELATED_PROCESS_SENTINEL', log.getvalue())
        self.assertIn('unparsed/unattributed rows omitted', log.getvalue())
        self.assertIn('partial ps error', log.getvalue())
        self.assertIn('truncated=false', log.getvalue())

    def test_partial_ps_with_unknown_parent_or_incomplete_rows_is_not_attributed(self):
        value = b'201 200 S 00:50 0 - known-child\n202 999 S 00:50 0 - unknown-parent\n203 201 S\nUNPARSEABLE\n204 200 S 00:50 0 - truncated-owned'
        rows, _ = CHECK.command_process_rows(value, 200, partial=True)
        self.assertEqual(list(rows), [201])
        self.assertIn('known-child', rows[201])

    def test_nonzero_ps_output_uses_same_command_tree_filter(self):
        error = subprocess.CalledProcessError(1, ['ps'], output='200 100 S 00:50 0 - owned-row\n900 1 S 00:50 0 - UNRELATED\n', stderr='ps failed')
        log = io.StringIO()
        with mock.patch.object(CHECK.subprocess, 'run', side_effect=error), redirect_stderr(log):
            CHECK.ManifestSample(200).start(CHECK.time.monotonic() + 10)
        self.assertIn('owned-row', log.getvalue())
        self.assertNotIn('UNRELATED', log.getvalue())
        self.assertIn('ps snapshot incomplete', log.getvalue())
        self.assertIn('ps failed', log.getvalue())

    def test_bounded_output_discloses_lengths_ranges_and_truncation(self):
        value = 'BEGIN' + 'x' * 17000 + 'END'
        head = CHECK.format_output('stack', value, 16000, False)
        tail = CHECK.format_output('stderr', value)
        self.assertIn('chars=17008 kept=[0,16000) truncated=true', head)
        self.assertIn('BEGIN', head)
        self.assertNotIn('END', head)
        self.assertIn('chars=17008 kept=[11008,17008) truncated=true', tail)
        self.assertTrue(tail.endswith('END'))
        self.assertIn('chars=0 kept=[0,0) truncated=false', CHECK.format_output('empty', None))
        self.assertIn('replacement', CHECK.format_output('bytes', b'replacement\xff'))

    def test_stack_file_read_is_bounded_and_reports_byte_ranges(self):
        with tempfile.TemporaryFile() as stream:
            stream.write(b'BEGIN' + b'x' * 17000 + b'END')
            stream.flush()
            with mock.patch.object(stream, 'read', wraps=stream.read) as read:
                head = CHECK.format_stream_output('stack', stream, 16000, False)
                read.assert_called_once_with(16000)
            tail = CHECK.format_stream_output('stderr', stream, 6000, True)
        self.assertIn('bytes=17008 kept=[0,16000) truncated=true', head)
        self.assertIn('BEGIN', head)
        self.assertNotIn('END', head)
        self.assertIn('bytes=17008 kept=[11008,17008) truncated=true', tail)
        self.assertTrue(tail.endswith('END'))

    def test_main_keeps_nonzero_malformed_and_timeout_results_blocking(self):
        for result in [subprocess.CompletedProcess([], 12, '{}', 'compiler failed'),
                       subprocess.CompletedProcess([], 0, 'not-json', ''),
                       subprocess.TimeoutExpired(['xcrun'], 60)]:
            with self.subTest(result=result):
                out, err = io.StringIO(), io.StringIO()
                options = {'side_effect': result} if isinstance(result, Exception) else {'return_value': result}
                with mock.patch.object(sys, 'argv', ['check-boundaries.py', '--root', str(ROOT)]), \
                     mock.patch.object(CHECK, 'dump_manifest', **options), \
                     redirect_stdout(out), redirect_stderr(err):
                    self.assertEqual(CHECK.main(), 1)
                self.assertNotIn('PASS:', out.getvalue())
                self.assertIn('FAIL:', err.getvalue())


if __name__ == "__main__":
    unittest.main()
