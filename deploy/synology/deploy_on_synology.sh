#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
ENV_FILE="$PROJECT_ROOT/.env"
DATA_ROOT=/volume1/wordcalendar-data

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[ -f "$PROJECT_ROOT/deploy/synology/compose.yaml" ] || fail "deploy/synology/compose.yaml is missing"
[ -f "$PROJECT_ROOT/python/Dockerfile.nas" ] || fail "python/Dockerfile.nas is missing"
[ -f "$PROJECT_ROOT/python/nas_api.py" ] || fail "python/nas_api.py is missing"
[ -f "$PROJECT_ROOT/python/nas_requirements.txt" ] || fail "python/nas_requirements.txt is missing"
[ -f "$ENV_FILE" ] || fail "$ENV_FILE is missing; run generate_tokens.sh and configure it first"
[ -d "$DATA_ROOT" ] || fail "$DATA_ROOT is missing; create the shared folder in DSM first"
command -v docker >/dev/null 2>&1 || fail "Docker CLI is unavailable; install/start Container Manager"

# A fresh Git checkout keeps the NAS deployment sources in their repository locations.
# Materialize the Compose build context expected by Docker Compose without touching .env or data.
mkdir -p "$PROJECT_ROOT/app" "$DATA_ROOT/data" "$DATA_ROOT/backups" || fail "Could not prepare app/data directories"
cp "$PROJECT_ROOT/deploy/synology/compose.yaml" "$PROJECT_ROOT/compose.yaml" || fail "Could not prepare compose.yaml"
cp "$PROJECT_ROOT/python/Dockerfile.nas" "$PROJECT_ROOT/app/Dockerfile.nas" || fail "Could not prepare app/Dockerfile.nas"
cp "$PROJECT_ROOT/python/nas_api.py" "$PROJECT_ROOT/app/nas_api.py" || fail "Could not prepare app/nas_api.py"
cp "$PROJECT_ROOT/python/nas_requirements.txt" "$PROJECT_ROOT/app/nas_requirements.txt" || fail "Could not prepare app/nas_requirements.txt"

if [ "$(id -u)" -eq 0 ]; then
  compose() { docker compose "$@"; }
else
  command -v sudo >/dev/null 2>&1 || fail "Run this script as root or install/use sudo"
  compose() { sudo docker compose "$@"; }
fi

compose version >/dev/null 2>&1 || fail "Docker Compose v2 is unavailable"

env_value() {
  awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$ENV_FILE"
}

USER_TOKEN=$(env_value WORDCALENDAR_NAS_TOKEN)
ADMIN_TOKEN=$(env_value WORDCALENDAR_NAS_ADMIN_TOKEN)
PUSH_URL=$(env_value WORDCALENDAR_NAS_PUSH_URL)
PUSH_SECRET=$(env_value WORDCALENDAR_NAS_PUSH_SECRET)

[ "${#USER_TOKEN}" -ge 32 ] || fail "WORDCALENDAR_NAS_TOKEN must contain at least 32 characters"
[ "${#ADMIN_TOKEN}" -ge 32 ] || fail "WORDCALENDAR_NAS_ADMIN_TOKEN must contain at least 32 characters"
[ "$USER_TOKEN" != "$ADMIN_TOKEN" ] || fail "User and admin tokens must be different"
case "$USER_TOKEN:$ADMIN_TOKEN" in *replace-with-*) fail "Replace the example tokens in .env" ;; esac

if { [ -n "$PUSH_URL" ] && [ -z "$PUSH_SECRET" ]; } || { [ -z "$PUSH_URL" ] && [ -n "$PUSH_SECRET" ]; }; then
  fail "Set both WORDCALENDAR_NAS_PUSH_URL and WORDCALENDAR_NAS_PUSH_SECRET, or leave both empty"
fi

chmod 600 "$ENV_FILE" || fail "Could not restrict .env permissions"
cd "$PROJECT_ROOT"

echo "Validating the Compose project..."
compose config --quiet || fail "Compose configuration is invalid"

echo "Building and starting wordcalendar-api..."
if ! compose up -d --build; then
  echo "Container startup failed. Recent service logs:" >&2
  compose logs --tail=80 wordcalendar-api >&2 || true
  exit 1
fi

compose ps
echo "Deployment command completed. Check the API and HTTPS endpoint using the README instructions."
