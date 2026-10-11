import importlib.util, unittest
from unittest.mock import patch
from pathlib import Path
p=Path(__file__).resolve().parents[1]/"versions/0.4.4/nirupresence.py"
spec=importlib.util.spec_from_file_location("nirupresence_qs",p)
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
class ModeTests(unittest.TestCase):
 def test_modes(self):
  for mode in ("auto","online","offline"):
   with patch.object(mod,"api",return_value={"ok":True}) as api, patch.object(mod,"save_state") as save, patch.object(mod,"state",return_value={"session_started":123}):
    self.assertTrue(mod.cmd_mode(mode)["ok"])
    api.assert_called_once_with("presence/offline","PUT",{"mode":mode})
    self.assertEqual(save.call_args.args[0]["manual_offline"],mode=="offline")
 def test_failure_no_local_change(self):
  with patch.object(mod,"api",return_value={"ok":False}), patch.object(mod,"save_state") as save:
   with self.assertRaises(RuntimeError):mod.cmd_mode("offline")
   save.assert_not_called()
 def test_heartbeat_does_not_clear_mode(self):
  with patch.object(mod,"api",return_value={"ok":True}) as api, patch.object(mod,"state",return_value={"session_started":123,"manual_offline":True}),patch.object(mod,"expire_temp_status"):
   mod.cmd_heartbeat()
   api.assert_called_once_with("presence/heartbeat","PUT",{"session_started":123})
 def test_invalid_mode(self):
  with self.assertRaises(ValueError):mod.cmd_mode("invalid")
if __name__=="__main__":unittest.main()
