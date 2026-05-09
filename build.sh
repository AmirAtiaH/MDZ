#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

case "$(uname -s)" in
  Linux)  ODIN=${ODIN:-odin} ;;
  Darwin) ODIN=${ODIN:-odin} ;;
  *)      echo "Unsupported OS"; exit 1 ;;
esac

echo "==> Building mdz (fast)..."
$ODIN build . -o:aggressive -microarch:native -no-bounds-check -disable-assert -lto:thin
echo "Done: ./mdz"
