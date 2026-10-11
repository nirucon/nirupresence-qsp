#!/bin/sh
set -eu
umask 077
bundle=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
python3 - "$bundle" <<'PY'
import hashlib,json,os,pathlib,shutil,subprocess,sys,tempfile,time
bundle=pathlib.Path(sys.argv[1]);src=bundle/'se.ilnr.nirupresence';home=pathlib.Path.home();dest=home/'.config/omarchy/plugins/se.ilnr.nirupresence'
checks=json.loads((bundle/'checksums.json').read_text())
for name,digest in checks.items():
 path=pathlib.PurePosixPath(name)
 if path.is_absolute() or '..' in path.parts:raise SystemExit('Unsafe package path')
 p=bundle/path
 if p.is_symlink() or hashlib.sha256(p.read_bytes()).hexdigest()!=digest:raise SystemExit('Package checksum mismatch: '+name)
manifest=json.loads((src/'manifest.json').read_text())
if manifest.get('id')!='se.ilnr.nirupresence' or manifest.get('version')!='0.4.4':raise SystemExit('Unexpected manifest')
for ancestor in [dest,*dest.parents]:
 if ancestor==home:break
 if ancestor.is_symlink():raise SystemExit('Symlink installation path refused')
dest.parent.mkdir(parents=True,exist_ok=True)
safety=home/'.local/state/nirupresence/package-backups'/time.strftime('%Y-%m-%d_%H%M%S')
if safety.exists():raise SystemExit('Safety path already exists; retry in a second')
with tempfile.TemporaryDirectory(prefix='.nirupresence-stage-',dir=dest.parent) as t:
 stage=pathlib.Path(t)/'package';shutil.copytree(src,stage)
 dest.mkdir(exist_ok=True)
 for relative in ['versions/0.4.4','tests','README.md','VALIDATION.md','manifest.json']:
  p=stage/relative;target=dest/relative
  if any(a.is_symlink() for a in [target,*target.parents] if a!=home):raise SystemExit('Symlink target refused')
  if target.exists():
   saved=safety/relative;saved.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
   if target.is_dir():shutil.copytree(target,saved)
   else:shutil.copy2(target,saved)
  if p.is_dir():
   if target.exists():
    # Version/test files are published individually; unrelated existing files are retained.
    for f in p.rglob('*'):
     if f.is_file():
      out=target/f.relative_to(p);out.parent.mkdir(parents=True,exist_ok=True);os.replace(f,out)
   else:target.parent.mkdir(parents=True,exist_ok=True);os.replace(p,target)
  else:os.replace(p,target)
print('Installed NIRUPRESENCE 0.4.4; rollback files:',safety)
r=subprocess.run(['omarchy-shell','shell','rescanPlugins'],capture_output=True,text=True)
if r.returncode:print('Automatic shell rescan unavailable; run: omarchy-shell shell rescanPlugins')
else:print('Shell plugins rescanned.')
PY
