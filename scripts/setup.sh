#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PATH="${LEXMEMORIA_VENV:-/workspace/lexmemoria-venv}"
python3 -m venv "$VENV_PATH"
"$VENV_PATH/bin/python" -m pip install -r "$PROJECT_ROOT/backend/requirements.lock"
if ! command -v flutter >/dev/null; then
  if [[ -x /workspace/tools/flutter/bin/flutter ]]; then
    export PATH="/workspace/tools/flutter/bin:$PATH"
  else
    echo 'Instala Flutter 3.47.9 y añádelo a PATH antes de preparar el cliente móvil.' >&2
    exit 1
  fi
fi
flutter --version
cd "$PROJECT_ROOT/mobile"
# Generate tool metadata/wrappers missing from a clean checkout, preserving sources.
flutter create --platforms=android,ios,web --org es.lexmemoria --project-name lexmemoria --no-pub .
flutter pub get
flutter analyze
flutter test
