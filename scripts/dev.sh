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
PY="services/api/.venv/bin/python"
export PYTHONPATH="$ROOT/services/api"

# Xcode 26 lives in /Applications. The command-line tools alone cannot build an
# iOS target, and xcodebuild's error for that names the wrong cause.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }

cmd_setup() {
  need uv
  uv sync --project services/api --locked --extra dev --python 3.13 >/dev/null
  echo "· python env ready"

  if ! pg_isready -q -h localhost -p 5432 2>/dev/null; then
    echo "· postgres is not running — try: brew services start postgresql@17" >&2
    exit 1
  fi
  psql -h localhost -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='novi'" | grep -q 1 \
    || psql -h localhost -d postgres -c "CREATE ROLE novi LOGIN PASSWORD 'novi';" >/dev/null
  for db in novi novi_test; do
    psql -h localhost -d postgres -tc "SELECT 1 FROM pg_database WHERE datname='$db'" | grep -q 1 \
      || createdb -h localhost -O novi "$db"
  done
  echo "· databases ready"
  [ -f .env ] || { cp .env.example .env; echo "· wrote .env — add your AI_API_KEY"; }
  cmd_migrate
  cmd_seed
}

cmd_migrate() { services/api/.venv/bin/alembic -c database/alembic.ini upgrade head; }
cmd_seed()    { $PY -m database.seeds.seed; }
cmd_api()     { services/api/.venv/bin/uvicorn novi.main:app --reload --host 127.0.0.1 --port 8000; }
cmd_test()    { $PY -m pytest services/api/tests "$@"; }

cmd_check() {
  services/api/.venv/bin/ruff check services/api database
  $PY -m pytest services/api/tests -q
  # A model changed without a migration is the failure this catches.
  services/api/.venv/bin/alembic -c database/alembic.ini check
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
