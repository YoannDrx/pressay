#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
CATALOG_DIR="$REPO_DIR/src-tauri/src/catalog"
CATALOG="$CATALOG_DIR/catalog.json"
PUBLIC_KEY="$CATALOG_DIR/catalog.pub"
SIGNATURE="$CATALOG_DIR/catalog.sig"

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pressay-catalog-sign.XXXXXX")
PRIVATE_KEY="$TMP_DIR/catalog-signing.pem"
PUBLIC_DER="$TMP_DIR/catalog-public.der"
DERIVED_PUBLIC="$TMP_DIR/catalog-public.raw"

cleanup() {
  if [[ -f "$PRIVATE_KEY" ]]; then unlink "$PRIVATE_KEY"; fi
  if [[ -f "$PUBLIC_DER" ]]; then unlink "$PUBLIC_DER"; fi
  if [[ -f "$DERIVED_PUBLIC" ]]; then unlink "$DERIVED_PUBLIC"; fi
  rmdir "$TMP_DIR"
}
trap cleanup EXIT

if [[ -n "${PRESSAY_MODEL_CATALOG_SIGNING_KEY:-}" ]]; then
  printf '%s\n' "$PRESSAY_MODEL_CATALOG_SIGNING_KEY" > "$PRIVATE_KEY"
elif [[ "$(uname -s)" == "Darwin" ]]; then
  KEY_VALUE=$(security find-generic-password \
    -a "$USER" \
    -s app.pressay.models.signing \
    -w)
  printf '%s' "$KEY_VALUE" | base64 -D > "$PRIVATE_KEY"
  unset KEY_VALUE
else
  echo "PRESSAY_MODEL_CATALOG_SIGNING_KEY is required outside macOS" >&2
  exit 1
fi
chmod 600 "$PRIVATE_KEY"

openssl pkey -in "$PRIVATE_KEY" -pubout -outform DER -out "$PUBLIC_DER"
tail -c 32 "$PUBLIC_DER" > "$DERIVED_PUBLIC"
if ! cmp -s "$DERIVED_PUBLIC" "$PUBLIC_KEY"; then
  echo "Refusing to sign: the private key does not match catalog.pub" >&2
  exit 1
fi

openssl pkeyutl \
  -sign \
  -rawin \
  -inkey "$PRIVATE_KEY" \
  -in "$CATALOG" \
  -out "$SIGNATURE"

echo "Signed src-tauri/src/catalog/catalog.json"
