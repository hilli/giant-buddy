# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10.3"]
# ///
"""Render captioned 6.9" iPhone App Store screenshots.

Reads raw screenshots from docs/appstore/screenshots/source/ (photos and stills
from the App Review screen recording), crops the status bar and places each on
a branded background with a headline and subline. Writes 1320x2868 PNGs to
docs/appstore/screenshots/iphone/, which `task appstore:push` uploads.

Usage:
  uv run scripts/appstore_frames.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "docs" / "appstore" / "screenshots" / "source"
OUT_DIR = ROOT / "docs" / "appstore" / "screenshots" / "iphone"
FONT = "/System/Library/Fonts/SFNS.ttf"

SIZE = (1320, 2868)
TOP_COLOR = (0, 160, 64)
BOTTOM_COLOR = (0, 84, 40)
CARD_WIDTH = 1060
CARD_TOP = 560
CARD_RADIUS = 64
STATUS_BAR = 0.06  # fraction of the source height cropped from the top

# source file -> (headline, subline); "\n" forces a line break
FRAMES = {
    "01-ride.png": ("Your ride, live", "Speed, power, cadence and battery\nstraight from your e-bike"),
    "02-navigation.png": ("Turn-by-turn by bike", "Cycling directions that reroute\nwhen you leave the route"),
    "03-search.png": ("Find what's nearby", "Bike shops, cafés and more,\none tap from directions"),
    "04-charts.png": ("Every ride, analyzed", "Motor power, rider power\nand battery over time"),
    "05-export.png": ("Share it your way", "Upload to Strava or export GPX and CSV"),
    "06-routes.png": ("Routes ready to ride", "Save rides as routes or import GPX files"),
    "07-bike.png": ("Your bike at a glance", "Battery, odometer and maintenance\nin one place"),
    "08-crash.png": ("Crash detection", "Asks if you're OK, then drafts\nan SMS with your location"),
}


def font(size: int, weight: str) -> ImageFont.FreeTypeFont:
    face = ImageFont.truetype(FONT, size)
    face.set_variation_by_name(weight)
    return face


def gradient() -> Image.Image:
    column = Image.new("RGB", (1, SIZE[1]))
    for y in range(SIZE[1]):
        t = y / (SIZE[1] - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(TOP_COLOR, BOTTOM_COLOR)))
    return column.resize(SIZE)


def wrap(draw: ImageDraw.ImageDraw, text: str, face: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines: list[str] = []
    for paragraph in text.split("\n"):
        start = len(lines)
        for word in paragraph.split():
            candidate = f"{lines[-1]} {word}" if len(lines) > start else word
            if len(lines) > start and draw.textlength(candidate, font=face) <= width:
                lines[-1] = candidate
            else:
                lines.append(word)
    return lines


def card(source: Path) -> Image.Image:
    shot = Image.open(source).convert("RGB")
    shot = shot.crop((0, round(shot.height * STATUS_BAR), shot.width, shot.height))
    height = round(shot.height * CARD_WIDTH / shot.width)
    shot = shot.resize((CARD_WIDTH, height), Image.Resampling.LANCZOS)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *shot.size), CARD_RADIUS, fill=255)
    shot.putalpha(mask)
    return shot


def render(name: str, headline: str, subline: str) -> None:
    canvas = gradient().convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    title_font, sub_font = font(112, "Bold"), font(54, "Medium")
    y = 190
    for line in wrap(draw, headline, title_font, SIZE[0] - 160):
        draw.text((SIZE[0] / 2, y), line, font=title_font, fill="white", anchor="mt")
        y += 128
    y += 18
    for line in wrap(draw, subline, sub_font, SIZE[0] - 220):
        draw.text((SIZE[0] / 2, y), line, font=sub_font, fill=(255, 255, 255, 225), anchor="mt")
        y += 70

    shot = card(SOURCE_DIR / name)
    left = (SIZE[0] - CARD_WIDTH) // 2
    top = max(CARD_TOP, y + 50)
    shadow = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    shadow_box = (left, top + 24, left + shot.width, top + 24 + shot.height)
    ImageDraw.Draw(shadow).rounded_rectangle(shadow_box, CARD_RADIUS, fill=(0, 0, 0, 110))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(36)))
    canvas.alpha_composite(shot, (left, top))
    canvas.convert("RGB").save(OUT_DIR / name, optimize=True)
    print(f"{name}: {headline}")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for stale in OUT_DIR.glob("*.png"):
        if stale.name not in FRAMES:
            stale.unlink()
    for name, (headline, subline) in FRAMES.items():
        render(name, headline, subline)


if __name__ == "__main__":
    main()
