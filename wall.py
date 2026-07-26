#!/usr/bin/env python3
"""Serves wall.html on :3000 and proxies /api/* to VictoriaMetrics on :8428.

The proxy exists only so the page is same-origin with the query API — no CORS,
no datasource config, no Grafana. RAM: ~15 MB vs Grafana's ~250 MB.
"""
import http.server, urllib.request, urllib.error, os

VM = "http://localhost:8428"
HERE = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/api/"):
            return self.proxy()
        try:
            with open(os.path.join(HERE, "wall.html"), "rb") as f:
                body = f.read()
        except OSError:
            return self.send_error(404)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def proxy(self):
        # ponytail: read-only GET passthrough to a loopback service; add an
        # allowlist if VM ever gets write endpoints exposed here.
        try:
            with urllib.request.urlopen(VM + self.path, timeout=15) as r:
                body, code = r.read(), r.status
        except urllib.error.HTTPError as e:
            body, code = e.read(), e.code
        except OSError as e:
            body, code = str(e).encode(), 502
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    http.server.ThreadingHTTPServer(("0.0.0.0", 3000), Handler).serve_forever()
