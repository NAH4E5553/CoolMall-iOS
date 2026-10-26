import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'Scripts/split-test-shards.py'


class TestShardTests(unittest.TestCase):
    def test_disjoint_union_and_duplicate_rejection(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            source = root / 'expected.txt'
            source.write_text('CatalogFeatureTests/A()\nCoolMalliOSUITests/Home/a()\n')
            result = subprocess.run([sys.executable, str(SCRIPT), '--expected', str(source),
                                     '--out-dir', str(root / 'out')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            ui = (root / 'out/expected-ui.txt').read_text().splitlines()
            nonui = (root / 'out/expected-nonui.txt').read_text().splitlines()
            self.assertEqual(ui, ['CoolMalliOSUITests/Home/a()'])
            self.assertEqual(nonui, ['CatalogFeatureTests/A()'])
            source.write_text('CatalogFeatureTests/A()\nCatalogFeatureTests/A()\n')
            result = subprocess.run([sys.executable, str(SCRIPT), '--expected', str(source),
                                     '--out-dir', str(root / 'out2')], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
