#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT/backend"
exec "${LEXMEMORIA_VENV:-/workspace/lexmemoria-venv}/bin/python" -u -m app.eu_supervisor --root "${LEXMEMORIA_EU_ARCHIVE:-/workspace/lexmemoria-eu-corpus}"
