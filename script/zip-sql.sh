#!/bin/sh
# Pack src/sql/*.sql into res/*.zip for embedding via res/sql.rc.
# POSIX equivalent of zip-sql.bat. Run from anywhere; paths resolve to the repo.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SQL_DIR="$SCRIPT_DIR/../src/sql"
RES_DIR="$SCRIPT_DIR/../res"

command -v zip >/dev/null 2>&1 || { echo "zip not found; install it first." >&2; exit 1; }

for sql in "$SQL_DIR"/*.sql; do
  name=$(basename "$sql" .sql)
  rm -f "$RES_DIR/$name.zip"
  zip -q -j "$RES_DIR/$name.zip" "$sql"
  echo "packed $name.zip"
done
