#!/usr/bin/env python3
"""labkit-agent: lets the RHCSA study site drive the lab kit on your lab host.

It is a small, dependency-free (Python 3.8+ stdlib only) HTTP + WebSocket server that:
  * runs the kit's fixed commands: ./lab start|reset|check|stop NN   (nothing else, no free-form exec)
  * opens a root shell in a lab (./lab shell NN) over a WebSocket, shown in the browser with xterm.js
  * stores your notes as Markdown files in a git repo and commits/pushes them
  * serves a local copy of the site (docs/) so you can use it without GitHub Pages

Security model (read agent/README.md):
  * listens on 127.0.0.1 only; reach it from other machines through `tailscale serve` (HTTPS, tailnet only)
  * every API call and terminal needs the bearer token from `labkit-agent.py init`
  * browser Origins are allow-listed (GitHub Pages site, localhost, the agent's own host)

    python3 agent/labkit-agent.py init      # create config + token, init the notes repo
    python3 agent/labkit-agent.py serve     # run it (or install the systemd user unit)
    python3 agent/labkit-agent.py token     # print the token again
"""
import base64
import fcntl
import hashlib
import hmac
import http.server
import json
import mimetypes
import os
import pathlib
import pty
import re
import secrets
import select
import shutil
import signal
import socket
import socketserver
import struct
import subprocess
import sys
import termios
import threading
import time
import urllib.parse

VERSION = "1.0"
KIT = pathlib.Path(__file__).resolve().parent.parent
CONF_DIR = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config")) / "labkit-agent"
CONF_FILE = CONF_DIR / "config.json"
DEFAULT_ORIGINS = ["https://braden-develops.github.io"]

LAB_ID = re.compile(r"^\d\d$")
NOTE_KEY = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
ACTIONS = {"start", "reset", "check", "stop"}
MUTATING = {"start", "reset", "stop"}
MAX_NOTE = 1_000_000


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


# --------------------------------------------------------------------------- config
def load_conf():
    if not CONF_FILE.exists():
        sys.exit(f"no config at {CONF_FILE}; run: {sys.argv[0]} init")
    c = json.loads(CONF_FILE.read_text())
    c.setdefault("port", 8737)
    c.setdefault("bind", "127.0.0.1")
    c.setdefault("notes_dir", str(pathlib.Path.home() / "rhcsa-notes"))
    c.setdefault("allowed_origins", DEFAULT_ORIGINS)
    c.setdefault("serve_site", True)
    return c


def cmd_init():
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(CONF_DIR, 0o700)
    c = json.loads(CONF_FILE.read_text()) if CONF_FILE.exists() else {}
    c.setdefault("token", secrets.token_urlsafe(32))
    c.setdefault("port", 8737)
    c.setdefault("bind", "127.0.0.1")
    c.setdefault("notes_dir", str(pathlib.Path.home() / "rhcsa-notes"))
    c.setdefault("allowed_origins", DEFAULT_ORIGINS)
    CONF_FILE.write_text(json.dumps(c, indent=2) + "\n")
    os.chmod(CONF_FILE, 0o600)
    nd = pathlib.Path(c["notes_dir"])
    nd.mkdir(parents=True, exist_ok=True)
    if not (nd / ".git").exists():
        subprocess.run(["git", "init", "-q", "-b", "main", str(nd)], check=True)
        (nd / "README.md").write_text("# RHCSA notes\n\nWritten in the RHCSA Study Kit site, committed by labkit-agent.\n")
        git(nd, "add", "-A")
        git(nd, "commit", "-q", "-m", "Start RHCSA notes")
    print(f"config: {CONF_FILE}\nnotes:  {nd}\ntoken:  {c['token']}")
    print("\nPaste the token into the site's Lab host settings. To back notes up, add a private remote:")
    print(f"  git -C {nd} remote add origin git@github.com:<you>/rhcsa-notes.git && git -C {nd} push -u origin main")


# --------------------------------------------------------------------------- labs
def lab_dir(lab):
    if not LAB_ID.match(lab or ""):
        return None
    m = sorted((KIT / "labs").glob(lab + "-*"))
    return m[0] if m and m[0].is_dir() else None


