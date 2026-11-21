#!/usr/bin/env python3
"""Simulated captive-portal web server (CI only): portal-server.py <bind-ip> <state-dir>

Before login every HTTP request is redirected to the portal page, like hotel/train Wi-Fi.
GET /accept is the user clicking "accept": it writes <state-dir>/accepted, which makes
tests/portal/portal-test.sh open the network (real DNS + NAT).
"""
import http.server
import os
import sys

BIND, STATE = sys.argv[1], sys.argv[2]
PORTAL = f"http://{BIND}/login"


class Portal(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body=b"", headers=None):
        self.send_response(code)
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/accept"):
            open(os.path.join(STATE, "accepted"), "w").close()
            self._send(200, b"<h1>Welcome. You are online.</h1>")
        elif self.path.startswith("/login"):
            self._send(200, b'<h1>Free Wi-Fi</h1><a href="/accept">Accept the terms</a>')
        else:
            self._send(302, headers={"Location": PORTAL})

    do_HEAD = do_GET

    def log_message(self, fmt, *args):
        sys.stderr.write("portal-http: " + (fmt % args) + "\n")


http.server.ThreadingHTTPServer((BIND, 80), Portal).serve_forever()
