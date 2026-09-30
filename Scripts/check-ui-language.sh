#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build >/dev/null
TASK_BIN="$(swift build --show-bin-path)"
mkdir -p build
TASK_CHECK="$(mktemp -d "$PWD/build/language-ui.XXXXXX")"
trap 'rm -rf "$TASK_CHECK"' EXIT
# Compile the actual production views/controller with a separate test entry point.
# No test hook or microphone activation is added to the shipping app.
sed -n '/^struct SessionView/,$p' Sources/WingmanApp/WingmanApp.swift > "$TASK_CHECK/ViewBody.swift"
printf 'import SwiftUI\nimport AppKit\nimport WingmanCore\n' > "$TASK_CHECK/Views.swift"
cat "$TASK_CHECK/ViewBody.swift" >> "$TASK_CHECK/Views.swift"
if [ -f "$TASK_BIN/WingmanCore.o" ]; then
  TASK_MODULE="$TASK_BIN"
  TASK_OBJECTS=("$TASK_BIN/WingmanCore.o")
else
  TASK_MODULE="$TASK_BIN/Modules"
  TASK_OBJECTS=("$TASK_BIN"/WingmanCore.build/*.o)
fi
xcrun swiftc -parse-as-library -I "$TASK_MODULE" "${TASK_OBJECTS[@]}" \
  Sources/WingmanApp/SessionController.swift Sources/WingmanApp/AlertPresenter.swift Sources/WingmanApp/AudioCapture.swift \
  "$TASK_CHECK/Views.swift" Tests/UILayout/main.swift -o "$TASK_CHECK/language-ui-check"
TASK_OUTPUT="$PWD/local-evaluation/language-ui"
if [ "${1:-}" = "--public-demo" ]; then TASK_OUTPUT="$PWD/docs/assets"; fi
"$TASK_CHECK/language-ui-check" "$TASK_OUTPUT" "$@"
