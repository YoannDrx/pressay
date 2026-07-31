#!/bin/zsh

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
project="$project_root/Pressay.xcodeproj"
scheme="Pressay App Store"
team_id="${APPLE_TEAM_ID:-G9WFV7HNV6}"
export_options="$project_root/Pressay/ExportOptions-AppStore.plist"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/pressay-appstore-archive.XXXXXX")"
archive_path="$temporary_directory/PressayCompanion.xcarchive"

cleanup() {
  rm -rf "$temporary_directory"
}
trap cleanup EXIT

if ! security find-identity -v -p codesigning \
    | rg -q "\"Apple Distribution: .+ \\($team_id\\)\""; then
  echo "Certificat Apple Distribution avec clé privée introuvable pour l'équipe $team_id." >&2
  echo "Crée-le dans Xcode > Settings > Accounts > Manage Certificates." >&2
  exit 1
fi

"$project_root/scripts/validate-app-store.sh"

settings="$(xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Release \
  -showBuildSettings)"

marketing_version="$(printf '%s\n' "$settings" \
  | awk -F ' = ' '$1 ~ /^[[:space:]]*MARKETING_VERSION$/ { print $2; exit }')"
build_number="$(printf '%s\n' "$settings" \
  | awk -F ' = ' '$1 ~ /^[[:space:]]*CURRENT_PROJECT_VERSION$/ { print $2; exit }')"
output_directory="$project_root/build/app-store/$marketing_version-$build_number"

if [[ -e "$output_directory" ]]; then
  echo "La destination existe déjà: $output_directory" >&2
  echo "Déplace-la ou choisis un nouveau numéro de build avant de recommencer." >&2
  exit 1
fi

provisioning_arguments=()
if [[ "${ALLOW_PROVISIONING_UPDATES:-0}" == "1" ]]; then
  provisioning_arguments+=("-allowProvisioningUpdates")
fi

xcodebuild archive \
  -quiet \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive_path" \
  DEVELOPMENT_TEAM="$team_id" \
  "${provisioning_arguments[@]}"

archived_app="$archive_path/Products/Applications/Pressay Companion.app"
[[ -d "$archived_app" ]] || {
  echo "L'application est absente de l'archive." >&2
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$archived_app"
[[ "$(codesign -d --entitlements :- "$archived_app" 2>/dev/null \
  | plutil -extract 'com\.apple\.security\.app-sandbox' raw -)" == "true" ]]

mkdir -p "${output_directory:h}"
xcodebuild -exportArchive \
  -quiet \
  -archivePath "$archive_path" \
  -exportPath "$output_directory" \
  -exportOptionsPlist "$export_options" \
  "${provisioning_arguments[@]}"

echo "Archive Mac App Store exportée dans $output_directory"
echo "Valide puis téléverse ce paquet avec Xcode Organizer ou Transporter."
