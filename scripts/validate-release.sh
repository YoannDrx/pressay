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

if [[ "$marketing_version" != "1.2.0" ]]; then
  echo "La série 1.2 doit conserver MARKETING_VERSION=1.2.0 (trouvé: $marketing_version)." >&2
  exit 1
fi

release_kind="development"
if [[ -n "$expected_tag" ]]; then
  if [[ "$expected_tag" == "v1.2.0" ]]; then
    release_kind="stable"
    if [[ "$build_number" -ne 12099 ]]; then
      echo "La stable v1.2.0 exige le build 12099 (trouvé: $build_number)." >&2
      exit 1
    fi
  elif [[ "$expected_tag" =~ '^v1\.2\.0-beta\.([1-9][0-9]?)$' ]]; then
    release_kind="beta"
    beta_number="${match[1]}"
    expected_build=$((12000 + beta_number))
    if [[ "$build_number" -lt 12001 || "$build_number" -gt 12089
          || "$build_number" -ne "$expected_build" ]]; then
      echo "$expected_tag exige le build $expected_build dans la plage 12001–12089 (trouvé: $build_number)." >&2
      exit 1
    fi
  elif [[ "$expected_tag" =~ '^v1\.2\.0-rc\.([1-8])$' ]]; then
    release_kind="rc"
    rc_number="${match[1]}"
    expected_build=$((12090 + rc_number))
    if [[ "$build_number" -ne "$expected_build" ]]; then
      echo "$expected_tag exige le build $expected_build (trouvé: $build_number)." >&2
      exit 1
    fi
  else
    echo "Tag invalide: $expected_tag. Attendu: v1.2.0, v1.2.0-beta.N ou v1.2.0-rc.N." >&2
    exit 1
  fi
elif [[ "$build_number" -lt 12001 || "$build_number" -gt 12099 ]]; then
  echo "Un build de développement 1.2 doit être compris entre 12001 et 12099." >&2
  exit 1
fi

last_published_build="${LAST_PUBLISHED_BUILD:-0}"
if [[ "$last_published_build" != <-> ]]; then
  echo "LAST_PUBLISHED_BUILD doit être numérique." >&2
  exit 1
fi
if [[ "$last_published_build" -gt 0 && "$build_number" -le "$last_published_build" ]]; then
  echo "Le build $build_number doit être supérieur au dernier publié ($last_published_build)." >&2
  exit 1
fi

echo "Version validée: ${expected_tag:-v$marketing_version-dev}, type $release_kind, build $build_number, $bundle_identifier"
