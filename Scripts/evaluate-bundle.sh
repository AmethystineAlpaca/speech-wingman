#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
TASK_CHECK="$(mktemp -d "$TASK_ROOT/build/wingman-check.XXXXXX")"
trap 'rm -rf "$TASK_CHECK"' EXIT
TASK_APP="$TASK_CHECK/OfflineCheck.app"
cp -cR 'build/Speech Wingman.app' "$TASK_APP"
cp .build/release/wingman-evaluate "$TASK_APP/Contents/MacOS/SpeechWingman"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.speechwingman.offlinecheck' "$TASK_APP/Contents/Info.plist"
cp local-evaluation/A1.wav "$TASK_APP/Contents/Resources/"
# A public, synthetic rule unrelated to the input should stay quiet.
printf '%s\n' 'Alert only if the speaker reveals a numeric password.' > "$TASK_APP/Contents/Resources/cli-policy.txt"
codesign --force --sign - --entitlements Resources/App.entitlements "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
TASK_RES="$TASK_APP/Contents/Resources"
# Parent has App Sandbox with no network entitlement; the original shipped helpers inherit it.
"$TASK_APP/Contents/MacOS/SpeechWingman" "$TASK_RES/text-worker" "$TASK_RES/asr-worker" "$TASK_RES/Models" "$TASK_RES/A1.wav" "$TASK_RES/cli-policy.txt" --realtime
