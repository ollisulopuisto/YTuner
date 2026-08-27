#!/bin/sh
# Build YTuner on Linux/BSD with plain FPC — no Lazarus IDE required.
#
#   ./script/build.sh              release build -> bin/<cpu>-<os>/ytuner
#   DEBUG=1 ./script/build.sh      unoptimised build with debug info
#
# Dependencies:
#   fpc, zip, git
#   LazUtils sources  (Debian/Ubuntu: apt install lazarus-src)
#   Indy sources      (cloned into .build/indy on first run)
#
# Override autodetection with INDY_DIR / LAZUTILS_DIR if you keep them elsewhere.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

have fpc || die "fpc not found (Debian/Ubuntu: apt install fp-compiler fp-units-fcl fp-units-net fp-units-db fp-units-misc)"
have zip || die "zip not found (needed to pack the embedded SQL resources)"

# ---- LazUtils (LazUTF8, FileUtil) -------------------------------------------
if [ -z "${LAZUTILS_DIR:-}" ]; then
  for d in /usr/lib/lazarus/*/components/lazutils \
           /usr/share/lazarus/*/components/lazutils \
           /usr/lib/lazarus/components/lazutils \
           "$HOME"/lazarus/components/lazutils; do
    [ -f "$d/lazutf8.pas" ] && { LAZUTILS_DIR=$d; break; }
  done
fi
[ -n "${LAZUTILS_DIR:-}" ] && [ -f "$LAZUTILS_DIR/lazutf8.pas" ] \
  || die "LazUtils sources not found (Debian/Ubuntu: apt install lazarus-src), or set LAZUTILS_DIR"

# ---- Indy --------------------------------------------------------------------
INDY_DIR=${INDY_DIR:-$ROOT/.build/indy/Lib}
if [ ! -f "$INDY_DIR/System/IdGlobal.pas" ]; then
  have git || die "git not found, and Indy is missing; clone it yourself and set INDY_DIR"
  echo "Fetching Indy into .build/indy ..."
  rm -rf "$ROOT/.build/indy"
  mkdir -p "$ROOT/.build"
  git clone --depth 1 https://github.com/IndySockets/Indy.git "$ROOT/.build/indy"
  INDY_DIR=$ROOT/.build/indy/Lib
fi
[ -f "$INDY_DIR/System/IdGlobal.pas" ] || die "Indy sources not found under $INDY_DIR"

# ---- Embedded SQL resources --------------------------------------------------
sh "$ROOT/script/zip-sql.sh" >/dev/null

# ---- Resource compiler -------------------------------------------------------
# FPC drives the resource step with windres-style arguments. On ELF targets we
# have fpcres instead, so bridge the two command lines.
OUT_CPU=$(fpc -iTP)
OUT_OS=$(fpc -iTO)
BUILD_DIR=$ROOT/.build/$OUT_CPU-$OUT_OS
mkdir -p "$BUILD_DIR/units"

SHIM=$BUILD_DIR/windres
cat > "$SHIM" <<'SHIM_EOF'
#!/bin/sh
IN=""; OUT=""; FMT="res"; ARGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --include|--include-dir|-I) shift; ARGS="$ARGS -I $1" ;;
    --define|-D)                shift; ARGS="$ARGS -D $1" ;;
    --output|-o)                shift; OUT="$1" ;;
    --output-format|-O)         shift; FMT="$1" ;;
    --input|-i)                 shift; IN="$1" ;;
    --input-format|-J)          shift ;;
    --preprocessor=*|--preprocessor-arg=*|--codepage=*) ;;
    --preprocessor|--preprocessor-arg) shift ;;
    -*) ;;
    *)  IN="$1" ;;
  esac
  shift
done
exec fpcres -of "$FMT" -o "$OUT" $ARGS "$IN"
SHIM_EOF
chmod +x "$SHIM"

# ---- Compile -----------------------------------------------------------------
TARGET_DIR=$ROOT/bin/$OUT_CPU-$OUT_OS
mkdir -p "$TARGET_DIR"

if [ -n "${DEBUG:-}" ]; then
  OPTS="-O- -gl -gw"
else
  OPTS="-O2 -Xs"
fi

# shellcheck disable=SC2086
fpc -MObjFPC -Scghi $OPTS -vew -FC"$SHIM" \
  -Fu"$LAZUTILS_DIR" \
  -Fu"$INDY_DIR/Core" -Fu"$INDY_DIR/System" -Fu"$INDY_DIR/Protocols" \
  -Fi"$INDY_DIR/Core" -Fi"$INDY_DIR/System" -Fi"$INDY_DIR/Protocols" \
  -Fu"$ROOT/src" \
  -FU"$BUILD_DIR/units" \
  -o"$TARGET_DIR/ytuner" \
  "$ROOT/src/ytuner.pas"

echo "Built $TARGET_DIR/ytuner"
