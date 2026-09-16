#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <Mach-O executable> <dSYM bundle>" >&2
  exit 2
fi

test -f "$1"
test -d "$2/Contents/Resources/DWARF"

binary_uuids=$(xcrun dwarfdump --uuid "$1" | awk '/^UUID:/ { print $2, $3 }' | sort)
symbol_uuids=$(xcrun dwarfdump --uuid "$2" | awk '/^UUID:/ { print $2, $3 }' | sort)
if [[ -z "$binary_uuids" || "$binary_uuids" != "$symbol_uuids" ]]; then
  echo "The dSYM does not match the executable architectures and UUIDs." >&2
  exit 1
fi

echo "dSYM matches the executable: $binary_uuids"
