#!/usr/bin/env python3
"""Render /privacy and /terms from the plain-text copy in landing/legal/.

Those .txt files are the single source of truth for the Terms and the Privacy
Policy. The app links out to the published pages rather than shipping its own
copy, so editing the text here and redeploying updates every client — no app
release needed.

Run after editing landing/legal/*.txt:  python3 landing/generate_legal.py
"""

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'landing' / 'legal'
OUT = ROOT / 'landing'

CONTACT = 'neatgreece@gmail.com'
SECTION_RE = re.compile(r'^(\d+)\.\s+(.+)$')


def source(name: str) -> str:
    path = SRC / name
    if not path.exists():
        raise SystemExit('missing %s' % path)
    return path.read_text(encoding='utf-8')


def parse(text: str) -> dict:
    """Split the flat legal text into title / updated / intro / sections."""
    lines = [ln.rstrip() for ln in text.strip().splitlines()]
    doc = {'title': lines[0].strip(), 'updated': '', 'intro': [], 'sections': []}

    i = 1
    while i < len(lines) and not lines[i].strip():
        i += 1
    if i < len(lines) and not SECTION_RE.match(lines[i].strip()):
        doc['updated'] = lines[i].strip()
        i += 1

    current = None
    for line in lines[i:]:
        stripped = line.strip()
        if not stripped:
            continue
        m = SECTION_RE.match(stripped)
        if m:
            current = {'n': m.group(1), 'heading': m.group(2).strip(), 'blocks': []}
            doc['sections'].append(current)
            continue
        target = current['blocks'] if current else doc['intro']
        if stripped.startswith('•'):
            item = stripped.lstrip('•').strip()
            if target and target[-1][0] == 'ul':
                target[-1][1].append(item)
            else:
                target.append(['ul', [item]])
        else:
            target.append(['p', stripped])
    return doc


def linkify(s: str) -> str:
    """Escape, then turn the support address into a mailto link."""
    return html.escape(s).replace(CONTACT, '<a href="mailto:%s">%s</a>' % (CONTACT, CONTACT))


def render_blocks(blocks: list) -> str:
    out = []
    for kind, value in blocks:
        if kind == 'ul':
            items = '\n'.join('        <li>%s</li>' % linkify(v) for v in value)
            out.append('      <ul>\n%s\n      </ul>' % items)
        else:
            out.append('      <p>%s</p>' % linkify(value))
    return '\n'.join(out)


def slug(doc_id: str, n: str) -> str:
    return '%s-%s' % (doc_id, n)


def render_doc(doc: dict, doc_id: str, lang: str, heading: str, toc_label: str) -> str:
    # Section headings are kept verbatim (the source text sets them in caps) —
    # case-folding Greek all-caps would strip the accents.
    toc = '\n'.join(
        '      <li><a href="#%s">%s</a></li>' % (slug(doc_id, s['n']), html.escape(s['heading']))
        for s in doc['sections']
    )
    sections = '\n'.join(
        '    <section id="%s">\n      <h2>%s. %s</h2>\n%s\n    </section>'
        % (slug(doc_id, s['n']), s['n'], html.escape(s['heading']), render_blocks(s['blocks']))
        for s in doc['sections']
    )
    intro = render_blocks(doc['intro'])
    return f"""<div class="doc-lang" data-lang="{lang}" lang="{lang}">
  <div class="legal-head">
    <h1>{html.escape(heading)}</h1>
    <p class="updated">{html.escape(doc['updated'])}</p>
{intro}
  </div>

  <nav class="toc" aria-label="{html.escape(toc_label)}">
    <h2>{html.escape(toc_label)}</h2>
    <ol>
{toc}
    </ol>
  </nav>

  <article class="doc">
{sections}
  </article>
</div>"""


