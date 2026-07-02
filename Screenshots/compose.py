#!/usr/bin/env python3
"""Bake App Store marketing chrome onto raw device screenshots.

Reads from screenshots/iphone and screenshots/ipad, writes to screenshots/marketing/{iphone,ipad}.
"""
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
SF_BOLD = "/System/Library/Fonts/SFNS.ttf"
SF_REG  = "/System/Library/Fonts/SFNS.ttf"

# Warm cream palette
BG_TOP    = (251, 247, 242)   # #FBF7F2
BG_BOT    = (244, 236, 226)   # #F4ECE2
INK       = (44,  36,  29)    # warm charcoal
INK_SOFT  = (110, 92,  72)    # subhead

# Per-scene marketing copy
_iphone_copy = {
        "01_home":    ("Your stash, finally\norganized.",       "Track every ounce — pump to bottle."),
        "02_stash":   ("Never waste\na drop again.",            "Smart expiration alerts before milk turns."),
        "03_addbag":  ("Log a pump\nin seconds.",                "Volume, date, storage — done in two taps."),
        "04_goal":    ("Hit your goals,\ngently.",               "Daily totals that celebrate progress."),
        "05_feed":    ("Every feed,\nevery bottle.",             "Dispense the oldest milk first, automatically."),
        "06_settings":("Private\nby design.",                    "Synced securely with iCloud. Never shared, never sold."),
}
COPY = {
    "iphone":    _iphone_copy,
    "iphone_65": _iphone_copy,
    "iphone_69": _iphone_copy,
    "ipad": {
        "01_home":    ("Your whole stash,\nat a glance.",        "Built for iPad. Built for real life."),
        "02_stash":   ("Expirations you can\nsee coming.",       "Sort, filter, and plan ahead."),
        "03_addbag":  ("Log without\nlosing your place.",        "Add a bag while your stash stays in view."),
        "04_goal":    ("Goals, totals, trends —\ntogether.",     "See the whole week without switching screens."),
        "05_feed":    ("A calm home base\nfor every parent.",    "Designed for the kitchen, the nursery, the 3am pump."),
    },
}


def gradient(size, top, bot):
    w, h = size
    img = Image.new("RGB", size, top)
    px  = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b)
    return img

def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out

def drop_shadow(img, blur=40, offset=(0, 24), opacity=0.18):
    w, h = img.size
    pad  = blur * 3
    shadow = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    silhouette = Image.new("RGBA", img.size, (0, 0, 0, int(255 * opacity)))
    silhouette.putalpha(img.split()[-1].point(lambda v: int(v * opacity)))
    shadow.paste(silhouette, (pad + offset[0], pad + offset[1]), silhouette)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    return shadow, pad

def wrap_lines(text, font, max_w, draw):
    out = []
    for raw in text.split("\n"):
        words, line = raw.split(" "), ""
        for w in words:
            test = (line + " " + w).strip()
            if draw.textlength(test, font=font) <= max_w:
                line = test
            else:
                if line: out.append(line)
                line = w
        out.append(line)
    return out

def compose(src_path: Path, headline: str, sub: str, out_path: Path, canvas_size=None):
    shot = Image.open(src_path).convert("RGBA")
    W, H = canvas_size if canvas_size else shot.size
    canvas = gradient((W, H), BG_TOP, BG_BOT).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    # Typography scaling — based on canvas width.
    is_pad   = W >= 1800
    head_pt  = int(W * (0.075 if is_pad else 0.085))
    sub_pt   = int(W * (0.030 if is_pad else 0.034))
    head_font = ImageFont.truetype(SF_BOLD, head_pt)
    sub_font  = ImageFont.truetype(SF_REG,  sub_pt)

    # Top text block.
    margin_x = int(W * 0.08)
    text_top = int(H * 0.055)
    max_text_w = W - margin_x * 2

    head_lines = wrap_lines(headline, head_font, max_text_w, draw)
    line_h = head_pt * 1.05
    y = text_top
    for ln in head_lines:
        tw = draw.textlength(ln, font=head_font)
        draw.text(((W - tw) / 2, y), ln, font=head_font, fill=INK)
        y += line_h
    y += int(head_pt * 0.35)

    sub_lines = wrap_lines(sub, sub_font, max_text_w, draw)
    sub_line_h = sub_pt * 1.25
    for ln in sub_lines:
        tw = draw.textlength(ln, font=sub_font)
        draw.text(((W - tw) / 2, y), ln, font=sub_font, fill=INK_SOFT)
        y += sub_line_h

    text_block_bottom = y + int(H * 0.015)

    # Device area — fits between text and bottom margin.
    bottom_margin = int(H * 0.04)
    avail_h = H - text_block_bottom - bottom_margin
    avail_w = W - int(W * 0.12) * 2

    sw, sh = shot.size
    scale = min(avail_w / sw, avail_h / sh)
    new_w, new_h = int(sw * scale), int(sh * scale)
    device = shot.resize((new_w, new_h), Image.LANCZOS)
    radius = int(min(new_w, new_h) * 0.06)
    device = rounded(device, radius)

    shadow, pad = drop_shadow(device, blur=int(new_w * 0.04), offset=(0, int(new_h * 0.012)), opacity=0.22)
    dev_x = int((W - new_w) // 2)
    dev_y = int(text_block_bottom + (avail_h - new_h) // 2)
    canvas.alpha_composite(shadow, (int(dev_x - pad), int(dev_y - pad)))
    canvas.alpha_composite(device, (dev_x, dev_y))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"  wrote {out_path.relative_to(ROOT)}")

CANVAS = {
    "iphone":     None,            # native (1206x2622) — for 6.3" iPhone slot
    "ipad":       None,            # native (2064x2752) — for 13" iPad slot
    "iphone_65":  (1242, 2688),    # required 6.5" slot
    "iphone_69":  (1320, 2868),    # required 6.9" slot
}

def main():
    for kind, scenes in COPY.items():
        src_dir = ROOT / kind.split("_")[0]
        out_dir = ROOT / "marketing" / kind
        size = CANVAS.get(kind)
        for stem, (head, sub) in scenes.items():
            src = src_dir / f"{stem}.png"
            if not src.exists():
                print(f"skip {src}"); continue
            print(f"{kind}/{stem}: {head!r} / {sub!r}")
            compose(src, head, sub, out_dir / f"{stem}.png", canvas_size=size)

if __name__ == "__main__":
    main()
