"""The Play Store graphics from the app icon: the icon (512 x 512) and one feature graphic
(1024 x 500, no transparency) per language, written to store/play/.

    uv run --with pillow python tool/store_graphics.py
"""

from __future__ import annotations

import contextlib
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

APP = Path(__file__).resolve().parents[1]
OUT = APP / "store" / "play"
FONT = APP / "assets" / "fonts" / "SpaceGrotesk.ttf"
W, H = 1024, 500
CLAIMS = {
    "de-DE": "Planen, aufnehmen,\nentwickeln – von unterwegs.",
    "en-US": "Plan, capture, develop –\nfrom anywhere.",
}


def _sky() -> Image.Image:
    """The icon's background: deep blue above, near black below, two soft glows, and a
    warm town glow along the horizon (the Bortle scale is about exactly that)."""
    sky = Image.new("RGB", (W, H))
    top, mid, bottom = (10, 18, 48), (4, 6, 15), (2, 3, 10)
    draw = ImageDraw.Draw(sky)
    for y in range(H):
        t = y / (H - 1)
        a, b, f = (top, mid, t / 0.6) if t < 0.6 else (mid, bottom, (t - 0.6) / 0.4)
        draw.line([(0, y), (W, y)], fill=tuple(round(a[i] + (b[i] - a[i]) * f) for i in range(3)))
    glow = Image.new("RGB", (W, H))
    g = ImageDraw.Draw(glow)
    g.ellipse((-200, -330, 520, 260), fill=(79, 227, 176))
    g.ellipse((560, -320, 1240, 230), fill=(180, 140, 255))
    g.ellipse((80, 430, 944, 760), fill=(242, 192, 107))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    sky = Image.blend(sky, glow, 0.26)
    # a few stars, placed by a fixed rule so every run draws the same ones
    stars = ImageDraw.Draw(sky)
    for i in range(70):
        x, y = (i * 389 + 57) % W, (i * 211 + 23) % int(H * 0.8)
        r = 1.6 if i % 9 == 0 else 0.9
        level = 200 + (i * 37) % 55
        stars.ellipse((x - r, y - r, x + r, y + r), fill=(level, level, min(255, level + 20)))
    return sky


def _font(size: int, weight: int) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(str(FONT), size)
    with contextlib.suppress(OSError):  # not a variable font
        font.set_variation_by_axes([weight])
    return font


def icon() -> Image.Image:
    return Image.open(APP / "assets" / "icon" / "icon.png").convert("RGB").resize((512, 512), Image.Resampling.LANCZOS)


def feature(claim: str) -> Image.Image:
    image = _sky()
    # the icon as a rounded tile, as the launcher shows it
    tile = icon().resize((340, 340), Image.Resampling.LANCZOS)
    mask = Image.new("L", tile.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *tile.size), radius=76, fill=255)
    shadow = Image.new("RGBA", (W, H))
    ImageDraw.Draw(shadow).rounded_rectangle((70, 90, 410, 430), radius=76, fill=(0, 0, 0, 150))
    image.paste(Image.new("RGB", (W, H)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(18)).getchannel("A"))
    image.paste(tile, (64, 80), mask)
    draw = ImageDraw.Draw(image)
    draw.text((470, 140), "Bortle", font=_font(112, 700), fill=(238, 241, 251))
    draw.text((474, 285), claim, font=_font(38, 500), fill=(167, 176, 204), spacing=10)
    return image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    icon().save(OUT / "icon.png", optimize=True)
    for language, claim in CLAIMS.items():
        (OUT / language).mkdir(exist_ok=True)
        feature(claim).save(OUT / language / "feature.png", optimize=True)


if __name__ == "__main__":
    main()
