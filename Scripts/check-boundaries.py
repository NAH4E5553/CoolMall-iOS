#!/usr/bin/env python3
"""Check the SwiftPM manifest graph. Not a Swift source or Xcode project checker."""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time


class BoundaryError(ValueError):
    pass


def format_output(label, value, limit=6000, tail=True):
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")
    value = value or ""
    start = max(0, len(value) - limit) if tail else 0
    end = min(len(value), start + limit)
    return (f"{label}: chars={len(value)} kept=[{start},{end}) "
            f"truncated={str(end - start < len(value)).lower()}\n{value[start:end]}")


def format_stream_output(label, stream, limit, tail):
    # Count bytes without reading an unbounded sample file into memory.
    size = os.fstat(stream.fileno()).st_size
    start = max(0, size - limit) if tail else 0
    end = min(size, start + limit)
    stream.seek(start)
    value = stream.read(end - start).decode("utf-8", errors="replace")
    return (f"{label}: bytes={size} kept=[{start},{end}) "
            f"truncated={str(end - start < size).lower()}\n{value}")


def command_process_rows(value, root_pid, partial=False):
    if isinstance(value, bytes):
        value = value.decode("utf-8", errors="replace")
    rows = {}
    for line in (value or "").splitlines(keepends=True):
        if partial and not line.endswith("\n"):
            continue
        line = line.rstrip("\r\n")
        fields = line.split(None, 6)
        if len(fields) == 7 and fields[0].isdigit() and fields[1].isdigit():
            rows[int(fields[0])] = (int(fields[1]), line)
    depths = {root_pid: 0}
    while True:
        added = {pid: depths[parent] + 1 for pid, (parent, _) in rows.items()
                 if parent in depths and pid not in depths}
        if not added:
            break
        depths.update(added)
    return {pid: rows[pid][1] for pid in rows if pid in depths}, depths


class ManifestSample:
    """Own only the diagnostic subprocess; never wait beyond the command deadline."""
    def __init__(self, root_pid):
        self.root_pid = root_pid
        self.process = None
        self.stdout = self.stderr = None
        self.deadline = None

    def start(self, command_deadline):
        print("dump-package: pre-deadline process sample (50s)", file=sys.stderr, flush=True)
        try:
            if time.monotonic() >= command_deadline:
                print("dump-package: sample state=unavailable; command deadline reached", file=sys.stderr, flush=True)
                return
            result = subprocess.run(
                ["/bin/ps", "-axo", "pid=,ppid=,state=,etime=,pcpu=,wchan=,comm="],
                capture_output=True, text=True, timeout=min(2, max(0, command_deadline - time.monotonic())), check=True,
            )
            owned, depths = command_process_rows(result.stdout, self.root_pid)
            print(format_output("PID PPID STATE ELAPSED CPU WCHAN COMMAND",
                                "\n".join(owned.values()), tail=False), file=sys.stderr, flush=True)
            if not owned:
                print("dump-package: sample state=unavailable; no live command process observed", file=sys.stderr, flush=True)
                return
            if time.monotonic() >= command_deadline:
                print("dump-package: sample state=unavailable; command deadline reached", file=sys.stderr, flush=True)
                return
            pid = max(owned, key=lambda item: depths[item])
            self.stdout = tempfile.TemporaryFile()
            self.stderr = tempfile.TemporaryFile()
            self.process = subprocess.Popen(
                ["/usr/bin/sample", str(pid), "1", "10", "-file", "/dev/stdout"],
                stdout=self.stdout, stderr=self.stderr, text=True, start_new_session=True,
            )
            self.deadline = min(command_deadline, time.monotonic() + 3)
            print(f"dump-package: sample state=started target={pid} sampler={self.process.pid}", file=sys.stderr, flush=True)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"dump-package: sample state=unavailable: {error}", file=sys.stderr, flush=True)
            if isinstance(error, (subprocess.TimeoutExpired, subprocess.CalledProcessError)):
                owned, _ = command_process_rows(error.stdout, self.root_pid, partial=True)
                print("dump-package: ps snapshot incomplete; only attributable parsed rows retained; "
                      "unparsed/unattributed rows omitted", file=sys.stderr, flush=True)
                print(format_output("ps partial stdout (command tree only)", "\n".join(owned.values()), tail=False),
                      file=sys.stderr, flush=True)
                print(format_output("ps partial stderr", error.stderr), file=sys.stderr, flush=True)

    def finish(self, reason, command_deadline):
        if self.process is not None:
            process, self.process = self.process, None
            running = process.poll() is None
            try:
                # The diagnostic has its own session. Also close any helpers
                # left in that group after the sample leader has exited.
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            except OSError as error:
                print(f"dump-package: sample cancellation signal: {error}", file=sys.stderr, flush=True)
            try:
                process.wait(timeout=max(0, min(0.2, command_deadline - time.monotonic())))
                state = "interrupted" if running else "complete"
            except (OSError, subprocess.TimeoutExpired):
                state = "incomplete-unreaped"
            print(f"dump-package: sample state={state} reason={reason} sampler={process.pid} exit={process.returncode}",
                  file=sys.stderr, flush=True)
        for label, stream, limit, tail in [("stack stdout", self.stdout, 16000, False),
                                           ("stack stderr", self.stderr, 6000, True)]:
            if stream is not None:
                try:
                    print(format_stream_output(label, stream, limit, tail), file=sys.stderr, flush=True)
                except OSError as error:
                    print(f"dump-package: {label} state=unavailable: {error}", file=sys.stderr, flush=True)
                finally:
                    stream.close()
        self.stdout = self.stderr = None


