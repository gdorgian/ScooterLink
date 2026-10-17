#!/usr/bin/env bash
# Build ScooterLink and install it on a paired iPhone (Developer Mode on).
#   bash App/install-device.sh <device-udid>     (find it with: xcrun devicectl list devices)
# Signing comes from Config/Signing.xcconfig (copy Config/Signing.example.xcconfig).
set -euo pipefail
cd "$(dirname "$0")"
DEVICE="${1:-${SCOOTERLINK_DEVICE:-}}"
[[ -n "$DEVICE" ]] || { echo "usage: $0 <device-udid>  (or set SCOOTERLINK_DEVICE)"; exit 1; }
DERIVED="$PWD/build/device"
xcodegen generate >/dev/null
xcodebuild -project ScooterLink.xcodeproj -scheme ScooterLink -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath "$DERIVED" -allowProvisioningUpdates build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
APP="$DERIVED/Build/Products/Release-iphoneos/ScooterLink.app"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" \
  || echo "Installed. Unlock the iPhone and open ScooterLink."
