#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# != 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Usage: bash scripts/package.sh MAJOR.MINOR.PATCH' >&2
    exit 64
fi
pip_version="$1"
pip_build="${GITHUB_RUN_NUMBER:-1}"
if [[ ! "$pip_build" =~ ^[1-9][0-9]*$ ]]; then
    echo 'Build number must be a positive integer.' >&2
    exit 64
fi

# Keep release output separate from the running local development app.
xcodebuild -quiet -project Pip.xcodeproj -scheme Pip \
    -destination 'generic/platform=macOS' -configuration Release \
    -derivedDataPath build-release CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO 'ARCHS=arm64 x86_64' \
    PRODUCT_BUNDLE_IDENTIFIER=io.github.rusintez.pip \
    MARKETING_VERSION="$pip_version" CURRENT_PROJECT_VERSION="$pip_build" build

pip_app='build-release/Build/Products/Release/Pip.app'
xcrun lipo -verify_arch arm64 "$pip_app/Contents/MacOS/Pip"
xcrun lipo -verify_arch x86_64 "$pip_app/Contents/MacOS/Pip"
mkdir -p "$pip_app/Contents/Resources"
cp LICENSE "$pip_app/Contents/Resources/LICENSE.txt"
# Ad hoc signing needs no certificate. This is not Developer ID signing or notarization.
codesign --force --sign - --options runtime --entitlements Config/Pip.entitlements "$pip_app"
codesign --verify --strict "$pip_app"

mkdir -p dist
pip_archive="Pip-${pip_version}-macos-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$pip_app" "dist/$pip_archive"
(
    cd dist
    shasum -a 256 "$pip_archive" > "$pip_archive.sha256"
)
echo "Packaged dist/$pip_archive (ad hoc signed; not notarized)"
