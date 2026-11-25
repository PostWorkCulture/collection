#!/usr/bin/env python3
"""Surface pass (AAA phase 3): gives the exported Mansion real surface detail.

The web game's textures are flat greyscale canvas patterns (tile grids, wood grain, brick, carpet) tinted by each
material's colour. This pass reads collection/level/mansion.glb, works out a height field from each known pattern,
and adds to every material that uses it:
  - a normal map (grout and seams sink, grain and weave stand up),
  - a roughness map (glossy tile faces, rough grout; matte carpet; polished marble),
so Godot lights them as real surfaces. Layout, colliders, colours and UVs are untouched.

Patterns are matched by a hash of their pixels (surfaces.json), so a fresh export from the web game still maps.
Run it after every export:  python3 tools/mansion_export/surface_pass.py [in.glb] [out.glb]
Needs numpy, scipy and Pillow.
"""
import hashlib, io, json, struct, sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "collection/level/mansion.glb"
DST = Path(sys.argv[2]) if len(sys.argv) > 2 else SRC


def read_glb(p: Path):
    b = p.read_bytes()
    assert b[:4] == b"glTF"
    jl = struct.unpack("<I", b[12:16])[0]
    g = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", b[off:off + 4])[0]
    return g, bytearray(b[off + 8:off + 8 + bl])


def write_glb(p: Path, g: dict, bin_: bytes):
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_ = bytes(bin_) + b"\0" * ((4 - len(bin_) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bin_)
    out = struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(bin_), b"BIN\0") + bin_
    p.write_bytes(out)


def image_bytes(g, bin_, i):
    bv = g["bufferViews"][g["images"][i]["bufferView"]]
    o = bv.get("byteOffset", 0)
    return bytes(bin_[o:o + bv["byteLength"]])


def pix_hash(rgba: np.ndarray) -> str:
    return hashlib.md5(rgba.tobytes()).hexdigest()[:12]


def tile_noise(h, w, cells, seed):
    """smooth tileable value noise in 0..1"""
    rng = np.random.default_rng(seed)
    g = rng.random((cells, cells))
    g = np.tile(g, (3, 3))
    big = ndimage.zoom(g, (3 * h) / (3 * cells), order=3, mode="grid-wrap")
    big = big[h:2 * h, w:2 * w] if big.shape[0] >= 2 * h else np.resize(big, (h, w))
    big = big[:h, :w]
    return (big - big.min()) / max(1e-6, np.ptp(big))


def height_field(rgba: np.ndarray, c: dict) -> np.ndarray:
    rgb = rgba[..., :3].astype(np.float32) / 255.0
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    if c.get("mask") == "ridges":
        # thin light lines (grout, mortar) between darker faces: a top-hat picks out the lines whatever the face colour
        t = ndimage.white_tophat(lum, size=c.get("ridge", 5), mode="wrap")
        h = 1.0 - np.clip(t / max(1e-3, np.percentile(t, 99)), 0, 1)
    elif c.get("mask") == "white":
        # light grout / mortar: low saturation and bright; everything else is the raised face
        sat = rgb.max(-1) - rgb.min(-1)
        grout = np.clip((lum - 0.72) / 0.2, 0, 1) * np.clip((0.25 - sat) / 0.15, 0, 1)
        h = 1.0 - grout
    else:
        lo, hi = np.percentile(lum, 2), np.percentile(lum, 98)
        h = np.clip((lum - lo) / max(1e-3, hi - lo), 0, 1)
        if c.get("invert"):
            h = 1.0 - h
    if c.get("noise", 0) > 0:
        n = tile_noise(h.shape[0], h.shape[1], c.get("noise_cells", 16), 7)
        f = tile_noise(h.shape[0], h.shape[1], max(4, h.shape[0] // 4), 11)
        h = h * (1 - c["noise"]) + (0.6 * n + 0.4 * f) * c["noise"]
    s = c.get("blur", 0.8)
    if s > 0:
        h = ndimage.gaussian_filter(h, s, mode="wrap")
    return h


def normal_map(h: np.ndarray, strength: float) -> Image.Image:
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx, ny, nz = -dx * strength, dy * strength, np.ones_like(h)   # glTF/OpenGL: +Y up, image rows go down
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / l, ny / l, nz / l], -1)
    return Image.fromarray(np.uint8(np.clip((n * 0.5 + 0.5) * 255 + 0.5, 0, 255)), "RGB")


