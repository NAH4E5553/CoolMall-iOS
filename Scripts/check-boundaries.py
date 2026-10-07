#!/usr/bin/env python3
"""Check the SwiftPM manifest graph. Not a Swift source or Xcode project checker."""

import argparse
import json
from pathlib import Path
import subprocess
import sys


class BoundaryError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise BoundaryError(message)


def read_policy(handbook):
    text = handbook.read_text(encoding="utf-8")
    exception_header = "| 例外 ID | 规则/范围 | 原因与替代验证 | 负责人/批准人 | 到期与撤销任务 |"
    require(text.count(exception_header) == 1, "MOD-06: exception registry missing/duplicated")
    exception_rows = text.split(exception_header)[1].split("\n\n", 1)[0].strip().splitlines()
    require(exception_rows == ["| --- | --- | --- | --- | --- |", "| 无 | 无 | 当前没有生效中的例外 | — | — |"], "MOD-06: active/unknown exceptions require explicit checker support; no automatic waiver")
    start = "<!-- boundary-policy:start -->"
    end = "<!-- boundary-policy:end -->"
    require(text.count(start) == text.count(end) == 1, "MOD-01: expected one policy block")
    block = text.split(start)[1].split(end)[0].strip()
    require(block.startswith("```json\n") and block.endswith("```"), "MOD-01: invalid policy fence")
    policy = json.loads(block[len("```json\n") : -3])
    require(set(policy) == {"schemaVersion", "package", "targets", "tests"}, "MOD-01: unknown policy fields")
    require(policy.get("schemaVersion") == 1, "MOD-01: unsupported policy schema")
    require(isinstance(policy.get("package"), str) and policy["package"], "MOD-01: missing package name")
    for group in ("targets", "tests"):
        require(isinstance(policy.get(group), dict) and policy[group], f"MOD-01: missing {group}")
        for name, deps in policy[group].items():
            require(isinstance(name, str) and name.isidentifier(), "MOD-01: invalid target name")
            require(isinstance(deps, list) and all(isinstance(d, str) for d in deps), "MOD-01: invalid dependencies")
            require(len(deps) == len(set(deps)), f"MOD-01: duplicate policy dependencies: {name}")
    require(not (policy["targets"].keys() & policy["tests"].keys()), "MOD-01: test/production name collision")
    graph = {**policy["targets"], **policy["tests"]}
    for name, deps in graph.items():
        require(set(deps) <= policy["targets"].keys(), f"MOD-01: {name} has unknown/test dependency in policy")
    check_cycles(graph)
    return policy


def check_cycles(graph):
    visiting, visited = set(), set()

    def visit(name):
        require(name not in visiting, f"MOD-01: dependency cycle at {name}")
        if name in visited:
            return
        visiting.add(name)
        for dependency in graph[name]:
            require(dependency in graph, f"MOD-01: unknown dependency {dependency}")
            visit(dependency)
        visiting.remove(name)
        visited.add(name)

    for name in graph:
        visit(name)


def dependency_name(dependency):
    require(isinstance(dependency, dict) and len(dependency) == 1, "MOD-01: unrecognized dependency encoding")
    kind, value = next(iter(dependency.items()))
    require(kind in ("byName", "target"), "MOD-06: external product/unknown dependency requires policy support")
    require(isinstance(value, list) and len(value) == 2 and isinstance(value[0], str), "MOD-01: unsupported dependency shape")
    require(value[1] is None, "MOD-06: conditional dependency requires explicit review and checker support")
    return value[0]


def validate_manifest(manifest, policy):
    require(manifest.get("name") == policy["package"], "MOD-01: wrong package name")
    require(manifest.get("platforms") == [{"options": [], "platformName": "ios", "version": "17.0"}], "MOD-06: Package deployment baseline must be iOS 17")
    require(manifest.get("swiftLanguageVersions") == ["6"], "MOD-06: Package language mode must be Swift 6")
    require(manifest.get("dependencies") == [], "MOD-06: external packages are not approved")
    require(not manifest.get("traits"), "MOD-06: package traits are not approved")
    targets = manifest.get("targets")
    require(isinstance(targets, list) and all(isinstance(t, dict) for t in targets), "MOD-01: targets missing or invalid")
    actual = {t.get("name"): t for t in targets}
    require(len(actual) == len(targets), "MOD-01: duplicate targets")
    expected = {**policy["targets"], **policy["tests"]}
    require(actual.keys() == expected.keys(), f"MOD-01: target set mismatch; missing={sorted(expected.keys()-actual.keys())}, extra={sorted(str(n) for n in actual.keys()-expected.keys())}")
    graph = {}
    for name, target in actual.items():
        expected_type = "regular" if name in policy["targets"] else "test"
        require(target.get("type") == expected_type, f"MOD-01: wrong target type: {name}")
        require(target.get("path") is None and target.get("sources") is None, f"MOD-03: custom source layout: {name}")
        require(not target.get("exclude"), f"MOD-03: excluded source paths: {name}")
        for key in ("settings", "pluginUsages", "providers", "pkgConfig", "publicHeadersPath", "url", "checksum"):
            require(not target.get(key), f"MOD-06: unapproved {key}: {name}")
        dependencies = target.get("dependencies")
        require(isinstance(dependencies, list), f"MOD-01: missing dependencies: {name}")
        names = [dependency_name(d) for d in dependencies]
        require(len(names) == len(set(names)), f"MOD-01: duplicate dependencies: {name}")
        require(set(names) == set(expected[name]), f"MOD-01: forbidden/missing dependency for {name}: actual={names}, expected={expected[name]}")
        graph[name] = names
        resources = target.get("resources", [])
        require(isinstance(resources, list), f"MOD-03: invalid resources: {name}")
        for resource in resources:
            path = Path(resource["path"])
            require(not path.is_absolute() and ".." not in path.parts, f"MOD-03: resource escapes target: {name}")
    check_cycles(graph)
    products = manifest.get("products")
    require(isinstance(products, list) and all(isinstance(p, dict) for p in products), "MOD-01: products missing or invalid")
    require(len(products) == len(policy["targets"]), "MOD-01: product count mismatch")
    require({p.get("name") for p in products} == policy["targets"].keys(), "MOD-01: product set mismatch")
    for product in products:
        require(product.get("targets") == [product["name"]], "MOD-01: each library product must expose its own target only")
        require(product.get("type") == {"library": ["automatic"]}, "MOD-01: unapproved library linkage/product type")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        policy = read_policy(args.root / "ENGINEERING.md")
        package = args.root / "Packages" / policy["package"]
        require((package / "Package.swift").is_file(), "MOD-01: Package.swift missing; F0 is incomplete (not a passing check)")
        result = subprocess.run(
            ["xcrun", "swift", "package", "--package-path", str(package), "dump-package"],
            capture_output=True, text=True, timeout=60, check=False,
        )
        require(result.returncode == 0, "MOD-01: dump-package failed:\n" + result.stderr[-6000:])
        validate_manifest(json.loads(result.stdout), policy)
    except (BoundaryError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: SwiftPM manifest graph only; source imports, Xcode membership and runtime behavior are separate gates.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
