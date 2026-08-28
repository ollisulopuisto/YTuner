#!/bin/sh
# Update an installed Retuner to the latest release, and put the old one back
# if the new one does not come up.
#
#   sudo ./retuner-update.sh            # update if there is a newer release
#   sudo ./retuner-update.sh --check    # say what would happen, change nothing
#
# Environment: PREFIX (default /usr/local/retuner), REPO, SERVICE, RESTART_CMD.
#
# This is meant to run unattended, on a machine nobody is sitting at - which is
# the whole reason the rollback exists. A release that does not start would
# otherwise leave the receiver with no station list until somebody visits.
set -eu

REPO=${REPO:-ollisulopuisto/retuner}
PREFIX=${PREFIX:-/usr/local/retuner}
SERVICE=${SERVICE:-io.github.ollisulopuisto.retuner}
API=${API:-https://api.github.com}
DOWNLOAD=${DOWNLOAD:-https://github.com}
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say() { echo "$(date '+%Y-%m-%d %H:%M:%S') retuner-update: $*"; }
die() { say "$*" >&2; exit 1; }

# Which archive this machine wants. The target triple is what the build script
# and the release assets both use, not what uname says.
case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux)  os=linux ;;
  *) die "unsupported system $(uname -s)" ;;
esac
case "$(uname -m)" in
  arm64|aarch64) cpu=aarch64 ;;
  x86_64|amd64)  cpu=x86_64 ;;
  *) die "unsupported architecture $(uname -m)" ;;
esac
[ "$os" = linux ] && [ "$cpu" = aarch64 ] && die "no aarch64-linux release is built"
TARGET="$cpu-$os"

[ -x "$PREFIX/retuner" ] || die "no installed binary at $PREFIX/retuner"

# The installed version. Written here on every successful update; absent on an
# install that predates this script, which is treated as "unknown, so update".
INSTALLED=$(cat "$PREFIX/.version" 2>/dev/null || echo unknown)

# The latest version, without parsing any JSON: /releases/latest redirects to
# the tag, and the tag is the version with a 'v' on the front.
latest_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$DOWNLOAD/$REPO/releases/latest") \
  || die "could not reach $DOWNLOAD/$REPO/releases/latest"
