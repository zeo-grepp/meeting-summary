#!/bin/bash
# 팀원에게 줄 .zip을 만든다. 배포하는 사람만 쓴다.
#
# Developer ID 인증서가 없어 ad-hoc으로 서명한다. 받는 쪽은 Gatekeeper를
# 한 번 넘겨야 하고, 그 방법은 루트 README에 적어뒀다.
set -euo pipefail

cd "$(dirname "$0")"

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

xcodebuild -project MeetingAssistant.xcodeproj -scheme MeetingAssistant \
    -configuration Release -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
    build > "$BUILD_DIR/build.log" || { tail -30 "$BUILD_DIR/build.log"; exit 1; }

APP="$BUILD_DIR/Build/Products/Release/MeetingAssistant.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" MeetingAssistant/Info.plist)
ZIP="$PWD/MeetingAssistant-$VERSION.zip"

# ditto는 서명과 심볼릭 링크를 보존한다. zip(1)은 서명을 깨뜨린다.
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

codesign --verify --strict "$APP"
echo "만들어졌습니다: $ZIP"
# 태그 접두사로 앱 종류를 구분한다. app-v는 Python 없이 도는 쪽(feat-team-deploy)이다.
echo "올리기:  gh release create script-v$VERSION \"$ZIP\""
