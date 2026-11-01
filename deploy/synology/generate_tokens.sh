#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
ENV_FILE="$PROJECT_ROOT/.env"

if [ -e "$ENV_FILE" ]; then
  echo "Refusing to overwrite $ENV_FILE. Keep existing tokens, or back up and rotate them manually." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "OpenSSL is required to generate secure tokens." >&2
  exit 1
fi

USER_TOKEN=$(openssl rand -hex 48)
ADMIN_TOKEN=$(openssl rand -hex 48)
if [ -z "$USER_TOKEN" ] || [ -z "$ADMIN_TOKEN" ] || [ "$USER_TOKEN" = "$ADMIN_TOKEN" ]; then
  echo "OpenSSL did not return valid, distinct tokens." >&2
  exit 1
fi

umask 077
TMP_FILE="$PROJECT_ROOT/.env.tmp.$$"
trap 'rm -f "$TMP_FILE"' EXIT HUP INT TERM
(set -C; : > "$TMP_FILE") || {
  echo "Could not create a temporary .env file." >&2
  exit 1
}

printf '%s\n' \
  "WORDCALENDAR_NAS_TOKEN=$USER_TOKEN" \
  "WORDCALENDAR_NAS_ADMIN_TOKEN=$ADMIN_TOKEN" \
  'WORDCALENDAR_NAS_PUSH_URL=' \
  'WORDCALENDAR_NAS_PUSH_SECRET=' > "$TMP_FILE"
chmod 600 "$TMP_FILE"

# A hard link creates the destination only if it does not already exist.
if ! ln "$TMP_FILE" "$ENV_FILE"; then
  echo "Could not create $ENV_FILE; it may already exist." >&2
  exit 1
fi
rm -f "$TMP_FILE"
trap - EXIT HUP INT TERM

echo "Created $ENV_FILE with separate user and admin tokens (mode 600)."
echo "Keep the values private. Add push URL and secret only when configuring the FCM relay."
