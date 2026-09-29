#!/bin/bash
# 배포용 .app을 만들어 Developer ID로 서명하고 공증까지 받는다.
#
#   ./release.sh
#
# 필요한 것 (한 번만 준비한다):
#   - Developer ID Application 인증서가 키체인에 있을 것 (유료 Apple Developer Program)
#   - 공증 자격증명을 키체인 프로파일로 저장해둘 것:
#       xcrun notarytool store-credentials meeting-assistant \
#         --apple-id <계정> --team-id <팀 id> --password <앱 암호>
#
# 환경변수로 덮을 수 있다: TEAM_ID, NOTARY_PROFILE
set -euo pipefail
cd "$(dirname "$0")"

TEAM_ID="${TEAM_ID:-N6UD8K5KSC}"
NOTARY_PROFILE="${NOTARY_PROFILE:-meeting-assistant}"

build="$PWD/build/release"
app="$build/export/MeetingAssistant.app"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" MeetingAssistant/Info.plist)
zip="$build/MeetingAssistant-$version.zip"

rm -rf "$build"
mkdir -p "$build"

# 공증은 Hardened Runtime을 요구한다. 프로젝트에 이미 켜져 있다(ENABLE_HARDENED_RUNTIME).
xcodebuild archive -project MeetingAssistant.xcodeproj -scheme MeetingAssistant \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -archivePath "$build/MeetingAssistant.xcarchive"

# Debug는 Apple Development로 서명한다. 여기서 Developer ID로 다시 서명한다 —
# Apple Development 서명본은 그 팀의 프로비저닝이 없는 맥에서 열리지 않는다.
cat > "$build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$build/MeetingAssistant.xcarchive" \
    -exportOptionsPlist "$build/ExportOptions.plist" -exportPath "$build/export"

# 공증은 .app 디렉터리를 그대로 못 받는다. ditto로 싸서 올린다.
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait

# 티켓을 .app에 박아둔다. 이게 있어야 받는 사람이 오프라인에서도 바로 연다.
xcrun stapler staple "$app"
rm "$zip"
ditto -c -k --keepParent "$app" "$zip"

# 받는 사람 맥이 보는 것과 같은 판정. accepted가 아니면 Gatekeeper 경고가 뜬다.
spctl -a -vvv -t install "$app"

echo
echo "완료: $zip"
echo "GitHub Releases에 이 파일을 올린다."
