"""Exercise rejected manifest changes, including attempts to bypass the graph."""

import copy
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("boundaries", ROOT / "Scripts/check-boundaries.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class BoundariesTests(unittest.TestCase):
    def setUp(self):
        self.policy = CHECK.read_policy(ROOT / "ENGINEERING.md")
        self.manifest = {
            "name": self.policy["package"], "dependencies": [],
            "platforms": [{"options": [], "platformName": "ios", "version": "17.0"}],
            "swiftLanguageVersions": ["6"],
            "targets": [
                {"name": name, "type": kind, "dependencies": [{"byName": [d, None]} for d in deps]}
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


if __name__ == "__main__":
    unittest.main()
