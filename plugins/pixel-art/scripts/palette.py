"""Palette presets, project palette files, and nearest-color snapping.

Standard library only. `render.py` resolves a spec's `palette` string through
`prepare_spec` and exposes snapping as `render.py --snap`.
"""
import json
import pathlib
import struct
import zlib

TRANSPARENT = "."
# Assigned, in order, to colors that do not name a key. 64 marks, none of them ".".
KEY_ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ~!"
# 4x4 Bayer index matrix. Ordered dither adds ((index * 2 + 1) - 16) * AMP // 16
# to each sRGB channel before the nearest-color pick. Off unless requested.
BAYER_4X4 = (
    (0, 8, 2, 10),
    (12, 4, 14, 6),
    (3, 11, 1, 9),
    (15, 7, 13, 5),
)
DITHER_AMPLITUDE = 32
ALPHA_CUTOFF = 128  # alpha below 128 (below 50% of 255) becomes transparent


def hex_rgb(value):
    text = value.strip().lstrip("#")
    if len(text) != 6 or any(c not in "0123456789abcdefABCDEF" for c in text):
        raise ValueError(f"color {value!r} is not #rrggbb")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


def normalize_hex(value):
    rgb = hex_rgb(value)
    return "#{:02x}{:02x}{:02x}".format(*rgb)


def preset_dir():
    return pathlib.Path(__file__).resolve().parent.parent / "palettes"


def list_presets():
    return sorted(path.stem for path in preset_dir().glob("*.json"))


def load_palette_document(data, source_name):
    """A preset or project file: {"colors": [{"key": optional, "hex": "#rrggbb"}, ...]}."""
    colors = data.get("colors") if isinstance(data, dict) else None
    if not isinstance(colors, list) or not colors:
        raise ValueError(f"palette {source_name} needs a non-empty 'colors' list")
    entries = []
    used = set()
    missing = []
    for i, entry in enumerate(colors):
        if isinstance(entry, str):
            entry = {"hex": entry}
        if not isinstance(entry, dict) or "hex" not in entry:
            raise ValueError(f"palette {source_name} color {i} needs a hex value")
        item = {"hex": normalize_hex(entry["hex"])}
        key = entry.get("key")
        if key is None:
            missing.append(i)
        else:
            if not isinstance(key, str) or len(key) != 1 or key == TRANSPARENT:
                raise ValueError(f"palette {source_name} key {key!r} must be one character other than '.'")
            if key in used:
                raise ValueError(f"palette {source_name} repeats key {key!r}")
            used.add(key)
            item["key"] = key
        entries.append(item)
    if missing:
        pool = [char for char in KEY_ALPHABET if char not in used]
        if len(missing) > len(pool):
            raise ValueError(
                f"palette {source_name} needs {len(missing)} keys but only {len(pool)} remain "
                f"in the {len(KEY_ALPHABET)}-character alphabet"
            )
        for index, char in zip(missing, pool):
            entries[index]["key"] = char
    return {entry["key"]: entry["hex"] for entry in entries}


def resolve_palette(value, base_dir):
    """Object, preset name, palette-file path, or inline JSON object text."""
    if isinstance(value, dict):
        return value
    if not isinstance(value, str) or not value.strip():
        raise ValueError("palette must be an object, a preset name, or a palette file path")
    text = value.strip()
    if text.startswith("{"):
        try:
            obj = json.loads(text)
        except json.JSONDecodeError as exc:
            raise ValueError(f"palette JSON is not valid: {exc}") from exc
        if not isinstance(obj, dict):
            raise ValueError("inline palette JSON must be an object of character to #rrggbb")
        return obj
    pathish = "/" in text or "\\" in text or text.endswith(".json")
    if not pathish:
        presets = list_presets()
        path = preset_dir() / f"{text}.json"
        if text not in presets or not path.is_file():
            raise ValueError(f"unknown palette preset {text!r}; available: {', '.join(presets)}")
        return load_palette_document(json.loads(path.read_text()), text)
    path = pathlib.Path(text)
    if not path.is_absolute():
        path = pathlib.Path(base_dir) / path
    if not path.is_file():
        raise ValueError(f"palette file {value!r} not found")
    try:
        data = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise ValueError(f"palette file {path.name} is not JSON: {exc}") from exc
    return load_palette_document(data, path.name)


def prepare_spec(spec, spec_path=None):
    """Return spec with a string `palette` replaced by its color object."""
    palette = spec.get("palette")
    if isinstance(palette, dict):
        return spec
    if isinstance(palette, str):
        base = pathlib.Path(spec_path).resolve().parent if spec_path else pathlib.Path.cwd()
        resolved = dict(spec)
        resolved["palette"] = resolve_palette(palette, base)
        return resolved
    raise ValueError("palette must be an object, a preset name, or a palette file path")


def paeth(left, up, up_left):
    estimate = left + up - up_left
    dist_left = abs(estimate - left)
    dist_up = abs(estimate - up)
    dist_up_left = abs(estimate - up_left)
    if dist_left <= dist_up and dist_left <= dist_up_left:
        return left
    if dist_up <= dist_up_left:
        return up
    return up_left