def dump_manifest(package):
    command = ["xcrun", "swift", "package", "--package-path", str(package), "--verbose", "dump-package"]
    start = time.monotonic()
    print(f"dump-package: start timeout=60 command={json.dumps(command)}", file=sys.stderr, flush=True)
    sample = None
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
        deadline = time.monotonic() + 60
        try:
            try:
                stdout, stderr = process.communicate(timeout=50)
            except subprocess.TimeoutExpired:
                sample = ManifestSample(process.pid)
                sample.start(deadline)
                if sample.process is not None:
                    try:
                        stdout, stderr = process.communicate(timeout=max(0, min(deadline, sample.deadline) - time.monotonic()))
                    except subprocess.TimeoutExpired:
                        sample.finish("sample-window-ended", deadline)
                        stdout, stderr = process.communicate(timeout=max(0, deadline - time.monotonic()))
                else:
                    stdout, stderr = process.communicate(timeout=max(0, deadline - time.monotonic()))
            return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)
        except subprocess.TimeoutExpired as error:
            process.kill()
            # Match subprocess.run on POSIX: reap the direct command, but do not
            # wait for inherited stdout/stderr pipes held by a surviving child.
            process.wait()
            print(format_output("dump-package partial stdout", error.stdout), file=sys.stderr, flush=True)
            print(format_output("dump-package partial stderr", error.stderr), file=sys.stderr, flush=True)
            raise subprocess.TimeoutExpired(command, 60, output=error.stdout, stderr=error.stderr) from None
        except BaseException:
            process.kill()
            raise
        finally:
            if sample is not None:
                sample.finish("command-finished", deadline)
            print(f"dump-package: finished elapsed={time.monotonic() - start:.3f}s", file=sys.stderr, flush=True)


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
    require(set(policy) == {"schemaVersion", "package", "targets", "tests", "externalPackages"}, "MOD-01: unknown policy fields")
    require(policy.get("schemaVersion") == 1, "MOD-01: unsupported policy schema")
    require(isinstance(policy.get("package"), str) and policy["package"], "MOD-01: missing package name")
    for group in ("targets", "tests"):
        require(isinstance(policy.get(group), dict) and policy[group], f"MOD-01: missing {group}")
        for name, deps in policy[group].items():
            require(isinstance(name, str) and name.isidentifier(), "MOD-01: invalid target name")
            require(isinstance(deps, list) and all(isinstance(d, str) for d in deps), "MOD-01: invalid dependencies")
            require(len(deps) == len(set(deps)), f"MOD-01: duplicate policy dependencies: {name}")
    require(not (policy["targets"].keys() & policy["tests"].keys()), "MOD-01: test/production name collision")
    packages = policy["externalPackages"]
    require(isinstance(packages, dict), "MOD-06: invalid external packages policy")
    external = set()
    for identity, package in packages.items():
        require(isinstance(identity, str) and identity == identity.lower(), "MOD-06: invalid package identity")
        require(set(package) == {"url", "version", "products", "revision"}, "MOD-06: invalid external package fields")
        require(isinstance(package["url"], str) and package["url"].startswith("https://") and isinstance(package["version"], str), "MOD-06: invalid external package pin")
        require(isinstance(package["products"], list) and package["products"] and all(isinstance(x, str) for x in package["products"]), "MOD-06: invalid external products")
        require(not external.intersection(package["products"]) and len(set(package["products"])) == len(package["products"]), "MOD-06: duplicate external product")
        external.update(package["products"])
    require(not external.intersection(policy["targets"]), "MOD-06: external/local product collision")
    graph = {**policy["targets"], **policy["tests"], **{name: [] for name in external}}
    for name, deps in graph.items():
        require(set(deps) <= (policy["targets"].keys() | external), f"MOD-01: {name} has unknown/test dependency in policy")
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


