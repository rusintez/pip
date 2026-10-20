#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Replacing a signed executable while Pip is running can invalidate its playback-service connection.
pip_binary="$(pwd -P)/build/Build/Products/Debug/Pip.app/Contents/MacOS/Pip"
for pip_pid in $(pgrep -x Pip || true); do
    if [ "$(ps -p "$pip_pid" -o comm=)" = "$pip_binary" ]; then
        kill -TERM "$pip_pid"
        pip_attempt=0
        while kill -0 "$pip_pid" 2>/dev/null; do
            pip_attempt=$((pip_attempt + 1))
            if [ "$pip_attempt" -ge 20 ]; then
                echo 'Pip is still running. Quit it before rebuilding.' >&2
                exit 1
            fi
            sleep 0.1
        done
    fi
done
xcodebuild -quiet -project Pip.xcodeproj -scheme Pip -destination "platform=macOS,arch=$(uname -m)" -configuration Debug \
    -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
codesign --force --sign - --entitlements Config/Pip.entitlements build/Build/Products/Debug/Pip.app
open build/Build/Products/Debug/Pip.app
