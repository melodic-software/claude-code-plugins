"""Shop web app."""

import json
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 8080
ROUTES = {"/": "catalog", "/cart": "cart", "/checkout": "checkout", "/account/reset-password": "reset_password"}
BUILD = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            body = json.dumps({"status": "ok", "build": BUILD, "db": "local"}).encode()
        elif self.path in ROUTES:
            body = ROUTES[self.path].encode()
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