def dependency_name(dependency, policy=None):
    require(isinstance(dependency, dict) and len(dependency) == 1, "MOD-01: unrecognized dependency encoding")
    kind, value = next(iter(dependency.items()))
    if kind == "product":
        require(isinstance(value, list) and len(value) == 4 and value[2:] == [None, None], "MOD-06: conditional/unknown external product")
        package = (policy or {}).get("externalPackages", {}).get(str(value[1]).lower())
        require(package is not None and value[0] in package["products"], "MOD-06: external product is not approved")
        return value[0]
    require(kind in ("byName", "target"), "MOD-06: external product/unknown dependency requires policy support")
    require(isinstance(value, list) and len(value) == 2 and isinstance(value[0], str), "MOD-01: unsupported dependency shape")
    require(value[1] is None, "MOD-06: conditional dependency requires explicit review and checker support")
    require(value[0] not in {product for p in (policy or {}).get("externalPackages", {}).values() for product in p["products"]}, "MOD-06: external product requires explicit package mapping")
    return value[0]


def validate_manifest(manifest, policy):
    require(manifest.get("name") == policy["package"], "MOD-01: wrong package name")
    require(manifest.get("platforms") == [{"options": [], "platformName": "ios", "version": "17.0"}], "MOD-06: Package deployment baseline must be iOS 17")
    require(manifest.get("swiftLanguageVersions") == ["6"], "MOD-06: Package language mode must be Swift 6")
    expected_packages = [
        {"sourceControl": [{"identity": identity, "location": {"remote": [{"urlString": package["url"]}]}, "productFilter": None, "requirement": {"exact": [package["version"]]}, "traits": [{"name": "default"}]}]}
        for identity, package in policy["externalPackages"].items()
    ]
    require(manifest.get("dependencies") == expected_packages, "MOD-06: external packages URL/version/shape not approved")
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
        names = [dependency_name(d, policy) for d in dependencies]
        require(len(names) == len(set(names)), f"MOD-01: duplicate dependencies: {name}")
        require(set(names) == set(expected[name]), f"MOD-01: forbidden/missing dependency for {name}: actual={names}, expected={expected[name]}")
        graph[name] = names
        resources = target.get("resources", [])
        require(isinstance(resources, list), f"MOD-03: invalid resources: {name}")
        for resource in resources:
            path = Path(resource["path"])
            require(not path.is_absolute() and ".." not in path.parts, f"MOD-03: resource escapes target: {name}")
    graph.update({product: [] for package in policy["externalPackages"].values() for product in package["products"]})
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
        result = dump_manifest(package)
        require(result.returncode == 0, "MOD-01: dump-package failed:\n" + format_output("dump-package stderr", result.stderr))
        validate_manifest(json.loads(result.stdout), policy)
        lock_path = args.root / "CoolMalliOS.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        require(lock_path.is_file(), "MOD-06: dependency lock missing")
        lock = json.loads(lock_path.read_text())
        expected_pins = [{"identity": identity, "kind": "remoteSourceControl", "location": p["url"], "state": {"revision": p["revision"], "version": p["version"]}} for identity,p in policy["externalPackages"].items()]
        require(lock.get("version") == 3 and lock.get("pins") == expected_pins, "MOD-06: dependency lock version/revision/product mismatch")
    except (BoundaryError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    print("PASS: SwiftPM manifest graph only; source imports, Xcode membership and runtime behavior are separate gates.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
