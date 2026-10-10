"""Real project copies: assert each rejection's rule and diagnostic, never any failure."""
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('project_gate', ROOT / 'Scripts/check-project-boundaries.py')
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)
BINARY = ROOT / '.build/governance/source-boundaries'


class ProjectBoundariesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not BINARY.is_file():
            raise RuntimeError('Run Scripts/check-source-boundaries.sh first; missing tool is not a skip')

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mall-boundary-')
        self.root = Path(self.temp.name)
        for name in ['ENGINEERING.md', 'CoolMalliOS', 'CoolMalliOSUITests', 'CoolMalliOS.xcodeproj', 'CoolMalliOS.xctestplan', 'Packages']:
            src, dst = ROOT / name, self.root / name
            if src.is_dir(): shutil.copytree(src, dst, ignore=shutil.ignore_patterns('.build', 'xcuserdata'))
            else: shutil.copy2(src, dst)
        self.addCleanup(self.temp.cleanup)

    def append(self, code, target='CatalogFeature'):
        p = self.root / 'Packages/MallKit/Sources' / target / 'BoundaryProbe.swift'
        p.write_text(code)

    def reject(self, message):
        with self.assertRaisesRegex(GATE.manifest_gate.BoundaryError, message):
            GATE.check(self.root, BINARY)

    def mutate_project(self, mutation):
        p = self.root / 'CoolMalliOS.xcodeproj/project.pbxproj'
        data = plistlib.loads(p.read_bytes())
        mutation(data['objects'])
        p.write_bytes(plistlib.dumps(data))

    def test_normal_project(self): GATE.check(self.root, BINARY)

    def test_comments_and_strings_are_not_imports(self):
        self.append('// import MallData\nlet text = "URLSession @testable import CartFeature"\nlet apiName = "URLSession"')
        GATE.check(self.root, BINARY)

    def test_catalog_imports_cart(self):
        self.append('import CartFeature'); self.reject('MOD-01.*forbidden import CartFeature')

    def test_catalog_imports_data_in_inactive_branch(self):
        self.append('#if NEVER_ENABLED\nimport MallData\n#endif'); self.reject('MOD-01.*forbidden import MallData')

    def test_selective_import(self):
        self.append('import struct MallData.FixtureProductService'); self.reject('MOD-01.*forbidden import MallData')

    def test_core_imports_swiftui(self):
        self.append('import SwiftUI', 'MallCore'); self.reject('MOD-01.*forbidden import SwiftUI')

    def test_production_testable(self):
        self.append('@testable import MallCore'); self.reject('MOD-02.*forbidden @testable')

    def test_reexport(self):
        self.append('@_exported import MallCore'); self.reject('MOD-02.*forbidden attribute @_exported')

    def test_spi(self):
        self.append('@_spi(Probe) import MallCore'); self.reject('MOD-02.*forbidden attribute @_spi')

    def test_package_access(self):
        self.append('package struct Probe {}'); self.reject('MOD-02.*forbidden package')

    def test_public_viewmodel(self):
        self.append('public final class ProbeViewModel {}'); self.reject('MOD-02.*implementation type')

    def test_unregistered_feature_public_type(self):
        self.append('public struct RandomView {}'); self.reject('MOD-02.*unregistered Feature public type RandomView')

    def test_direct_api(self):
        self.append('import Foundation\nlet probe = Foundation.URLSession.shared'); self.reject('MOD-05.*direct API URLSession')

    def test_unknown_system_import(self):
        self.append('import Security'); self.reject('MOD-01.*forbidden import Security')

    def test_syntax_error(self):
        self.append('struct {'); self.reject('MOD-02: Swift parse error')

    def test_unregistered_source(self):
        (self.root / 'Unexpected.swift').write_text('struct Hidden {}'); self.reject('MOD-03: unregistered source')

    def test_source_symlink(self):
        (self.root / 'Packages/MallKit/Sources/CartFeature/Link.swift').symlink_to(self.root / 'CoolMalliOS/AppDependencies.swift')
        self.reject('MOD-03: source/resource symlink')

    def test_duplicate_membership(self):
        def mutation(objects):
            phases = [o for o in objects.values() if o['isa'] == 'PBXSourcesBuildPhase']
            phases[0]['files'].append(phases[1]['files'][0])
        self.mutate_project(mutation); self.reject('MOD-03: duplicate/missing/foreign source membership')

    def test_package_source_in_app(self):
        def mutation(objects):
            ref = next(o for o in objects.values() if o['isa']=='PBXFileReference' and o.get('path')=='CoolMalliOS/AppDependencies.swift')
            ref['path']='Packages/MallKit/Sources/MallData/Cart/FakeCartStore.swift'
        self.mutate_project(mutation); self.reject('MOD-03: duplicate/missing/foreign source membership')

    def test_search_path(self):
        def mutation(objects):
            next(o for o in objects.values() if o['isa']=='XCBuildConfiguration')['buildSettings']['SWIFT_INCLUDE_PATHS']='$(SRCROOT)/Other'
        self.mutate_project(mutation); self.reject('MOD-06: unknown/unsafe build settings')

    def test_compilation_conditions_release_forbidden(self):
        def mutation(objects):
            release = next(o for o in objects.values() if o['isa']=='XCBuildConfiguration' and o['name']=='Release')
            release['buildSettings']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        self.mutate_project(mutation); self.reject('MOD-06: SWIFT_ACTIVE_COMPILATION_CONDITIONS must be exactly DEBUG')

    def test_compilation_conditions_unsafe_value_forbidden(self):
        def mutation(objects):
            debug = next(o for o in objects.values() if o['isa']=='XCBuildConfiguration' and o['name']=='Debug')
            debug['buildSettings']['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG NAV_TEST_BACKDOOR'
        self.mutate_project(mutation); self.reject('MOD-06: SWIFT_ACTIVE_COMPILATION_CONDITIONS must be exactly DEBUG')

    def test_unknown_project_object(self):
        self.mutate_project(lambda o: o.update({'UNKNOWN': {'isa':'PBXShellScriptBuildPhase'}})); self.reject('MOD-06: unsupported Xcode object')

    def test_missing_package_file_reference(self):
        def mutation(objects):
            root = next(o for o in objects.values() if o['isa']=='PBXProject')
            group = objects[root['mainGroup']]
            group['children'] = [i for i in group['children'] if objects[i].get('lastKnownFileType') != 'wrapper']
        self.mutate_project(mutation); self.reject('MOD-03: Package missing from main group')

    def test_missing_link(self):
        def mutation(objects):
            next(o for o in objects.values() if o['isa']=='PBXFrameworksBuildPhase' and o['files'])['files'].pop()
        self.mutate_project(mutation); self.reject('MOD-01: App link membership mismatch')

    def test_skipped_test_target(self):
        p=self.root/'CoolMalliOS.xctestplan'; data=json.loads(p.read_text());data['testTargets'][0]['skippedTests']=['aTest'];p.write_text(json.dumps(data))
        self.reject('MOD-01: disabled/selected/skipped tests')

    def test_missing_test_target(self):
        p=self.root/'CoolMalliOS.xctestplan'; data=json.loads(p.read_text());data['testTargets'].pop();p.write_text(json.dumps(data))
        self.reject('MOD-01: Test Plan must include all')

    def test_formatter_rejects_malformed_spacing(self):
        p = self.root / 'format-probe.swift'; p.write_text('struct Probe{let value:Int=1}\n')
        result = subprocess.run(['xcrun','swift-format','lint','--strict','--configuration',str(ROOT/'.swift-format'),str(p)],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('format-probe.swift',result.stderr)

    def test_real_manifest_unknown_target(self):
        p=self.root/'Packages/MallKit/Package.swift';s=p.read_text();p.write_text(s.replace('targets: [\n        .target', 'targets: [\n        .target(name: "Hidden"),\n        .target',1))
        self.assert_manifest_failure('MOD-01: target set mismatch')

    def test_real_manifest_external_package(self):
        p=self.root/'Packages/MallKit/Package.swift';s=p.read_text();p.write_text(s.replace('    targets: [\n', '    dependencies: [.package(url: "https://example.invalid/unapproved.git", from: "1.0.0")],\n    targets: [\n',1))
        self.assert_manifest_failure('MOD-06: external packages')

    def assert_manifest_failure(self, diagnostic):
        run=subprocess.run(['python3',str(ROOT/'Scripts/check-boundaries.py'),'--root',str(self.root)],capture_output=True,text=True)
        self.assertEqual(run.returncode,1,run.stdout+run.stderr)
        self.assertIn(diagnostic,run.stderr)

if __name__ == '__main__': unittest.main()
