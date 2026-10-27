#!/bin/bash
# Build YTLanguage.dylib inside WSL2. Run from WSL: bash build.sh
# Source lives on the Windows drive; build happens in the Linux filesystem for speed.
#   bash build.sh               release build -> dist/YTLanguage-v<VERSION>.dylib (refuses to overwrite)
#   CHECK_ONLY=1 bash build.sh  compile check only, nothing written to dist/
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
WORK="$HOME/ytlanguage-build"
export THEOS="${THEOS:-$HOME/theos}"
VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"
NAME="YTLanguage-v$VERSION"

if [ -z "${CHECK_ONLY:-}" ] && [ -e "$SRC/dist/$NAME.dylib" ]; then
  echo "dist/$NAME.dylib already exists; bump VERSION before a new release build"; exit 1
fi

rsync -a --delete --exclude '.theos' --exclude 'packages' --exclude 'dist' "$SRC/" "$WORK/"
cd "$WORK"
make clean >/dev/null
make FINALPACKAGE=1 2>&1 | tee build.log

DYLIB="$(find .theos/obj -name 'YTLanguage.dylib' -type f -not -path '*.dSYM/*' | head -1)"
[ -n "$DYLIB" ] || { echo "dylib not found"; exit 1; }

if [ -n "${CHECK_ONLY:-}" ]; then
  echo "CHECK_ONLY: v$VERSION compiled, dist/ untouched"; exit 0
fi

mkdir -p "$SRC/dist"
cp "$DYLIB" "$SRC/dist/$NAME.dylib"
cp build.log "$SRC/dist/$NAME-build.log"

OBJDUMP="$THEOS/toolchain/linux/iphone/bin/llvm-objdump"
{
  echo "Version: $VERSION"
  echo "Built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Source dylib: $WORK/$DYLIB"
  echo; echo "== file"; file "$SRC/dist/$NAME.dylib"
  echo; echo "== sha256"; sha256sum "$SRC/dist/$NAME.dylib"
  echo; echo "== linked dylibs"; "$OBJDUMP" --macho --dylibs-used "$SRC/dist/$NAME.dylib"
} | tee "$SRC/dist/$NAME-build-info.txt"
