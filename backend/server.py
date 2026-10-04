#!/usr/bin/env python3
"""Tiny REST backend. Stdlib only — no pip install needed.
Run:  python3 server.py A 3001   (Mac 3)
      python3 server.py B 3002   (Mac 4)
"""
import hashlib, json, socket, sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NAME = sys.argv[1] if len(sys.argv) > 1 else "A"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3001

# Same data on both backends -> same ETag -> 304 works no matter which backend answers.
CATALOG = json.dumps({"items": ["router", "switch", "firewall"], "version": 1}, sort_keys=True).encode()
ETAG = '"' + hashlib.sha1(CATALOG).hexdigest()[:16] + '"'


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"  # keep-alive, like a real server

    def reply(self, code, body=b"", headers=None):
        self.send_response(code)
        self.send_header("X-Backend", NAME)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        if code != 304:
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body and self.command != "HEAD" and code != 304:
            self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/":
            body = {"service": "running", "backend": NAME}
            self.reply(200, json.dumps(body).encode(), {"Cache-Control": "no-store"})
        elif path == "/api/status":
            body = {"backend": NAME, "status": "ok", "host": socket.gethostname(),
                    "time": datetime.now(timezone.utc).isoformat()}
            self.reply(200, json.dumps(body).encode(), {"Cache-Control": "no-store"})
        elif path == "/api/catalog":  # the caching demo endpoint (Task F)
            cache = {"Cache-Control": "max-age=60", "ETag": ETAG}
            if self.headers.get("If-None-Match") == ETAG:
                self.reply(304, headers=cache)       # conditional hit: no body sent
            else:
                self.reply(200, CATALOG, cache)      # full response
        else:
            self.reply(404, b'{"error":"not found"}')

    do_HEAD = do_GET  # so `curl -I` works

    def log_message(self, fmt, *args):
        ip, port = self.client_address
        print(f"[backend {NAME}] from {ip}:{port}  {fmt % args}", flush=True)


if __name__ == "__main__":
    # 0.0.0.0 = listen on every interface, including the LAN. 127.0.0.1 would be unreachable from Mac 2.
    print(f"Backend {NAME} listening on 0.0.0.0:{PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
