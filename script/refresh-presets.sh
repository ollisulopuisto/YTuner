#!/bin/sh
# Re-check every shipped preset and record what no longer plays.
#
#   ./script/refresh-presets.sh [preset-directory] [strikes-file]
#
# Run weekly by .github/workflows/preset-refresh.yml, which opens a pull
# request if this leaves anything changed. It deliberately does not commit:
# what belongs in a national preset is a human decision, and a station can stop
# answering for reasons that have nothing to do with it being gone.
#
# Removal takes --strike-limit consecutive weekly failures, so the summary this
# prints is mostly a watchlist rather than a list of removals. See
# presets/README.md and script/make-preset.py.
set -eu

# shellcheck disable=SC1007  # CDPATH= is a deliberate empty assignment for cd
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DIR=${1:-$ROOT/presets}
STRIKES=${2:-$DIR/strikes.json}
GEN="$ROOT/script/make-preset.py"

# A preset that has not been generated yet is not an error: the repository
# ships the generator before it ships the files.
count=0
for f in "$DIR"/*.ini; do
  [ -e "$f" ] || continue
  count=$((count + 1))
done
if [ "$count" -eq 0 ]; then
  echo "No presets in $DIR yet; nothing to re-check."
  exit 0
fi

echo "Re-checking $count preset(s) in $DIR"
echo
for f in "$DIR"/*.ini; do
  [ -e "$f" ] || continue
  echo "### $(basename "$f")"
  # A country whose radio-browser entries are all unreachable should not stop
  # the other countries being checked, so a failure here is reported and the
  # loop goes on.
  "$GEN" --prune "$f" --strikes "$STRIKES" --timeout 8 2>&1 \
    || echo "  (make-preset.py exited non-zero for $(basename "$f"))"
  echo
done
