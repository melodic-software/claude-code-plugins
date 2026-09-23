#!/usr/bin/env python3
"""Render a pixel-art spec to engine-ready files using only the Python standard library.

Spec (JSON):
  palette     {"k": "#1a1c2c", ...}   one character per colour; "." is always transparent
  frames      {"name": ["row", ...]}  every frame the same width and height
  animations  {"name": {"frames": ["f0", "f1"], "fps": 8, "durations_ms": [..optional..]}}
  sheet       {"columns": 3, "order": ["f0", ...]}   optional; defaults to one row of all frames

Outputs in --out:
  sheet.png          1x sprite sheet (the engine asset)
  sheet.json         frame rects, durations and animation tags (Aseprite json-hash shape)
  preview.png        sheet upscaled by --scale with nearest-neighbour, for review
  <animation>.gif    looping preview per animation, upscaled by --scale
"""
import argparse
import json
import pathlib
import struct
import sys
import zlib

TRANSPARENT = "."


def hex_rgb(value):
    value = value.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"colour {value!r} is not #rrggbb")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def validate(spec):
    palette, frames = spec.get("palette"), spec.get("frames")
    if not palette or not frames:
        raise ValueError("spec needs non-empty 'palette' and 'frames'")
    for key, colour in palette.items():
        if len(key) != 1 or key == TRANSPARENT:
            raise ValueError(f"palette key {key!r} must be one character other than '.'")
        hex_rgb(colour)
    first = next(iter(frames.values()))
    h, w = len(first), len(first[0])
    for name, rows in frames.items():
        if len(rows) != h or any(len(r) != w for r in rows):
            raise ValueError(f"frame {name!r} is not {w}x{h}")
        unknown = {c for r in rows for c in r if c != TRANSPARENT and c not in palette}
        if unknown:
            raise ValueError(f"frame {name!r} uses colours not in the palette: {sorted(unknown)}")
    for name, anim in spec.get("animations", {}).items():
        missing = [f for f in anim["frames"] if f not in frames]
        if missing:
            raise ValueError(f"animation {name!r} names unknown frames {missing}")
        if "durations_ms" in anim and len(anim["durations_ms"]) != len(anim["frames"]):
            raise ValueError(f"animation {name!r} durations_ms length differs from frames")
    order = spec.get("sheet", {}).get("order", [])
    missing = [f for f in order if f is not None and f not in frames]
    if missing:
        raise ValueError(f"sheet order names unknown frames {missing}")
    return w, h


def write_png(path, width, height, rows):
    """rows: list of lists of (r, g, b, a)."""
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in rows)

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))


def lzw_encode(indices, min_code_size):
    """Variable-width GIF LZW, emitting a clear code when the 4096-entry table fills."""
    clear, end = 1 << min_code_size, (1 << min_code_size) + 1
    out, acc, nbits = bytearray(), 0, 0
    size = min_code_size + 1

    def emit(code):
        nonlocal acc, nbits
        acc |= code << nbits
        nbits += size
        while nbits >= 8:
            out.append(acc & 0xFF)
            acc >>= 8
            nbits -= 8

    def fresh():
        return {(i,): i for i in range(clear)}

    table, nxt = fresh(), end + 1
    emit(clear)
    current = (indices[0],)
    for px in indices[1:]:
        candidate = current + (px,)
        if candidate in table:
            current = candidate
            continue
        emit(table[current])
        if nxt < 4096:
            table[candidate] = nxt
            nxt += 1
            if nxt > (1 << size) and size < 12:
                size += 1
        else:
            emit(clear)
            table, nxt, size = fresh(), end + 1, min_code_size + 1
        current = (px,)
    emit(table[current])
    emit(end)
    if nbits:
        out.append(acc & 0xFF)
    return bytes(out)


