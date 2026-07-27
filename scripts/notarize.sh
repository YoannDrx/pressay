#!/bin/zsh

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
release_dir="${RELEASE_DIR:-$project_root/build/release}"
archive_path="$release_dir/Pressay.xcarchive"
export_path="$release_dir/export"
dmg_path="$release_dir/Pressay.dmg"
checksum_path="$release_dir/Pressay.dmg.sha256"
appcast_path="$release_dir/appcast.xml"

: "${DEVELOPER_ID_APPLICATION:?Définis DEVELOPER_ID_APPLICATION (Developer ID Application: …)}"
: "${APPLE_TEAM_ID:?Définis APPLE_TEAM_ID}"
: "${APPLE_ID:?Définis APPLE_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Définis APPLE_APP_SPECIFIC_PASSWORD}"
: "${SPARKLE_PRIVATE_KEY:?Définis SPARKLE_PRIVATE_KEY}"
: "${SPARKLE_GENERATE_APPCAST:?Définis SPARKLE_GENERATE_APPCAST vers l’outil Sparkle 2.9.2}"

if [[ ! -x "$SPARKLE_GENERATE_APPCAST" ]]; then
  echo "Outil Sparkle introuvable ou non exécutable: $SPARKLE_GENERATE_APPCAST" >&2
  exit 1
fi

"$project_root/scripts/validate-release.sh"

version="$(xcodebuild -project "$project_root/Pressay.xcodeproj" -scheme Pressay -configuration Release -showBuildSettings | awk -F ' = ' '/^[[:space:]]*MARKETING_VERSION = / { print $2; exit }')"
build_number="$(xcodebuild -project "$project_root/Pressay.xcodeproj" -scheme Pressay -configuration Release -showBuildSettings | awk -F ' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION = / { print $2; exit }')"
release_tag="${RELEASE_TAG:-v$version}"
download_url="https://github.com/YoannDrx/pressay/releases/download/$release_tag/"

mkdir -p "$release_dir"
work_dir="$(mktemp -d "$release_dir/work.XXXXXX")"
mount_dir="$work_dir/mount"
staging_dir="$work_dir/dmg"
appcast_dir="$work_dir/appcast"
export_options="$work_dir/ExportOptions.plist"
notary_result="$release_dir/notary-result.json"
notary_log="$release_dir/notary-log.json"
private_key_file="$work_dir/sparkle-private-key"
mounted=0

cleanup() {
  if [[ "$mounted" -eq 1 ]]; then
    hdiutil detach "$mount_dir" -quiet || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

rm -rf "$archive_path" "$export_path"
rm -f "$dmg_path" "$checksum_path" "$appcast_path" "$notary_result" "$notary_log"

/usr/bin/plutil -create xml1 "$export_options"
/usr/bin/plutil -insert method -string developer-id "$export_options"
/usr/bin/plutil -insert signingStyle -string manual "$export_options"
/usr/bin/plutil -insert teamID -string "$APPLE_TEAM_ID" "$export_options"
/usr/bin/plutil -insert signingCertificate -string "$DEVELOPER_ID_APPLICATION" "$export_options"

echo "Archive Release universelle de Pressay $version ($build_number)…"
xcodebuild archive \
  -project "$project_root/Pressay.xcodeproj" \
  -scheme Pressay \
  -configuration Release \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ONLY_ACTIVE_ARCH=NO

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options"

app_path="$export_path/Pressay.app"
if [[ ! -d "$app_path" ]]; then
  echo "Pressay.app est absent de l’export." >&2
  exit 1
fi

echo "Vérification des signatures, entitlements et architectures…"
codesign --verify --deep --strict --verbose=2 "$app_path"
codesign --display --entitlements :- "$app_path" >/dev/null

sparkle_framework="$app_path/Contents/Frameworks/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then
  echo "Sparkle.framework est absent de l’application exportée." >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$sparkle_framework"

architectures="$(lipo -archs "$app_path/Contents/MacOS/Pressay")"
for required_arch in arm64 x86_64; do
  if [[ " $architectures " != *" $required_arch "* ]]; then
    echo "Architecture manquante: $required_arch (trouvé: $architectures)" >&2
    exit 1
  fi
done

mkdir -p "$staging_dir" "$appcast_dir" "$mount_dir"
/usr/bin/ditto "$app_path" "$staging_dir/Pressay.app"
ln -s /Applications "$staging_dir/Applications"

echo "Création et signature de Pressay.dmg…"
hdiutil create \
  -volname Pressay \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$dmg_path"
codesign --verify --verbose=2 "$dmg_path"

echo "Soumission du DMG à la notarisation Apple…"
if ! xcrun notarytool submit "$dmg_path" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait \
  --output-format json >"$notary_result"; then
  submission_id="$(/usr/bin/plutil -extract id raw -o - "$notary_result" 2>/dev/null || true)"
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      "$notary_log" || true
  fi
  echo "La notarisation a échoué. Consulte $notary_result et $notary_log." >&2
  exit 1
fi

notary_status="$(/usr/bin/plutil -extract status raw -o - "$notary_result")"
submission_id="$(/usr/bin/plutil -extract id raw -o - "$notary_result")"
if [[ "$notary_status" != "Accepted" ]]; then
  xcrun notarytool log "$submission_id" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    "$notary_log" || true
  echo "Notarisation non acceptée: $notary_status. Consulte $notary_log." >&2
  exit 1
fi

xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg_path"

echo "Montage et contrôle final du DMG…"
hdiutil attach "$dmg_path" -mountpoint "$mount_dir" -nobrowse -readonly -quiet
mounted=1
mounted_app="$mount_dir/Pressay.app"
if [[ ! -d "$mounted_app" || ! -L "$mount_dir/Applications" || "$(readlink "$mount_dir/Applications")" != "/Applications" ]]; then
  echo "Le contenu du DMG n’est pas conforme." >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=2 "$mounted_app"
spctl --assess --type execute --verbose=4 "$mounted_app"
hdiutil detach "$mount_dir" -quiet
mounted=0

echo "Génération de la somme SHA-256 et de l’appcast Sparkle…"
shasum -a 256 "$dmg_path" | awk '{ print $1 "  Pressay.dmg" }' >"$checksum_path"
/usr/bin/ditto "$dmg_path" "$appcast_dir/Pressay.dmg"
printf '%s' "$SPARKLE_PRIVATE_KEY" >"$private_key_file"
chmod 600 "$private_key_file"

"$SPARKLE_GENERATE_APPCAST" \
  --ed-key-file "$private_key_file" \
  --download-url-prefix "$download_url" \
  --link "https://www.yoann-andrieux.fr/fr/projects/pressay" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o "$appcast_path" \
  "$appcast_dir"

if ! grep -Fq "${download_url}Pressay.dmg" "$appcast_path"; then
  echo "L’appcast ne référence pas l’URL immuable attendue." >&2
  exit 1
fi
if ! grep -Fq 'sparkle:edSignature=' "$appcast_path"; then
  echo "La signature EdDSA est absente de l’appcast." >&2
  exit 1
fi

echo "Release prête:"
echo "  $dmg_path"
echo "  $checksum_path"
echo "  $appcast_path"
