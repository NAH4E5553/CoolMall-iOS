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

    def test_checkout_cannot_import_orders_feature(self):
        self.append('import OrdersFeature\n', target='CheckoutFeature')
        self.reject('MOD-01:.*forbidden import OrdersFeature')

    def test_orders_cannot_import_checkout_or_data(self):
        self.append('import CheckoutFeature\nimport MallData\n', target='OrdersFeature')
        self.reject('MOD-01:.*forbidden import CheckoutFeature')

    def test_new_feature_viewmodel_cannot_be_public(self):
        self.append('public struct LeakedViewModel {}\n', target='CheckoutFeature')
        self.reject('MOD-02:.*implementation type must remain internal')

    def test_new_feature_entry_requires_exact_registration(self):
        self.append('public struct UnexpectedEntryView {}\n', target='OrdersFeature')
        self.reject('MOD-02:.*unregistered Feature public type')


    def test_cashier_registration_does_not_allow_extra_public_entries_or_models(self):
        self.append('public struct CashierSettingsEntryView {}\n', target='CheckoutFeature')
        self.reject('MOD-02:.*unregistered Feature public type CashierSettingsEntryView')

    def test_simulator_identity_missing_setting_rejected(self):
        def mutation(objects):
            config = next(o for o in objects.values() if o.get('isa') == 'XCBuildConfiguration' and 'MALL_SIMULATOR_ENTITLEMENTS_NO' in o['buildSettings'])
            del config['buildSettings']['MALL_SIMULATOR_ENTITLEMENTS_NO']
        self.mutate_project(mutation); self.reject('MOD-06: simulator Keychain identity settings mismatch')

    def test_simulator_identity_cannot_apply_to_device(self):
        def mutation(objects):
            config = next(o for o in objects.values() if o.get('isa') == 'XCBuildConfiguration')
            config['buildSettings']['CODE_SIGN_ENTITLEMENTS'] = 'CoolMalliOS/Simulator.entitlements'
        self.mutate_project(mutation); self.reject('MOD-06: unknown/unsafe build settings')

    def test_simulator_identity_non_app_target_rejected(self):
        def mutation(objects):
            target = next(o for o in objects.values() if o.get('isa') == 'PBXNativeTarget' and o['name'] == 'CoolMalliOSUITests')
            cid = objects[target['buildConfigurationList']]['buildConfigurations'][0]
            objects[cid]['buildSettings']['MALL_SIMULATOR_ENTITLEMENTS_YES'] = ''
        self.mutate_project(mutation); self.reject('MOD-06: simulator Keychain identity must be App-only')

    def test_simulator_identity_extra_entitlement_rejected(self):
        p = self.root / 'CoolMalliOS/Simulator.entitlements'
        data = plistlib.loads(p.read_bytes()); data['get-task-allow'] = True
        p.write_bytes(plistlib.dumps(data)); self.reject('MOD-06: simulator Keychain identity contents mismatch')

    def test_unsigned_simulator_debug_layout_required(self):
        def mutation(objects):
            config = next(o for o in objects.values() if o.get('isa') == 'XCBuildConfiguration' and 'MALL_SIMULATOR_DEBUG_DYLIB_NO' in o['buildSettings'])
            config['buildSettings']['MALL_SIMULATOR_DEBUG_DYLIB_NO'] = 'YES'
        self.mutate_project(mutation); self.reject('MOD-06: simulator Keychain debug layout mismatch')

    def test_signed_simulator_debug_layout_preserved(self):
        def mutation(objects):
            config = next(o for o in objects.values() if o.get('isa') == 'XCBuildConfiguration' and 'MALL_SIMULATOR_DEBUG_DYLIB_YES' in o['buildSettings'])
            config['buildSettings']['MALL_SIMULATOR_DEBUG_DYLIB_YES'] = 'NO'
        self.mutate_project(mutation); self.reject('MOD-06: simulator Keychain debug layout mismatch')

    def test_simulator_identity_shared_group_rejected(self):
        p = self.root / 'CoolMalliOS/Simulator.entitlements'
        data = plistlib.loads(p.read_bytes()); data['keychain-access-groups'].append('another.application')
        p.write_bytes(plistlib.dumps(data)); self.reject('MOD-06: simulator Keychain identity contents mismatch')

    def test_simulator_identity_wrong_identifier_rejected(self):
        p = self.root / 'CoolMalliOS/Simulator.entitlements'
        data = plistlib.loads(p.read_bytes()); data['application-identifier'] = 'another.application'
        p.write_bytes(plistlib.dumps(data)); self.reject('MOD-06: simulator Keychain identity contents mismatch')

    def test_footprint_registered_adapter_and_entry(self):
        GATE.check(self.root, BINARY)

    def test_footprint_other_data_file_cannot_import_swiftdata(self):
        self.append('import SwiftData', target='MallData')
        self.reject('MOD-01.*SwiftData import is scoped')

    def test_footprint_other_feature_cannot_access_storage(self):
        self.append('import SwiftData', target='AccountFeature')
        self.reject('MOD-01.*forbidden import SwiftData')

    def test_footprint_extra_public_view_rejected(self):
        self.append('public struct FootprintSettingsView {}', target='AccountFeature')
        self.reject('MOD-02.*unregistered Feature public type')

    def test_address_exact_registered_entries(self):
        GATE.check(self.root, BINARY)

    def test_address_extra_entry_rejected(self):
        self.append('public struct AddressConfirmView {}', 'AccountFeature')
        self.reject('MOD-02.*unregistered Feature public type AddressConfirmView')

    def test_address_public_viewmodel_rejected(self):
        self.append('public final class AddressEditorViewModel {}', 'AccountFeature')
        self.reject('MOD-02.*implementation type must remain internal')

    def test_coupon_exact_registered_entries(self):
        GATE.check(self.root, BINARY)

    def test_coupon_extra_receive_entry_rejected(self):
        self.append('public struct CouponBatchReceiveView {}', 'AccountFeature')
        self.reject('MOD-02.*unregistered Feature public type CouponBatchReceiveView')

    def test_coupon_extra_account_entry_rejected(self):
        self.append('public struct CouponReceiveView {}', 'AccountFeature')
        self.reject('MOD-02.*unregistered Feature public type CouponReceiveView')

    def test_coupon_extra_catalog_entry_rejected(self):
        self.append('public struct CouponScopePickerView {}', 'CatalogFeature')
        self.reject('MOD-02.*unregistered Feature public type CouponScopePickerView')

    def test_account_registered_entries_and_adapters(self):
        GATE.check(self.root, BINARY)

    def test_account_extra_public_entry_rejected(self):
        self.append('public struct ExtraAccountView {}', 'AccountFeature')
        self.reject('MOD-02.*unregistered Feature public type ExtraAccountView')

    def test_account_cross_feature_rejected(self):
        self.append('import CartFeature', 'AccountFeature')
        self.reject('MOD-01.*forbidden import CartFeature')

    def test_security_outside_adapter_rejected(self):
        self.append('import Security', 'MallData')
        self.reject('MOD-01.*Security import is scoped')

    def test_security_api_without_import_rejected(self):
        self.append('let f = SecItemAdd', 'MallData')
        self.reject('MOD-05.*Keychain API is scoped')

    def test_notifications_outside_adapter_rejected(self):
        self.append('import UserNotifications', 'MallData')
        self.reject('MOD-01.*UserNotifications import is scoped')

    def test_notification_api_without_import_rejected(self):
        self.append('let c = UNUserNotificationCenter.current()', 'AccountFeature')
        self.reject('MOD-05.*notification API is scoped')

    def test_captcha_decoder_outside_adapter_rejected(self):
        self.append('import ImageIO', 'AccountFeature')
        self.reject('MOD-01.*captcha image import is scoped')

    def test_account_testplan_target_required(self):
        p = self.root / 'CoolMalliOS.xctestplan'
        data = json.loads(p.read_text())
        data['testTargets'] = [x for x in data['testTargets'] if x['target']['identifier'] != 'AccountFeatureTests']
        p.write_text(json.dumps(data))
        self.reject('MOD-01: Test Plan must include all registered tests')


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

    def test_feature_cannot_import_nuke(self):
        self.append('import Nuke'); self.reject('MOD-01.*forbidden import Nuke')

    def test_inactive_feature_cannot_import_nukeui(self):
        self.append('#if NEVER_ENABLED\nimport NukeUI\n#endif'); self.reject('MOD-01.*forbidden import NukeUI')

    def test_image_adapter_exception_is_file_scoped(self):
        self.append('import Foundation\nlet probe = URLSession.shared', 'MallImages')
        self.reject('MOD-05.*direct API URLSession')

    def test_pipeline_protocol_type_requires_debug(self):
        p = self.root / 'Packages/MallKit/Sources/MallImages/MallImagePipeline.swift'
        p.write_text(p.read_text() + '\nlet invalidTestType: URLProtocol.Type? = nil\n')
        self.reject('MOD-05.*direct API URLProtocol')

    def test_image_app_exception_requires_debug(self):
        p = self.root / 'CoolMalliOS/Testing/ImageUITestSupport.swift'
        p.write_text('import Foundation\nlet probe = URLSession.shared')
        self.reject('MOD-05.*direct API URLSession')

    def test_direct_api(self):
        self.append('import Foundation\nlet probe = Foundation.URLSession.shared'); self.reject('MOD-05.*direct API URLSession')

    def test_cartfeature_can_import_registered_mallimages(self):
        self.append('import MallImages', 'CartFeature')
        GATE.check(self.root, BINARY)

    def test_cartfeature_cannot_import_malldata(self):
        self.append('import MallData', 'CartFeature'); self.reject('MOD-01.*forbidden import MallData')

    def test_swiftdata_is_scoped_to_persistent_cart_store(self):
        p = self.root / 'Packages/MallKit/Sources/MallData/Cart/PersistentCartStore.swift'
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text('import SwiftData\nlet context: ModelContext? = nil\n')
        GATE.check(self.root, BINARY)

    def test_swiftdata_import_outside_persistent_store_rejected(self):
        self.append('import SwiftData', 'MallData')
        self.reject('MOD-01.*SwiftData import is scoped')

    def test_swiftdata_api_outside_persistent_store_rejected(self):
        self.append('import Foundation\nlet context: ModelContext? = nil', 'MallData')
        self.reject('MOD-05.*SwiftData API is scoped')

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

    def test_dependency_lock_wrong_revision(self):
        p=self.root/'CoolMalliOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        data=json.loads(p.read_text());data['pins'][0]['state']['revision']='0'*40;p.write_text(json.dumps(data))
        self.assert_manifest_failure('MOD-06: dependency lock')

    def test_dependency_lock_missing(self):
        (self.root/'CoolMalliOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').unlink()
        self.assert_manifest_failure('MOD-06: dependency lock missing')

    def test_real_manifest_unknown_target(self):
        p=self.root/'Packages/MallKit/Package.swift';s=p.read_text();p.write_text(s.replace('targets: [\n        .target', 'targets: [\n        .target(name: "Hidden"),\n        .target',1))
        self.assert_manifest_failure('MOD-01: target set mismatch')

    def test_real_manifest_external_package(self):
        p=self.root/'Packages/MallKit/Package.swift';s=p.read_text();p.write_text(s.replace('https://github.com/kean/Nuke.git', 'https://example.invalid/Nuke.git',1))
        self.assert_manifest_failure('MOD-06: external packages')

    def assert_manifest_failure(self, diagnostic):
        run=subprocess.run(['python3',str(ROOT/'Scripts/check-boundaries.py'),'--root',str(self.root)],capture_output=True,text=True)
        self.assertEqual(run.returncode,1,run.stdout+run.stderr)
        self.assertIn(diagnostic,run.stderr)

if __name__ == '__main__': unittest.main()