def write_gif(path, width, height, colours, frames, delays_cs):
    """colours: list of (r, g, b); index 0 of every frame is transparent. frames: flat index lists."""
    bits = 2
    while (1 << bits) < len(colours) + 1:
        bits += 1
    if bits > 8:
        raise ValueError("GIF allows at most 255 colours plus transparency")
    table = bytearray(3 * (1 << bits))
    for i, rgb in enumerate(colours, 1):
        table[3 * i:3 * i + 3] = bytes(rgb)
    data = bytearray(b"GIF89a" + struct.pack("<HHBBB", width, height, 0x80 | (bits - 1), 0, 0) + table)
    data += b"\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00"  # loop forever
    for indices, delay in zip(frames, delays_cs):
        data += b"\x21\xf9\x04" + struct.pack("<BHBB", 0x09, delay, 0, 0)  # restore-to-background, index 0 transparent
        data += b"\x2c" + struct.pack("<HHHHB", 0, 0, width, height, 0) + bytes([bits])
        body = lzw_encode(indices, bits)
        for i in range(0, len(body), 255):
            block = body[i:i + 255]
            data += bytes([len(block)]) + block
        data += b"\x00"
    data += b"\x3b"
    path.write_bytes(bytes(data))


def frame_durations(anim):
    if "durations_ms" in anim:
        return list(anim["durations_ms"])
    return [round(1000 / anim.get("fps", 8))] * len(anim["frames"])


def render(spec, out_dir, scale=8):
    w, h = validate(spec)
    out_dir.mkdir(parents=True, exist_ok=True)
    palette, frames = spec["palette"], spec["frames"]
    keys = list(palette)
    rgba = {k: hex_rgb(v) + (255,) for k, v in palette.items()}
    rgba[TRANSPARENT] = (0, 0, 0, 0)

    sheet = spec.get("sheet", {})
    order = sheet.get("order") or list(frames)
    columns = sheet.get("columns") or len(order)
    rows_n = -(-len(order) // columns)
    placed = {}
    for i, name in enumerate(order):
        if name is not None and name not in placed:
            placed[name] = ((i % columns) * w, (i // columns) * h)

    def sheet_pixels(s):
        grid = [[rgba[TRANSPARENT]] * (columns * w * s) for _ in range(rows_n * h * s)]
        for i, name in enumerate(order):
            if name is None:
                continue
            ox, oy = (i % columns) * w, (i // columns) * h
            for y, row in enumerate(frames[name]):
                for x, c in enumerate(row):
                    for dy in range(s):
                        grid[(oy + y) * s + dy][(ox + x) * s:(ox + x + 1) * s] = [rgba[c]] * s
        return grid

    write_png(out_dir / "sheet.png", columns * w, rows_n * h, sheet_pixels(1))
    write_png(out_dir / "preview.png", columns * w * scale, rows_n * h * scale, sheet_pixels(scale))

    animations = spec.get("animations") or {"all": {"frames": list(frames), "fps": 8}}
    index_of = {k: i + 1 for i, k in enumerate(keys)}
    index_of[TRANSPARENT] = 0
    for name, anim in animations.items():
        flat = [[index_of[frames[f][y // scale][x // scale]] for y in range(h * scale) for x in range(w * scale)]
                for f in anim["frames"]]
        delays = [max(2, round(ms / 10)) for ms in frame_durations(anim)]
        write_gif(out_dir / f"{name}.gif", w * scale, h * scale, [hex_rgb(palette[k]) for k in keys], flat, delays)

    frame_meta = {}
    for name, (x, y) in placed.items():
        frame_meta[name] = {"frame": {"x": x, "y": y, "w": w, "h": h}, "rotated": False, "trimmed": False,
                            "spriteSourceSize": {"x": 0, "y": 0, "w": w, "h": h}, "sourceSize": {"w": w, "h": h},
                            "duration": 100}
    tags = []
    for name, anim in animations.items():
        for f, ms in zip(anim["frames"], frame_durations(anim)):
            if f in frame_meta:
                frame_meta[f]["duration"] = ms
        tags.append({"name": name, "frames": anim["frames"], "durations_ms": frame_durations(anim),
                     "direction": anim.get("direction", "forward")})
    meta = {"frames": frame_meta,
            "meta": {"app": "pixel-art render.py", "image": "sheet.png", "format": "RGBA8888",
                     "size": {"w": columns * w, "h": rows_n * h}, "scale": "1", "frameTags": tags}}
    (out_dir / "sheet.json").write_text(json.dumps(meta, indent=2))
    return sorted(p.name for p in out_dir.iterdir())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spec", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--scale", type=int, default=8, help="preview and GIF upscale factor (default 8)")
    args = parser.parse_args(argv)
    try:
        written = render(json.loads(args.spec.read_text()), args.out, args.scale)
    except (ValueError, KeyError) as exc:
        print(f"render.py: {exc}", file=sys.stderr)
        return 2
    print("\n".join(str(args.out / name) for name in written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
