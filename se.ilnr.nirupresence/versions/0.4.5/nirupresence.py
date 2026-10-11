#!/usr/bin/env python3
"""Small, dependency-free client for n.rudolfsson.net Presence API."""
from __future__ import annotations
import contextlib, fcntl, tempfile, stat
import json, os, shutil, subprocess, sys, time, urllib.error, urllib.parse, urllib.request
from pathlib import Path

VERSION="0.4.5"
BASE_DEFAULT="https://n.rudolfsson.net"
CONFIG_DIR=Path.home()/".config/nirupresence"
STATE_DIR=Path.home()/".local/state/nirupresence"
CONFIG=CONFIG_DIR/"config.json"
STATE=STATE_DIR/"state.json"
UA=f"NIRUPRESENCE-Omarchy/{VERSION}"

def emit(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False, separators=(",",":")))
    raise SystemExit(code)

def read_json(path, default):
    try:
        value=json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value,dict) else default
    except Exception: return default

@contextlib.contextmanager
def locked(path):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd=os.open(path,os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode): raise RuntimeError("Ogiltig låsfil")
        os.fchmod(fd,0o600)
        fcntl.flock(fd,fcntl.LOCK_EX)
        yield
    finally: os.close(fd)

def atomic_write(path, data, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink(): raise RuntimeError("Symbolisk konfigurationsfil stöds inte")
    fd,tmp=tempfile.mkstemp(prefix="."+path.name+"-",dir=path.parent)
    try:
        os.fchmod(fd,mode)
        with os.fdopen(fd,"w",encoding="utf-8") as f:
            json.dump(data,f,ensure_ascii=False,indent=2);f.write("\n");f.flush();os.fsync(f.fileno())
        os.replace(tmp,path)
    finally:
        Path(tmp).unlink(missing_ok=True)

def config():
    c=read_json(CONFIG,{})
    return {"base_url":str(c.get("base_url") or BASE_DEFAULT).rstrip("/"),"token":str(c.get("token") or "").strip(),"navidrome":c.get("navidrome") if isinstance(c.get("navidrome"),dict) else {}}

def state():
    s=read_json(STATE,{})
    return {"manual_offline":bool(s.get("manual_offline",False)),"share_music":bool(s.get("share_music",True)),"session_started":int(s.get("session_started") or 0),"last_track_key":str(s.get("last_track_key") or ""),"last_music_sent":int(s.get("last_music_sent") or 0),"night_date":str(s.get("night_date") or ""),"wake_date":str(s.get("wake_date") or ""),"force_wake_date":str(s.get("force_wake_date") or ""),"micro_draft":str(s.get("micro_draft") or "")[:1000],"temp_until":int(s.get("temp_until") or 0),"temp_previous_status":str(s.get("temp_previous_status") or ""),"temp_previous_detail":str(s.get("temp_previous_detail") or "")}

def save_state(patch):
    with locked(STATE_DIR/"state.lock"):
        s=read_json(STATE,{})
        s.update(patch); atomic_write(STATE,s); return s

def api(endpoint, method="GET", payload=None, public=False):
    c=config()
    if public:
        url=c["base_url"]+"/?r=presence-json"
    else:
        if not c["token"]: raise RuntimeError("API-token saknas. Kör configure-kommandot först.")
        url=c["base_url"]+"/?"+urllib.parse.urlencode({"r":"api","endpoint":endpoint})
    headers={"Accept":"application/json","User-Agent":UA}
    if not public: headers["Authorization"]="Bearer "+c["token"]
    body=None
    if payload is not None:
        body=json.dumps(payload,ensure_ascii=False).encode("utf-8"); headers["Content-Type"]="application/json"
    req=urllib.request.Request(url,data=body,headers=headers,method=method)
    try:
        with urllib.request.urlopen(req,timeout=10) as res: raw=res.read(262144).decode("utf-8","replace")
    except urllib.error.HTTPError as e:
        raw=e.read(8192).decode("utf-8","replace")
        try: msg=json.loads(raw).get("error")
        except Exception: msg=None
        raise RuntimeError(msg or f"HTTP {e.code}")
    except urllib.error.URLError as e: raise RuntimeError("Webbplatsen kunde inte nås") from e
    try: result=json.loads(raw or "{}")
    except Exception as e: raise RuntimeError("Servern returnerade ogiltigt JSON") from e
    if isinstance(result,dict) and result.get("error"): raise RuntimeError(str(result["error"]))
    return result

def _run_playerctl(exe, player, *args, timeout=3):
    p=subprocess.run([exe,"-p",player,*args],capture_output=True,text=True,timeout=timeout)
    return p.stdout.strip()

def _clean_bandcamp(artist, title, url):
    """Return normalized Bandcamp metadata, or None for ordinary browser media."""
    raw=title.strip()
    low_url=(url or "").lower()
    url_bandcamp="bandcamp.com" in low_url
    bandcamp_shape=raw.startswith(("▶", "▷", "►")) and " | " in raw
    if not (url_bandcamp or bandcamp_shape):
        return None
    raw=raw.lstrip("▶︎▷► ").strip()
    if not artist and " | " in raw:
        track, maybe_artist=raw.rsplit(" | ",1)
        if track.strip() and maybe_artist.strip():
            artist=maybe_artist.strip().title() if maybe_artist.isupper() else maybe_artist.strip()
            raw=track.strip()
    return artist, raw

def _navidrome_stream_id(*values):
    """Return a Subsonic track id from known stream URL/title shapes, otherwise None."""
    for value in values:
        raw=str(value or "").strip()
        if not raw:
            continue
        # playerctl/mpv may expose either a complete URL or e.g.
        # ``stream.view?...`` / ``stream?...`` as xesam:title.
        candidate=raw if "://" in raw else "https://nirupresence.invalid/"+raw.lstrip("/")
        try:
            parsed=urllib.parse.urlparse(candidate)
            path=(parsed.path or "").lower().rstrip("/")
            leaf=path.rsplit("/",1)[-1]
            if leaf not in ("stream","stream.view"):
                continue
            track_ids=urllib.parse.parse_qs(parsed.query,keep_blank_values=False).get("id",[])
            if track_ids and str(track_ids[0]).strip():
                return str(track_ids[0]).strip()
        except Exception:
            continue
    return None

def _safe_media_url(url):
    """Keep useful source identity without leaking Subsonic auth query parameters."""
    raw=str(url or "").strip()
    if not raw:
        return ""
    try:
        parsed=urllib.parse.urlparse(raw)
        if parsed.scheme and parsed.netloc:
            return urllib.parse.urlunparse((parsed.scheme,parsed.netloc,parsed.path,"","",""))[:500]
    except Exception:
        pass
    return ""

def _navidrome_song(track_id, stream_url):
    """Resolve Navidrome/OpenSubsonic track metadata for an mpv stream."""
    c=config(); n=c.get("navidrome") or {}
    username=str(n.get("username") or "").strip(); password=str(n.get("password") or "")
    if not username or not password: return None
    configured_base=str(n.get("base_url") or "").rstrip("/")
    parsed=urllib.parse.urlparse(stream_url or "")
    base=configured_base or ((parsed.scheme+"://"+parsed.netloc) if parsed.scheme and parsed.netloc else "")
    if not base: return None
    import hashlib, secrets
    salt=secrets.token_hex(6)
    token=hashlib.md5((password+salt).encode("utf-8")).hexdigest()
    params={"u":username,"t":token,"s":salt,"v":"1.16.1","c":"nirupresence","f":"json","id":track_id}
    url=base+"/rest/getSong.view?"+urllib.parse.urlencode(params)
    req=urllib.request.Request(url,headers={"Accept":"application/json","User-Agent":UA})
    try:
        with urllib.request.urlopen(req,timeout=5) as res: data=json.loads(res.read(262144).decode("utf-8","replace"))
        root=data.get("subsonic-response",{})
        if root.get("status")!="ok": return None
        song=root.get("song") or {}
        return {"artist":str(song.get("artist") or "").strip(),"title":str(song.get("title") or "").strip(),"album":str(song.get("album") or "").strip()}
    except Exception:
        return None

def playerctl_metadata():
    exe=shutil.which("playerctl")
    if not exe: return {"available":False,"playing":False,"reason":"playerctl saknas"}
    try:
        players=subprocess.run([exe,"-l"],capture_output=True,text=True,timeout=3).stdout.splitlines()
    except Exception: players=[]
    playing=[]
    for order, player in enumerate(players):
        player=player.strip()
        if not player: continue
        try:
            st=_run_playerctl(exe,player,"status",timeout=2).lower()
            if st!="playing": continue
            fmt="{{artist}}|||NIRU|||{{title}}|||NIRU|||{{album}}"
            raw=_run_playerctl(exe,player,"metadata","--format",fmt,timeout=3)
            vals=(raw.split("|||NIRU|||")+["",""])[:3]
            artist,title,album=[x.strip() for x in vals]
            try: media_url=_run_playerctl(exe,player,"metadata","xesam:url",timeout=2)
            except Exception: media_url=""
            source=player.split(".",1)[0][:60]
            if source in ("chromium","chrome","helium","brave"):
                bandcamp=_clean_bandcamp(artist,title,media_url)
                if bandcamp is None:
                    # Browser media is private by default. Only Bandcamp is an allowed browser source.
                    continue
                artist,title=bandcamp
                source="bandcamp"
            navidrome=False; unresolved=False
            track_id=_navidrome_stream_id(title,media_url) if source=="mpv" else None
            if track_id:
                song=_navidrome_song(track_id,media_url)
                navidrome=True
                if song and song.get("title"):
                    artist=song.get("artist") or artist; title=song["title"]; album=song.get("album") or album
                else:
                    # Never expose a stream URL (which can contain auth material) as a title.
                    title="Okänd titel"; unresolved=True
            if not title: continue
            # NPLAY owns its mpv backend; prefer its richer MPRIS metadata.
            # Preserve standalone Spotify/mpv and Bandcamp fallbacks.
            priority={"nplay":0,"spotify":1,"spotifyd":1,"mpv":2,"bandcamp":3}.get(source,10)
            # Explicit radio classification only when metadata identifies a live SR stream.
            # Unknown NPLAY content stays music; do not guess podcasts from titles.
            media_type="radio" if source=="nplay" and album.casefold().startswith("sveriges radio") and "live" in album.casefold() else "music"
            playing.append((priority,order,{"media_type":media_type,"available":True,"playing":True,"artist":artist[:160],"title":title[:220],"album":album[:220],"source":source,"url":_safe_media_url(media_url),"navidrome":navidrome,"metadata_incomplete":unresolved}))
        except Exception: continue
    if playing:
        playing.sort(key=lambda x:(x[0],x[1]))
        return playing[0][2]
    return {"available":True,"playing":False}

def cmd_configure(args):
    if not args: raise RuntimeError("Ange API-token")
    token=args[0].strip(); base=(args[1].strip() if len(args)>1 else BASE_DEFAULT).rstrip("/")
    if not token.startswith("nru_"):
        raise RuntimeError("Fel typ av API-nyckel. Skapa nyckeln i n.rudolfsson.net Admin > API-nycklar. Den ska börja med nru_.")
    if len(token) != 52:
        raise RuntimeError("API-nyckeln har oväntad längd. Skapa en ny nyckel i webbadmin och kopiera hela värdet.")
    # Validate before replacing a working configuration.
    old = read_json(CONFIG,{})
    newcfg={"base_url":base,"token":token}
    if isinstance(old.get("navidrome"),dict): newcfg["navidrome"]=old["navidrome"]
    atomic_write(CONFIG,newcfg)
    try:
        check=api("presence/statuses")
    except Exception:
        if old:
            atomic_write(CONFIG,old)
        else:
            try: CONFIG.unlink()
            except FileNotFoundError: pass
        raise
    return {"ok":True,"configured":True,"base_url":base,"statuses":len(check.get("statuses",[]))}

def cmd_configure_navidrome(args):
    if len(args)<2: raise RuntimeError("Ange Navidrome-användarnamn och lösenord")
    username=args[0].strip(); password=args[1]
    base=(args[2].strip().rstrip("/") if len(args)>2 else "")
    if not username or not password: raise RuntimeError("Navidrome-användarnamn/lösenord saknas")
    c=read_json(CONFIG,{})
    c["navidrome"]={"username":username,"password":password,"base_url":base}
    atomic_write(CONFIG,c)
    return {"ok":True,"navidrome":True,"username":username,"base_url":base or "auto från MPRIS"}

def cmd_api_test():
    c=config()
    if not c["token"]:
        raise RuntimeError("API-token saknas. Kör configure.fish.")
    result=api("presence/statuses")
    return {"ok":True,"api":True,"base_url":c["base_url"],"statuses":len(result.get("statuses",[]))}

def cmd_doctor():
    c=config(); s=state(); checks={}
    checks["configured"]=bool(c["token"])
    checks["token_format"]=bool(c["token"].startswith("nru_") and len(c["token"])==52)
    try:
        pub=api("",public=True); checks["website"]=True; checks["public_presence"]=isinstance(pub,dict)
    except Exception as e:
        checks["website"]=False; checks["website_error"]=str(e)
    if c["token"]:
        try:
            r=api("presence/statuses"); checks["api_auth"]=True; checks["statuses"]=len(r.get("statuses",[]))
        except Exception as e:
            checks["api_auth"]=False; checks["api_error"]=str(e)
    else:
        checks["api_auth"]=False
    checks["playerctl"]=bool(shutil.which("playerctl"))
    checks["navidrome_configured"]=bool(c.get("navidrome",{}).get("username") and c.get("navidrome",{}).get("password"))
    checks["manual_offline"]=s["manual_offline"]
    checks["share_music"]=s["share_music"]
    return {"ok":all(checks.get(k,False) for k in ("website","configured","token_format","api_auth")),"version":VERSION,"checks":checks}

def clock_policy():
    """Informational only. Server controls Europe/Stockholm night hours."""
    return {"server_owned": True, "night_window": "23:30–04:00 Europe/Stockholm"}


def apply_clock_policy():
    """Compatibility no-op: never overwrite shared server state on a timer."""
    return clock_policy()


def cmd_mode(mode):
    """Change shared server mode; only commit local state on confirmed success."""
    mode = str(mode).lower().strip()
    if mode not in ("auto", "online", "offline"):
        raise ValueError("Läge måste vara auto, online eller offline")
    result = api("presence/offline", "PUT", {"mode": mode})
    if not isinstance(result, dict) or result.get("ok") is not True:
        raise RuntimeError("Servern bekräftade inte närvaroläget")
    save_state({"manual_offline": mode == "offline", "session_started": 0 if mode == "offline" else state()["session_started"]})
    return result

def cmd_dashboard():
    c=config(); configured=bool(c["token"])
    if configured:
        try: expire_temp_status()
        except Exception: pass
    s=state()
    policy=clock_policy()
    pub={}
    try: pub=api("",public=True)
    except Exception: pass
    statuses=[]; api_ok=False; error=""
    if configured:
        try: statuses=api("presence/statuses").get("statuses",[]); api_ok=True
        except Exception as e: error=str(e)
    music=playerctl_metadata()
    return {"ok":True,"version":VERSION,"configured":configured,"api_ok":api_ok,"error":error,"statuses":statuses,"public":pub,"local":s,"player":music,"policy":policy}

def cmd_heartbeat():
    expire_temp_status()
    s = state()
    started = s["session_started"]
    if started < 1:
        started = int(time.time())
        save_state({"session_started": started})
    # Server decides whether Auto/Online/Offline and night policy allow public presence.
    # Heartbeat must never clear a manual global Offline selection.
    return api("presence/heartbeat", "PUT", {"session_started": started})


def cmd_offline(value):
    # Backwards-compatible CLI mapping. 'false' now means Auto, not forced Online.
    return cmd_mode("offline" if value.lower() in ("1", "true", "yes", "on", "offline") else "auto")


def cmd_wake():
    # Explicit night exception, without resetting status or music.
    return cmd_mode("online")

def cmd_status(args):
    status=args[0] if args else ""; detail=args[1] if len(args)>1 else ""
    result=confirmed(api("presence/status","PUT",{"status":status,"detail":detail}))
    save_state({"temp_until":0,"temp_previous_status":"","temp_previous_detail":""})
    return result

def confirmed(result):
    if not isinstance(result,dict) or result.get("ok") is not True:
        raise RuntimeError("Servern bekräftade inte åtgärden")
    return result

def expire_temp_status():
    """Server 0.7.23 owns expiry. Never restore another device's old status."""
    return False

def cmd_temp_status(args):
    if len(args)<2: raise RuntimeError("Ange status och minuter")
    status=args[0]; minutes=int(args[1]); detail=args[2] if len(args)>2 else ""
    if minutes not in (30,60,120): raise RuntimeError("Tillfällig status måste vara 30, 60 eller 120 minuter")
    result=confirmed(api("presence/temporary","PUT",{"status":status,"detail":detail,"minutes":minutes}))
    save_state({"temp_until":0,"temp_previous_status":"","temp_previous_detail":""})
    return result

def cmd_cancel_temp():
    result=confirmed(api("presence/temporary","DELETE"))
    save_state({"temp_until":0,"temp_previous_status":"","temp_previous_detail":""})
    return result

def cmd_draft(args):
    body=" ".join(args) if args else ""
    if len(body)>1000: raise RuntimeError("Utkast får vara högst 1000 tecken")
    save_state({"micro_draft":body})
    return {"ok":True,"draft":bool(body)}

def cmd_share_music(value):
    enabled=value.lower() in ("1","true","yes","on")
    if not enabled: confirmed(api("presence/nowplaying","PUT",{"sharing":False,"playing":False}))
    save_state({"share_music":enabled,"last_track_key":"","last_music_sent":0})
    return {"ok":True,"share_music":enabled}

def cmd_sync_music(force=False):
    s=state()
    if not s["share_music"]: return {"ok":True,"skipped":True,"share_music":False}
    m=playerctl_metadata()
    if not m.get("available"): return {"ok":True,"skipped":True,"warning":m.get("reason","MPRIS saknas")}
    key="stopped"
    payload={"sharing":True,"playing":False}
    if m.get("playing"):
        key="|".join(str(m.get(k,"")) for k in ("source","artist","title","album","media_type"))
        payload={"sharing":True,"playing":True,"artist":m.get("artist",""),"title":m.get("title",""),"album":m.get("album",""),"source":m.get("source",""),"media_type":m.get("media_type","music")}
    now=int(time.time())
    # Refresh playing state periodically so the website's 10-minute freshness window never lies.
    if not force and key=="stopped" and s["last_track_key"] in ("", "stopped"):
        return {"ok":True,"unchanged":True,"player":m}
    if not force and key==s["last_track_key"] and now-s["last_music_sent"]<240: return {"ok":True,"unchanged":True,"player":m}
    result=confirmed(api("presence/nowplaying","PUT",payload))
    save_state({"last_track_key":key,"last_music_sent":now})
    return {"ok":True,"sent":True,"player":m,"presence":result.get("presence",{})}

def cmd_microlog(args):
    body=" ".join(args).strip()
    if not body: raise RuntimeError("Microlog är tom")
    if len(body)>1000: raise RuntimeError("Microlog får vara högst 1000 tecken")
    result=api("microlog","POST",{"body":body})
    save_state({"micro_draft":""})
    return result

def main():
    cmd=sys.argv[1] if len(sys.argv)>1 else "dashboard"; args=sys.argv[2:]
    if cmd=="configure": result=cmd_configure(args)
    elif cmd=="dashboard": result=cmd_dashboard()
    elif cmd=="ping": result=api("presence/statuses")
    elif cmd=="api-test": result=cmd_api_test()
    elif cmd=="configure-navidrome": result=cmd_configure_navidrome(args)
    elif cmd=="doctor": result=cmd_doctor()
    elif cmd=="heartbeat": result=cmd_heartbeat()
    elif cmd=="mode": result=cmd_mode(args[0] if args else "auto")
    elif cmd=="offline": result=cmd_offline(args[0] if args else "true")
    elif cmd=="wake": result=cmd_wake()
    elif cmd=="status": result=cmd_status(args)
    elif cmd=="temp-status": result=cmd_temp_status(args)
    elif cmd=="cancel-temp": result=cmd_cancel_temp()
    elif cmd=="draft": result=cmd_draft(args)
    elif cmd=="share-music": result=cmd_share_music(args[0] if args else "true")
    elif cmd=="now-playing": result=playerctl_metadata()
    elif cmd=="sync-music": result=cmd_sync_music("--force" in args)
    elif cmd=="microlog": result=cmd_microlog(args)
    elif cmd=="public": result=api("",public=True)
    else: raise RuntimeError("Okänt kommando")
    emit(result)

if __name__=="__main__":
    try:
        with locked(STATE_DIR/"command.lock"): main()
    except Exception as e: emit({"error":str(e)},1)
