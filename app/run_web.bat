@echo off
cd /d "%~dp0"
REM Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy are required
REM for sqlite3.wasm's async OPFS worker (SharedArrayBuffer) — without
REM these, AppDatabase.open() hangs forever on web and nothing ever
REM renders, since main() awaits it before runApp(). See docs/ARCHITECTURE.md
REM known-issues notes for this dev environment.
"C:\Users\abdul\flutter\bin\flutter.bat" run -d web-server --web-port=8765 --web-hostname=127.0.0.1 --web-header=Cross-Origin-Opener-Policy=same-origin --web-header=Cross-Origin-Embedder-Policy=require-corp
