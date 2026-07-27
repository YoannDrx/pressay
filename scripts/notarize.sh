#!/bin/zsh

set -euo pipefail

: "${DEVELOPER_ID_APPLICATION:?Définis DEVELOPER_ID_APPLICATION}"
: "${APPLE_TEAM_ID:?Définis APPLE_TEAM_ID}"
: "${NOTARY_PROFILE:?Définis NOTARY_PROFILE}"

project_root="$(cd "$(dirname "$0")/.." && pwd)"
release_dir="$project_root/build/release"
archive_path="$release_dir/Whisper.xcarchive"
app_path="$archive_path/Products/Applications/Whisper.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Whisper/Info.plist")"
zip_path="$release_dir/Whisper-$version.zip"

mkdir -p "$release_dir"

xcodebuild archive \
  -project "$project_root/Whisper.xcodeproj" \
  -scheme Whisper \
  -configuration Release \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp"

/usr/bin/ditto -c -k --keepParent "$app_path" "$zip_path"
xcrun notarytool submit "$zip_path" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"

/usr/bin/ditto -c -k --keepParent "$app_path" "$zip_path"
echo "Release notarized: $zip_path"
