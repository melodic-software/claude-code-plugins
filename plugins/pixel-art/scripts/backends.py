#!/usr/bin/env python3
"""Select a pixel-art backend and write the artifact contract.

  python3 backends.py spec.json --out dir
  python3 backends.py spec.json --out dir --backend aseprite
  python3 backends.py spec.json --out dir --backend pixellab --confirm
  python3 backends.py --ingest frame.png --palette pico-8 --out dir --width 32 --height 32

`native` always works. `aseprite` runs when the CLI is on PATH (or ASEPRITE).
`pixellab` and `retrodiffusion` run only with an API token and `--confirm`,
because each call spends money. A missing backend prints one line and renders
with native. An adapter that cannot meet the contract does the same and does
not leave a partial sheet behind.
"""
import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse

import aseprite_backend
import hosted_backends
import image_pipeline
import palette as palette_mod
import render

NOTICES = {
    "aseprite-missing": "Aseprite not found on PATH; rendered with the native backend",
    "pixellab-missing": "PixelLab API token not set (PIXELLAB_API_TOKEN); rendered with the native backend",
    "retro-missing": "Retro Diffusion API key not set (RD_API_KEY); rendered with the native backend",
    "pixellab-confirm": (
        "PixelLab was not called (confirmation required; each image reports usage.usd). "
        "Rendered with the native backend"
    ),
    "retro-confirm": (
        "Retro Diffusion was not called (confirmation required; the task reports balance_cost in USD). "
        "Rendered with the native backend"
    ),
}


def backend_name(explicit, env):
    name = (explicit or env.get("CLAUDE_PLUGIN_OPTION_BACKEND") or "native").strip().lower()
    if name in ("", "native"):
        return "native"
    return name


def confirmed(flag, env):
    return bool(flag) or env.get("PIXEL_ART_BACKEND_CONFIRM") == "1"


