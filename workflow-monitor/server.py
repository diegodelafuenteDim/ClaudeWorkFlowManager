"""Workflow Monitor - local dashboard to watch the state of Claude Code workflows/subagents.

Entry point only: HTTP plumbing and the __main__ block. The layers live in their own
modules — fsread (pure disk readers), prompts (prompt cache + derived views, sole owner
of mutable state), api (endpoint functions). Import DAG: fsread <- prompts <- api <- server.

Usage:  python server.py [puerto]   (default 8787) -> opens http://localhost:8787
Stdlib only. Read only. Binds to 127.0.0.1.

LANGUAGE CONVENTION (the ES/EN boundary, deliberate): all code — identifiers, comments,
docstrings — is English. Everything the outside world sees stays in SPANISH byte-for-byte,
because the HTTP contract and the audience are Spanish:
  - JSON keys and values ("agentes", "listos", "estado", "mision", "molde", ...)
  - state values: ACTIVO / LENTO / TERMINADO / REEMPLAZADO / MUERTO / ESTANCADO
  - event types (TOOL/DICE/RES), motivo values ('sueltos', 'sin-script', ...)
  - the 'sueltos_' run-id prefix and the '(agentes sueltos)' label
  - query param names (q, run, id, proyecto, tipo), error strings and console messages
Do NOT translate any of those: clients and users depend on them verbatim.
"""
import json
import os
import sys
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse, parse_qs

import api

__version__ = "1.0.0"

# Packaged with PyInstaller (--onefile), index.html does not sit next to the .exe but is
# unpacked into a temp directory that PyInstaller exposes as sys._MEIPASS.
HERE = Path(getattr(sys, "_MEIPASS", Path(__file__).parent))


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlparse(self.path)
        q = parse_qs(url.query)
        try:
            if url.path == "/" or url.path == "/index.html":
                body = (HERE / "index.html").read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.end_headers()
                self.wfile.write(body)
            elif url.path == "/api/ping":
                # Cheap liveness with a signature: /api/runs walks all of ~/.claude/projects
                # (seconds with many runs), so it is no good for "is this alive?".
                self._json({"ok": True, "app": "workflow-monitor", "version": __version__})
            elif url.path == "/api/runs":
                self._json(api.api_runs())
            elif url.path == "/api/search":
                self._json(api.api_search(q.get("q", [""])[0], q.get("proyecto", [""])[0],
                                          q.get("tipo", [""])[0]))
            elif url.path in api.ROUTES_404:
                fn, params, msg = api.ROUTES_404[url.path]
                data = fn(*(q.get(p, [""])[0] for p in params))
                self._json(data if data else {"error": msg}, 200 if data else 404)
            else:
                self._json({"error": "ruta desconocida"}, 404)
        except Exception as e:  # noqa: BLE001 - best-effort monitor, never take the server down
            traceback.print_exc()  # the client's 500 is brief; the traceback goes to stderr
            self._json({"error": str(e)}, 500)


class MonitorServer(ThreadingHTTPServer):
    # ThreadingHTTPServer inherits allow_reuse_address=1, and on Windows that is NOT the
    # POSIX TIME_WAIT thing: it lets a SECOND process bind the same port without error.
    # The "a monitor is already listening" guard never fired and two servers were left
    # answering alternately (measurements and health checks talking to the old process
    # without noticing).
    allow_reuse_address = os.name != "nt"


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    try:
        server = MonitorServer(("127.0.0.1", port), Handler)
    except OSError:
        print(f"Ya hay un monitor escuchando en el puerto {port} — uso esa instancia.", flush=True)
        sys.exit(0)
    # flush: when the POSIX launcher redirects stdout to the log file, Python
    # block-buffers it — without the flush the banner sits unseen until exit.
    print(f"Workflow Monitor v{__version__} -> http://localhost:{port}   (Ctrl+C para salir)", flush=True)
    server.serve_forever()
