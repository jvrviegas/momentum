#!/usr/bin/env bash
# Builds a Developer ID-signed, notarized Release DMG of Momentum and a signed Sparkle appcast for it.
#
#   scripts/release.sh             build only (output in build/releases/<version>/)
#   scripts/release.sh --publish   build, then create the GitHub release with the DMG and appcast.xml
#
# One-time setup:
#   - A "Developer ID Application" certificate in the login keychain
#     (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application).
#   - Notary credentials in the keychain, under the profile name in NOTARY_PROFILE:
#       xcrun notarytool store-credentials momentum-notary --apple-id <apple-id> --team-id KL88H3WKQ9
#   - For --publish: the project must be a git checkout whose HEAD is pushed to GitHub; the release tag points at it.
#
# Before each release, bump MARKETING_VERSION (e.g. 1.1) and CURRENT_PROJECT_VERSION (e.g. 2) in Xcode.
# Sparkle compares CURRENT_PROJECT_VERSION, so it must increase every release.
# Optional release notes: put build/releases/<version>/Momentum-<version>.md next to the DMG before
# the appcast step, or pass them to the GitHub release.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME=Momentum
SCHEME=Momentum
REPO=jvrviegas/momentum
SPARKLE_ACCOUNT=momentum   # Keychain account holding the EdDSA private key (see generate_keys --account)
NOTARY_PROFILE=${NOTARY_PROFILE:-momentum-notary}

PUBLISH=false
if [[ "${1:-}" == "--publish" ]]; then
    PUBLISH=true
fi

# Check prerequisites before the slow steps.
if ! security find-identity -v -p codesigning | grep -q '"Developer ID Application:'; then
    echo "No Developer ID Application certificate in the keychain; see the setup notes at the top of this script." >&2
    exit 1
fi
if $PUBLISH; then
    if ! COMMIT=$(git rev-parse --verify HEAD 2>/dev/null); then
        echo "--publish needs a git checkout, so the release tag points at the code being built." >&2
        exit 1
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Commit or stash your changes first; the release must match a pushed commit." >&2
        exit 1
    fi
    if [[ -z "$(git branch -r --contains "$COMMIT")" ]]; then
        echo "Push $COMMIT to GitHub first; the release tag is created on it." >&2
        exit 1
    fi
fi

setting() {
    xcodebuild -project "$APP_NAME.xcodeproj" -target "$APP_NAME" -configuration Release -showBuildSettings 2>/dev/null \
        | awk -v key="$1" '$1 == key && !found { print $3; found = 1 }'
}
VERSION=$(setting MARKETING_VERSION)
BUILD_NUMBER=$(setting CURRENT_PROJECT_VERSION)
TAG="v$VERSION"
WORK=build/work
OUT="build/releases/$VERSION"
DMG="$OUT/$APP_NAME-$VERSION.dmg"

echo "==> Momentum $VERSION ($BUILD_NUMBER)"
rm -rf "$WORK" "$OUT"
mkdir -p "$WORK" "$OUT"

echo "==> Archiving"
xcodebuild archive -quiet \
    -project "$APP_NAME.xcodeproj" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$WORK/$APP_NAME.xcarchive"

# The archive is signed for development; exporting re-signs it with Developer ID for distribution.
echo "==> Exporting with Developer ID"
cat > "$WORK/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -quiet \
    -archivePath "$WORK/$APP_NAME.xcarchive" \
    -exportOptionsPlist "$WORK/ExportOptions.plist" \
    -exportPath "$WORK/export"
APP="$WORK/export/$APP_NAME.app"
codesign --verify --deep --strict "$APP"
# No early `exit` in awk: with pipefail, closing the pipe early would fail the script.
IDENTITY=$(codesign -dv --verbose=2 "$APP" 2>&1 | awk -F= '/^Authority=/ && !found { print $2; found = 1 }')
echo "    signed by: $IDENTITY"
if [[ "$IDENTITY" != "Developer ID Application:"* ]]; then
    echo "Expected a Developer ID signature." >&2
    exit 1
fi

echo "==> Building DMG"
mkdir -p "$WORK/dmg"
cp -R "$APP" "$WORK/dmg/"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$WORK/dmg" -format UDZO "$DMG"
codesign --sign "$IDENTITY" "$DMG"

echo "==> Notarizing (usually a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
# Stapling fails if notarization was rejected; `xcrun notarytool log <id>` shows why.
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

# After stapling: stapling changes the DMG, and the appcast signs its exact bytes.
echo "==> Generating appcast"
SPARKLE_BIN=${SPARKLE_BIN:-$(ls -d ~/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)}
if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "Sparkle tools not found; build the project in Xcode once, or set SPARKLE_BIN." >&2
    exit 1
fi
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    "$OUT"

echo "==> Done: $DMG"
echo "          $OUT/appcast.xml"

if $PUBLISH; then
    echo "==> Publishing $TAG at $COMMIT to github.com/$REPO"
    gh release create "$TAG" "$DMG" "$OUT/appcast.xml" \
        --repo "$REPO" --target "$COMMIT" --title "$APP_NAME $VERSION" --generate-notes
fi
