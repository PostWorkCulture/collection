"""Hall of Fame posters for the trophy room (Pete, 26 Nov): rock singers and guitarists, poster art in the style of a
gig poster. No photos or likenesses of anyone: each shows an instrument under a stage light (an electric guitar, or a
vintage microphone for a singer) with the name in gold. Run: python3 make_posters.py <out dir> (writes <slug>.jpg,
600 x 760, JPEG 88)."""
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

W, H = 600, 760
SS = 2
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
SANS = "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf"
ROCKERS = [   # name, role, instrument, body colour, light colour
    ("Freddie Mercury", "VOCALS", "mic", (210, 210, 215), (255, 206, 120)),
    ("Brian May", "GUITAR", "double", (120, 34, 26), (255, 160, 90)),
    ("Slash", "GUITAR", "single", (150, 60, 20), (255, 110, 70)),
    ("Axl Rose", "VOCALS", "mic", (200, 200, 205), (255, 120, 170)),
    ("Jimi Hendrix", "GUITAR", "strat", (240, 236, 222), (190, 140, 255)),
    ("Robert Plant", "VOCALS", "mic", (205, 205, 210), (255, 190, 120)),
    ("Jimmy Page", "GUITAR", "single", (28, 28, 30), (140, 230, 200)),
    ("Mick Jagger", "VOCALS", "mic", (210, 210, 215), (255, 100, 100)),
    ("Eddie Van Halen", "GUITAR", "strat", (190, 30, 28), (255, 236, 140)),
    ("Kurt Cobain", "GUITAR", "offset", (60, 110, 170), (170, 205, 255)),
]

def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))

def background(light):
    w, h = W // 2, H // 2   # drawn at half size and scaled up: it's all soft light
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            dx = (x - w * 0.5) / w
            t = y / h
            cone = max(0.0, 1.0 - abs(dx) / (0.1 + 0.42 * t)) ** 1.8 * (0.75 - 0.4 * t)
            pool = math.exp(-(((x - w * 0.5) / (w * 0.32)) ** 2 + ((y - h * 0.62) / (h * 0.2)) ** 2)) * 0.35
            v = min(1.0, cone + pool + 0.04)
            px[x, y] = mix((7, 7, 10), light, v)
    return img.resize((W * SS, H * SS), Image.BICUBIC)

def shade(mask, base, light, angle=0.0):
    """fill a mask with base colour, lit from the upper left: a smooth gradient and a soft highlight"""
    w, h = mask.size
    grad = Image.linear_gradient("L").rotate(angle, expand=False).resize((w, h))
    dark = Image.new("RGB", (w, h), mix(base, (0, 0, 0), 0.55))
    lit = Image.new("RGB", (w, h), mix(base, light, 0.35))
    body = Image.composite(dark, lit, grad)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(body, (0, 0), mask)
    return out

