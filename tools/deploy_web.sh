#!/usr/bin/env bash
# Publish neatapp.gr — the marketing landing page, the legal pages and the
# brand assets — to the Lightsail box that also runs the API.
#
# This replaces tools/build_web.sh, which built the Flutter web app and pushed
# the result to Netlify. There is no Flutter web build any more: shared post
# links (/post/<id>) are rendered server-side by the Django `web` app, so the
# only thing left to publish is static files.
#
# The Django side is deployed separately, by pulling on the server:
#   ssh …@neat 'cd neatbackend && git pull && sudo systemctl restart gunicorn gunicorn-asgi'
#
# Usage: tools/deploy_web.sh [--dry-run]
set -euo pipefail

HOST="${NEAT_DEPLOY_HOST:-bitnami@63.181.201.175}"
KEY="${NEAT_DEPLOY_KEY:-$HOME/Desktop/LightsailDefaultKey-eu-central-1-2.pem}"
REMOTE_ROOT="/home/bitnami/neat-web"

cd "$(dirname "$0")/.."
ROOT="$PWD"

DRY=""
[[ "${1:-}" == "--dry-run" ]] && DRY="--dry-run"

echo "==> Rendering legal pages from lib/src/legal/legal_page.dart"
python3 landing/generate_legal.py

echo "==> Publishing landing/ to $HOST:$REMOTE_ROOT"
# generate_legal.py and generate_og_default.py are build inputs, and legal/ is
# their source material — none of it belongs on the public server. well-known
# ships separately below because it has to land under a dotted name.
rsync -az --delete $DRY \
  -e "ssh -i $KEY -o StrictHostKeyChecking=no" \
  --exclude 'generate_legal.py' \
  --exclude 'generate_og_default.py' \
  --exclude 'legal/' \
  --exclude 'well-known/' \
  --exclude '.well-known/' \
  --exclude '.DS_Store' \
  --exclude '._*' \
  "$ROOT/landing/" "$HOST:$REMOTE_ROOT/"

# Apple and Google fetch these to verify that neatapp.gr and the app belong
# together. The source directory is `well-known` because a leading dot hides it
# from too many tools; it has to be served from `.well-known`.
echo "==> Publishing .well-known"
rsync -az --delete $DRY \
  -e "ssh -i $KEY -o StrictHostKeyChecking=no" \
  --exclude '.DS_Store' --exclude '._*' \
  "$ROOT/landing/well-known/" "$HOST:$REMOTE_ROOT/.well-known/"

if [[ -n "$DRY" ]]; then
  echo "==> Dry run only; nothing was written."
  exit 0
fi

echo "==> Verifying"
# Over HTTPS and pinned to this box with --resolve: port 80 now answers 301, so
# probing plain HTTP would only ever report the redirect, and going through DNS
# would not prove that *this* server is the one serving the new files.
for path in / /privacy /terms /robots.txt /.well-known/apple-app-site-association; do
  code=$(curl -s -o /dev/null -w '%{http_code}' \
    --resolve "neatapp.gr:443:63.181.201.175" "https://neatapp.gr$path")
  printf '    %-46s %s\n' "$path" "$code"
done

echo "==> Done."