LATEST=${latest_url##*/tag/}
LATEST=${LATEST#v}
case "$LATEST" in
  ''|*/*) die "could not read a version out of $latest_url" ;;
esac

say "installed $INSTALLED, latest $LATEST, target $TARGET"
if [ "$INSTALLED" = "$LATEST" ]; then
  say "already current"
  exit 0
fi
if [ "$CHECK_ONLY" = 1 ]; then
  say "would update $INSTALLED -> $LATEST"
  exit 0
fi

ASSET="retuner-$LATEST-$TARGET.tar.gz"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

say "downloading $ASSET"
curl -fsSL -o "$WORK/$ASSET" "$DOWNLOAD/$REPO/releases/download/v$LATEST/$ASSET" \
  || die "download failed"

# Best effort integrity check. TLS to GitHub already says the bytes came from
# GitHub, so this is guarding against a truncated or half-uploaded asset rather
# than against an attacker. The release API carries a sha256 per asset; if it
# cannot be read, that is not a reason to refuse to update.
digest=$(curl -fsS "$API/repos/$REPO/releases/latest" 2>/dev/null \
  | tr -d ' \n' | tr '{' '\n' | grep -F "\"name\":\"$ASSET\"" \
  | sed -n 's/.*"digest":"sha256:\([0-9a-f]\{64\}\)".*/\1/p' | head -1) || digest=
if [ -n "$digest" ]; then
  if command -v shasum >/dev/null 2>&1; then
    got=$(shasum -a 256 "$WORK/$ASSET" | cut -d' ' -f1)
  else
    got=$(sha256sum "$WORK/$ASSET" | cut -d' ' -f1)
  fi
  [ "$got" = "$digest" ] || die "sha256 mismatch: got $got, expected $digest"
  say "sha256 verified"
else
  say "no published digest found; continuing on the TLS transport alone"
fi

tar -xzf "$WORK/$ASSET" -C "$WORK" || die "archive did not extract"
NEW="$WORK/retuner-$LATEST-$TARGET/retuner"
[ -x "$NEW" ] || die "no binary inside the archive at $NEW"

# Prove the new binary serves before it becomes the installed one. A build that
# cannot start is the failure this whole script exists to survive, and finding
# out here costs nothing.
PROBE_PORT=${PROBE_PORT:-18999}
mkdir -p "$WORK/probe/config"
cp "$NEW" "$WORK/probe/retuner"
cat > "$WORK/probe/retuner.ini" <<INI
[Configuration]
INIVersion=1.2.2
MessageInfoLevel=4
IPAddress=127.0.0.1
[WebServer]
WebServerIPAddress=127.0.0.1
WebServerPort=$PROBE_PORT
[DNSServer]
Enable=0
[RadioBrowser]
Enable=0
[MyStations]
Enable=0
INI
( cd "$WORK/probe" && ./retuner > probe.log 2>&1 ) &
probe_pid=$!
probe_ok=0
i=0
while [ "$i" -lt 100 ]; do
  if curl -fsS --noproxy '*' -o /dev/null \
       "http://127.0.0.1:$PROBE_PORT/setupapp/x/loginxml.asp?token=0" 2>/dev/null; then
    probe_ok=1; break
  fi
  kill -0 "$probe_pid" 2>/dev/null || break
  i=$((i + 1)); sleep 0.2
done
kill "$probe_pid" 2>/dev/null || true
wait "$probe_pid" 2>/dev/null || true
if [ "$probe_ok" != 1 ]; then
  say "the downloaded binary did not serve; keeping $INSTALLED"
  sed -n '$p' "$WORK/probe/probe.log" >&2 2>/dev/null || true
  exit 1
fi
say "the new binary serves"

# Where the service answers, so the health check below asks the right socket.
# A specific WebServerIPAddress means it is not listening on loopback at all.
host=$(sed -n 's/^WebServerIPAddress=//p' "$PREFIX/retuner.ini" 2>/dev/null | head -1)
case "$host" in ''|default|0.0.0.0) host=127.0.0.1 ;; esac
port=$(sed -n 's/^WebServerPort=//p' "$PREFIX/retuner.ini" 2>/dev/null | head -1)
[ -n "$port" ] || port=80

# Overridable so an install that is not launchd-with-this-label - a different
# unit name, a container, the test suite - can say how to restart itself. A
# failing restart is reported by the health check below, not by set -e here.
if [ -z "${RESTART_CMD:-}" ]; then
  if [ "$os" = darwin ]; then
    RESTART_CMD="launchctl kickstart -k system/$SERVICE"
  else
    RESTART_CMD="systemctl restart $SERVICE"
  fi
fi
restart() {
  say "restarting: $RESTART_CMD"
  # shellcheck disable=SC2086  # deliberately word-split: this is a command line
  sh -c "$RESTART_CMD" >/dev/null 2>&1 || say "the restart command reported a failure"
}
healthy() {
  i=0
  while [ "$i" -lt 150 ]; do
    if curl -fsS --noproxy '*' -o /dev/null \
         "http://$host:$port/setupapp/x/loginxml.asp?token=0" 2>/dev/null; then
      return 0
    fi
    i=$((i + 1)); sleep 0.2
  done
  return 1
}

# Only the binary is replaced. retuner.ini and config/ are the user's, and the
# archive carries its own copies of both - copying those over an install is how
# somebody's filters, stations and podcasts would silently revert to the
# shipped defaults on a routine update.
say "installing $LATEST"
cp "$PREFIX/retuner" "$PREFIX/retuner.previous"
cp "$NEW" "$PREFIX/retuner.new"
chmod +x "$PREFIX/retuner.new"
mv "$PREFIX/retuner.new" "$PREFIX/retuner"
restart

if healthy; then
  printf '%s\n' "$LATEST" > "$PREFIX/.version"
  say "updated $INSTALLED -> $LATEST"
  exit 0
fi

say "the service did not answer on $host:$port after the update; rolling back"
cp "$PREFIX/retuner.previous" "$PREFIX/retuner"
restart
if healthy; then
  say "rolled back to $INSTALLED"
else
  say "rolled back to $INSTALLED and it is STILL not answering - look at this by hand"
fi
exit 1
