"""Generate the add-on's textures (TGA, power-of-two, RGBA). Run: python tools/make_textures.py"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media")
FONTS = "C:/Windows/Fonts"


def font(names, size):
    for n in names:
        p = os.path.join(FONTS, n)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def save(img, name):
    img.save(os.path.join(OUT, name), orientation=1)  # bottom-left origin, uncompressed
    print("wrote", name, img.size)


def felt():
    W, H = 1024, 512
    rnd = random.Random(3)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # wooden rim with grain
    rim = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rim)
    rd.ellipse((4, 4, W - 5, H - 5), fill=(74, 42, 20, 255))
    for i in range(900):
        y = rnd.randint(0, H)
        x = rnd.randint(0, W)
        L = rnd.randint(40, 160)
        c = rnd.choice([(98, 58, 28), (60, 33, 15), (110, 66, 32)])
        rd.line((x, y, x + L, y + rnd.randint(-3, 3)), fill=c + (255,), width=rnd.randint(1, 3))
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse((4, 4, W - 5, H - 5), fill=255)
    img.paste(rim, (0, 0), mask)
    # gold trim
    d.ellipse((30, 26, W - 31, H - 27), outline=(212, 168, 62, 255), width=5)
    d.ellipse((36, 32, W - 37, H - 33), outline=(120, 86, 30, 255), width=2)
    # felt with radial light and noise
    fw, fh = W - 80, H - 72
    feltimg = Image.new("RGBA", (fw, fh))
    px = feltimg.load()
    cx, cy = fw / 2, fh / 2
    for y in range(fh):
        for x in range(fw):
            dx, dy = (x - cx) / cx, (y - cy) / cy
            r = math.sqrt(dx * dx + dy * dy)
            light = max(0.0, 1.0 - r * 0.55)
            n = rnd.randint(-7, 7)
            g = int(70 + 70 * light) + n
            px[x, y] = (int(14 + 18 * light) + n // 2, max(0, min(255, g)), int(34 + 26 * light) + n // 2, 255)
    fmask = Image.new("L", (fw, fh), 0)
    ImageDraw.Draw(fmask).ellipse((0, 0, fw - 1, fh - 1), fill=255)
    img.paste(feltimg, (40, 36), fmask)
    # inner betting line
    d.ellipse((150, 110, W - 151, H - 111), outline=(170, 210, 140, 70), width=2)
    # faint table name
    f = font(["georgiab.ttf", "timesbd.ttf"], 34)
    text = "GOBLIN HOLD'EM"
    tw = d.textlength(text, font=f)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text(((W - tw) / 2, H * 0.70), text, font=f, fill=(230, 210, 140, 60))
    img = Image.alpha_composite(img, layer)
    # soft shadow under the table
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((10, 16, W - 10, H - 2), fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(6))
    out = Image.alpha_composite(shadow, img)
    save(out, "felt.tga")


def rounded(size, radius, fill, outline=None, width=0):
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=fill, outline=outline, width=width)
    return img


def card_face():
    img = Image.new("RGBA", (128, 256), (0, 0, 0, 0))
    face = rounded((128, 180), 12, (246, 238, 220, 255), (120, 96, 60, 255), 3)
    # parchment speckle
    rnd = random.Random(5)
    px = face.load()
    for _ in range(1600):
        x, y = rnd.randint(4, 123), rnd.randint(4, 175)
        r, g, b, a = px[x, y]
        if a:
            k = rnd.randint(-10, 4)
            px[x, y] = (max(0, r + k), max(0, g + k), max(0, b + k), a)
    img.paste(face, (0, 0))
    save(img, "card.tga")


def card_back():
    img = Image.new("RGBA", (128, 256), (0, 0, 0, 0))
    back = rounded((128, 180), 12, (110, 18, 22, 255), (212, 168, 62, 255), 4)
    d = ImageDraw.Draw(back)
    d.rounded_rectangle((10, 10, 117, 169), 8, outline=(212, 168, 62, 255), width=2)
    for k in range(-180, 300, 14):
        d.line((12 + k, 12, 12 + k + 160, 172), fill=(150, 40, 40, 255), width=2)
        d.line((12 + k, 172, 12 + k + 160, 12), fill=(150, 40, 40, 255), width=2)
    # restore the frame over the lattice
    d.rounded_rectangle((0, 0, 127, 179), 12, outline=(212, 168, 62, 255), width=4)
    d.rounded_rectangle((10, 10, 117, 169), 8, outline=(212, 168, 62, 255), width=2)
    # central coin
    d.ellipse((34, 60, 94, 120), fill=(222, 178, 70, 255), outline=(120, 80, 20, 255), width=3)
    d.ellipse((44, 70, 84, 110), outline=(150, 105, 30, 255), width=2)
    f = font(["georgiab.ttf", "timesbd.ttf"], 30)
    tw = d.textlength("G", font=f)
    d.text((64 - tw / 2, 71), "G", font=f, fill=(110, 70, 15, 255))
    mask = Image.new("L", (128, 180), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 127, 179), 12, fill=255)
    img.paste(back, (0, 0), mask)
    save(img, "cardback.tga")


def suits():
    img = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font(["seguisym.ttf", "segoeui.ttf", "arial.ttf"], 54)
    glyphs = ["\u2663", "\u2666", "\u2665", "\u2660"]  # clubs, diamonds, hearts, spades (= suit index)
    colors = [(20, 20, 24, 255), (200, 24, 28, 255), (200, 24, 28, 255), (20, 20, 24, 255)]
    for i, (g, c) in enumerate(zip(glyphs, colors)):
        bbox = d.textbbox((0, 0), g, font=f)
        w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
        d.text((i * 64 + (64 - w) / 2 - bbox[0], (64 - h) / 2 - bbox[1]), g, font=f, fill=c)
    save(img, "suits.tga")


def dealer_button():
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((2, 4, 61, 63), fill=(0, 0, 0, 110))
    d.ellipse((2, 1, 60, 59), fill=(245, 240, 225, 255), outline=(150, 120, 60, 255), width=3)
    d.ellipse((9, 8, 53, 52), outline=(200, 170, 90, 255), width=2)
    f = font(["georgiab.ttf", "arialbd.ttf"], 30)
    bbox = d.textbbox((0, 0), "D", font=f)
    d.text((31 - (bbox[2] - bbox[0]) / 2 - bbox[0], 30 - (bbox[3] - bbox[1]) / 2 - bbox[1]), "D", font=f, fill=(30, 20, 10, 255))
    save(img, "dealer.tga")


def chip():
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((3, 5, 61, 63), fill=(0, 0, 0, 120))
    d.ellipse((2, 1, 60, 59), fill=(205, 160, 50, 255), outline=(110, 75, 15, 255), width=2)
    for k in range(8):
        a = k * math.pi / 4
        x, y = 31 + 24 * math.cos(a), 30 + 24 * math.sin(a)
        d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(250, 240, 210, 255))
    d.ellipse((14, 13, 48, 47), fill=(225, 185, 70, 255), outline=(140, 95, 20, 255), width=2)
    save(img, "chip.tga")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    felt()
    card_face()
    card_back()
    suits()
    dealer_button()
    chip()
