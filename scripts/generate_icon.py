# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "pillow",
# ]
# ///
"""Generate the Jools app icon — a centered pixel-art "J".

The pixel map mirrors ``PixelJoolsMark`` in ``Typography.swift`` so the
on-screen logo and the installed app icon stay in lockstep. Run via
``uv run scripts/generate_icon.py``.
"""

from pathlib import Path

from PIL import Image, ImageDraw

# --- Pixel map (kept in sync with Typography.swift PixelJoolsMark) ---------
PIXEL_MAP: list[str] = [
    ".......BBS.",
    ".......BBSS",
    ".......BBSS",
    ".......BBSS",
    ".......BBSS",
    ".......BBSS",
    ".......BBSS",
    ".......BBSS",
    ".......BBSS",
    ".S.....BBSS",
    "SBB....BBSS",
    "SBBBBBBBBSS",
    ".SBBBBBBSS.",
    "..SSSSSSS..",
]
GRID_W = len(PIXEL_MAP[0])
GRID_H = len(PIXEL_MAP)


def _centroid() -> tuple[float, float]:
    """Visual centroid of the active cells so the J reads as centred."""
    xs: list[int] = []
    ys: list[int] = []
    for y, row in enumerate(PIXEL_MAP):
        for x, char in enumerate(row):
            if char != ".":
                xs.append(x)
                ys.append(y)
    return sum(xs) / len(xs) + 0.5, sum(ys) / len(ys) + 0.5


CENTROID_X, CENTROID_Y = _centroid()

# Effective footprint after centroid-centring. When the centroid sits off
# the geometric centre the far side needs extra clearance, so we scale
# against this enlarged footprint — otherwise pixels spill out of frame.
FOOTPRINT_W = 2 * max(CENTROID_X, GRID_W - CENTROID_X)
FOOTPRINT_H = 2 * max(CENTROID_Y, GRID_H - CENTROID_Y)

# --- Jools palette ----------------------------------------------------------
BODY_COLOR = (139, 92, 246, 255)    # joolsAccent (light mode)
SHADOW_COLOR = (20, 16, 34, 255)    # deep navy/near-black outline

# Background: subtly Jools-tinted light surface reminiscent of the reference
BG_TOP = (243, 238, 252, 255)
BG_BOTTOM = (224, 214, 246, 255)

# iOS-style safe zone: the pixel art occupies ~56% of the full 1024 canvas,
# leaving generous padding so the icon still reads after the system rounded
# mask is applied.
ICON_FILL_RATIO = 0.58


def build_background(size: int) -> Image.Image:
    """Vertical gradient background that flatters the purple letter."""
    img = Image.new("RGBA", (size, size), BG_TOP)
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t)
        g = int(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t)
        b = int(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))
    return img


def draw_pixel_j(img: Image.Image, size: int) -> None:
    """Rasterise the pixel map onto ``img`` so it sits centred in the canvas."""
    draw = ImageDraw.Draw(img)

    # Scale the pixel art so the centroid-centred footprint hits the target
    # fill ratio. Using the raw grid size would let pixels escape the canvas.
    target = size * ICON_FILL_RATIO
    cell = int(min(target / FOOTPRINT_W, target / FOOTPRINT_H))

    # Centre on the centroid of the active cells, not the grid bounding box —
    # otherwise the heavy stem pulls the letter visually to one side.
    origin_x = int(size / 2 - CENTROID_X * cell)
    origin_y = int(size / 2 - CENTROID_Y * cell)

    for gy, row in enumerate(PIXEL_MAP):
        for gx, char in enumerate(row):
            if char == ".":
                continue
            color = BODY_COLOR if char == "B" else SHADOW_COLOR
            x0 = origin_x + gx * cell
            y0 = origin_y + gy * cell
            draw.rectangle([x0, y0, x0 + cell - 1, y0 + cell - 1], fill=color)


def main() -> None:
    size = 1024
    canvas = build_background(size)
    draw_pixel_j(canvas, size)

    repo_root = Path(__file__).resolve().parents[1]
    output_path = (
        repo_root
        / "Jools"
        / "Assets.xcassets"
        / "AppIcon.appiconset"
        / "AppIcon.png"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(output_path, "PNG")
    print(f"App icon saved to {output_path}")


if __name__ == "__main__":
    main()
