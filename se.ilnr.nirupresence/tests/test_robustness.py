import importlib.util,json,multiprocessing,os,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
p=Path(__file__).resolve().parents[1]/'versions/0.4.4/nirupresence.py'
spec=importlib.util.spec_from_file_location('presence',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def writer(root,index):
 m.STATE_DIR=Path(root);m.STATE=m.STATE_DIR/'state.json'
 for n in range(30):m.save_state({'writer_'+str(index):n})
class Robustness(unittest.TestCase):
 def test_concurrent_state_transactions_preserve_every_update(self):
  with tempfile.TemporaryDirectory() as root:
   workers=[multiprocessing.get_context('fork').Process(target=writer,args=(root,i)) for i in range(6)]
   for w in workers:w.start()
   for w in workers:w.join(10);self.assertEqual(w.exitcode,0)
   target=Path(root)/'state.json';self.assertEqual(json.loads(target.read_text()),{'writer_'+str(i):29 for i in range(6)})
   self.assertEqual(target.stat().st_mode&0o777,0o600);self.assertFalse(list(Path(root).glob('*.tmp')))
 def test_temporary_status_uses_server_contract(self):
  with patch.object(m,'api',return_value={'ok':True}) as api,patch.object(m,'save_state'):
   m.cmd_temp_status(['Working','30','detail']);api.assert_called_once_with('presence/temporary','PUT',{'status':'Working','detail':'detail','minutes':30})
 def test_cancel_temporary_does_not_restore_old_status(self):
  with patch.object(m,'api',return_value={'ok':True}) as api,patch.object(m,'save_state'):
   m.cmd_cancel_temp();api.assert_called_once_with('presence/temporary','DELETE')
 def test_expiry_never_writes_shared_status(self):
  with patch.object(m,'api') as api:self.assertFalse(m.expire_temp_status());api.assert_not_called()
 def test_failed_status_does_not_clear_local_state(self):
  with patch.object(m,'api',return_value={'ok':False}),patch.object(m,'save_state') as save:
   with self.assertRaises(RuntimeError):m.cmd_status(['Working']);save.assert_not_called()
 def test_failed_music_disable_preserves_settings(self):
  with patch.object(m,'api',side_effect=RuntimeError('offline')),patch.object(m,'save_state') as save:
   with self.assertRaises(RuntimeError):m.cmd_share_music('false')
   save.assert_not_called()
 def test_state_updates_preserve_unknown_fields(self):
  with tempfile.TemporaryDirectory() as root,patch.object(m,'STATE_DIR',Path(root)),patch.object(m,'STATE',Path(root)/'state.json'):
   m.atomic_write(m.STATE,{'future_field':42});m.save_state({'share_music':False})
   self.assertEqual(json.loads(m.STATE.read_text())['future_field'],42)
 def test_symlink_write_refused(self):
  with tempfile.TemporaryDirectory() as root:
   target=Path(root)/'target';target.write_text('untouched');link=Path(root)/'link';link.symlink_to(target)
   with self.assertRaises(RuntimeError):m.atomic_write(link,{'token':'example'})
   self.assertEqual(target.read_text(),'untouched')
if __name__=='__main__':unittest.main()
