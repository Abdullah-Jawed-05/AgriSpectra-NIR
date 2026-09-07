"""Serve app/build/web with the COOP/COEP headers sqflite_common_ffi_web
needs (SharedArrayBuffer / cross-origin isolation). For eyeballing a
release/profile web build locally — `flutter run -d web-server` is the
normal dev path.

    python tool/serve_web_build.py [port]
"""
import functools
import http.server
import socketserver
import sys
from pathlib import Path

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8091
ROOT = Path(__file__).resolve().parent.parent / "build" / "web"


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


if __name__ == "__main__":
    if not ROOT.exists():
        raise SystemExit(f"{ROOT} not found — run `flutter build web` first.")
    with socketserver.TCPServer(
        ("127.0.0.1", PORT), functools.partial(Handler, directory=str(ROOT))
    ) as httpd:
        print(f"serving {ROOT} at http://127.0.0.1:{PORT}")
        httpd.serve_forever()
