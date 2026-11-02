#!/bin/sh
# ./build.sh builds osk:gn.app; ./build.sh test builds and runs the tests instead.
# SIGN_ID="Developer ID Application: … (TEAMID)" signs for distribution; without it the app is signed ad hoc for this Mac.
set -e
cd "$(dirname "$0")"
# With xcode-select on the Command Line Tools, SwiftUI's macros fail to load ("plugin for module 'SwiftUIMacros' not found").
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
# Finder shows a ":" in a file name as "/", so this appears as osk/gn.
APP="osk:gn.app"
SPARKLE=2.10.1
# The public half of the EdDSA key that signs updates; the private half stays in the login keychain (generate_keys --account oskgn).
ED_KEY="DSIstBLv+8qxe70YZrjHJGEwSM4FJsoIdVvkrrFirkI="

if [ ! -d "Sparkle/$SPARKLE" ]; then
    rm -rf Sparkle && mkdir -p "Sparkle/$SPARKLE"
    curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE/Sparkle-$SPARKLE.tar.xz" -o Sparkle/sparkle.tar.xz
    echo "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27  Sparkle/sparkle.tar.xz" | shasum -a 256 -c -
    tar -xf Sparkle/sparkle.tar.xz -C "Sparkle/$SPARKLE" && rm Sparkle/sparkle.tar.xz
fi
# Without -target this toolchain stamps minos 28.0 and macOS 27 refuses to open the app (-10825).
SWIFTC="swiftc -target $(uname -m)-apple-macos14 -F Sparkle/$SPARKLE -framework Sparkle"

if [ "$1" = test ]; then
    # Top-level globals load the bundle's sound as the binary starts, so the tests run from a bundle too.
    T=.build/Test.app/Contents
    mkdir -p "$T/MacOS" "$T/Resources" && cp notify.wav "$T/Resources/"
    $SWIFTC -D TESTING -Xlinker -rpath -Xlinker "$PWD/Sparkle/$SPARKLE" gn.swift -o "$T/MacOS/gn"
    exec "$T/MacOS/gn" --test
fi

VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
VERSION="${VERSION:-0.0.0}"
# Sparkle compares this, so it has to grow with every release: the commit count does.
BUILD="$(git rev-list --count HEAD)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp notify.wav "$APP/Contents/Resources/"
cp -R "Sparkle/$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/"
$SWIFTC -O -Xlinker -rpath -Xlinker @executable_path/../Frameworks gn.swift -o "$APP/Contents/MacOS/gn"
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
"$APP/Contents/MacOS/gn" --icon AppIcon.iconset/icon_512x512@2x.png
for s in 16 32 128 256 512; do
    sips -z $s $s AppIcon.iconset/icon_512x512@2x.png --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s * 2)) $((s * 2)) AppIcon.iconset/icon_512x512@2x.png --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -r AppIcon.iconset
# macOS ties notification permission, Focus and summary settings to the bundle ID, so changing it resets them.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>gn</string>
<key>CFBundleName</key><string>osk/gn</string>
<key>CFBundleDisplayName</key><string>osk/gn</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleIdentifier</key><string>io.github.oskar-nilsen-roos.oskgn</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<!-- Alerts stay until dismissed; macOS reads this only as the default, the first time it sees the app. -->
<key>NSUserNotificationAlertStyle</key><string>alert</string>
<!-- release.sh uploads appcast.xml to every release, so the latest release's copy is always the current feed. -->
<key>SUFeedURL</key><string>https://github.com/Oskar-Nilsen-Roos/oskgn/releases/latest/download/appcast.xml</string>
<key>SUPublicEDKey</key><string>$ED_KEY</string>
<key>SUEnableAutomaticChecks</key><true/>
</dict></plist>
PLIST

if [ -z "$SIGN_ID" ]; then
    codesign -s - --force --deep "$APP"
    exit 0
fi
# Inside out, as Sparkle's docs order it; --deep would drop the Downloader's entitlements.
F="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
sign() { codesign --force --timestamp --options runtime -s "$SIGN_ID" "$@"; }
sign "$F/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$F/XPCServices/Downloader.xpc"
sign "$F/Autoupdate" "$F/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign "$APP"
