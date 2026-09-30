#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TASK_FIXTURES="${ULTIMATE_OUTPUT:-$PWD/local-evaluation/ultimate}"
mkdir -p "$TASK_FIXTURES"
if [ ! -f "$TASK_FIXTURES/events.json" ]; then
  /usr/bin/python3 Samples/UltimateTestCase/audio.py --output "$TASK_FIXTURES"
fi
# Each invocation gets an immutable result directory; previous levels cannot leak in.
TASK_RUN="$(mktemp -d "$TASK_FIXTURES/run.XXXXXX")"
printf '%s\n' "$TASK_RUN" > "$TASK_FIXTURES/latest-run.txt"
printf 'Result directory: %s\n' "$TASK_RUN"
swift build --product WingmanCoreTests >/dev/null
TASK_BIN="$(swift build --show-bin-path)"
if [ -f "$TASK_BIN/WingmanCore.o" ]; then
  TASK_MODULE="$TASK_BIN"
  TASK_OBJECTS=("$TASK_BIN/WingmanCore.o")
else
  TASK_MODULE="$TASK_BIN/Modules"
  TASK_OBJECTS=("$TASK_BIN"/WingmanCore.build/*.o)
fi
xcrun swiftc -parse-as-library -I "$TASK_MODULE" "${TASK_OBJECTS[@]}" Samples/UltimateTestCase/main.swift -o "$TASK_RUN/ultimate-replay"
/usr/bin/python3 Samples/UltimateTestCase/provenance.py "$TASK_FIXTURES" "$TASK_RUN"
/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)' "$TASK_RUN/ultimate-replay" \
  "$PWD/build/native/bin/text-worker" "$PWD/Models/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
  "$PWD/Samples/UltimateTestCase/scenario.json" "$TASK_FIXTURES/events.json" "$TASK_RUN" "${1:-all}"