def rough_map(h: np.ndarray, c: dict) -> Image.Image:
    r = c["rough_groove"] + (c["rough_face"] - c["rough_groove"]) * h   # the raised face vs the grooves
    z = np.zeros_like(r)
    mr = np.stack([np.ones_like(r), r, z], -1)                  # R unused (occlusion), G roughness, B metal (factor keeps it)
    return Image.fromarray(np.uint8(np.clip(mr * 255 + 0.5, 0, 255)), "RGB")


def add_image(g, bin_: bytearray, im: Image.Image) -> int:
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    data = buf.getvalue()
    while len(bin_) % 4:
        bin_.append(0)
    g["bufferViews"].append({"buffer": 0, "byteOffset": len(bin_), "byteLength": len(data)})
    bin_ += data
    g["images"].append({"mimeType": "image/png", "bufferView": len(g["bufferViews"]) - 1})
    return len(g["images"]) - 1


def main():
    table = json.loads((HERE / "surfaces.json").read_text())
    classes, patterns = table["classes"], table["patterns"]
    g, bin_ = read_glb(SRC)
    if g.get("extras", {}).get("surface_pass"):
        sys.exit("already has the surface pass: run it on a fresh export")
    tex_img = {i: t["source"] for i, t in enumerate(g["textures"])}
    hashes, done, n_mats = {}, {}, 0
    for i in range(len(g["images"])):
        rgba = np.asarray(Image.open(io.BytesIO(image_bytes(g, bin_, i))).convert("RGBA"))
        hashes[i] = (pix_hash(rgba), rgba)
    for mi, m in enumerate(g["materials"]):
        if "KHR_materials_unlit" in m.get("extensions", {}) or m.get("alphaMode") == "BLEND":
            continue
        p = m.get("pbrMetallicRoughness", {})
        bt = p.get("baseColorTexture")
        if not bt:
            continue
        img = tex_img[bt["index"]]
        hsh, rgba = hashes[img]
        cls = patterns.get(hsh, {}).get("class")
        if not cls:
            continue
        c = classes[cls]
        if img not in done:
            src = rgba
            if c.get("max_size") and src.shape[0] > c["max_size"]:
                src = np.asarray(Image.fromarray(src).resize((c["max_size"], c["max_size"]), Image.LANCZOS))
            h = height_field(src, c)
            nt = rt = None
            sampler = g["textures"][bt["index"]].get("sampler")
            if c.get("strength", 0) > 0:
                g["textures"].append({"source": add_image(g, bin_, normal_map(h, c["strength"])), **({"sampler": sampler} if sampler is not None else {})})
                nt = len(g["textures"]) - 1
            g["textures"].append({"source": add_image(g, bin_, rough_map(h, c)), **({"sampler": sampler} if sampler is not None else {})})
            rt = len(g["textures"]) - 1
            done[img] = (nt, rt)
        nt, rt = done[img]
        ext = {k: v for k, v in bt.items() if k != "index"}
        if nt is not None:
            m["normalTexture"] = {"index": nt, "scale": 1.0, **ext}
        p["metallicRoughnessTexture"] = {"index": rt, **ext}
        p["roughnessFactor"] = 1.0
        if "metal" in c:
            p["metallicFactor"] = c["metal"]
        if c.get("clearcoat"):
            m.setdefault("extensions", {})["KHR_materials_clearcoat"] = {"clearcoatFactor": c["clearcoat"], "clearcoatRoughnessFactor": 0.08}
        m.setdefault("extras", {})["surface"] = cls
        n_mats += 1
    g.setdefault("extras", {})["surface_pass"] = {"materials": n_mats, "patterns": len(done)}
    g["buffers"][0]["byteLength"] = len(bin_) + (4 - len(bin_) % 4) % 4
    write_glb(DST, g, bin_)
    print(f"surface pass: {len(done)} patterns, {n_mats} materials -> {DST} ({DST.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
