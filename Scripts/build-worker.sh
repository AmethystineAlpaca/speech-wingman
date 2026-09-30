#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_CMAKE="${WINGMAN_CMAKE:-$TASK_ROOT/.tools/cmake-package/cmake/data/bin/cmake}"
if [ ! -x "$TASK_CMAKE" ]; then
  printf 'Set WINGMAN_CMAKE to an arm64-compatible CMake binary.\n' >&2
  exit 1
fi
if [ ! -f "$TASK_ROOT/Vendor/sherpa-onnx/c-api.h" ] || [ ! -f "$TASK_ROOT/Vendor/sherpa-onnx/lib/libsherpa-onnx-c-api.dylib" ]; then
  printf 'Run Scripts/setup-asr-runtime.py with a working Python first.\n' >&2
  exit 1
fi
TASK_COMMIT=272aad8b984a4470d26f14bea8d958be68ac7c0c
if [ ! -d "$TASK_ROOT/Vendor/llama.cpp/.git" ]; then
  /usr/bin/git clone https://github.com/ggml-org/llama.cpp.git "$TASK_ROOT/Vendor/llama.cpp"
fi
if [ "$(/usr/bin/git -C "$TASK_ROOT/Vendor/llama.cpp" rev-parse HEAD)" != "$TASK_COMMIT" ]; then
  /usr/bin/git -C "$TASK_ROOT/Vendor/llama.cpp" fetch origin "$TASK_COMMIT"
  /usr/bin/git -C "$TASK_ROOT/Vendor/llama.cpp" checkout --detach "$TASK_COMMIT"
fi
"$TASK_CMAKE" -S "$TASK_ROOT" -B "$TASK_ROOT/build/native" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
"$TASK_CMAKE" --build "$TASK_ROOT/build/native" --target text-worker asr-worker -j 4
