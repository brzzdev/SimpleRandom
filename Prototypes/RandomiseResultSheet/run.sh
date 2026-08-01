#!/bin/bash
# PROTOTYPE — throwaway. Builds the randomise-result-sheet prototype straight to the simulator, no Xcode project.
#   ./Prototypes/RandomiseResultSheet/run.sh
set -euo pipefail

cd "$(dirname "$0")"

DEVICE="${DEVICE:-iPhone 17 Pro}"
BUNDLE_ID="dev.brzz.ResultSheetPrototype"
BUILD=".build"
APP="$BUILD/ResultSheetPrototype.app"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

rm -rf "$APP"
mkdir -p "$APP"

swiftc \
	-sdk "$SDK" \
	-target arm64-apple-ios26.0-simulator \
	-swift-version 6 \
	-parse-as-library \
	-O \
	-o "$APP/ResultSheetPrototype" \
	Sources/*.swift

cat >"$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>ResultSheetPrototype</string>
	<key>CFBundleIdentifier</key><string>dev.brzz.ResultSheetPrototype</string>
	<key>CFBundleName</key><string>SR Result Sheet</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSRequiresIPhoneOS</key><true/>
	<key>MinimumOSVersion</key><string>26.0</string>
	<key>UIDeviceFamily</key><array><integer>1</integer></array>
	<key>UILaunchScreen</key><dict/>
	<key>UISupportedInterfaceOrientations</key>
	<array><string>UIInterfaceOrientationPortrait</string></array>
</dict>
</plist>
PLIST

UDID="$(xcrun simctl list devices available -j | python3 -c "
import json,sys
data = json.load(sys.stdin)['devices']
for runtime, devices in data.items():
    if 'iOS-26' not in runtime: continue
    for device in devices:
        if device['name'] == '''$DEVICE''': print(device['udid']); raise SystemExit
raise SystemExit('no matching iOS 26 device')
")"

xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$UDID"
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@"
