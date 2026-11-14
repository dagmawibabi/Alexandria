"""Builds windows/runner/resources/app_icon.ico: Alexandria's ring on a rounded black tile.

Each size is drawn on its own (supersampled, then reduced) rather than scaled down
from one big image, so the ring stays crisp in the taskbar and title bar.

    python tool/windows_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
OUT = Path(__file__).resolve().parent.parent / "windows" / "runner" / "resources" / "app_icon.ico"
SS = 8  # supersampling factor


def frame(size: int) -> Image.Image:
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Tile: nearly the full square, softly rounded, like other Windows app icons.
    inset = round(n * 0.04)
    d.rounded_rectangle([inset, inset, n - inset - 1, n - inset - 1], radius=round(n * 0.22), fill=(0, 0, 0, 255))
    # A hairline edge so the black tile doesn't vanish on a dark taskbar.
    if size >= 32:
        d.rounded_rectangle([inset, inset, n - inset - 1, n - inset - 1], radius=round(n * 0.22), outline=(255, 255, 255, 38), width=max(SS, round(n * 0.006)))

    # The ring, bolder at small sizes so it survives at 16 px.
    outer = n * 0.31
    stroke = n * (0.085 if size <= 24 else 0.065 if size <= 48 else 0.052)
    c = n / 2
    d.ellipse([c - outer, c - outer, c + outer, c + outer], fill=(255, 255, 255, 255))
    inner = outer - stroke
    d.ellipse([c - inner, c - inner, c + inner, c + inner], fill=(0, 0, 0, 255))

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    frames = [frame(s) for s in SIZES]
    frames[-1].save(OUT, format="ICO", sizes=[(s, s) for s in SIZES], append_images=frames[:-1])
    print(f"wrote {OUT} ({', '.join(map(str, SIZES))})")


if __name__ == "__main__":
    main()
