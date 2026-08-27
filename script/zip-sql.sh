#!/bin/sh
# Pack src/sql/*.sql into res/*.zip for embedding via res/sql.rc.
# POSIX equivalent of zip-sql.bat. Run from anywhere; paths resolve to the repo.
set -eu

# shellcheck disable=SC1007  # CDPATH= is a deliberate empty assignment for cd
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SQL_DIR="$SCRIPT_DIR/../src/sql"
RES_DIR="$SCRIPT_DIR/../res"

# zip everywhere except a Windows runner, which has 7z instead. Both are told
# to store the bare file name: res/sql.rc names the entries, so a stored path
# would leave the resource looking for something that is not in the archive.
if command -v zip >/dev/null 2>&1; then
  pack() { zip -q -j "$1" "$2"; }
elif command -v 7z >/dev/null 2>&1; then
  # shellcheck disable=SC1007  # CDPATH= is a deliberate empty assignment for cd
  pack() { ( CDPATH= cd -- "$(dirname -- "$2")" && 7z a -tzip -bso0 -bsp0 "$1" "$(basename -- "$2")" >/dev/null ); }
else
  echo "neither zip nor 7z found; install one of them first." >&2
  exit 1
fi

for sql in "$SQL_DIR"/*.sql; do
  name=$(basename "$sql" .sql)
  rm -f "$RES_DIR/$name.zip"
  pack "$RES_DIR/$name.zip" "$sql"
  echo "packed $name.zip"
done
