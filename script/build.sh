#!/bin/sh
# Build Retuner on Linux/BSD with plain FPC — no Lazarus IDE required.
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

# shellcheck disable=SC1007  # CDPATH= is a deliberate empty assignment for cd
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

# ---- Target ------------------------------------------------------------------
# Empty means "whatever this compiler builds by default". Set it to cross-
# compile, e.g. FPC_FLAGS='-Px86_64 -Twin64' on a 32-bit Windows compiler that
# carries the x86_64 cross-compiler alongside it. The same flags have to reach
# the queries below, or the output lands in a directory named after the host.
FPC_FLAGS=${FPC_FLAGS:-}

# ---- Resource compiler -------------------------------------------------------
# FPC drives the resource step with windres-style arguments. On ELF targets we
# have fpcres instead, so bridge the two command lines.
# shellcheck disable=SC2086  # FPC_FLAGS is a deliberately split flag list
OUT_CPU=$(fpc $FPC_FLAGS -iTP)
# shellcheck disable=SC2086  # ditto
OUT_OS=$(fpc $FPC_FLAGS -iTO)
BUILD_DIR=$ROOT/.build/$OUT_CPU-$OUT_OS
mkdir -p "$BUILD_DIR/units"

# Windows has the real windres, and an .exe suffix to go with it. Everything
# below that differs between the two lives here rather than in the fpc line.
case "$OUT_OS" in
  win32|win64) RESOURCE_FLAG=""; EXE_SUFFIX=".exe" ;;
  *)           RESOURCE_FLAG="-FC$BUILD_DIR/windres"; EXE_SUFFIX="" ;;
esac

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

# Under Git Bash the shell hands out /d/a/... and the compiler is a native
# Windows program that reads that as \d\a\..., a path that does not exist. It
# fails as "Can't create object file", which names the symptom and not the
# cause. cygpath is how the two agree; everywhere else this is the identity.
winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    printf '%s' "$1"
  fi
}

if [ -n "${DEBUG:-}" ]; then
  OPTS="-O- -gl -gw"
elif [ -n "${CHECKED:-}" ]; then
  # Range, overflow and object-method-call checking. These turn a class of
  # latent bug into a loud failure at the point it happens rather than a wrong
  # answer somewhere later, which is worth a build that CI runs the test suites
  # against even though the shipped binary does not carry the cost.
  #
  # -dUSE_HEAPTRC rather than -gh: see the uses clause in src/retuner.pas. -gh
  # puts heaptrc first, where cmem's initialization then replaces the memory
  # manager underneath it; the define lists heaptrc after cmem so it wraps it
  # and actually sees the program's allocations.
  OPTS="-O1 -Cr -Co -CR -gl -gh -dNO_CMEM"
else
  OPTS="-O2 -Xs"
fi

# shellcheck disable=SC2086
fpc $FPC_FLAGS -MObjFPC -Scghi $OPTS -vew $RESOURCE_FLAG \
  -Fu"$(winpath "$LAZUTILS_DIR")" \
  -Fu"$(winpath "$INDY_DIR/Core")" -Fu"$(winpath "$INDY_DIR/System")" \
  -Fu"$(winpath "$INDY_DIR/Protocols")" \
  -Fi"$(winpath "$INDY_DIR/Core")" -Fi"$(winpath "$INDY_DIR/System")" \
  -Fi"$(winpath "$INDY_DIR/Protocols")" \
  -Fu"$(winpath "$ROOT/src")" \
  -FU"$(winpath "$BUILD_DIR/units")" \
  -o"$(winpath "$TARGET_DIR/retuner$EXE_SUFFIX")" \
  "$(winpath "$ROOT/src/retuner.pas")"

echo "Built $TARGET_DIR/retuner$EXE_SUFFIX"
