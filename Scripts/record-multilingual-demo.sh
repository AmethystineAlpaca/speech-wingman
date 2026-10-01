#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_ROOT="$PWD"
TASK_WORK="$TASK_ROOT/local-evaluation/multilingual-demo"
mkdir -p "$TASK_WORK/workers" "$TASK_WORK/frames" build
/usr/bin/python3 Scripts/generate-multilingual-demo.py "$@"
swift build >/dev/null
TASK_BIN="$(swift build --show-bin-path)"
TASK_CHECK="$(mktemp -d "$TASK_ROOT/build/multilingual-demo.XXXXXX")"
trap 'rm -rf "$TASK_CHECK"' EXIT
# Test copy relaxes access; the shipped app has no replay hooks.
sed 's/private //g' Sources/WingmanApp/SessionController.swift > "$TASK_CHECK/SessionController.swift"
printf 'import SwiftUI\nimport AppKit\nimport WingmanCore\n' > "$TASK_CHECK/Views.swift"
sed -n '/^struct SessionView/,$p' Sources/WingmanApp/WingmanApp.swift >> "$TASK_CHECK/Views.swift"
for TASK_HELPER in text-worker asr-worker; do
  cp "build/Speech Wingman.app/Contents/Resources/$TASK_HELPER" "$TASK_WORK/workers/$TASK_HELPER"
  codesign --remove-signature "$TASK_WORK/workers/$TASK_HELPER"
  codesign --force --sign - "$TASK_WORK/workers/$TASK_HELPER"
done
ln -sfn "$TASK_ROOT/build/Speech Wingman.app/Contents/Resources/lib" "$TASK_WORK/workers/lib"
if [ -f "$TASK_BIN/WingmanCore.o" ]; then
  TASK_MODULE="$TASK_BIN"; TASK_OBJECTS=("$TASK_BIN/WingmanCore.o")
else
  TASK_MODULE="$TASK_BIN/Modules"; TASK_OBJECTS=("$TASK_BIN"/WingmanCore.build/*.o)
fi
xcrun swiftc -parse-as-library -I "$TASK_MODULE" "${TASK_OBJECTS[@]}" \
  "$TASK_CHECK/SessionController.swift" "$TASK_CHECK/Views.swift" \
  Sources/WingmanApp/AlertPresenter.swift Sources/WingmanApp/AudioCapture.swift Sources/WingmanApp/FloatingControl.swift \
  Tests/MultilingualDemo/main.swift -o "$TASK_CHECK/replay"
"$TASK_CHECK/replay" "$TASK_ROOT"