PAGE = """<!DOCTYPE html>
<html lang="el">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title_el} — Neat</title>
<meta name="description" content="{description}">
<meta name="robots" content="index, follow">
<link rel="canonical" href="https://neatapp.gr{path}">
<link rel="icon" type="image/png" href="/brand/logo-dark.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Neat">
<meta property="og:title" content="{title_el} — Neat">
<meta property="og:description" content="{description}">
<meta property="og:url" content="https://neatapp.gr{path}">
<link rel="stylesheet" href="/legal.css">
<style>
  .lang-switch {{ display: inline-flex; padding: 2px; border-radius: 20px; background: var(--paper-dim); border: 1px solid var(--line); }}
  .lang-switch button {{
    appearance: none; border: 0; background: transparent; cursor: pointer;
    padding: 6px 12px; border-radius: 18px; font: 700 12px/1 var(--sans); color: var(--ink-soft);
  }}
  .lang-switch button[aria-pressed="true"] {{ background: var(--blue); color: #fff; }}
  .doc-lang[hidden] {{ display: none; }}
</style>
</head>
<body>

<header class="site">
  <div class="wrap">
    <a class="back-link" href="/" aria-label="{back_label}">←</a>
    <a class="brand" href="/" aria-label="Neat"><img src="/brand/logo-dark.png" alt=""></a>
    <div class="lang-switch" role="group" aria-label="Language">
      <button type="button" data-set-lang="el" aria-pressed="true">ΕΛ</button>
      <button type="button" data-set-lang="en" aria-pressed="false">EN</button>
    </div>
  </div>
</header>

<main class="legal">
  <div class="wrap">
{body_el}
{body_en}
  </div>
</main>

<footer class="site">
  <div class="wrap">
    <div class="foot-copy">© 2026 Neat. Με αγάπη για κάθε ελληνική πόλη.</div>
    <div class="foot-links">
      <a href="/">Αρχική</a>
      <a href="/terms">Όροι Χρήσης</a>
      <a href="/privacy">Απόρρητο</a>
      <a href="mailto:neatgreece@gmail.com">Επικοινωνία</a>
    </div>
  </div>
</footer>

<script>
  // Greek is the default; ?lang=en (or the switch) shows the English original.
  const docs = document.querySelectorAll('.doc-lang');
  const buttons = document.querySelectorAll('[data-set-lang]');

  function setLang(lang, push) {{
    docs.forEach(d => {{ d.hidden = d.dataset.lang !== lang; }});
    buttons.forEach(b => b.setAttribute('aria-pressed', String(b.dataset.setLang === lang)));
    document.documentElement.lang = lang;
    if (push) {{
      const url = new URL(location.href);
      if (lang === 'el') url.searchParams.delete('lang'); else url.searchParams.set('lang', lang);
      history.replaceState(null, '', url);
    }}
  }}

  buttons.forEach(b => b.addEventListener('click', () => setLang(b.dataset.setLang, true)));
  setLang(new URLSearchParams(location.search).get('lang') === 'en' ? 'en' : 'el', false);
</script>
</body>
</html>
"""


def build(doc_id: str, path: str, title_el: str, title_en: str, description: str) -> None:
    el = parse(source('%s.el.txt' % doc_id))
    en = parse(source('%s.en.txt' % doc_id))
    page = PAGE.format(
        title_el=html.escape(title_el),
        description=html.escape(description),
        path=path,
        back_label='Επιστροφή στην αρχική',
        body_el=render_doc(el, doc_id, 'el', title_el, 'Περιεχόμενα'),
        body_en=render_doc(en, doc_id + '-en', 'en', title_en, 'Contents'),
    )
    target = OUT / (doc_id + '.html')
    target.write_text(page, encoding='utf-8')
    print('wrote', target.relative_to(ROOT), '(%d bytes)' % len(page))


if __name__ == '__main__':
    build(
        'privacy', '/privacy', 'Πολιτική Απορρήτου', 'Privacy Policy',
        'Πώς το Neat συλλέγει, χρησιμοποιεί και προστατεύει τα δεδομένα σου.',
    )
    build(
        'terms', '/terms', 'Όροι Χρήσης', 'Terms of Service',
        'Οι όροι χρήσης και οι κανόνες της κοινότητας του Neat.',
    )
