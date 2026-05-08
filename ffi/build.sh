#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

case "$(uname -s)" in
  Linux)  ODIN=${ODIN:-odin}; LIB=libmdz.so ;;
  Darwin) ODIN=${ODIN:-odin}; LIB=libmdz.dylib ;;
  *)      echo "Unsupported OS"; exit 1 ;;
esac

echo "==> Building mdz shared library..."
$ODIN build ffi -build:shared -o:speed -no-bounds-check -disable-assert
echo "Done: $LIB"