def lab_runtime(d):
    m = re.search(r'^RUNTIME=(\w+)', (d / "lab.conf").read_text(), re.M)
    return m.group(1) if m else "container"


def engine():
    if os.environ.get("ENGINE"):
        return os.environ["ENGINE"]
    return "podman" if shutil.which("podman") else "docker"


_status_cache = {"t": 0, "v": None}


def lab_status(state):
    """Which lab containers exist and whether the VM is up. Cached for 5 s (vagrant status is slow)."""
    if time.time() - _status_cache["t"] < 5 and _status_cache["v"]:
        return _status_cache["v"]
    running = []
    try:
        out = subprocess.run([engine(), "ps", "--format", "{{.Names}}"], capture_output=True, text=True, timeout=15).stdout
        running = sorted(n[len("rhcsa-"):][:2] for n in out.split() if n.startswith("rhcsa-"))
    except Exception:
        pass
    vm = "unknown"
    if shutil.which("vagrant"):
        try:
            out = subprocess.run(["vagrant", "status", "--machine-readable"], cwd=KIT / "vm",
                                 capture_output=True, text=True, timeout=60).stdout
            m = re.search(r",state,([\w-]+)", out)
            vm = m.group(1) if m else "not_created"
        except Exception:
            pass
    else:
        vm = "no_vagrant"
    v = {"containers": running, "vm": vm, "vm_lab": state.get("vm_lab")}
    _status_cache.update(t=time.time(), v=v)
    return v


# --------------------------------------------------------------------------- jobs
class Job:
    def __init__(self, jid, lab, action):
        self.id, self.lab, self.action = jid, lab, action
        self.buf, self.rc, self.started = bytearray(), None, time.time()
        self.proc = None


JOBS = {}
JOB_LOCK = threading.Lock()
BUSY = {"job": None}
STATE_FILE = CONF_DIR / "state.json"


def read_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {}


def write_state(s):
    try:
        STATE_FILE.write_text(json.dumps(s))
    except Exception:
        pass


def run_job(job):
    env = dict(os.environ, TERM="dumb", NO_COLOR="1")
    try:
        job.proc = subprocess.Popen(["./lab", job.action, job.lab], cwd=KIT, env=env, stdin=subprocess.DEVNULL,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True)
        for chunk in iter(lambda: job.proc.stdout.read1(4096), b""):
            job.buf.extend(chunk)
            if len(job.buf) > 2_000_000:
                del job.buf[:500_000]
        job.rc = job.proc.wait()
    except Exception as e:
        job.buf.extend(f"\nagent: {e}\n".encode())
        job.rc = 127
    finally:
        _status_cache["t"] = 0
        if job.action in ("start", "reset") and job.rc == 0 and lab_runtime(lab_dir(job.lab)) == "vm":
            s = read_state(); s["vm_lab"] = job.lab; write_state(s)
        with JOB_LOCK:
            if BUSY["job"] is job:
                BUSY["job"] = None
        log(f"job {job.id} {job.action} {job.lab} -> rc {job.rc}")


def start_job(lab, action):
    with JOB_LOCK:
        if action in MUTATING:
            if BUSY["job"]:
                b = BUSY["job"]
                return None, f"busy: {b.action} {b.lab} is still running"
        jid = secrets.token_hex(6)
        job = Job(jid, lab, action)
        JOBS[jid] = job
        if action in MUTATING:
            BUSY["job"] = job
        # forget old finished jobs
        for k in [k for k, j in JOBS.items() if j.rc is not None and time.time() - j.started > 3600]:
            JOBS.pop(k, None)
    threading.Thread(target=run_job, args=(job,), daemon=True).start()
    log(f"job {jid} {action} {lab}")
    return job, None