def read_png(path):
    """8-bit non-interlaced RGB or RGBA PNG. Returns (width, height, rgba rows)."""
    data = pathlib.Path(path).read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"{path} is not a PNG")
    pos = 8
    width = height = bit_depth = color_type = interlace = None
    idat = bytearray()
    while pos + 8 <= len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        end = pos + 12 + length
        if end > len(data):
            raise ValueError(f"PNG chunk {tag!r} is truncated")
        body = data[pos + 8:pos + 8 + length]
        pos = end
        if tag == b"IHDR":
            if length != 13:
                raise ValueError("PNG IHDR is not 13 bytes")
            width, height, bit_depth, color_type, compression, filter_method, interlace = struct.unpack(
                ">IIBBBBB", body)
            if compression != 0 or filter_method != 0:
                raise ValueError("PNG compression or filter method is not the standard one")
        elif tag == b"IDAT":
            idat += body
        elif tag == b"tRNS":
            raise ValueError("PNG tRNS is not supported; use 8-bit RGBA")
        elif tag == b"IEND":
            break
    if width is None:
        raise ValueError("PNG has no IHDR")
    if interlace != 0:
        raise ValueError("PNG is interlaced; only non-interlaced 8-bit RGB or RGBA is supported")
    if bit_depth != 8 or color_type not in (2, 6):
        raise ValueError(
            f"PNG bit depth {bit_depth} color type {color_type} is not supported; "
            "only 8-bit RGB (color type 2) or RGBA (color type 6), non-interlaced"
        )
    if not idat:
        raise ValueError("PNG has no image data")
    bpp = 4 if color_type == 6 else 3
    try:
        raw = zlib.decompress(bytes(idat))
    except zlib.error as exc:
        raise ValueError(f"PNG image data did not decompress: {exc}") from exc
    stride = 1 + width * bpp
    if len(raw) != stride * height:
        raise ValueError("PNG image data length does not match the header")
    rows = []
    previous = bytearray(width * bpp)
    for y in range(height):
        filter_type = raw[y * stride]
        scan = raw[y * stride + 1:(y + 1) * stride]
        if filter_type > 4:
            raise ValueError(f"PNG filter type {filter_type} is not supported")
        recon = bytearray(width * bpp)
        for i, sample in enumerate(scan):
            left = recon[i - bpp] if i >= bpp else 0
            up = previous[i]
            up_left = previous[i - bpp] if i >= bpp else 0
            if filter_type == 0:
                value = sample
            elif filter_type == 1:
                value = sample + left
            elif filter_type == 2:
                value = sample + up
            elif filter_type == 3:
                value = sample + ((left + up) // 2)
            else:
                value = sample + paeth(left, up, up_left)
            recon[i] = value & 255
        previous = recon
        row = []
        if bpp == 4:
            for x in range(width):
                i = x * 4
                row.append((recon[i], recon[i + 1], recon[i + 2], recon[i + 3]))
        else:
            for x in range(width):
                i = x * 3
                row.append((recon[i], recon[i + 1], recon[i + 2], 255))
        rows.append(row)
    return width, height, rows


def palette_colors(palette):
    """(keys, [(r, g, b), ...]) in palette order."""
    keys = list(palette)
    return keys, [hex_rgb(palette[key]) for key in keys]


def nearest_index(red, green, blue, colors):
    """Squared Euclidean distance in 8-bit sRGB. Ties take the earlier color."""
    best_i = 0
    best_d = None
    for i, (cr, cg, cb) in enumerate(colors):
        distance = (red - cr) ** 2 + (green - cg) ** 2 + (blue - cb) ** 2
        if best_d is None or distance < best_d:
            best_d = distance
            best_i = i
    return best_i


def dither_offset(x, y):
    bayer = BAYER_4X4[y % 4][x % 4]
    return ((bayer * 2 + 1) - 16) * DITHER_AMPLITUDE // 16


def snap_rgba(rows, colors, dither=False):
    """Map RGBA rows onto `colors`. Alpha below 128 becomes (0, 0, 0, 0); the rest are opaque."""
    snapped = []
    for y, row in enumerate(rows):
        out = []
        for x, (red, green, blue, alpha) in enumerate(row):
            if alpha < ALPHA_CUTOFF:
                out.append((0, 0, 0, 0))
                continue
            if dither:
                offset = dither_offset(x, y)
                red = min(255, max(0, red + offset))
                green = min(255, max(0, green + offset))
                blue = min(255, max(0, blue + offset))
            cr, cg, cb = colors[nearest_index(red, green, blue, colors)]
            out.append((cr, cg, cb, 255))
        snapped.append(out)
    return snapped


def snap_frame_rows(rows, palette, dither=False):
    """One spec frame: strings of palette keys, '.' where the pixel is transparent."""
    keys, colors = palette_colors(palette)
    by_rgb = {}
    for key, rgb in zip(keys, colors):
        by_rgb.setdefault(rgb, key)
    frame = []
    for row in snap_rgba(rows, colors, dither):
        chars = []
        for red, green, blue, alpha in row:
            chars.append(TRANSPARENT if alpha == 0 else by_rgb[(red, green, blue)])
        frame.append("".join(chars))
    return frame
