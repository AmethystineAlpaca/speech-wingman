#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_PYTHON="${WINGMAN_PYTHON:-/usr/bin/python3}"
"$TASK_PYTHON" -m pip install --target "$TASK_ROOT/.tools/cmake-package" 'cmake==4.4.3'
"$TASK_PYTHON" "$TASK_ROOT/Scripts/setup-asr-runtime.py"
bash "$TASK_ROOT/Scripts/build-worker.sh"
