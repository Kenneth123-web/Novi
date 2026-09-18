#!/usr/bin/env bash
# Everything needed to go from a fresh clone to a running stack.
#
#   ./scripts/dev.sh setup     install deps, create the database, migrate, seed
#   ./scripts/dev.sh api       run the API on :8000
#   ./scripts/dev.sh test      run the backend test suite
#   ./scripts/dev.sh check     lint + tests + migration parity
#   ./scripts/dev.sh ios       regenerate the Xcode project and build
#   ./scripts/dev.sh migrate   alembic upgrade head
#   ./scripts/dev.sh seed      (re)seed subjects, concepts and content
#   ./scripts/dev.sh console   run the Cloudflare console Worker on :8788
#   ./scripts/dev.sh ingest    fetch real tutorials (YouTube, Reddit, X, MediaCrawler)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PG_BIN="/opt/homebrew/opt/postgresql@17/bin"
[ -d "$PG_BIN" ] && export PATH="$PG_BIN:$PATH"
PY=".venv/bin/python"

# Xcode 26 lives in /Applications. The command-line tools alone cannot build an
# iOS target, and xcodebuild's error for that names the wrong cause.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }

cmd_setup() {
  need uv
  uv venv .venv --python 3.13 >/dev/null
  VIRTUAL_ENV=.venv uv pip install -e "services/api[dev]" >/dev/null
  echo "· python env ready"

  if ! pg_isready -q -h localhost -p 5432 2>/dev/null; then
    echo "· postgres is not running — try: brew services start postgresql@17" >&2
    exit 1
  fi
  psql -h localhost -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='novi'" | grep -q 1 \
    || psql -h localhost -d postgres -c "CREATE ROLE novi LOGIN PASSWORD 'novi' SUPERUSER;" >/dev/null
  for db in novi novi_test; do
    psql -h localhost -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1 \
      || createdb -h localhost -O novi "$db"
  done
  echo "· databases ready"
  [ -f .env ] || { cp .env.example .env; echo "· wrote .env — add your AI_API_KEY"; }
  cmd_migrate
  cmd_seed
}

cmd_migrate() { .venv/bin/alembic -c database/alembic.ini upgrade head; }
cmd_seed()    { $PY -m database.seeds.seed; }

# xcconfig treats `//` as a comment, so `http://host` is written `http:/$()/host`.
xc_url() { python3 -c 'import sys; print(sys.argv[1].replace("://", ":/$()/", 1))' "$1"; }

set_xc() {
  python3 - "$ROOT/apps/mobile/Configs/Local.xcconfig" "$1" "$2" <<'PY'
from pathlib import Path
import re
import sys

path, key, value = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text() if path.exists() else (
    "// Gitignored. Device URLs are filled by ./scripts/dev.sh api.\n"
    "DEVELOPMENT_TEAM =\n"
)
line = f"{key} = {value}"
pat = re.compile(rf"^{re.escape(key)}\s*=.*$", re.M)
if pat.search(text):
    text = pat.sub(line, text)
else:
    if text and not text.endswith("\n"):
        text += "\n"
    text += line + "\n"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text)
PY
}

sync_lan_urls() {
  local ip usb host
  ip=$(ipconfig getifaddr en0 2>/dev/null || true)
  usb=$(ifconfig -a 2>/dev/null | awk '/inet 169\.254\./ { print $2; exit }')
  host=$(scutil --get LocalHostName 2>/dev/null || true)
  if [ -n "$ip" ]; then
    set_xc NOV_API_BASE_URL "$(xc_url "http://${ip}:8000/v1")"
    echo "· device API  http://${ip}:8000/v1"
  fi
  if [ -n "$usb" ]; then
    set_xc NOV_API_USB_URL "$(xc_url "http://${usb}:8000/v1")"
  fi
  if [ -n "$host" ]; then
    set_xc NOV_API_HOST_URL "$(xc_url "http://${host}.local:8000/v1")"
  fi
}

start_tunnel() {
  command -v cloudflared >/dev/null 2>&1 || return 0
  mkdir -p "$ROOT/.run"
  local log="$ROOT/.run/cloudflared.log"
  cloudflared tunnel --url http://127.0.0.1:8000 --no-autoupdate >"$log" 2>&1 &
  NOVI_TUNNEL_PID=$!
  local url="" i
  for i in $(seq 1 40); do
    url=$(grep -oE 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$log" | head -1 || true)
    [ -n "$url" ] && break
    sleep 0.25
  done
  if [ -n "$url" ]; then
    set_xc NOV_API_TUNNEL_URL "$(xc_url "${url}/v1")"
    echo "· tunnel      ${url}/v1  (rebuild the iOS app to pick this up)"
  else
    echo "· cloudflared did not print a URL yet — see $log" >&2
  fi
}

cmd_api() {
  sync_lan_urls
  NOVI_TUNNEL_PID=""
  start_tunnel
  trap 'if [ -n "${NOVI_TUNNEL_PID:-}" ]; then kill "$NOVI_TUNNEL_PID" 2>/dev/null || true; fi' EXIT
  .venv/bin/uvicorn novi.main:app --reload --host 0.0.0.0 --port 8000
}
cmd_test()    { $PY -m pytest services/api/tests "$@"; }

cmd_check() {
  .venv/bin/ruff check services/api database
  $PY -m pytest services/api/tests -q
  # A model changed without a migration is the failure this catches.
  .venv/bin/alembic -c database/alembic.ini check
}

cmd_ios() {
  need xcodegen
  ( cd apps/mobile && xcodegen generate )
  # DerivedData must stay outside the repo: it sits in iCloud-synced Documents,
  # and the sync daemon puts extended attributes on build products that
  # codesign then refuses.
  xcodebuild -project apps/mobile/Novi.xcodeproj -scheme Novi \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath /tmp/novi-dd build
}

cmd_console() {
  ( cd "$ROOT/services/console" && npm install && npx wrangler d1 migrations apply novi-console --local && npx wrangler dev --port 8788 )
}

cmd_ingest()  { $PY -m novi.services.ingest; }

case "${1:-}" in
  setup|migrate|seed|api|test|check|ios|console|ingest) c="$1"; shift; "cmd_$c" "$@" ;;
  *) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ; exit 1 ;;
esac
