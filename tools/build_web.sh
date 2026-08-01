#!/usr/bin/env bash
# Assemble the neatapp.gr publish directory: the marketing landing page, the
# legal pages, and the Flutter web app, all on one origin.
#
#   build/netlify/index.html     landing page          → /
#   build/netlify/privacy.html   legal page            → /privacy
#   build/netlify/terms.html     legal page            → /terms
#   build/netlify/app.html       Flutter shell         → /app, /post/<id>, …
#   build/netlify/main.dart.js…  Flutter build assets
#
# Usage: tools/build_web.sh            build only
#        tools/build_web.sh --deploy   build, then push to production
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/build/netlify"
FLUTTER_OUT="$ROOT/build/flutter-web"

echo "==> Rendering legal pages from lib/src/legal/legal_page.dart"
python3 landing/generate_legal.py

echo "==> Building the Flutter web app"
# -o keeps the output next to the publish dir regardless of any global
# `flutter config --build-dir` override.
flutter build web --release -o "$FLUTTER_OUT"

echo "==> Assembling $OUT"
rm -rf "$OUT"
cp -R "$FLUTTER_OUT" "$OUT"

# The Flutter shell steps aside so the landing page can own `/`. Its <base
# href="/"> means every asset still resolves from the root, on any route.
mv "$OUT/index.html" "$OUT/app.html"

cp "$ROOT/landing/index.html"   "$OUT/index.html"
cp "$ROOT/landing/privacy.html" "$OUT/privacy.html"
cp "$ROOT/landing/terms.html"   "$OUT/terms.html"
cp "$ROOT/landing/legal.css"    "$OUT/legal.css"
# Real files, so the SPA fallback stops answering crawlers with the app shell.
cp "$ROOT/landing/robots.txt"   "$OUT/robots.txt"
cp "$ROOT/landing/sitemap.xml"  "$OUT/sitemap.xml"
# Same reason: Apple and Google fetch these to verify that neatapp.gr and the
# app belong together. Both must be real files served as JSON, not the shell.
mkdir -p "$OUT/.well-known"
cp "$ROOT"/landing/well-known/* "$OUT/.well-known/"
mkdir -p "$OUT/brand"
cp "$ROOT"/landing/brand/*.png  "$OUT/brand/"

echo "==> Done: $(du -sh "$OUT" | cut -f1) in $OUT"

if [[ "${1:-}" == "--deploy" ]]; then
  echo "==> Deploying to production"
  netlify deploy --prod --dir "$OUT"
fi
