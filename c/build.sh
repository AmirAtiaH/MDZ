#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

case "$(uname -s)" in
  Linux)  CC=${CC:-gcc}; LIB_DIR=..; LIBS=-ldl; LIB=libmdz.so ;;
  Darwin) CC=${CC:-clang}; LIB_DIR=..; LIBS=; LIB=libmdz.dylib ;;
  *)      echo "Unsupported OS"; exit 1 ;;
esac

echo "==> Building C example..."
$CC example.c -o mdz_c -I. -L$LIB_DIR -lmdz $LIBS
echo "Done: ./mdz_c"
