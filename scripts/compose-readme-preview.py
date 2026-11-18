#!/usr/bin/env python3
"""Compose the public cover from offline Flutter fixture renders; no live data."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
IMAGES = ROOT / "docs" / "images"
FONT = ROOT / "phonelink_desktop" / "assets" / "fonts" / "Manrope.ttf"



def font(size, weight=450):
    value = ImageFont.truetype(str(FONT), size)
    try:
        axes = value.get_variation_axes()
        value.set_variation_by_axes([
            min(axis["maximum"], max(axis["minimum"], weight))
            if axis["name"] == b"Weight" else axis["default"]
            for axis in axes
        ])
    except OSError:
        pass
    return value


def panel(canvas, source, position, width, radius=20, border=8):
    image = Image.open(source).convert("RGBA")
    height = round(image.height * width / image.width)
    image = image.resize((width, height), Image.Resampling.LANCZOS)
    x, y = position
    shadow = Image.new("RGBA", canvas.size)
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle((x - border, y - border + 12, x + width + border,
                            y + height + border + 12), radius + border, fill=(17, 37, 31, 50))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    frame = Image.new("RGBA", (width + border * 2, height + border * 2))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, frame.width - 1, frame.height - 1),
                                           radius + border, fill="#252A27")
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius, fill=255)
    frame.paste(image, (border, border), mask)
    canvas.alpha_composite(frame, (x - border, y - border))


def main():
    canvas = Image.new("RGBA", (1800, 1110), "#E8ECE6")
    logo = Image.open(ROOT / "assets" / "branding" / "phonelink-1024.png").convert("RGBA")
    logo.thumbnail((74, 74), Image.Resampling.LANCZOS)
    canvas.alpha_composite(logo, (48, 46))
    draw = ImageDraw.Draw(canvas)
    draw.text((144, 44), "PhoneLink", font=font(44, 650), fill="#182D29")
    draw.text((145, 100), "Your phone, on your Linux desktop.",
              font=font(22), fill="#63726C")
    draw.text((1440, 66), "Fictional demo data", font=font(16), fill="#63726C")
    panel(canvas, IMAGES / "desktop-messages-dark.png", (48, 184), 1310)
    panel(canvas, IMAGES / "phone-device-light.png", (1420, 250), 320, radius=30, border=10)
    draw = ImageDraw.Draw(canvas)
    draw.text((50, 1060), "Android + Linux   /   Direct local connections   /   No cloud relay",
              font=font(19), fill="#63726C")
    output = IMAGES / "overview.png"
    canvas.convert("RGB").save(output, optimize=True)
    print(output)


if __name__ == "__main__":
    main()
