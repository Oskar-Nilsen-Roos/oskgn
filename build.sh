#!/bin/sh
set -e
cd "$(dirname "$0")"
# Finder shows a ":" in a file name as "/", so this appears as osk/gn.
APP="osk:gn.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp notify.wav "$APP/Contents/Resources/"
# Without -target this toolchain stamps minos 28.0 and macOS 27 refuses to open the app (-10825).
swiftc -O -target "$(uname -m)-apple-macos14" gn.swift -o "$APP/Contents/MacOS/gn"
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
"$APP/Contents/MacOS/gn" --icon AppIcon.iconset/icon_512x512@2x.png
for s in 16 32 128 256 512; do
    sips -z $s $s AppIcon.iconset/icon_512x512@2x.png --out AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s * 2)) $((s * 2)) AppIcon.iconset/icon_512x512@2x.png --out AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -r AppIcon.iconset
# The bundle ID stays local.gitbar: macOS ties notification permission, Focus and summary settings to it.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>gn</string>
<key>CFBundleName</key><string>osk/gn</string>
<key>CFBundleDisplayName</key><string>osk/gn</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>CFBundleIdentifier</key><string>local.gitbar</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSUIElement</key><true/>
<!-- Alerts stay until dismissed; macOS reads this only as the default, the first time it sees the app. -->
<key>NSUserNotificationAlertStyle</key><string>alert</string>
</dict></plist>
PLIST
codesign -s - --force "$APP"
