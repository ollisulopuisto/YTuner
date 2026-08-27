#!/bin/sh
# Start a freshly built YTuner against a throwaway config and check that it
# actually serves the vTuner endpoints an AVR hits first.
#
#   ./script/smoke-test.sh [path-to-ytuner]
#
# Radio-browser and the DNS server are switched off so the test stays offline
# and needs no privileged ports.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN=${1:-}
if [ -z "$BIN" ]; then
  BIN=$(ls "$ROOT"/bin/*/ytuner 2>/dev/null | head -1) \
    || { echo "error: no binary found; run script/build.sh first" >&2; exit 1; }
fi
[ -x "$BIN" ] || { echo "error: $BIN is not executable" >&2; exit 1; }

PORT=${PORT:-18100}
WORK=$(mktemp -d)
PID=""
cleanup() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
  [ -n "$PID" ] && wait "$PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

cp "$BIN" "$WORK/ytuner"
cat > "$WORK/ytuner.ini" <<EOF
[Configuration]
INIVersion=1.2.2
MessageInfoLevel=4
IPAddress=127.0.0.1
[WebServer]
WebServerIPAddress=127.0.0.1
WebServerPort=$PORT
[DNSServer]
Enable=0
[RadioBrowser]
Enable=0
[MyStations]
Enable=0
[Bookmark]
Enable=1
EOF

( cd "$WORK" && ./ytuner > server.log 2>&1 ) &
PID=$!

# Wait for the listener rather than sleeping a fixed amount.
ready=""
i=0
while [ "$i" -lt 50 ]; do
  if curl -fsS --noproxy '*' -o /dev/null \
       "http://127.0.0.1:$PORT/setupapp/x/loginxml.asp?token=0" 2>/dev/null; then
    ready=1; break
  fi
  kill -0 "$PID" 2>/dev/null || { echo "error: server exited during startup" >&2; cat "$WORK/server.log" >&2; exit 1; }
  i=$((i + 1))
  sleep 0.2
done
[ -n "$ready" ] || { echo "error: server did not start listening" >&2; cat "$WORK/server.log" >&2; exit 1; }

fail=0
check() {
  name=$1; url=$2; expect=$3
  body=$(curl -fsS --noproxy '*' "http://127.0.0.1:$PORT$url" 2>/dev/null || true)
  if printf '%s' "$body" | grep -q "$expect"; then
    echo "  ok   $name"
  else
    echo "  FAIL $name (expected '$expect')"
    printf '       got: %.200s\n' "$body"
    fail=1
  fi
}

echo "Smoke testing $BIN on port $PORT"
check "login token handshake" "/setupapp/x/loginxml.asp?token=0"        "EncryptedToken"
check "main menu"             "/setupapp/x/loginxml.asp?mac=aabbccddee" "<ListOfItems>"
check "about page"            "/ytuner/about?mac=aabbccddee"            "Welcome to Retuner"
check "empty folder message"  "/ytuner/empty?mac=aabbccddee"            "<ItemType>Display</ItemType>"

if [ "$fail" -ne 0 ]; then
  echo "--- server log ---" >&2
  cat "$WORK/server.log" >&2
  exit 1
fi
echo "All smoke checks passed."
