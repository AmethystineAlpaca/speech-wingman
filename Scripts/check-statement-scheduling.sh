#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product WingmanCoreTests >/dev/null
TASK_BIN="$(swift build --show-bin-path)"
mkdir -p build
TASK_CHECK="$(mktemp -d "$PWD/build/statement-check.XXXXXX")"
trap 'rm -rf "$TASK_CHECK"' EXIT
# Relax access in a temporary test copy; shipping controller has no test hooks.
sed 's/private //g' Sources/WingmanApp/SessionController.swift > "$TASK_CHECK/SessionController.swift"
if [ -f "$TASK_BIN/WingmanCore.o" ]; then
  TASK_MODULE="$TASK_BIN"
  TASK_OBJECTS=("$TASK_BIN/WingmanCore.o")
else
  TASK_MODULE="$TASK_BIN/Modules"
  TASK_OBJECTS=("$TASK_BIN"/WingmanCore.build/*.o)
fi
xcrun swiftc -parse-as-library -I "$TASK_MODULE" "${TASK_OBJECTS[@]}" \
  "$TASK_CHECK/SessionController.swift" Sources/WingmanApp/AlertPresenter.swift Sources/WingmanApp/AudioCapture.swift \
  Tests/StatementScheduling/main.swift -o "$TASK_CHECK/statement-check"
"$TASK_CHECK/statement-check"
