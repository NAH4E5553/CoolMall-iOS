"""Exercise actual Git diffs in isolated repos; never mutate the user's checkout."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('ci_scope', ROOT / 'Scripts/classify-ci-changes.py')
SCOPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCOPE)
ROOT_VIEW = 'CoolMalliOS/Navigation/RootView.swift'


class CIScopeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mall-ci-scope-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'CI scope fixture')
        self.git('config', 'user.email', 'ci-fixture@example.invalid')
        self.write('README.md', 'Documentation\n')
        self.write(ROOT_VIEW, 'Text("暂未开放").font(.body)\n')
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.PIPE).decode().strip()

    def write(self, name, text):
        file = self.root / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)

    def commit(self):
        self.git('add', '--all')
        self.git('commit', '-qm', 'fixture')
        return self.git('rev-parse', 'HEAD')

    def decision(self, event='pull_request', base=None):
        return SCOPE.classify(self.root, event, base or self.base, self.commit())

    def test_documentation_and_placeholder_copy_skip(self):
        self.write('README.md', 'Updated documentation\n')
        self.write(ROOT_VIEW, 'Text("功能暂未开放").font(.body)\n')
        self.assertEqual(self.decision()[:2], (False, 'docs-or-placeholder-only'))

    def test_document_add_delete_and_rename_skip(self):
        (self.root / 'README.md').unlink()
        self.write('docs/guide.md', 'Moved documentation\n')
        self.assertFalse(self.decision()[0])
        self.assertTrue(SCOPE.classify(self.root, 'push', self.base, self.git('rev-parse', 'HEAD'))[0])

    def test_placeholder_navigation_or_callback_change_runs(self):
        self.write(ROOT_VIEW, 'Text("暂未开放").font(.title)\nshowProduct()\n')
        self.assertEqual(self.decision()[:2], (True, 'implementation-rules-or-unknown'))

    def test_new_inert_placeholder_source_skips(self):
        self.write('CoolMalliOS/NewPlaceholder.swift',
                   'import SwiftUI\nprivate struct NewPlaceholderView: View { var body: some View { Text("待接入") } }\n')
        self.assertFalse(self.decision()[0])

    def test_new_placeholder_must_not_shadow_existing_or_imported_types(self):
        for name, access in [('Button', ''), ('RootView', ''), ('NewPlaceholderView', ''),
                             ('Text', 'private '), ('View', 'private ')]:
            source = f'import SwiftUI\n{access}struct {name}: View {{ var body: some View {{ Text("待接入") }} }}'
            with self.subTest(name=name, access=access):
                self.assertFalse(SCOPE.inert_placeholder_only(
                    'CoolMalliOS/Placeholder.swift', None, source.encode()))

    def test_placeholder_becoming_real_or_renaming_runs(self):
        old = 'import SwiftUI\nstruct Pending: View { var body: some View { Text("待接入") } }'
        for new in [old.replace('待接入', '商品详情'), old.replace('Pending:', 'Other:'),
                    old.replace('Text("待接入")', 'Text("待接入").task { await load() }'),
                    old.replace('struct Pending', 'public struct Pending')]:
            with self.subTest(new=new):
                self.assertFalse(SCOPE.inert_placeholder_only(
                    'CoolMalliOS/Pending.swift', old.encode(), new.encode()))
        self.assertFalse(SCOPE.inert_placeholder_only('CoolMalliOS/Pending.swift', old.encode(), None))

    def test_unknown_stub_structure_runs(self):
        self.write('CoolMalliOS/NewPlaceholder.swift', 'struct NewPlaceholder {}\n')
        self.assertTrue(self.decision()[0])

    def test_mixed_docs_and_implemented_change_runs(self):
        self.write('README.md', 'Updated\n')
        self.write('Packages/MallKit/Sources/MallData/Home/HTTPHomeService.swift', 'changed implementation')
        self.assertTrue(self.decision()[0])

    def test_rules_workflow_tests_assets_and_unknown_paths_run(self):
        for path in ['ENGINEERING.md', 'AGENTS.md', 'docs/AGENTS.md', 'docs/SKILL.md',
                     '.github/workflows/ios.yml', 'Scripts/check-ci-results.py',
                     'CoolMalliOSUITests/HomeLoadTests.swift', 'Resources/image.png', 'unknown.md']:
            with self.subTest(path=path):
                self.assertFalse(SCOPE.is_document(path))

    def test_unknown_markdown_runs(self):
        self.write('Scripts/instructions.md', 'May be consumed by tooling')
        self.assertTrue(self.decision()[0])

    def test_symlink_document_never_skips(self):
        (self.root / 'docs').mkdir()
        (self.root / 'docs/linked.md').symlink_to('../README.md')
        self.assertEqual(self.decision()[:2], (True, 'file-mode-or-type'))

    def test_mode_change_never_skips(self):
        (self.root / 'README.md').chmod(0o755)
        self.assertEqual(self.decision()[:2], (True, 'file-mode-or-type'))

    def test_schedule_manual_and_initial_push_run(self):
        for event in ['schedule', 'workflow_dispatch']:
            with self.subTest(event=event):
                self.assertTrue(SCOPE.classify(self.root, event, '', self.base)[0])
        self.assertEqual(SCOPE.classify(self.root, 'push', '0' * 40, self.base)[:2],
                         (True, 'non-pr-full'))

    def test_invalid_or_unavailable_history_does_not_skip(self):
        with self.assertRaisesRegex(ValueError, 'diff head'):
            SCOPE.classify(self.root, 'pull_request', self.base, 'bad')
        with self.assertRaises(subprocess.CalledProcessError):
            SCOPE.classify(self.root, 'pull_request', '1' * 40, self.base)
        self.assertTrue(SCOPE.classify(self.root, 'push', self.base, self.base)[0])

    def test_branch_base_advance_does_not_hide_implementation(self):
        self.git('checkout', '-qb', 'feature')
        self.write('feature.swift', 'implemented')
        head = self.commit()
        self.git('checkout', '-qb', 'base-advance', self.base)
        self.write('base.swift', 'base advanced')
        base = self.commit()
        run, _, paths = SCOPE.classify(self.root, 'pull_request', base, head)
        self.assertTrue(run)
        self.assertEqual(paths, ['feature.swift'])

    def test_copy_interpolation_or_logic_never_skips(self):
        before = b'Text("pending")'
        # Unknown slots, interpolation and removal of a view cannot be called copy-only.
        for after in [b'', b'Text("pending"); action()', b'Text("pending \\(value)")']:
            with self.subTest(after=after):
                self.assertFalse(SCOPE.placeholder_copy_only(ROOT_VIEW, before, after))


if __name__ == '__main__':
    unittest.main()