# --------------------------------------------------------------------------- notes
class Notes:
    def __init__(self, d):
        self.dir = pathlib.Path(d)
        self.lock = threading.Lock()
        self.timer = None

    def path(self, key):
        return self.dir / (key + ".md")

    def list(self):
        out = {}
        for p in self.dir.glob("*.md"):
            if p.stem != "README" and NOTE_KEY.match(p.stem):
                out[p.stem] = int(p.stat().st_mtime * 1000)
        return out

    def get(self, key):
        p = self.path(key)
        if not p.exists():
            return {"key": key, "text": "", "updated": 0}
        return {"key": key, "text": p.read_text(encoding="utf-8"), "updated": int(p.stat().st_mtime * 1000)}

    def put(self, key, text, updated=None):
        with self.lock:
            p = self.path(key)
            tmp = p.with_suffix(".tmp")
            tmp.write_text(text, encoding="utf-8")
            os.replace(tmp, p)
            if updated:
                t = updated / 1000
                os.utime(p, (t, t))
        self.schedule_commit()
        return self.get(key)

    def schedule_commit(self):
        if self.timer:
            self.timer.cancel()
        self.timer = threading.Timer(20, self.commit)
        self.timer.daemon = True
        self.timer.start()

    def commit(self):
        with self.lock:
            if not (self.dir / ".git").exists():
                return
            git(self.dir, "add", "-A")
            if git(self.dir, "diff", "--cached", "--quiet").returncode == 0:
                return
            git(self.dir, "commit", "-q", "-m", "Notes " + time.strftime("%Y-%m-%d %H:%M"))
            if git(self.dir, "remote").stdout.strip():
                r = git(self.dir, "push", "-q")
                log("notes pushed" if r.returncode == 0 else "notes push failed: " + r.stderr.strip()[:200])

    def git_status(self):
        if not (self.dir / ".git").exists():
            return {"git": False}
        last = git(self.dir, "log", "-1", "--format=%ct").stdout.strip()
        remote = git(self.dir, "remote", "get-url", "origin").stdout.strip()
        ahead = git(self.dir, "rev-list", "--count", "@{u}..HEAD").stdout.strip() if remote else ""
        return {"git": True, "last_commit": int(last) * 1000 if last else 0, "remote": bool(remote),
                "unpushed": int(ahead) if ahead.isdigit() else None, "pending": bool(self.timer and self.timer.is_alive())}


def git(d, *args):
    return subprocess.run(["git", "-C", str(d), *args], capture_output=True, text=True,
                          env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))


# --------------------------------------------------------------------------- websocket (RFC 6455, minimal)
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class WS:
    def __init__(self, sock):
        self.sock, self.wlock, self.closed = sock, threading.Lock(), False

    def _recv(self, n):
        b = b""
        while len(b) < n:
            c = self.sock.recv(n - len(b))
            if not c:
                raise ConnectionError("closed")
            b += c
        return b

    def recv(self):
        """Return (opcode, payload) for the next complete message."""
        msg, op0 = b"", None
        while True:
            h = self._recv(2)
            fin, op, masked, ln = h[0] & 0x80, h[0] & 0x0F, h[1] & 0x80, h[1] & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", self._recv(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", self._recv(8))[0]
            if ln > 4_000_000:
                raise ConnectionError("frame too large")
            mask = self._recv(4) if masked else None
            data = self._recv(ln)
            if mask:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            if op >= 8:  # control frame
                if op == 8:
                    self.close()
                    raise ConnectionError("closed")
                if op == 9:
                    self.send(data, 10)
                continue
            if op0 is None:
                op0 = op
            msg += data
            if fin:
                return op0, msg

    def send(self, data, op=1):
        if self.closed:
            return
        if isinstance(data, str):
            data = data.encode()
        n = len(data)
        h = bytes([0x80 | op]) + (bytes([n]) if n < 126 else bytes([126]) + struct.pack(">H", n) if n < 65536
                                   else bytes([127]) + struct.pack(">Q", n))
        with self.wlock:
            try:
                self.sock.sendall(h + data)
            except OSError:
                self.closed = True

    def close(self):
        if not self.closed:
            self.send(b"\x03\xe8", 8)
            self.closed = True


