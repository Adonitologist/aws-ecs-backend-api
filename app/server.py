import json
import os
import ssl
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pg8000.dbapi


def check_db():
    """Run SELECT 1 using the JSON injected by ECS in DB_CREDENTIALS. Never logs credentials."""
    creds = json.loads(os.environ["DB_CREDENTIALS"])
    # NOTE: encrypted but the server certificate is not verified; bundle the RDS CA to verify.
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    conn = pg8000.dbapi.connect(
        user=creds["username"],
        password=creds["password"],
        host=creds["host"],
        port=int(creds["port"]),
        database=os.environ.get("DB_NAME", "appdb"),
        timeout=3,
        ssl_context=ctx,
    )
    try:
        cur = conn.cursor()
        cur.execute("SELECT 1")
        return cur.fetchone()[0] == 1
    finally:
        conn.close()


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok"})
        elif self.path == "/db-check":
            try:
                ok = check_db()
            except Exception as exc:  # log only the exception type: messages may echo connection details
                print("db-check failed: " + type(exc).__name__, flush=True)
                ok = False
            self._send(200 if ok else 503, {"db": "ok" if ok else "unavailable"})
        else:
            self._send(404, {"error": "not found"})


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
