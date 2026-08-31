#!/bin/bash
#
# Wraps Clipper in a disk image, building it first if you have not.
#
#   Scripts/package.sh                    build Release, then package
#   Scripts/package.sh path/to/Clipper.app
#                                         package one Xcode already built
#   Scripts/package.sh --xcode            package Xcode's latest Release build
#
# Signs and notarizes when the material for it is on the machine, and says
# plainly what it did when it is not, because an unnotarized app is something
# the person receiving it has to work around.
#
#   NOTARY_PROFILE=clipper Scripts/package.sh …
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Clipper"
SCHEME="Clipper"
BUILD_DIR="build/package"
DIST_DIR="dist"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
INPUT="${1:-}"

mkdir -p "$DIST_DIR"

# A Developer ID certificate is what lets this open on a machine that has never
# seen it. Without one the build is still signed, but only to itself.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/' || true)

case "$INPUT" in
"--xcode")
    # Where Product > Build leaves it. Newest wins, in case of several.
    APP=$(find ~/Library/Developer/Xcode/DerivedData \
        -maxdepth 5 -path "*/Build/Products/Release/$APP_NAME.app" \
        -not -path "*/Index.noindex/*" 2>/dev/null \
        | xargs -I{} stat -f "%m %N" {} 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    [ -n "$APP" ] || { echo "No Release build in DerivedData. Build in Xcode first."; exit 1; }
    echo "==> Packaging Xcode's build"
    ;;
"")
    rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"
    echo "==> Generating the project"
    xcodegen generate >/dev/null

    echo "==> Building $APP_NAME"
    ARGS=(-project "$APP_NAME.xcodeproj" -scheme "$SCHEME"
          -configuration Release -destination 'platform=macOS,arch=arm64'
          -derivedDataPath "$BUILD_DIR/dd" ARCHS=arm64
          -skipPackagePluginValidation -skipMacroValidation)
    if [ -n "$IDENTITY" ]; then
        echo "    signing as: $IDENTITY"
        # `build` injects com.apple.security.get-task-allow, the entitlement
        # that lets a debugger attach. `archive` does not, which is why this is
        # only a problem here: the notary service rejects an executable that
        # asks for it, and the whole submission comes back Invalid.
        ARGS+=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual
               CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
               OTHER_CODE_SIGN_FLAGS="--timestamp")
    else
        echo "    no Developer ID certificate found, signing to this machine only"
    fi
    xcodebuild "${ARGS[@]}" build >"$BUILD_DIR/build.log" 2>&1
    APP="$BUILD_DIR/dd/Build/Products/Release/$APP_NAME.app"
    ;;
*)
    APP="${INPUT%/}"
    echo "==> Packaging $APP"
    ;;
esac

[ -d "$APP" ] || { echo "No app at $APP"; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"

# Captured rather than tested through a pipe. `grep -q` exits on its first
# match, the writer ahead of it dies of SIGPIPE, and `pipefail` reports the
# whole pipeline as failed, so a signature that IS Developer ID reads as one
# that is not.
SIGNING=$(codesign -dvv "$APP" 2>&1 | grep "^Authority=Developer ID" || true)

# Already stapled means it came out of Organizer notarized; nothing to do.
if xcrun stapler validate "$APP" >/dev/null 2>&1; then
    echo "==> Already notarized and stapled"
elif [ -n "$NOTARY_PROFILE" ] && [ -n "$SIGNING" ]; then
    echo "==> Notarizing"
    ditto -c -k --keepParent "$APP" "$DIST_DIR/$APP_NAME.zip"
    xcrun notarytool submit "$DIST_DIR/$APP_NAME.zip" \
        --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$DIST_DIR/$APP_NAME.zip"
fi

echo "==> Building the disk image"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
    -ov -format UDZO "$DMG" >/dev/null

echo
echo "$DMG  ($(du -h "$DMG" | cut -f1))"
codesign -dvv "$APP" 2>&1 | grep -E "^Authority|^Signature" | sed 's/^/    /' || true

VERDICT=$(spctl -a -t exec -vv "$APP" 2>&1 | grep "accepted" || true)
if [ -n "$VERDICT" ]; then
    echo "    Gatekeeper: accepted, opens by double click anywhere"
else
    echo "    Gatekeeper: NOT accepted. A colleague will see \"cannot be opened\""
    echo "    and has to right-click the app and choose Open the first time."
fi
