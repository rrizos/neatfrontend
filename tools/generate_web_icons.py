#!/usr/bin/env python3
"""Render the browser and PWA icons for the web build from the neat mark.

Writes web/favicon.png and web/icons/*.png, which `flutter build web` copies to
/favicon.png and /icons/ — the landing page, the legal pages and the app shell
all point at those URLs.

The mark itself (landing/brand/logo-dark.png) is a near-white script "n" on
transparency, which would disappear against a light browser tab strip, so every
icon here sits on the brand's dark paper.

Run after changing the logo:  python3 tools/generate_web_icons.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
MARK = ROOT / 'landing' / 'brand' / 'logo-dark.png'

PAPER = (10, 13, 24, 255)

# Plain icons get rounded corners and a little breathing room; maskable icons
# are full-bleed with the mark inside Android's 80% safe zone.
ROUNDED = [
    # 96px because Google Search wants the favicon it shows next to a result to
    # be a multiple of 48px square. The mark is delicate at the 16px a browser
    # tab renders, so it takes more of the frame than the larger icons need.
    (ROOT / 'web' / 'favicon.png', 96, 0.80, True),
    (ROOT / 'web' / 'icons' / 'Icon-192.png', 192, 0.70, True),
    (ROOT / 'web' / 'icons' / 'Icon-512.png', 512, 0.70, True),
    (ROOT / 'web' / 'icons' / 'Icon-maskable-192.png', 192, 0.55, False),
    (ROOT / 'web' / 'icons' / 'Icon-maskable-512.png', 512, 0.55, False),
]


def mark() -> Image.Image:
    """The logo cropped to its ink, so scaling is about the glyph not padding."""
    src = Image.open(MARK).convert('RGBA')
    return src.crop(src.split()[3].getbbox())


def render(path: Path, size: int, scale: float, rounded: bool, glyph: Image.Image) -> None:
    icon = Image.new('RGBA', (size, size), (0, 0, 0, 0))

    background = Image.new('RGBA', (size, size), PAPER)
    if rounded:
        mask = Image.new('L', (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, size - 1, size - 1], radius=round(size * 0.22), fill=255
        )
        icon.paste(background, (0, 0), mask)
    else:
        icon.paste(background, (0, 0))

    # resize(), not thumbnail() — the source mark is smaller than most of the
    # icons here and thumbnail() refuses to scale up.
    box = size * scale
    ratio = min(box / glyph.width, box / glyph.height)
    fitted = glyph.resize(
        (max(1, round(glyph.width * ratio)), max(1, round(glyph.height * ratio))),
        Image.LANCZOS,
    )
    icon.paste(
        fitted,
        ((size - fitted.width) // 2, (size - fitted.height) // 2),
        fitted,
    )

    path.parent.mkdir(parents=True, exist_ok=True)
    icon.save(path, optimize=True)
    print('wrote', path.relative_to(ROOT), icon.size)


def main() -> None:
    glyph = mark()
    for path, size, scale, rounded in ROUNDED:
        render(path, size, scale, rounded, glyph)

    # Google Search asks for /favicon.ico at the site root whether or not the
    # page declares one, so ship a real multi-resolution .ico there.
    ico = ROOT / 'web' / 'favicon.ico'
    Image.open(ROOT / 'web' / 'favicon.png').save(
        ico, format='ICO', sizes=[(16, 16), (32, 32), (48, 48)]
    )
    print('wrote', ico.relative_to(ROOT), '16/32/48')


if __name__ == '__main__':
    main()
