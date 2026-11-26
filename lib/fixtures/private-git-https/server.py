"""A private git remote over HTTPS for tests: Basic auth in front of git http-backend.

Usage: server.py PROJECT_ROOT CERT KEY PORT_FILE USER PASSWORD

Binds 127.0.0.1 on a free port and writes the port to PORT_FILE once listening. A request
without the one accepted Authorization header gets 401 with a Basic challenge, so a git client
must ask its credential helper before it can read anything.
"""

import base64
import http.server
import os
import ssl
import subprocess
import sys


def main():
    root, cert, key, port_file, user, password = sys.argv[1:7]
    accepted = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, fmt, *args):
            sys.stderr.write(
                "private-git-https: %s %s\n" % (self.command, self.path.split("?")[0])
            )

        def challenge(self):
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="private"')
            self.send_header("Content-Length", "0")
            self.end_headers()

        def backend(self):
            if self.headers.get("Authorization") != accepted:
                self.challenge()
                return
            path, _, query = self.path.partition("?")
            env = {
                "PATH": os.environ.get("PATH", ""),
                "GIT_PROJECT_ROOT": root,
                "GIT_HTTP_EXPORT_ALL": "1",
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": "/dev/null",
                "REQUEST_METHOD": self.command,
                "PATH_INFO": path,
                "QUERY_STRING": query,
                "REMOTE_USER": user,
                "REMOTE_ADDR": "127.0.0.1",
                "CONTENT_TYPE": self.headers.get("Content-Type", ""),
            }
            for name, value in self.headers.items():
                env["HTTP_" + name.upper().replace("-", "_")] = value
            body = b""
            if self.command == "POST":
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length)
                env["CONTENT_LENGTH"] = str(length)
            out = subprocess.run(
                ["git", "http-backend"],
                input=body,
                env=env,
                capture_output=True,
                check=False,
            ).stdout
            head, _, payload = out.partition(b"\r\n\r\n")
            status = 200
            headers = []
            for line in head.decode("latin-1").split("\r\n"):
                name, _, value = line.partition(":")
                if name.lower() == "status":
                    status = int(value.strip().split()[0])
                elif name:
                    headers.append((name, value.strip()))
            self.send_response(status)
            for name, value in headers:
                self.send_header(name, value)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        do_GET = backend
        do_POST = backend

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    with open(port_file + ".tmp", "w", encoding="ascii") as f:
        f.write(str(server.server_address[1]))
    os.replace(port_file + ".tmp", port_file)
    server.serve_forever()


if __name__ == "__main__":
    main()
