#!/usr/bin/env python3
"""Compile real MallData exports against its internal DTO from a temporary App copy."""
from pathlib import Path
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
logs = ROOT / '.build/verification' / ('compiler-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
logs.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='mall-compiler-') as directory:
    root = Path(directory)
    for name in ['CoolMalliOS', 'CoolMalliOSUITests', 'CoolMalliOS.xcodeproj', 'CoolMalliOS.xctestplan', 'Packages']:
        src, dst = ROOT / name, root / name
        if src.is_dir(): shutil.copytree(src, dst, ignore=shutil.ignore_patterns('.build', 'xcuserdata'))
        else: shutil.copy2(src, dst)
    path = root / 'CoolMalliOS/AppDependencies.swift'
    original = path.read_text()
    command = ['xcodebuild', 'build', '-project', str(root / 'CoolMalliOS.xcodeproj'), '-scheme', 'CoolMalliOS', '-configuration', 'Debug', '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', str(root / 'DerivedData'), 'CODE_SIGNING_ALLOWED=NO']
    for name, code, success in [('public-control', '\nprivate let boundaryProbe = MallData.FixtureProductService.self\n', True), ('internal-dto', '\nprivate let boundaryProbe = MallData.FixtureProductDTO.self\n', False)]:
        path.write_text(original + code)
        with (logs / f'{name}.log').open('w') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        output = (logs / f'{name}.log').read_text()
        if success:
            if result.returncode != 0 or '** BUILD SUCCEEDED **' not in output:
                raise RuntimeError(f'Normal control failed; see {logs / (name + ".log")}')
        else:
            if result.returncode == 0 or "module 'MallData' has no member named 'FixtureProductDTO'" not in output:
                raise RuntimeError(f'Wrong failure reason; see {logs / (name + ".log")}')
        print(f'PASS: compiler {name}; exit={result.returncode}; log={logs / (name + ".log")}')
