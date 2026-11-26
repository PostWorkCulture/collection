"""Textures for the six weapon skins ported from imok 1v1 (its batTex / batMats canvases, redrawn with PIL): the patterned
finishes (gold, galaxy, lava, 128 x 256) and each skin's grip tape (32 x 128, diagonal wraps). Run:
python3 make_textures.py <out dir>   (writes <skin>.png and tape_<skin>.png)"""
import os, random, sys
from PIL import Image, ImageDraw, ImageFilter

TAPE = {   # base, light stripe, dark stripe (1v1 BAT_SKINS[..].tape)
    "classic": ("#c4161c", (255, 255, 255, 36), (0, 0, 0, 89)),
    "gold": ("#111111", (255, 214, 80, 204), (0, 0, 0, 128)),
    "toxic": ("#6a1bc4", (125, 255, 58, 89), (0, 0, 0, 102)),
    "candy": ("#21d4ff", (255, 255, 255, 102), (0, 40, 90, 89)),
    "galaxy": ("#0b0820", (41, 240, 255, 115), (0, 0, 0, 128)),
    "lava": ("#1a1412", (255, 106, 0, 140), (0, 0, 0, 128)),
}

def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def grad_h(img, stops):
    w, h = img.size
    px = img.load()
    for x in range(w):
        t = x / (w - 1)
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                k = (t - stops[i][0]) / max(1e-6, stops[i + 1][0] - stops[i][0])
                c = lerp(hexc(stops[i][1]), hexc(stops[i + 1][1]), k)
                break
        for y in range(h):
            px[x, y] = c

def gold(rnd):
    img = Image.new("RGB", (128, 256))
    grad_h(img, [(0, "#b87000"), (.28, "#ffb400"), (.46, "#ffe58a"), (.5, "#fff6d0"), (.56, "#ffd040"), (.8, "#e89a00"), (1, "#a86400")])
    d = ImageDraw.Draw(img, "RGBA")
    for i in range(90):   # brushed streaks
        x, y = rnd.random() * 128, rnd.random() * 256
        d.rectangle([x, y, x + 1, y + 2 + rnd.random() * 6], fill=(255, 226, 120, int(255 * (.2 + rnd.random() * .25))))
    for i in range(70):   # glitter
        x, y, a = rnd.random() * 128, rnd.random() * 256, rnd.random()
        s = 2 if a > .8 else 1
        d.rectangle([x, y, x + s - 1, y + s - 1], fill=(255, 255, 255, int(255 * (.6 + a * .4))))
        if a > .9:
            d.rectangle([x - 3, y, x + 3, y], fill=(255, 255, 255, 220))
            d.rectangle([x, y - 3, x, y + 3], fill=(255, 255, 255, 220))
    return img

def galaxy(rnd):
    img = Image.new("RGB", (128, 256))
    px = img.load()
    for y in range(256):
        t = y / 255
        c = lerp(hexc("#1a0640"), hexc("#2a0f7a"), t * 2) if t < .5 else lerp(hexc("#2a0f7a"), hexc("#08164a"), (t - .5) * 2)
        for x in range(128):
            px[x, y] = c
    neb = Image.new("RGBA", (128, 256), (0, 0, 0, 0))
    nd = ImageDraw.Draw(neb)
    for i in range(14):
        x, y, r = rnd.random() * 128, rnd.random() * 256, 18 + rnd.random() * 30
        col = (255, 79, 216, 110) if i % 2 else (41, 200, 255, 100)
        nd.ellipse([x - r, y - r, x + r, y + r], fill=col)
    neb = neb.filter(ImageFilter.GaussianBlur(12))
    img = Image.alpha_composite(img.convert("RGBA"), neb)
    d = ImageDraw.Draw(img)
    for i in range(260):
        a = rnd.random()
        s = 2 if a > .93 else 1
        x, y = rnd.random() * 128, rnd.random() * 256
        d.rectangle([x, y, x + s - 1, y + s - 1], fill=(255, 255, 255, int(255 * (.4 + a * .6))))
    return img.convert("RGB")

def lava(rnd):
    img = Image.new("RGB", (128, 256), hexc("#120c0a"))
    glow = Image.new("RGB", (128, 256), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    d = ImageDraw.Draw(img)
    for k in range(22):
        x, y = rnd.random() * 128, rnd.random() * 256
        pts = [(x, y)]
        for j in range(6):
            x += (rnd.random() - .5) * 34
            y += (rnd.random() - .3) * 30
            pts.append((x, y))
        col = hexc("#ff6a00") if k % 3 else hexc("#ffc23a")
        w = int(1 + rnd.random() * 2.4)
        gd.line(pts, fill=hexc("#ff5a00"), width=w + 5, joint="curve")
        d.line(pts, fill=col, width=w, joint="curve")
    glow = glow.filter(ImageFilter.GaussianBlur(4))
    from PIL import ImageChops
    return ImageChops.add(img, glow)

def tape(base, light, dark):
    img = Image.new("RGBA", (32, 128), hexc(base) + (255,))
    ov = Image.new("RGBA", (32, 128), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    for y in range(-40, 170, 9):
        d.line([(0, y), (32, y + 22)], fill=light, width=3)
        d.line([(0, y + 2), (32, y + 24)], fill=dark, width=3)
    return Image.alpha_composite(img, ov).convert("RGB")

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, fn in (("gold", gold), ("galaxy", galaxy), ("lava", lava)):
        fn(random.Random(1)).save(os.path.join(out, name + ".png"))
    for k, (b, l, dk) in TAPE.items():
        tape(b, l, dk).save(os.path.join(out, "tape_%s.png" % k))
    print("ok")
