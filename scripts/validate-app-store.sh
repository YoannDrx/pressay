#!/bin/zsh

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
project="$project_root/Pressay.xcodeproj"
scheme="Pressay App Store"
configuration="Release"
derived_data="$(mktemp -d "${TMPDIR:-/tmp}/pressay-appstore.XXXXXX")"

cleanup() {
  rm -rf "$derived_data"
}
trap cleanup EXIT

settings="$(xcodebuild \
  -project "$project" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -showBuildSettings)"

setting() {
  local key="$1"
  printf '%s\n' "$settings" \
    | awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }'
}

bundle_identifier="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
marketing_version="$(setting MARKETING_VERSION)"
build_number="$(setting CURRENT_PROJECT_VERSION)"
entitlements_path="$(setting CODE_SIGN_ENTITLEMENTS)"
info_plist_path="$(setting INFOPLIST_FILE)"
conditions="$(setting SWIFT_ACTIVE_COMPILATION_CONDITIONS)"
sandbox_enabled="$(setting ENABLE_APP_SANDBOX)"

[[ "$bundle_identifier" == "fr.yodev.pressay.appstore" ]] || {
  echo "Bundle ID App Store inattendu: $bundle_identifier" >&2
  exit 1
}
[[ "$marketing_version" == "1.0.0" ]] || {
  echo "Version App Store inattendue: $marketing_version" >&2
  exit 1
}
[[ "$build_number" == <-> && "$build_number" -ge 10001 ]] || {
  echo "Build App Store invalide: $build_number" >&2
  exit 1
}
[[ "$conditions" == *APP_STORE* ]] || {
  echo "La condition APP_STORE est absente." >&2
  exit 1
}
[[ "$sandbox_enabled" == "YES" ]] || {
  echo "ENABLE_APP_SANDBOX doit être activé pour la cible App Store." >&2
  exit 1
}

entitlements="$project_root/$entitlements_path"
info_plist="$project_root/$info_plist_path"
[[ -f "$entitlements" && -f "$info_plist" ]] || {
  echo "Info.plist ou entitlements App Store introuvable." >&2
  exit 1
}

[[ "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw "$entitlements")" == "true" ]]
[[ "$(plutil -extract 'com\.apple\.security\.device\.audio-input' raw "$entitlements")" == "true" ]]
[[ "$(plutil -extract 'com\.apple\.security\.network\.client' raw "$entitlements")" == "true" ]]

for forbidden_key in SUFeedURL SUPublicEDKey SUEnableSystemProfiling; do
  if plutil -extract "$forbidden_key" raw "$info_plist" >/dev/null 2>&1; then
    echo "$forbidden_key ne doit pas être présent dans la build App Store." >&2
    exit 1
  fi
done

[[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$info_plist")" == "false" ]] || {
  echo "La déclaration de chiffrement exempt doit être présente dans Info-AppStore.plist." >&2
  exit 1
}

xcodebuild build \
  -quiet \
  -project "$project" \
  -scheme "$scheme" \
  -configuration "$configuration" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO

app="$derived_data/Build/Products/$configuration/Pressay Companion.app"
binary="$app/Contents/MacOS/Pressay Companion"
privacy_manifest="$app/Contents/Resources/PrivacyInfo.xcprivacy"

[[ -d "$app" && -x "$binary" ]] || {
  echo "Le produit App Store n'a pas été généré." >&2
  exit 1
}
[[ -f "$privacy_manifest" ]] || {
  echo "Le manifeste PrivacyInfo.xcprivacy est absent du bundle." >&2
  exit 1
}
[[ ! -d "$app/Contents/Frameworks/Sparkle.framework" ]] || {
  echo "Sparkle ne doit pas être embarqué dans la build App Store." >&2
  exit 1
}

if otool -L "$binary" | rg -q 'Sparkle'; then
  echo "Le binaire App Store lie encore Sparkle." >&2
  exit 1
fi

for executable in "$app"/Contents/MacOS/*; do
  [[ -f "$executable" ]] || continue
  if nm -u "$executable" 2>/dev/null \
      | rg -q 'AXUIElement|CGEvent(Post|Create|Source|Tap)|RegisterEventHotKey|SPU[A-Z]|Sparkle'; then
    echo "API incompatible avec la distribution App Store détectée dans $executable." >&2
    exit 1
  fi
done

architectures="$(lipo -archs "$binary")"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || {
  echo "Le binaire App Store doit être universel (trouvé: $architectures)." >&2
  exit 1
}

echo "Build App Store validé: $marketing_version ($build_number), $bundle_identifier, $architectures"