def guitar(kind, col, light):
    k = SS
    L = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    m = Image.new("L", L.size, 0)
    d = ImageDraw.Draw(m)
    cx, cy = 300 * k, 470 * k
    E = lambda x0, y0, x1, y1: d.ellipse([cx + x0 * k, cy + y0 * k, cx + x1 * k, cy + y1 * k], fill=255)
    if kind == "single":       # single cutaway: a round lower bout, a smaller upper bout, the cut on the treble side
        E(-120, -10, 120, 170); E(-95, -120, 85, 40); d.rectangle([cx - 100 * k, cy - 60 * k, cx + 100 * k, cy + 100 * k], fill=255)
        d.ellipse([cx + 20 * k, cy - 150 * k, cx + 140 * k, cy - 30 * k], fill=0)
    elif kind == "double":     # double cutaway: two horns
        E(-125, -10, 125, 165); E(-110, -105, 110, 60)
        d.ellipse([cx - 70 * k, cy - 170 * k, cx - 5 * k, cy - 70 * k], fill=0); d.ellipse([cx + 5 * k, cy - 170 * k, cx + 70 * k, cy - 70 * k], fill=0)
        E(-118, -158, -72, -70); E(72, -150, 118, -70)
    elif kind == "strat":      # contoured double cutaway with a longer bass horn
        E(-122, -5, 122, 165); E(-105, -95, 105, 60)
        d.ellipse([cx - 60 * k, cy - 175 * k, cx + 5 * k, cy - 70 * k], fill=0); d.ellipse([cx + 12 * k, cy - 160 * k, cx + 75 * k, cy - 75 * k], fill=0)
        E(-116, -182, -74, -70); E(74, -142, 114, -70)
    else:                      # offset body
        E(-130, 0, 115, 165); E(-100, -105, 120, 70); d.ellipse([cx - 40 * k, cy - 160 * k, cx + 40 * k, cy - 80 * k], fill=0)
        E(-128, -170, -62, -60); E(70, -128, 126, -55)
    m = m.filter(ImageFilter.GaussianBlur(16 * k)).point(lambda a: 255 if a > 118 else 0)   # one smooth outline
    m = m.filter(ImageFilter.GaussianBlur(1.2 * k))
    body = shade(m, col, light, 30)
    L.alpha_composite(body)
    g = ImageDraw.Draw(L)
    # neck, frets, headstock, pickups, bridge, knobs, strings
    nw = 34 * k
    g.rectangle([cx - nw / 2, cy - 470 * k, cx + nw / 2, cy - 40 * k], fill=(92, 58, 34, 255))
    for i in range(1, 22):
        y = cy - 470 * k + (430 * k) * (1 - 0.94 ** i) / (1 - 0.94 ** 22)
        g.line([cx - nw / 2, y, cx + nw / 2, y], fill=(205, 200, 190, 255), width=max(1, k))
    for i in (3, 5, 7, 9, 12, 15, 17):
        y = cy - 470 * k + (430 * k) * ((1 - 0.94 ** i) + (1 - 0.94 ** (i - 1))) / 2 / (1 - 0.94 ** 22)
        g.ellipse([cx - 4 * k, y - 4 * k, cx + 4 * k, y + 4 * k], fill=(235, 230, 220, 255))
    hs = [(cx - 26 * k, cy - 470 * k), (cx + 26 * k, cy - 470 * k), (cx + 32 * k, cy - 560 * k), (cx - 30 * k, cy - 575 * k)]
    g.polygon(hs, fill=(20, 18, 18, 255))
    for i in range(3):
        for s in (-1, 1):
            y = cy - (490 + i * 26) * k
            g.ellipse([cx + s * 36 * k - 7 * k, y - 7 * k, cx + s * 36 * k + 7 * k, y + 7 * k], fill=(200, 200, 205, 255))
    for py in (cy - 20 * k, cy + 45 * k):
        g.rounded_rectangle([cx - 38 * k, py - 14 * k, cx + 38 * k, py + 14 * k], radius=5 * k, fill=(25, 25, 28, 255))
        for i in range(6):
            g.ellipse([cx - 30 * k + i * 12 * k - 3 * k, py - 3 * k, cx - 30 * k + i * 12 * k + 3 * k, py + 3 * k], fill=(190, 190, 195, 255))
    g.rectangle([cx - 42 * k, cy + 92 * k, cx + 42 * k, cy + 104 * k], fill=(200, 200, 205, 255))
    for i, (dx, dy) in enumerate([(70, 80), (92, 108), (68, 128), (90, 150)]):
        g.ellipse([cx + dx * k - 10 * k, cy + dy * k - 10 * k, cx + dx * k + 10 * k, cy + dy * k + 10 * k], fill=(205, 170, 90, 255))
    for i in range(6):
        x = cx - 14 * k + i * 5.6 * k
        g.line([x, cy - 470 * k, x, cy + 98 * k], fill=(230, 230, 235, 200), width=max(1, k // 2))
    return L

def microphone(col, light):
    k = SS
    L = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    g = ImageDraw.Draw(L)
    cx, cy = 300 * k, 300 * k
    # stand
    g.rectangle([cx - 7 * k, cy + 120 * k, cx + 7 * k, cy + 380 * k], fill=(40, 40, 44, 255))
    g.ellipse([cx - 90 * k, cy + 370 * k, cx + 90 * k, cy + 400 * k], fill=(30, 30, 34, 255))
    # the classic capsule: a rounded grille with horizontal bars, on a tapered chrome body
    m = Image.new("L", L.size, 0)
    md = ImageDraw.Draw(m)
    md.rounded_rectangle([cx - 85 * k, cy - 150 * k, cx + 85 * k, cy + 60 * k], radius=80 * k, fill=255)
    md.polygon([(cx - 60 * k, cy + 40 * k), (cx + 60 * k, cy + 40 * k), (cx + 28 * k, cy + 130 * k), (cx - 28 * k, cy + 130 * k)], fill=255)
    L.alpha_composite(shade(m, col, light, 20))
    for i in range(-130, 50, 12):
        y = cy + i * k
        g.line([cx - 78 * k, y, cx + 78 * k, y], fill=(60, 60, 66, 230), width=max(1, k * 2))
    for i in range(-70, 75, 14):
        g.line([cx + i * k, cy - 140 * k, cx + i * k, cy + 50 * k], fill=(80, 80, 86, 140), width=max(1, k))
    g.rounded_rectangle([cx - 88 * k, cy - 8 * k, cx + 88 * k, cy + 8 * k], radius=4 * k, fill=(220, 220, 228, 255))
    g.rounded_rectangle([cx - 86 * k, cy - 154 * k, cx + 86 * k, cy + 62 * k], radius=82 * k, outline=(235, 235, 240, 255), width=4 * k)
    return L

def poster(name, role, inst, col, light):
    img = background(light).convert("RGBA")
    art = microphone(col, light) if inst == "mic" else guitar(inst, col, light)
    if inst != "mic":
        art = art.rotate(-32, resample=Image.BICUBIC, center=(300 * SS, 420 * SS), translate=(0, -10 * SS))
    # a soft glow behind the instrument, then the instrument with a rim of light
    glow = Image.new("RGBA", art.size, mix(light, (255, 255, 255), 0.3) + (0,))
    glow.putalpha(art.getchannel("A").filter(ImageFilter.GaussianBlur(22 * SS)).point(lambda a: int(a * 0.55)))
    img.alpha_composite(glow)
    img.alpha_composite(art)
    rnd = random.Random(name)
    d = ImageDraw.Draw(img)
    for i in range(90):   # dust in the beam
        x, y = rnd.gauss(W * SS / 2, W * SS * 0.12), rnd.uniform(0, H * SS * 0.75)
        r = rnd.uniform(0.6, 1.8) * SS
        d.ellipse([x - r, y - r, x + r, y + r], fill=mix(light, (255, 255, 255), 0.5) + (int(rnd.uniform(40, 140)),))
    img = img.convert("RGB").resize((W, H), Image.LANCZOS)
    d = ImageDraw.Draw(img)
    gold, pale = (226, 186, 96), (236, 232, 222)
    d.rectangle([14, 14, W - 15, H - 15], outline=gold, width=2)
    f0 = ImageFont.truetype(SANS, 15)
    t0 = "H A L L   O F   F A M E"
    d.text(((W - d.textlength(t0, font=f0)) / 2, 30), t0, font=f0, fill=gold)
    d.rectangle([0, H - 118, W, H - 16], fill=(9, 9, 11))
    d.rectangle([14, H - 118, W - 15, H - 15], outline=gold, width=2)
    size = 46
    f = ImageFont.truetype(SERIF, size)
    while d.textlength(name.upper(), font=f) > W - 80:
        size -= 2
        f = ImageFont.truetype(SERIF, size)
    tw = d.textlength(name.upper(), font=f)
    d.text(((W - tw) / 2, H - 104), name.upper(), font=f, fill=gold)
    f2 = ImageFont.truetype(SANS, 15)
    r = " ".join(role)
    d.text(((W - d.textlength(r, font=f2)) / 2, H - 46), r, font=f2, fill=pale)
    return img

if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, role, inst, col, light in ROCKERS:
        slug = name.lower().replace(" ", "_")
        poster(name, role, inst, col, light).save(os.path.join(out, slug + ".jpg"), quality=88)
        print(slug)