def terminal_session(ws, lab, cols, rows):
    """Run `./lab shell NN` on a pty and pipe it to the WebSocket until either side closes."""
    pid, fd = pty.fork()
    if pid == 0:
        try:
            os.chdir(KIT)
            os.environ.update(TERM="xterm-256color", COLORTERM="truecolor")
            os.execvp("./lab", ["./lab", "shell", lab])
        finally:
            os._exit(127)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    log(f"terminal open lab {lab} pid {pid}")
    stop = threading.Event()

    def pump():
        try:
            while not stop.is_set():
                r, _, _ = select.select([fd], [], [], 0.5)
                if fd in r:
                    try:
                        d = os.read(fd, 65536)
                    except OSError:
                        break
                    if not d:
                        break
                    ws.send(d, 2)  # terminal output as binary frames; text frames are JSON control
        finally:
            ws.send(json.dumps({"exit": True}))
            ws.close()
            stop.set()

    t = threading.Thread(target=pump, daemon=True)
    t.start()
    try:
        while not stop.is_set():
            op, data = ws.recv()
            if op == 2:  # binary frame = keystrokes
                os.write(fd, data)
                continue
            try:  # text frame = JSON control message, e.g. {"cols":120,"rows":40}
                m = json.loads(data)
                if "cols" in m:
                    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", int(m["rows"]), int(m["cols"]), 0, 0))
            except (ValueError, TypeError):
                pass
    except (ConnectionError, OSError, ValueError):
        pass
    finally:
        stop.set()
        try:
            os.killpg(os.getpgid(pid), signal.SIGHUP)
        except Exception:
            pass
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
        log(f"terminal closed lab {lab}")


