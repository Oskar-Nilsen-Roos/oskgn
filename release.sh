#!/bin/sh
# Builds, notarizes and publishes the release for the v* tag on HEAD. The Release workflow runs it on the self-hosted runner.
set -e
cd "$(dirname "$0")"
# The Developer ID cert's full name, as `security find-identity -v -p codesigning` lists it.
export SIGN_ID="Developer ID Application: Oskar Nilsen Roos (NV9KD865ZN)"
[ -n "$SIGN_ID" ] || { echo "Set SIGN_ID in release.sh" >&2; exit 1; }
grep -q '^ED_KEY=".' build.sh || { echo "Set ED_KEY in build.sh" >&2; exit 1; }
TAG="$(git describe --tags --exact-match)"
APP="osk:gn.app"
ZIP="dist/oskgn-$TAG.zip"
REPO="https://github.com/Oskar-Nilsen-Roos/oskgn"

./build.sh test
./build.sh
rm -rf dist && mkdir dist
ditto -c -k --keepParent "$APP" "$ZIP"
# Credentials from `xcrun notarytool store-credentials oskgn`, kept in the login keychain.
xcrun notarytool submit "$ZIP" --keychain-profile oskgn --wait
# Given a relative path with a ":" in it, stapler crashes ("destination URL is nil"); an absolute one works.
xcrun stapler staple "$PWD/$APP"
rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"

# Prints sparkle:edSignature="…" length="…", the enclosure's attributes.
SIGNATURE="$(Sparkle/*/bin/sign_update --account oskgn "$ZIP")"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel>
<title>osk/gn</title>
<item>
<title>$TAG</title>
<pubDate>$(date -R)</pubDate>
<sparkle:version>$(git rev-list --count HEAD)</sparkle:version>
<sparkle:shortVersionString>${TAG#v}</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<sparkle:fullReleaseNotesLink>$REPO/releases/tag/$TAG</sparkle:fullReleaseNotesLink>
<enclosure url="$REPO/releases/download/$TAG/oskgn-$TAG.zip" type="application/octet-stream" $SIGNATURE/>
</item>
</channel>
</rss>
XML
gh release create "$TAG" "$ZIP" dist/appcast.xml --generate-notes
