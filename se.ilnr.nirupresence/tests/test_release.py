import importlib.util,json,unittest
from pathlib import Path
class ReleaseTests(unittest.TestCase):
 def test_manifest_helper_and_entrypoint_versions_agree(self):
  root=Path(__file__).resolve().parents[1];m=json.loads((root/'manifest.json').read_text())
  version=m['version'];p=root/'versions'/version/'nirupresence.py'
  spec=importlib.util.spec_from_file_location('release_helper',p);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
  self.assertEqual(mod.VERSION,version);self.assertIn(version,mod.UA)
  for entry in m['entryPoints'].values():self.assertTrue((root/entry).is_file());self.assertEqual(Path(entry).parts[1],version)
