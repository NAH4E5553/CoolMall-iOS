#!/usr/bin/env python3
"""Fail-closed Xcode membership/configuration + SwiftSyntax source gate."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('manifest_gate', SCRIPT_ROOT / 'Scripts/check-boundaries.py')
manifest_gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manifest_gate)
require = manifest_gate.require


def read_source_policy(root):
    text = (root / 'ENGINEERING.md').read_text()
    start, end = '<!-- source-policy:start -->', '<!-- source-policy:end -->'
    require(text.count(start) == text.count(end) == 1, 'MOD-01: missing/duplicate source policy')
    block = text.split(start)[1].split(end)[0].strip()
    require(block.startswith('```json\n') and block.endswith('```'), 'MOD-01: malformed source policy')
    policy = json.loads(block[8:-3])
    require(policy.get('schemaVersion') == 1, 'MOD-01: unsupported source policy')
    require(set(policy) == {'schemaVersion', 'systemImports'}, 'MOD-01: unknown source policy field')
    require(all(isinstance(v, list) and all(isinstance(x, str) for x in v) for v in policy['systemImports'].values()), 'MOD-01: invalid system imports')
    return policy['systemImports']


def inventory(root, policy):
    jobs, paths, identities = [], set(), set()
    systems = read_source_policy(root)
    graph = {**policy['targets'], **policy['tests'], 'CoolMalliOS': list(policy['targets']), 'CoolMalliOSUITests': []}
    require(graph.keys() == systems.keys(), 'MOD-01: system import targets differ from graph')
    for target, deps in graph.items():
        is_test = target in policy['tests'] or target == 'CoolMalliOSUITests'
        if target in ('CoolMalliOS', 'CoolMalliOSUITests'):
            directory = root / target
        else:
            directory = root / 'Packages/MallKit' / ('Tests' if is_test else 'Sources') / target
        require(directory.is_dir(), f'MOD-03: missing source directory: {target}')
        swift = sorted(directory.rglob('*.swift'))
        require(swift, f'MOD-03: empty source target: {target}')
        for path in directory.rglob('*'):
            require(not path.is_symlink(), f'MOD-03: source/resource symlink: {path}')
        for path in swift:
            require(all(not p.is_symlink() for p in [directory, *directory.parents] if p != root.parent), 'MOD-03: symlink source directory')
            stat = path.stat()
            key = (stat.st_dev, stat.st_ino)
            require(key not in identities, f'MOD-03: shared/hardlinked source: {path}')
            identities.add(key)
            paths.add(path.relative_to(root).as_posix())
            jobs.append({'path': str(path), 'target': target, 'imports': systems[target] + deps,
                         'testable': deps if is_test else [], 'restricted': not is_test and target != 'MallData'})
    # Unknown source roots fail; build caches and this host-only compiler tool are explicit exclusions.
    allowed = paths | {'Packages/MallKit/Package.swift', 'Scripts/SourceBoundaries.swift'}
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in {'.git', '.build', 'DerivedData', '__pycache__'}]
        for d in dirs:
            require(not (Path(base) / d).is_symlink(), f'MOD-03: directory symlink: {Path(base)/d}')
        for file in files:
            p = Path(base) / file
            if file.endswith(('.swift', '.m', '.mm', '.c', '.h', '.cpp')):
                require(p.relative_to(root).as_posix() in allowed, f'MOD-03: unregistered source: {p}')
    return jobs, paths


def validate_project(root, policy, paths):
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(root / 'CoolMalliOS.xcodeproj/project.pbxproj')], capture_output=True, text=True, check=True)
    project = json.loads(result.stdout)
    objects = project['objects']
    supported = {'PBXProject', 'PBXGroup', 'PBXFileReference', 'PBXBuildFile', 'PBXNativeTarget', 'PBXSourcesBuildPhase', 'PBXFrameworksBuildPhase', 'PBXResourcesBuildPhase', 'PBXContainerItemProxy', 'PBXTargetDependency', 'XCBuildConfiguration', 'XCConfigurationList', 'XCLocalSwiftPackageReference', 'XCSwiftPackageProductDependency'}
    for obj in objects.values():
        require(obj.get('isa') in supported, f'MOD-06: unsupported Xcode object: {obj.get("isa")}')
        require(not obj.get('baseConfigurationReference'), 'MOD-06: external xcconfig requires review')
    main = objects[project['rootObject']]
    require(main['isa'] == 'PBXProject', 'MOD-03: invalid project root')
    require(main.get('projectDirPath') == main.get('projectRoot') == '', 'MOD-03: project root override')
    local = [o for o in objects.values() if o['isa'] == 'XCLocalSwiftPackageReference']
    require(len(local) == 1 and local[0]['relativePath'] == 'Packages/MallKit', 'MOD-06: package reference mismatch')
    require(len(main['packageReferences']) == 1 and objects[main['packageReferences'][0]] == local[0], 'MOD-06: package not registered')
    package_files = [i for i,o in objects.items() if o['isa'] == 'PBXFileReference' and o.get('lastKnownFileType') == 'wrapper']
    require(len(package_files) == 1, 'MOD-03: local Package file reference required for test discovery')
    package_file = objects[package_files[0]]
    require(package_file.get('path') == 'Packages/MallKit' and package_file.get('sourceTree') == 'SOURCE_ROOT', 'MOD-03: Package file reference mismatch')
    require(package_files[0] in objects[main['mainGroup']]['children'], 'MOD-03: Package missing from main group; tests may silently disappear')
    targets = {objects[i]['name']: objects[i] for i in main['targets']}
    require(set(targets) == {'CoolMalliOS', 'CoolMalliOSUITests'}, 'MOD-01: App target set mismatch')
    require(len([o for o in objects.values() if o['isa'] == 'PBXNativeTarget']) == 2, 'MOD-01: unregistered App target')
    allowed_settings = {'PRODUCT_NAME', 'PRODUCT_BUNDLE_IDENTIFIER', 'GENERATE_INFOPLIST_FILE', 'SWIFT_VERSION', 'IPHONEOS_DEPLOYMENT_TARGET', 'TARGETED_DEVICE_FAMILY', 'SDKROOT', 'SUPPORTED_PLATFORMS', 'CODE_SIGN_STYLE', 'SWIFT_STRICT_CONCURRENCY', 'SWIFT_OPTIMIZATION_LEVEL', 'INFOPLIST_KEY_UILaunchScreen_Generation', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation', 'INFOPLIST_KEY_CFBundleDisplayName', 'CURRENT_PROJECT_VERSION', 'MARKETING_VERSION', 'TEST_TARGET_NAME', 'CLANG_ENABLE_MODULES', 'DEBUG_INFORMATION_FORMAT', 'ENABLE_TESTABILITY', 'ONLY_ACTIVE_ARCH'}
    for owner in [main, *targets.values()]:
        configs = objects[owner['buildConfigurationList']]['buildConfigurations']
        require(len(configs) == 2 and {objects[i]['name'] for i in configs} == {'Debug', 'Release'}, 'MOD-06: configuration set mismatch')
        for cid in configs:
            config = objects[cid]
            settings = config['buildSettings']
            require(settings.get('ONLY_ACTIVE_ARCH') == ('YES' if config['name'] == 'Debug' else 'NO'), 'MOD-06: active architecture configuration changed')
            require(set(settings) <= allowed_settings, f'MOD-06: unknown/unsafe build settings: {set(settings)-allowed_settings}')
            require(settings.get('SWIFT_VERSION') == '6.0' and settings.get('IPHONEOS_DEPLOYMENT_TARGET') == '17.0', 'MOD-06: language/deployment baseline changed')
            if owner != main:
                require(settings.get('SWIFT_STRICT_CONCURRENCY') == 'complete', 'MOD-06: strict concurrency disabled')
                require(settings.get('SDKROOT') == 'iphoneos' and settings.get('SUPPORTED_PLATFORMS') == 'iphoneos iphonesimulator', 'MOD-06: SDK/platform baseline changed')
            else:
                require(settings.get('ENABLE_TESTABILITY') == ('YES' if config['name'] == 'Debug' else 'NO'), 'MOD-06: testability baseline changed')
    all_members = set()
    for name, target in targets.items():
        require(not target.get('buildRules'), 'MOD-06: custom build rules')
        require(target['productType'] == 'com.apple.product-type.' + ('application' if name == 'CoolMalliOS' else 'bundle.ui-testing'), 'MOD-01: product type mismatch')
        phases = [objects[i] for i in target['buildPhases']]
        require(len(phases) == 3 and {p['isa'] for p in phases} == {'PBXSourcesBuildPhase', 'PBXFrameworksBuildPhase', 'PBXResourcesBuildPhase'}, 'MOD-06: build phases mismatch')
        source = next(p for p in phases if p['isa'] == 'PBXSourcesBuildPhase')
        members = []
        for bid in source['files']:
            build = objects[bid]
            require(set(build) == {'isa', 'fileRef'}, 'MOD-06: source build options')
            ref = objects[build['fileRef']]
            require(ref['sourceTree'] == 'SOURCE_ROOT' and ref.get('lastKnownFileType') == 'sourcecode.swift', 'MOD-03: unsupported source reference')
            members.append(ref['path'])
        expected = {p for p in paths if p.startswith(name + '/')}
        require(len(members) == len(set(members)) and set(members) == expected, f'MOD-03: duplicate/missing/foreign source membership: {name}')
        require(not all_members.intersection(members), 'MOD-03: duplicate target membership')
        all_members.update(members)
        prodrefs = target.get('packageProductDependencies', [])
        products = [objects[i]['productName'] for i in prodrefs]
        expected_products = set(policy['targets']) if name == 'CoolMalliOS' else set()
        require(len(products) == len(set(products)) and set(products) == expected_products, f'MOD-01: App library dependencies: {name}')
        links = next(p for p in phases if p['isa'] == 'PBXFrameworksBuildPhase')['files']
        require(len(links) == len(prodrefs) and {objects[i].get('productRef') for i in links} == set(prodrefs), 'MOD-01: App link membership mismatch')
        for i in links:
            require(set(objects[i]) == {'isa', 'productRef'}, 'MOD-06: link options')
        require(next(p for p in phases if p['isa'] == 'PBXResourcesBuildPhase')['files'] == [], 'MOD-03: unexpected App resource membership')
    plan = json.loads((root / 'CoolMalliOS.xctestplan').read_text())
    require(plan['version'] == 1, 'MOD-01: unsupported Test Plan version')
    require(len(plan['configurations']) == 1 and plan['configurations'][0]['options'] == {}, 'MOD-01: unreviewed Test Plan configuration override')
    require(set(plan['defaultOptions']) == {'testTimeoutsEnabled', 'defaultTestExecutionTimeAllowance', 'maximumTestExecutionTimeAllowance'} and plan['defaultOptions']['testTimeoutsEnabled'] is True, 'MOD-01: unsupported Test Plan options')
    entries = plan['testTargets']
    expected_tests = set(policy['tests']) | {'CoolMalliOSUITests'}
    require(len(entries) == len(expected_tests) and {e['target']['name'] for e in entries} == expected_tests, 'MOD-01: Test Plan must include all registered tests')
    for entry in entries:
        require(not (set(entry)-{'target', 'parallelizable'}), 'MOD-01: disabled/selected/skipped tests are forbidden')
        name = entry['target']['name']
        expected_container = 'container:CoolMalliOS.xcodeproj' if name == 'CoolMalliOSUITests' else 'container:Packages/MallKit'
        require(entry['target']['containerPath'] == expected_container, 'MOD-03: Test Plan container mismatch')
        expected_id = next(i for i,o in objects.items() if o == targets[name]) if name == 'CoolMalliOSUITests' else name
        require(entry['target']['identifier'] == expected_id, 'MOD-01: Test Plan target identifier mismatch')
    scheme = ET.parse(root / 'CoolMalliOS.xcodeproj/xcshareddata/xcschemes/CoolMalliOS.xcscheme')
    plans = scheme.findall('.//TestPlanReference')
    require(len(plans) == 1 and plans[0].get('reference') == 'container:CoolMalliOS.xctestplan', 'MOD-01: shared Scheme Test Plan mismatch')


def check(root, binary):
    root = root.resolve()
    policy = manifest_gate.read_policy(root / 'ENGINEERING.md')
    jobs, paths = inventory(root, policy)
    validate_project(root, policy, paths)
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json') as f:
        json.dump(jobs, f); f.flush()
        result = subprocess.run([str(binary), f.name], text=True, capture_output=True)
        require(result.returncode == 0, result.stdout + result.stderr)
        print(result.stdout.strip())
    print('PASS: Xcode membership/link/settings/shared test registration')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=SCRIPT_ROOT)
    parser.add_argument('--binary', type=Path, default=SCRIPT_ROOT / '.build/governance/source-boundaries')
    args = parser.parse_args()
    try:
        check(args.root.resolve(), args.binary.resolve())
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError, ET.ParseError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    sys.exit(main())
