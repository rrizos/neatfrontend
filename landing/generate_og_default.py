#!/usr/bin/env python3
"""Render brand/og-default.png — the 1200x630 card used as the social preview
for posts that have no image of their own (see netlify/edge-functions/og-image.js).

Run after changing the logo or the tagline:  python3 landing/generate_og_default.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
W, H = 1200, 630

# Landing-page tokens.
PAPER = (10, 13, 24)
INK = (238, 241, 251)
INK_SOFT = (167, 176, 208)
BLUE = (80, 137, 255)

TAGLINE = 'Μία εφαρμογή, τα πάντα για την περιοχή σου.'


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', size, index=1 if bold else 0)
    except OSError:
        return ImageFont.load_default(size)


def main() -> None:
    img = Image.new('RGB', (W, H), PAPER)

    # Soft blue glow behind the mark, echoing the landing page's hero gradient.
    glow = Image.new('RGB', (W, H), PAPER)
    gd = ImageDraw.Draw(glow)
    for i in range(240, 0, -6):
        a = i / 240
        colour = tuple(int(PAPER[k] + (BLUE[k] - PAPER[k]) * (1 - a) * 0.5) for k in range(3))
        gd.ellipse([W / 2 - i * 2.2, H / 2 - i * 1.6, W / 2 + i * 2.2, H / 2 + i * 1.6], fill=colour)
    img = Image.blend(img, glow, 0.55)

    logo = Image.open(HERE / 'brand' / 'logo-dark.png').convert('RGBA')
    logo.thumbnail((190, 190), Image.LANCZOS)
    img.paste(logo, ((W - logo.width) // 2, 150), logo)

    d = ImageDraw.Draw(img)

    def centre(text: str, y: int, f: ImageFont.FreeTypeFont, fill: tuple) -> None:
        width = d.textbbox((0, 0), text, font=f)[2]
        d.text(((W - width) // 2, y), text, font=f, fill=fill)

    centre('neat', 370, font(84, bold=True), INK)
    centre(TAGLINE, 480, font(34), INK_SOFT)

    out = HERE / 'brand' / 'og-default.png'
    img.save(out, optimize=True)
    print('wrote', out.relative_to(HERE.parent), img.size)


if __name__ == '__main__':
    main()
