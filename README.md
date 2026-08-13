# neat

The Flutter client for Neat — a hyperlocal social app, one feed per Greek city.

## Getting started

```sh
flutter pub get
flutter run
```

## Shipping updates without a store review (Shorebird)

Dart-only changes — a layout fix, a wrong string, a bad condition — can be
pushed to installed apps as a *patch* instead of a release. Native changes
(plugins, `android/`, `ios/`, assets, the pubspec's dependency list, the app
version) still need a real store release.

One-time setup on a machine that will cut releases:

```sh
curl --proto '=https' --tlsv1.2 \
  https://raw.githubusercontent.com/shorebirdtech/install/main/install.sh -sSf | bash
shorebird login   # opens a browser
shorebird init    # creates the app, writes shorebird.yaml, registers it as an asset
```

`shorebird doctor` checks the project over; the only thing it finds that is
worth acting on here is the missing `shorebird.yaml`, since Neat does not ship
a macOS build. `shorebird init` is what produces that file (it holds the app
id) and adds it to the pubspec's asset list. Everything else is already in place: the
`shorebird_code_push` dependency, and `CodePushService` in
[lib/src/core/code_push_service.dart](lib/src/core/code_push_service.dart),
which `main()` kicks off fire-and-forget on every launch.

Then, per store release:

```sh
shorebird release --platforms android      # instead of flutter build appbundle
shorebird release --platforms ios          # instead of flutter build ipa
```

and for each fix in between:

```sh
shorebird patch --platforms android --release-version 2.0.3+16
shorebird patch --platforms ios     --release-version 2.0.3+16
```

`--release-version` is the release the patch attaches to, and it must be the
version people already have installed — the pubspec version at the time that
release was cut, not the one in the working tree. `--release-version=latest`
targets the most recently updated release.

A patch only ever applies to the release it was cut from, so bump the version
and cut a fresh release whenever anything native changes. Patches are
downloaded in the background and boot on the app's next cold start — nothing
interrupts a session, and nothing prompts for a restart. Settings shows the
running patch number once one has been applied, which is the number worth
asking for in a bug report.

`shorebird.yaml` belongs in git: the app id is not a secret, and a build made
without it silently ships an app that can never be patched.

Checking and undoing:

```sh
shorebird releases list
shorebird patches list --release-version 2.0.3+16
shorebird preview                      # run a release + its patch on a device
shorebird patches promote --release-version 2.0.3+16 --patch-number 1
```

The last one moves a patch onto the `stable` track — only needed if a patch
was published to `beta`/`staging` first (`shorebird patch --track beta`), which
is the safe way to try a fix on yourself before everyone gets it.

A bad patch is rolled back from the [console](https://console.shorebird.dev) —
devices fall back to the last good code on their next launch. Nothing can
"unbrick" a bad *release*, though, which is the reason patches exist.

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

Two image sets are generated from `landing/brand/logo-dark.png` and committed
rather than built each time. Both need Pillow; re-run them after a logo change:

```sh
python3 landing/generate_og_default.py   # landing/brand/og-default.png — the
                                         # social card for posts with no image
python3 tools/generate_web_icons.py      # web/favicon.png + web/icons/* — the
                                         # browser tab and PWA icons
```

The mark is a near-white script "n" on transparency, so the icons put it on the
brand's dark paper; left bare it would vanish against a light browser tab.
