# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "pillow",
# ]
# ///
"""Generate Jools app icon matching the onboarding screen logo."""

from PIL import Image, ImageDraw
import math


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    """Convert hex color to RGB tuple."""
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))


def interpolate_color(
    color1: tuple[int, int, int], color2: tuple[int, int, int], t: float
) -> tuple[int, int, int]:
    """Linearly interpolate between two colors."""
    return tuple(int(c1 + (c2 - c1) * t) for c1, c2 in zip(color1, color2))


def create_gradient_background(size: int) -> Image.Image:
    """Create a diagonal gradient background."""
    img = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(img)

    # Colors from joolsAccentGradient
    color1 = hex_to_rgb("8B5CF6")  # Purple
    color2 = hex_to_rgb("A855F7")  # Medium purple
    color3 = hex_to_rgb("C084FC")  # Light purple

    for y in range(size):
        for x in range(size):
            # Diagonal gradient from top-left to bottom-right
            t = (x + y) / (2 * size)
            if t < 0.5:
                color = interpolate_color(color1, color2, t * 2)
            else:
                color = interpolate_color(color2, color3, (t - 0.5) * 2)
            draw.point((x, y), fill=(*color, 255))

    return img


def create_rounded_mask(size: int, radius: int) -> Image.Image:
    """Create a rounded rectangle mask."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_layers_icon(draw: ImageDraw.Draw, cx: float, cy: float, icon_size: float):
    """Draw the stacked layers icon (3 rhombuses) centered at (cx, cy)."""
    w = icon_size
    h = icon_size
    line_width = int(icon_size * 0.04)  # Proportional line width

    # Offsets to center the icon
    ox = cx - w / 2
    oy = cy - h / 2

    # Top layer (closed rhombus/diamond)
    top_points = [
        (ox + w * 0.5, oy),  # top
        (ox, oy + h * 0.25),  # left
        (ox + w * 0.5, oy + h * 0.5),  # bottom
        (ox + w, oy + h * 0.25),  # right
    ]
    draw.polygon(top_points, outline="white", width=line_width)

    # Middle layer (open chevron pointing down)
    middle_points = [
        (ox, oy + h * 0.5),  # left
        (ox + w * 0.5, oy + h * 0.75),  # bottom center
        (ox + w, oy + h * 0.5),  # right
    ]
    draw.line(middle_points, fill="white", width=line_width, joint="curve")

    # Bottom layer (open chevron pointing down)
    bottom_points = [
        (ox, oy + h * 0.75),  # left
        (ox + w * 0.5, oy + h),  # bottom center
        (ox + w, oy + h * 0.75),  # right
    ]
    draw.line(bottom_points, fill="white", width=line_width, joint="curve")


def main():
    size = 1024
    corner_radius = int(size * 0.22)  # iOS-style rounded corners

    # Create gradient background
    gradient = create_gradient_background(size)

    # Apply rounded corner mask
    mask = create_rounded_mask(size, corner_radius)
    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(gradient, mask=mask)

    # Draw the layers icon
    draw = ImageDraw.Draw(result)
    icon_size = size * 0.5  # Icon takes 50% of the total size
    draw_layers_icon(draw, size / 2, size / 2, icon_size)

    # Save
    output_path = (
        "/Users/robinsharma/XcodeProjects/jools/Jools/Assets.xcassets/"
        "AppIcon.appiconset/AppIcon.png"
    )
    result.save(output_path, "PNG")
    print(f"App icon saved to {output_path}")


if __name__ == "__main__":
    main()
