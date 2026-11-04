#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT/backend"
exec "${LEXMEMORIA_VENV:-/workspace/lexmemoria-venv}/bin/python" -m uvicorn app.main:app --host 127.0.0.1 --port "${PORT:-8000}"