# --------------------------------------------------------------------------- http
class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "labkit-agent/" + VERSION
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        if "/api/jobs/" not in self.path and "/api/status" not in self.path:
            log(self.address_string(), fmt % args)

    # --- origin / auth
    def origin_ok(self):
        o = self.headers.get("Origin")
        if not o:
            return True  # not a browser cross-site request (curl, same-origin GET)
        host = self.headers.get("Host", "")
        same = {"http://" + host, "https://" + host}
        local = {f"http://localhost:{CONF['port']}", f"http://127.0.0.1:{CONF['port']}"}
        return o in same or o in local or o in CONF["allowed_origins"]

    def cors(self):
        o = self.headers.get("Origin")
        if o and self.origin_ok():
            self.send_header("Access-Control-Allow-Origin", o)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
            self.send_header("Access-Control-Allow-Private-Network", "true")
            self.send_header("Access-Control-Max-Age", "600")

    def authed(self):
        h = self.headers.get("Authorization", "")
        return h.startswith("Bearer ") and hmac.compare_digest(h[7:].encode(), CONF["token"].encode())

    def reply(self, code, obj=None, body=None, ctype="application/json"):
        if body is None:
            body = json.dumps(obj).encode()
        self.send_response(code)
        self.cors()
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def body_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        if n > MAX_NOTE * 2:
            raise ValueError("too large")
        return json.loads(self.rfile.read(n) or b"{}")

    # --- verbs
    def do_OPTIONS(self):
        if not self.origin_ok():
            return self.reply(403, {"error": "origin not allowed"})
        self.send_response(204)
        self.cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        u = urllib.parse.urlsplit(self.path)
        if u.path == "/api/term":
            return self.terminal(urllib.parse.parse_qs(u.query))
        if u.path.startswith("/api/"):
            return self.api("GET", u)
        return self.static(u.path)

    do_HEAD = do_GET

    def do_POST(self):
        self.api("POST", urllib.parse.urlsplit(self.path))

    def do_PUT(self):
        self.api("PUT", urllib.parse.urlsplit(self.path))

    def api(self, method, u):
        if not self.origin_ok():
            return self.reply(403, {"error": "origin not allowed"})
        if not self.authed():
            return self.reply(401, {"error": "bad or missing token"})
        p = u.path.strip("/").split("/")[1:]  # drop "api"
        q = urllib.parse.parse_qs(u.query)
        try:
            if p == ["status"] and method == "GET":
                s = lab_status(read_state())
                b = BUSY["job"]
                s.update(version=VERSION, engine=engine(), host=socket.gethostname(),
                         busy={"id": b.id, "lab": b.lab, "action": b.action} if b else None,
                         notes=NOTES.git_status())
                return self.reply(200, s)
            if len(p) == 3 and p[0] == "labs" and method == "POST":
                lab, action = p[1], p[2]
                if not lab_dir(lab) or action not in ACTIONS:
                    return self.reply(404, {"error": "unknown lab or action"})
                job, err = start_job(lab, action)
                if err:
                    return self.reply(409, {"error": err})
                return self.reply(202, {"job": job.id})
            if len(p) == 2 and p[0] == "jobs" and method == "GET":
                job = JOBS.get(p[1])
                if not job:
                    return self.reply(404, {"error": "no such job"})
                off = int((q.get("offset") or ["0"])[0])
                data = bytes(job.buf[off:])
                return self.reply(200, {"lab": job.lab, "action": job.action, "rc": job.rc, "done": job.rc is not None,
                                        "offset": off + len(data), "output": data.decode("utf-8", "replace")})
            if p == ["notes"] and method == "GET":
                return self.reply(200, {"notes": NOTES.list(), "git": NOTES.git_status()})
            if p == ["notes", "sync"] and method == "POST":
                threading.Thread(target=NOTES.commit, daemon=True).start()
                return self.reply(202, {"ok": True})
            if len(p) == 2 and p[0] == "notes" and NOTE_KEY.match(p[1]):
                if method == "GET":
                    return self.reply(200, NOTES.get(p[1]))
                if method == "PUT":
                    b = self.body_json()
                    text = b.get("text", "")
                    if not isinstance(text, str) or len(text) > MAX_NOTE:
                        return self.reply(400, {"error": "bad note"})
                    return self.reply(200, NOTES.put(p[1], text, b.get("updated")))
            return self.reply(404, {"error": "not found"})
        except (ValueError, KeyError) as e:
            return self.reply(400, {"error": str(e)})

    def terminal(self, q):
        lab = (q.get("lab") or [""])[0]
        if not self.origin_ok():
            return self.reply(403, {"error": "origin not allowed"})
        if self.headers.get("Upgrade", "").lower() != "websocket" or not lab_dir(lab):
            return self.reply(400, {"error": "websocket upgrade with ?lab=NN required"})
        key = self.headers.get("Sec-WebSocket-Key", "")
        acc = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", acc)
        self.end_headers()
        self.wfile.flush()
        self.close_connection = True
        ws = WS(self.connection)
        self.connection.settimeout(None)
        # Browsers can't put headers on a WebSocket, so the first message must be {"token":..., "cols":.., "rows":..}
        try:
            self.connection.settimeout(10)
            op, data = ws.recv()
            self.connection.settimeout(None)
            hello = json.loads(data)
            if not hmac.compare_digest(str(hello.get("token", "")).encode(), CONF["token"].encode()):
                ws.send(json.dumps({"error": "bad token"}))
                return ws.close()
        except Exception:
            return ws.close()
        terminal_session(ws, lab, int(hello.get("cols", 100)), int(hello.get("rows", 30)))

    def static(self, path):
        if not CONF.get("serve_site", True):
            return self.reply(404, {"error": "not found"})
        root = (KIT / "docs").resolve()
        f = (root / urllib.parse.unquote(path).lstrip("/")).resolve()
        if f.is_dir():
            f = f / "index.html"
        if root not in f.parents and f != root / "index.html" or not f.is_file():
            return self.reply(404, body=b"not found", ctype="text/plain")
        ctype = mimetypes.guess_type(str(f))[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype.endswith("javascript"):
            ctype += "; charset=utf-8"
        self.reply(200, body=f.read_bytes(), ctype=ctype)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def cmd_serve():
    global CONF, NOTES
    CONF = load_conf()
    if not CONF.get("token") or len(CONF["token"]) < 20:
        sys.exit("token missing or too short; run init")
    NOTES = Notes(CONF["notes_dir"])
    pathlib.Path(CONF["notes_dir"]).mkdir(parents=True, exist_ok=True)
    if CONF["bind"] not in ("127.0.0.1", "localhost", "::1"):
        log(f"WARNING: binding to {CONF['bind']}. Only do this on an interface the internet can't reach (e.g. tailscale0).")
    srv = Server((CONF["bind"], CONF["port"]), Handler)
    log(f"labkit-agent {VERSION} on http://{CONF['bind']}:{CONF['port']}  kit={KIT}  engine={engine()}")
    signal.signal(signal.SIGTERM, lambda *a: (NOTES.commit(), sys.exit(0)))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        NOTES.commit()


CONF, NOTES = {}, None

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "serve"
    if cmd == "init":
        cmd_init()
    elif cmd == "serve":
        cmd_serve()
    elif cmd == "token":
        print(load_conf()["token"])
    else:
        print(__doc__)
