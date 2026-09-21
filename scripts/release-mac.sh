#!/bin/bash
# Builds, signs, notarises and staples a Mac app for direct distribution.
#
# This is Developer ID distribution: no App Store, no review, nothing anyone can reject.
# Notarisation is an automated malware scan that usually answers in a few minutes.
#
# Needs, once:
#   1. A "Developer ID Application" certificate in the login keychain.
#      Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application
#   2. Notarisation credentials stored in the keychain:
#      xcrun notarytool store-credentials olai \
#        --apple-id you@example.com --team-id YOURTEAMID --password <app-specific-password>
#      The app-specific password comes from appleid.apple.com ▸ Sign-In and Security.
#
# Then: scripts/release-mac.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/build/release"
archive="$build/Olai.xcarchive"
export_dir="$build/export"
profile="${NOTARY_PROFILE:-olai}"

team="$(grep -m1 'DEVELOPMENT_TEAM:' "$root/project.yml" | awk '{print $2}')"
[ -n "$team" ] || { echo "No DEVELOPMENT_TEAM in project.yml"; exit 1; }

echo "==> Checking for a Developer ID certificate"
security find-identity -v -p codesigning | grep -q "Developer ID Application" || {
  echo "None found. Create one in Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates."
  exit 1
}

echo "==> Archiving"
rm -rf "$build"
xcodegen generate --spec "$root/project.yml" --project "$root" >/dev/null
xcodebuild archive -project "$root/Olai.xcodeproj" -scheme Olai \
  -destination 'generic/platform=macOS' -archivePath "$archive" \
  -configuration Release -allowProvisioningUpdates

echo "==> Exporting with Developer ID"
cat > "$build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$archive" \
  -exportOptionsPlist "$build/ExportOptions.plist" \
  -exportPath "$export_dir" -allowProvisioningUpdates

app="$export_dir/Olai.app"

echo "==> Notarising (Apple usually answers within a few minutes)"
ditto -c -k --keepParent "$app" "$build/Olai.zip"
xcrun notarytool submit "$build/Olai.zip" --keychain-profile "$profile" --wait

echo "==> Stapling, so it opens without a network check"
xcrun stapler staple "$app"
xcrun stapler validate "$app"

echo "==> Building the disk image"
dmg="$build/Olai.dmg"
staging="$build/dmg"
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname "Olai" -srcfolder "$staging" -ov -format UDZO "$dmg" >/dev/null

echo
echo "Done: $dmg"
echo "Anyone can open this; Gatekeeper will accept it without a warning."
