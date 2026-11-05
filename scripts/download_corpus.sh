#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${LEXMEMORIA_PYTHON:-/workspace/lexmemoria-venv/bin/python}"
CORPUS_ROOT="${LEXMEMORIA_CORPUS_ROOT:-/workspace/lexmemoria-corpus}"
cd "$PROJECT_ROOT/backend"
"$PYTHON_BIN" -m app.bulk --root "$CORPUS_ROOT" discover "$@"
DOWNLOAD_EXIT=0
"$PYTHON_BIN" -m app.bulk --root "$CORPUS_ROOT" run --workers 2 || DOWNLOAD_EXIT=$?
"$PYTHON_BIN" -m app.bulk --root "$CORPUS_ROOT" verify
exit "$DOWNLOAD_EXIT"