def find_aseprite(env):
    candidate = env.get("ASEPRITE") or shutil.which("aseprite", path=env.get("PATH"))
    if not candidate:
        return None
    try:
        proc = subprocess.run(
            [candidate, "--version"], capture_output=True, text=True, timeout=20, env=env, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if proc.returncode != 0:
        return None
    return candidate


def _native(spec, out_dir, scale, spec_path, notice):
    if notice:
        print(notice)
    try:
        files = render.render(spec, out_dir, scale, spec_path)
    except (ValueError, KeyError, OSError) as exc:
        raise RuntimeError(str(exc)) from exc
    return files


def _upscale_sheet(sheet_path, preview_path, scale):
    _width, _height, rows = palette_mod.read_png(sheet_path)
    if scale == 1:
        shutil.copyfile(sheet_path, preview_path)
        return
    big = []
    for row in rows:
        expanded = []
        for pixel in row:
            expanded.extend([pixel] * scale)
        for _ in range(scale):
            big.append(expanded)
    render.write_png(preview_path, len(big[0]), len(big), big)


def _check_sheet(sheet_path, palette):
    _width, _height, rows = palette_mod.read_png(sheet_path)
    bad = image_pipeline.palette_violations(rows, palette)
    if bad:
        raise RuntimeError(f"sheet.png has {bad} pixels outside the palette")


def _normalize_sheet_json(data_path, plan):
    """Rewrite Aseprite's json-hash into the contract shape; return why it cannot, or None.

    Aseprite emits one frame per sheet slot (null cells are empty frames) in sheet order, keyed by
    a filename pattern, and records the absolute --sheet path as meta.image. The frames map back to
    spec names by position, so the result does not depend on the key format.
    """
    try:
        data = json.loads(data_path.read_text())
    except (ValueError, OSError):
        return "sheet.json is unreadable"
    frames = data.get("frames") if isinstance(data, dict) else None
    meta = data.get("meta") if isinstance(data, dict) else None
    if not isinstance(frames, dict) or not isinstance(meta, dict):
        return "sheet.json has no frames map or meta block"
    names = [frame["name"] for frame in plan["frames"]]
    if len(frames) != len(names):
        return f"sheet.json has {len(frames)} frames for {len(names)} sheet cells"
    cells = list(frames.values())
    kept = [i for i, name in enumerate(names) if name is not None]
    data["frames"] = {names[i]: cells[i] for i in kept}
    meta["image"] = "sheet.png"
    if "frameTags" in meta:
        tags = []
        for tag in meta["frameTags"]:
            inside = [n for n, i in enumerate(kept) if tag["from"] <= i <= tag["to"]]
            if inside:
                tags.append(dict(tag, **{"from": inside[0], "to": inside[-1]}))
        meta["frameTags"] = tags
    data_path.write_text(json.dumps(data, indent=2))
    return None


def _run_aseprite(spec, out_dir, scale, spec_path, env):
    executable = find_aseprite(env)
    if executable is None:
        return _native(spec, out_dir, scale, spec_path, NOTICES["aseprite-missing"])
    prepared = palette_mod.prepare_spec(spec, spec_path)
    plan = aseprite_backend.export_plan(prepared)
    if plan["noncontiguous"]:
        return _native(
            spec, out_dir, scale, spec_path,
            f"Aseprite tags need contiguous frames ({', '.join(plan['noncontiguous'])} are split in the "
            "sheet order); rendered with the native backend")
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        lua_path = work / "build.lua"
        ase_path = work / "source.aseprite"
        sheet_path = work / "sheet.png"
        data_path = work / "sheet.json"
        lua_path.write_text(aseprite_backend.build_lua(prepared))
        spec_file = work / "spec.json"
        spec_file.write_text(json.dumps(prepared))
        commands = [
            aseprite_backend.script_argv(executable, lua_path, ase_path, spec_file),
            aseprite_backend.export_argv(executable, ase_path, sheet_path, data_path, plan["columns"]),
        ]
        for argv in commands:
            try:
                proc = subprocess.run(argv, capture_output=True, text=True, timeout=120, env=env, check=False)
            except (OSError, subprocess.TimeoutExpired) as exc:
                return _native(spec, out_dir, scale, spec_path, f"Aseprite failed ({exc}); rendered with the native backend")
            if proc.returncode != 0:
                detail = (proc.stderr or proc.stdout or "export failed").strip().splitlines()
                tail = detail[-1] if detail else "export failed"
                return _native(
                    spec, out_dir, scale, spec_path,
                    f"Aseprite failed ({tail}); rendered with the native backend")
        if not sheet_path.is_file() or not data_path.is_file():
            return _native(spec, out_dir, scale, spec_path, "Aseprite produced no sheet; rendered with the native backend")
        try:
            _check_sheet(sheet_path, prepared["palette"])
        except (RuntimeError, ValueError, OSError) as exc:
            return _native(spec, out_dir, scale, spec_path, f"Aseprite sheet rejected ({exc}); rendered with the native backend")
        problem = _normalize_sheet_json(data_path, plan)
        if problem:
            return _native(
                spec, out_dir, scale, spec_path,
                f"Aseprite sheet rejected ({problem}); rendered with the native backend")
        gif_dir = work / "gif"
        # The native render into out_dir drops GIFs of removed animations using the previous
        # sheet.json; do the same here, since this path only copies the new GIFs.
        previous = out_dir / "sheet.json"
        if previous.is_file():
            try:
                old_tags = json.loads(previous.read_text()).get("meta", {}).get("frameTags", [])
            except (ValueError, OSError):
                old_tags = []
            live = set(prepared.get("animations") or {"all": None})
            for tag in old_tags:
                name = tag.get("name", "") if isinstance(tag, dict) else ""
                if name not in live and re.fullmatch(r"[\w-]+", name):
                    (out_dir / f"{name}.gif").unlink(missing_ok=True)
        render.render(prepared, gif_dir, scale, spec_path)
        for name in ("sheet.png", "sheet.json"):
            shutil.copyfile(work / name, out_dir / name)
        shutil.copyfile(ase_path, out_dir / "source.aseprite")
        _upscale_sheet(sheet_path, out_dir / "preview.png", scale)
        written = ["sheet.png", "sheet.json", "preview.png", "source.aseprite"]
        for gif in sorted(gif_dir.glob("*.gif")):
            shutil.copyfile(gif, out_dir / gif.name)
            written.append(gif.name)
        print(f"Aseprite {executable} wrote source.aseprite and an Aseprite sheet.json")
        return written


def _generate_frames(spec, rows_for_prompt, spec_path):
    block = spec.get("generate")
    if not isinstance(block, dict) or not block.get("prompt"):
        return None
    width = int(block.get("width") or 32)
    height = int(block.get("height") or 32)
    jobs = block.get("frames") or [{"name": "image", "prompt": block["prompt"]}]
    print(f"paid calls: {len(jobs)} (one per generated frame)")
    prepared = palette_mod.prepare_spec(spec, spec_path)
    palette = prepared["palette"]
    frames = {}
    order = []
    for job in jobs:
        name = job.get("name") or "image"
        prompt = job.get("prompt") or block["prompt"]
        rows = rows_for_prompt(prompt, width, height)
        frames[name] = image_pipeline.frame_from_rgba(rows, palette, width, height, dither=False)
        order.append(name)
    built = dict(prepared)
    built["frames"] = frames
    # Keep a declared engine layout when it names exactly the generated frames.
    declared = prepared.get("sheet") or {}
    declared_order = declared.get("order") or []
    same = {n for n in declared_order if n} == set(order)
    built["sheet"] = {
        "columns": declared.get("columns") or len(order),
        "order": declared_order if same else order,
    }
    names = set(frames)
    animations = built.get("animations") or {}
    covers = animations and all(
        frame in names for anim in animations.values() for frame in anim.get("frames", []))
    if not covers:
        built["animations"] = {"all": {"frames": order, "fps": 8}}
    return built


def safe_base(url):
    """The API token goes to this base, so it must be https, or plain http only to loopback (tests)."""
    parsed = urllib.parse.urlparse(url)
    return parsed.scheme == "https" or (parsed.scheme == "http" and parsed.hostname in ("127.0.0.1", "localhost", "::1"))


def _run_pixellab(spec, out_dir, scale, spec_path, env, confirm):
    token = env.get("PIXELLAB_API_TOKEN")
    if not token:
        return _native(spec, out_dir, scale, spec_path, NOTICES["pixellab-missing"])
    if not isinstance(spec.get("generate"), dict) or not spec["generate"].get("prompt"):
        return _native(spec, out_dir, scale, spec_path, "PixelLab needs spec.generate.prompt; rendered with the native backend")
    if not confirm:
        return _native(spec, out_dir, scale, spec_path, NOTICES["pixellab-confirm"])
    base = env.get("PIXELLAB_API_BASE", hosted_backends.PIXELLAB_BASE)
    if not safe_base(base):
        return _native(spec, out_dir, scale, spec_path, "PIXELLAB_API_BASE must be https (or loopback); rendered with the native backend")

    def fetch(prompt, width, height):
        rows, usage = hosted_backends.pixellab_image(token, prompt, width, height, base_url=base)
        usd = usage.get("usd") if isinstance(usage, dict) else None
        if usd is not None:
            print(f"PixelLab usage.usd={usd}")
        return rows

    try:
        built = _generate_frames(spec, fetch, spec_path)
    except hosted_backends.HostedError as exc:
        return _native(spec, out_dir, scale, spec_path, f"PixelLab failed ({exc}); rendered with the native backend")
    return _native(built, out_dir, scale, None, None)


def _run_retro(spec, out_dir, scale, spec_path, env, confirm):
    token = env.get("RD_API_KEY")
    if not token:
        return _native(spec, out_dir, scale, spec_path, NOTICES["retro-missing"])
    if not isinstance(spec.get("generate"), dict) or not spec["generate"].get("prompt"):
        return _native(spec, out_dir, scale, spec_path, "Retro Diffusion needs spec.generate.prompt; rendered with the native backend")
    if not confirm:
        return _native(spec, out_dir, scale, spec_path, NOTICES["retro-confirm"])
    base = env.get("RD_API_BASE", hosted_backends.RETRO_BASE)
    if not safe_base(base):
        return _native(spec, out_dir, scale, spec_path, "RD_API_BASE must be https (or loopback); rendered with the native backend")

    def fetch(prompt, width, height):
        rows, result = hosted_backends.retrodiffusion_image(token, prompt, width, height, base_url=base)
        cost = result.get("balance_cost") if isinstance(result, dict) else None
        if cost is not None:
            print(f"Retro Diffusion balance_cost={cost}")
        return rows

    try:
        built = _generate_frames(spec, fetch, spec_path)
    except hosted_backends.HostedError as exc:
        return _native(spec, out_dir, scale, spec_path, f"Retro Diffusion failed ({exc}); rendered with the native backend")
    return _native(built, out_dir, scale, None, None)


def ingest_png(image_path, palette_value, out_dir, width, height, scale, base_dir):
    """Snap one generated PNG into the artifact contract. Used for MCP images."""
    palette = palette_mod.resolve_palette(palette_value, base_dir)
    _w, _h, rows = palette_mod.read_png(image_path)
    frame = image_pipeline.frame_from_rgba(rows, palette, width, height, dither=False)
    spec = {
        "palette": palette,
        "frames": {"image": frame},
        "animations": {"all": {"frames": ["image"], "fps": 8}},
    }
    return render.render(spec, out_dir, scale, None)


def run(spec, out_dir, backend, scale, spec_path, env, confirm):
    out_dir = pathlib.Path(out_dir)
    name = backend_name(backend, env)
    if name == "native":
        return _native(spec, out_dir, scale, spec_path, None)
    if name == "aseprite":
        # Aseprite never needs the hosted API tokens; keep them out of its process.
        local_env = {k: v for k, v in env.items() if k not in ("PIXELLAB_API_TOKEN", "RD_API_KEY")}
        return _run_aseprite(spec, out_dir, scale, spec_path, local_env)
    if name == "pixellab":
        return _run_pixellab(spec, out_dir, scale, spec_path, env, confirm)
    if name == "retrodiffusion":
        return _run_retro(spec, out_dir, scale, spec_path, env, confirm)
    return _native(spec, out_dir, scale, spec_path, f"Unknown backend {name}; rendered with the native backend")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("spec", nargs="?", type=pathlib.Path)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--scale", type=int, default=8)
    parser.add_argument("--backend", choices=["native", "aseprite", "pixellab", "retrodiffusion"])
    parser.add_argument("--confirm", action="store_true", help="allow paid PixelLab or Retro Diffusion calls, one per generated frame")
    parser.add_argument("--ingest", type=pathlib.Path, help="snap this PNG instead of reading a spec")
    parser.add_argument("--palette", help="preset, palette file, or inline JSON (with --ingest)")
    parser.add_argument("--width", type=int, default=32)
    parser.add_argument("--height", type=int, default=32)
    args = parser.parse_args(argv)
    env = os.environ.copy()
    try:
        if args.ingest:
            if not args.palette:
                raise RuntimeError("--ingest requires --palette")
            base = pathlib.Path.cwd()
            written = ingest_png(args.ingest, args.palette, args.out, args.width, args.height, args.scale, base)
        else:
            if args.spec is None:
                raise RuntimeError("a spec path is required (or pass --ingest)")
            spec = json.loads(args.spec.read_text())
            written = run(spec, args.out, args.backend, args.scale, args.spec, env, confirmed(args.confirm, env))
    except (RuntimeError, ValueError, KeyError, OSError, json.JSONDecodeError) as exc:
        print(f"backends.py: {exc}", file=sys.stderr)
        return 2
    print("\n".join(str(args.out / name) for name in written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
