#!/bin/zsh

set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
expected_tag="${RELEASE_TAG:-${GITHUB_REF_NAME:-}}"

settings="$(xcodebuild \
  -project "$project_root/Pressay.xcodeproj" \
  -scheme Pressay \
  -configuration Release \
  -showBuildSettings)"

marketing_version="$(printf '%s\n' "$settings" | awk -F ' = ' '/^[[:space:]]*MARKETING_VERSION = / { print $2; exit }')"
build_number="$(printf '%s\n' "$settings" | awk -F ' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION = / { print $2; exit }')"
bundle_identifier="$(printf '%s\n' "$settings" | awk -F ' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = / { print $2; exit }')"

if [[ -z "$marketing_version" || -z "$build_number" ]]; then
  echo "MARKETING_VERSION ou CURRENT_PROJECT_VERSION est introuvable." >&2
  exit 1
fi
if [[ "$build_number" != <-> ]]; then
  echo "CURRENT_PROJECT_VERSION doit être numérique (trouvé: $build_number)." >&2
  exit 1
fi
if [[ "$bundle_identifier" != "fr.yodev.pressay" ]]; then
  echo "Bundle ID inattendu: $bundle_identifier." >&2
  exit 1
fi

if [[ -n "$expected_tag" && "$expected_tag" != "v$marketing_version" ]]; then
  echo "Le tag $expected_tag ne correspond pas à MARKETING_VERSION=$marketing_version." >&2
  exit 1
fi

echo "Version validée: ${expected_tag:-v$marketing_version}, build $build_number, $bundle_identifier"
