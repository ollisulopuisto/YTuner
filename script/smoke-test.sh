#!/bin/sh
# Start a freshly built YTuner against a throwaway config and check that it
# actually serves the vTuner endpoints an AVR hits first.
#
#   ./script/smoke-test.sh [path-to-ytuner]
#
# Radio-browser and the DNS server are switched off so the test stays offline
# and needs no privileged ports.
set -eu

# shellcheck disable=SC1007  # CDPATH= is a deliberate empty assignment for cd
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BIN=${1:-}
if [ -z "$BIN" ]; then
  # shellcheck disable=SC2012  # one glob under bin/, named by the target triple
  BIN=$(ls "$ROOT"/bin/*/ytuner 2>/dev/null | head -1) \
    || { echo "error: no binary found; run script/build.sh first" >&2; exit 1; }
fi
[ -x "$BIN" ] || { echo "error: $BIN is not executable" >&2; exit 1; }

PORT=${PORT:-18100}
WORK=$(mktemp -d)
PID=""
cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
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

# Frontier Silicon radios (Hama, Medion, Technisat, Roberts, Pure, Sangean,
# Karcher and the rest) speak the same vTuner protocol as the AVRs, but ask for
# it two path segments deeper: /setupapp/<vendor>/asp/BrowseXML/loginXML.asp
# rather than /setupapp/<vendor>/loginxml.asp. The route wildcard happens to
# span both, which is the only reason those radios work at all -- so it is
# asserted here rather than left to chance. A router change that narrowed the
# wildcard to a single segment would otherwise break every Frontier device
# without breaking a single test.
echo "Frontier Silicon path shape"
check "deep path token handshake" \
  "/setupapp/karcher/asp/BrowseXML/loginXML.asp?token=0"        "EncryptedToken"
check "deep path main menu" \
  "/setupapp/karcher/asp/BrowseXML/loginXML.asp?mac=aabbccddee" "<ListOfItems>"
check "deep path station lookup" \
  "/setupapp/karcher/asp/BrowseXML/statxml.asp?mac=aabbccddee&id=x" "<ListOfItems>"

if [ "$fail" -ne 0 ]; then
  echo "--- server log ---" >&2
  cat "$WORK/server.log" >&2
  exit 1
fi
echo "All smoke checks passed."
