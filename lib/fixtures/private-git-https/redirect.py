"""An HTTPS host for tests that answers every request with a 302 to another host.

Usage: redirect.py CERT KEY PORT_FILE TARGET_HOST_PORT

Binds 127.0.0.1 on a free port, writes the port to PORT_FILE once listening, and redirects each
request to https://TARGET_HOST_PORT with the same path, as a renamed or moved repository's host
does. Each request is logged to stderr with whether it carried an Authorization header.
"""

import http.server
import os
import ssl
import sys


def main():
    cert, key, port_file, target = sys.argv[1:5]

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, fmt, *args):
            sys.stderr.write(
                "redirect: %s %s auth=%s\n"
                % (self.command, self.path.split("?")[0], "Authorization" in self.headers)
            )

        def redirect(self):
            self.send_response(302)
            self.send_header("Location", "https://%s%s" % (target, self.path))
            self.send_header("Content-Length", "0")
            self.end_headers()

        do_GET = redirect
        do_POST = redirect

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
