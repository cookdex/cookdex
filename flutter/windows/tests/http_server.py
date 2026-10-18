"""Run only the standalone WinHTTP probe against a disposable loopback server."""
import http.server
import subprocess
import sys
import threading
import time


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        try:
            if self.path == '/headers':
                time.sleep(3)
            self.send_response(302 if self.path == '/redirect' else 200)
            if self.path == '/redirect':
                self.send_header('Location', '/ok')
            self.send_header('Content-Length', 3000000 if self.path == '/large' else 100 if self.path in ['/truncated', '/dribble', '/body'] else 13)
            self.end_headers()
            if self.path == '/body':
                time.sleep(3)
            elif self.path == '/dribble':
                for _ in range(30):
                    self.wfile.write(b'x')
                    self.wfile.flush()
                    time.sleep(.05)
                return
            elif self.path == '/truncated':
                return
            self.wfile.write(b'x' * 3000000 if self.path in ['/large', '/body'] else b'local fixture')
        except (ConnectionError, OSError):
            pass


with http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
    threading.Thread(target=server.serve_forever, daemon=True).start()
    result = subprocess.run([sys.argv[1], str(server.server_port)], timeout=30)
    server.shutdown()
    sys.exit(result.returncode)
