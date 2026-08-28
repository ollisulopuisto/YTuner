#!/bin/sh
# Build a preset for every country, one at a time, in the order somebody is
# most likely to want them.
#
#   ./script/build-all-presets.sh                 # start, or resume
#   nohup ./script/build-all-presets.sh &         # and leave it
#   ./script/build-all-presets.sh --dry-run       # just print the order
#   ./script/build-all-presets.sh fi se no        # only these
#
# This takes hours. Every stream in every preset is connected to and has to
# answer with audio before it is kept, which is the whole point -- a preset
# full of dead links is worse than no preset, because the receiver's only
# feedback is a spinner. So it is slow by design, not by accident.
#
# It is resumable: a country whose preset already exists is skipped, so an
# interrupted run continues where it stopped. Each file is written to a
# temporary name and moved into place only when make-preset.py succeeds, so an
# interruption never leaves a half-written preset that the next run would then
# skip as done.
#
# One country failing never stops the run. radio-browser goes away, a mirror
# times out, a country turns out to have nothing that plays: each is logged and
# the next country starts. The summary at the end names every one that failed,
# and rerunning retries exactly those, because no file was written for them.
set -eu

# shellcheck disable=SC1007  # CDPATH= is a deliberate empty assignment for cd
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTDIR=${OUTDIR:-$ROOT/presets}
LOG=${LOG:-$OUTDIR/build.log}
# Overridable so the wrapper's own logic - resume, the partial file, what it
# does with a failure - can be exercised without asking radio-browser for
# anything.
MAKE=${MAKE:-$ROOT/script/make-preset.py}
# radio-browser is a volunteer service and this asks it for every country in
# the world. A pause between them costs nothing here and is the difference
# between a courteous client and a rude one.
PAUSE=${PAUSE:-5}
FORCE=0
DRY=0

while [ $# -gt 0 ]; do
  case $1 in
    --force)   FORCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --) shift; break ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) break ;;
  esac
done

[ -f "$MAKE" ] || { echo "error: $MAKE not found" >&2; exit 1; }
command -v python3 >/dev/null || { echo "error: python3 is required" >&2; exit 1; }

# Finland first because that is where this was tested, then the two largest
# English-speaking audiences, then the EU by population, then the rest of the
# world by population. Non-EU Europe leads the remainder: those broadcasters
# are the ones an EU listener is next most likely to want.
COUNTRIES="
fi us gb
de fr it es pl ro nl be cz pt se gr hu at bg dk sk ie hr lt si lv ee cy lu mt
ru ua ch no rs by al ba md mk is me ge am az xk
in id br ng bd mx jp ph eg vn tr ir th za tz co ke kr ar dz sd ug iq ca ma uz
pe my ao gh mz np ye ve mg au ci cm lk tw sy bf ml cl kz mw zm ec ne gt sn td
so zw gn rw bj tn bi bo ht ae cu jo do nz sg hk il pk mm af sa kw qa om lb
cr pa uy py sv hn ni jm tt bs bb gy sr bz
"

if [ $# -gt 0 ]; then
  COUNTRIES=$*
fi

# One space-separated list, deduplicated, order preserved. The splitting is the
# point here - COUNTRIES is a list, not a string - so the usual quoting advice
# is inverted and the dedup catches anything that appears twice.
# shellcheck disable=SC2086
ORDER=$(printf '%s\n' $COUNTRIES | awk 'NF && !seen[$0]++' | tr '\n' ' ')

if [ "$DRY" = 1 ]; then
  n=0
  for c in $ORDER; do
    n=$((n + 1))
    if [ -s "$OUTDIR/$c.ini" ] && [ "$FORCE" = 0 ]; then
      printf '%3d  %s  (have it)\n' "$n" "$c"
    else
      printf '%3d  %s\n' "$n" "$c"
    fi
  done
  echo "$n countries"
  exit 0
fi

mkdir -p "$OUTDIR"
say() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

stop() { say "interrupted; rerun to continue where this stopped"; exit 130; }
trap stop INT TERM

built=0; skipped=0; failed=0; failures=''
# shellcheck disable=SC2086  # a list again, deliberately split
COUNT=$(printf '%s\n' $ORDER | wc -w | tr -d ' ')
say "starting; $COUNT countries, writing to $OUTDIR"

for c in $ORDER; do
  out=$OUTDIR/$c.ini
  if [ -s "$out" ] && [ "$FORCE" = 0 ]; then
    skipped=$((skipped + 1))
    continue
  fi
  say "$c: building"
  tmp=$out.partial
  rm -f "$tmp"
  # Never let one country stop the run: radio-browser goes away, a country has
  # no stations, a mirror times out. Record it and go on.
  if python3 "$MAKE" --country "$c" --out "$tmp" >>"$LOG" 2>&1; then
    if [ -s "$tmp" ]; then
      mv "$tmp" "$out"
      built=$((built + 1))
      say "$c: kept $(grep -c '=' "$out" 2>/dev/null || echo 0) stations"
    else
      rm -f "$tmp"
      failed=$((failed + 1)); failures="$failures $c"
      say "$c: nothing survived the play check"
    fi
  else
    rm -f "$tmp"
    failed=$((failed + 1)); failures="$failures $c"
    say "$c: FAILED (see $LOG)"
  fi
  sleep "$PAUSE"
done

say "done: $built built, $skipped already had one, $failed failed"
[ -z "$failures" ] || say "failed:$failures"
