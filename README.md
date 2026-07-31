# neat

The Flutter client for Neat — a hyperlocal social app, one feed per Greek city.

## Getting started

```sh
flutter pub get
flutter run
```

## Web

`neatapp.gr` serves the marketing site and the web app from a single origin, so
a shared post link previews and opens without an `app.` subdomain hop:

| URL                  | Serves                                                |
| -------------------- | ----------------------------------------------------- |
| `/`                  | landing page (`landing/index.html`)                    |
| `/privacy`, `/terms` | legal pages, generated from `landing/legal/*.txt`       |
| `/app`               | the Flutter web app                                    |
| `/post/<id>`         | the Flutter web app, with Open Graph tags injected by `netlify/edge-functions/post-meta.js` |
| `/api/*`, `/media/*` | proxied to the backend (see `netlify.toml`)            |

Build and deploy:

```sh
tools/build_web.sh            # assemble build/netlify
tools/build_web.sh --deploy   # …and push it to production
```

### Updating the Terms and the Privacy Policy

`landing/legal/{terms,privacy}.{el,en}.txt` is the single source of truth. The
app does not ship its own copy — Settings and the signup screen link out to
`/terms` and `/privacy` (see `lib/src/core/legal_links.dart`), so editing the
text and redeploying updates every installed client with no app release.

```sh
$EDITOR landing/legal/privacy.el.txt
tools/build_web.sh --deploy
```

The plain-text format is load-bearing: first line is the document title,
second is the "last updated" line, then numbered `1. HEADING` sections whose
bodies are paragraphs and `•` bullets.

`landing/brand/og-default.png` is the social card shown for posts without an
image of their own. It is committed; regenerate it with
`python3 landing/generate_og_default.py` (needs Pillow) after a logo or tagline
change.
