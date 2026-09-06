#!/usr/bin/env python3
"""Resolve the plugin's configuration through the config cascade (design T4).

Layers, in resolution order, each optional, merged by per-key override (a
later layer replaces an earlier layer's value key by key; a key absent from a
later layer keeps the earlier value; a list is a closed value and is replaced
whole):

  0. bundled defaults           scripts/config-defaults.json
  1. user-global                ~/.claude/code-metrics.yaml
  2. team                       <repo>/.claude/code-metrics.yaml
  3. local overlay              <repo>/.claude/code-metrics.local.yaml

The consumer's ecosystem files (`.claude/ecosystems/<lane>.yaml`, the
marketplace-wide ecosystem-commands convention) resolve through the same three
layers for their `globs` and `enabled` keys.

Usage:
  resolve-config.py [options] [<user.yaml> [<team.yaml> [<local.yaml>]]]

Positional files stand in for the three layers in that order (the suites use
them); otherwise the layers are discovered from --home (default $HOME) and
--repo-root (default the git top level, else the working directory).

Options:
  --defaults <file>        bundled defaults (default: config-defaults.json beside this script)
  --ladder <file>          validate `lanes.<lane>.collectors.<measure>` names against the ladder
  --format json            the resolved document (default): every key, plus `_layers`
                           (dotted key -> the layer that supplied it), `_provenance`
                           (dotted key -> {value, layer}), `_files` (the layer files read),
                           `_ecosystems` (lane -> {globs, enabled, layer}), `_warnings`
  --format dispatch-args   one dispatcher option per line: `--lane-globs <lane>=<g1,g2>`
                           for a lane whose ecosystem file declares globs, `--disable-lane
                           <lane>` for a lane resolved to enabled: false
  --format ladder-overrides
                           `lane<TAB>measure<TAB>tool` rows from `lanes.<lane>.collectors`
  --format excludes        one `scope.exclude` glob per line
  --from-json <file>       skip resolution and derive the format from a document this
                           script printed earlier (the dispatcher's `--config` path)

Exit 0 on success; 2 for a usage error or a layer file outside the YAML subset
(the message names the file, the construct, and the line).
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from typing import Any

MIN_PYTHON = (3, 9)


class ConfigTypeError(ValueError):
    """A resolved value has a type the plugin cannot compare (a quoted number)."""


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LAYER_NAMES = ("user-global", "team", "local")
SURFACE = "code-metrics"

_spec = importlib.util.spec_from_file_location(
    "yaml_subset", os.path.join(SCRIPT_DIR, "yaml_subset.py")
)
assert _spec is not None and _spec.loader is not None
yaml_subset = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(yaml_subset)


def _load_layer(path: str) -> dict[str, Any]:
    value = yaml_subset.load(path)
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise yaml_subset.YamlSubsetError(1, "the top level must be a mapping")
    return value


def merge(
    base: Any, overlay: Any, layer: str, prefix: str, layers: dict[str, str]
) -> Any:
    if isinstance(base, dict) and isinstance(overlay, dict):
        result = dict(base)
        for key, value in overlay.items():
            dotted = f"{prefix}.{key}" if prefix else key
            result[key] = merge(base.get(key), value, layer, dotted, layers)
        return result
    layers[prefix] = layer
    return overlay


def _walk(node: Any, prefix: str, out: dict[str, Any]) -> None:
    if isinstance(node, dict):
        for key, value in node.items():
            _walk(value, f"{prefix}.{key}" if prefix else key, out)
    else:
        out[prefix] = node


def repo_root() -> str:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip().replace("\\", "/")
    except OSError:
        pass
    return os.getcwd().replace("\\", "/")


def layer_paths(home: str, root: str, stem: str) -> list[tuple[str, str]]:
    return [
        ("user-global", os.path.join(home, ".claude", f"{stem}.yaml")),
        ("team", os.path.join(root, ".claude", f"{stem}.yaml")),
        ("local", os.path.join(root, ".claude", f"{stem}.local.yaml")),
    ]


def resolve(
    defaults_path: str,
    layer_files: list[tuple[str, str]],
    ecosystem_files: dict[str, list[tuple[str, str]]],
    ladder_path: str | None,
) -> dict[str, Any]:
    with open(defaults_path, encoding="utf-8") as handle:
        config: Any = json.load(handle)
    layers: dict[str, str] = {}
    files_read: list[str] = []
    warnings: list[str] = []
    for layer, path in layer_files:
        if not os.path.isfile(path):
            continue
        overlay = _load_layer(path)
        for key in overlay:
            if key.startswith("_") or key == "thresholds":
                warnings.append(f"{path}: key {key!r} is reserved and ignored")
        overlay = {
            k: v
            for k, v in overlay.items()
            if not (k.startswith("_") or k == "thresholds")
        }
        config = merge(config, overlay, layer, "", layers)
        files_read.append(path.replace("\\", "/"))
    if ladder_path:
        known: set[tuple[str, str, str]] = set()
        with open(ladder_path, encoding="utf-8") as handle:
            for raw in handle:
                if raw.startswith("#") or not raw.strip():
                    continue
                parts = raw.rstrip("\n").split("\t")
                if len(parts) >= 3:
                    known.add((parts[0], parts[1], parts[2]))
        for lane, lane_cfg in (config.get("lanes") or {}).items():
            collectors = (lane_cfg or {}).get("collectors") or {}
            for measure, tools in list(collectors.items()):
                if not isinstance(tools, list):
                    warnings.append(
                        f"lanes.{lane}.collectors.{measure}: expected a list; ignored"
                    )
                    del collectors[measure]
                    continue
                kept = []
                for tool in tools:
                    if (lane, measure, str(tool)) in known or (
                        lane,
                        "*",
                        str(tool),
                    ) in known:
                        kept.append(str(tool))
                    else:
                        warnings.append(
                            f"lanes.{lane}.collectors.{measure}: {tool!r} is not in the ladder for {lane}/{measure}; dropped"
                        )
                collectors[measure] = kept
    ecosystems: dict[str, Any] = {}
    for lane, files in ecosystem_files.items():
        eco: dict[str, Any] = {}
        eco_layers: dict[str, str] = {}
        for layer, path in files:
            if not os.path.isfile(path):
                continue
            eco = merge(eco, _load_layer(path), layer, "", eco_layers)
            files_read.append(path.replace("\\", "/"))
        if not eco:
            continue
        globs = eco.get("globs")
        enabled = eco.get("enabled", True)
        ecosystems[lane] = {
            "globs": [str(g) for g in globs] if isinstance(globs, list) else None,
            "enabled": bool(enabled) if enabled is not None else True,
            "layer": eco_layers.get("globs") or eco_layers.get("enabled") or "team",
        }
    flat: dict[str, Any] = {}
    _walk(
        {
            k: v
            for k, v in config.items()
            if not k.startswith("_") and k != "thresholds"
        },
        "",
        flat,
    )
    provenance = {
        key: {"value": value, "layer": layers.get(key, "bundled default")}
        for key, value in flat.items()
    }
    # Every threshold reference is compared against a measured number, so a
    # quoted number in a layer (`reference: "20"`, a string scalar) is refused
    # here by key and layer rather than reaching the assembler as a TypeError.
    for entry in config.get("thresholds") or []:
        key = entry.get("config_key")
        if not key:
            continue
        value = flat.get(key)
        if value is None or (
            isinstance(value, (int, float)) and not isinstance(value, bool)
        ):
            continue
        raise ConfigTypeError(
            f"{key} (layer {layers.get(key, 'bundled default')}) must be a number "
            f"or null, got {type(value).__name__} {value!r}"
        )
    config["_layers"] = layers
    config["_provenance"] = provenance
    config["_files"] = files_read
    config["_ecosystems"] = ecosystems
    config["_warnings"] = warnings
    return config


def _field(config: dict[str, Any], key: str, value: Any, tabs: bool = False) -> str:
    """One field of a line-oriented output format.

    `dispatch-args`, `ladder-overrides` and `excludes` are read a line at a
    time (the dispatcher uses `mapfile`, then dispatches on the first word),
    and the ladder rows are tab separated. The YAML subset's double-quoted
    scalars support a real `\\n` escape, so without this a layer could write
    `base: "auto\\n--disable-lane python"` and have one scalar key arrive as
    two directives, the second of them silently narrowing what gets measured.
    A field that would break out of its line, or out of its column, is refused
    by key instead of obeyed.
    """
    text = str(value)
    bad = [
        name
        for ch, name in (("\n", "newline"), ("\r", "carriage return"))
        if ch in text
    ]
    if tabs and "\t" in text:
        bad.append("tab")
    if not bad:
        return text
    layer = (config.get("_layers") or {}).get(key)
    where = f" (layer {layer})" if layer else ""
    raise ConfigTypeError(
        f"{key}{where} must not contain a {' or '.join(bad)}: the resolver's "
        f"output is line oriented, so {text!r} would reach the dispatcher as "
        "more than one directive"
    )


def dispatch_args(config: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    # A configured `all` default and a configured base travel to the dispatcher,
    # which lets an explicit command-line --all, path, or --base win over them.
    # `change` is the bundled default and the dispatcher's own, so it emits
    # nothing: a no-op line would only be noise on the dispatcher's command line.
    scope = config.get("scope") or {}
    default = scope.get("default")
    if default == "all":
        lines.append(f"--scope-default {default}")
    base = scope.get("base")
    if isinstance(base, str) and base.strip() and base != "auto":
        lines.append(f"--scope-base {_field(config, 'scope.base', base.strip())}")
    lanes = config.get("lanes") or {}
    ecosystems = config.get("_ecosystems") or {}
    for lane in sorted(set(lanes) | set(ecosystems)):
        eco = ecosystems.get(lane) or {}
        plugin_enabled = (lanes.get(lane) or {}).get("enabled", True)
        enabled = eco.get("enabled", True) if eco else True
        name = _field(config, "lanes.<lane>", lane)
        if plugin_enabled is False or enabled is False:
            lines.append(f"--disable-lane {name}")
            continue
        if eco.get("globs"):
            globs = ",".join(
                _field(config, f"ecosystems.{name}.globs", glob)
                for glob in eco["globs"]
            )
            lines.append(f"--lane-globs {name}={globs}")
    return lines


def ladder_overrides(config: dict[str, Any]) -> list[str]:
    lines: list[str] = []
    for lane, lane_cfg in sorted((config.get("lanes") or {}).items()):
        name = _field(config, "lanes.<lane>", lane, tabs=True)
        for measure, tools in sorted(
            ((lane_cfg or {}).get("collectors") or {}).items()
        ):
            key = f"lanes.{name}.collectors.<measure>"
            column = _field(config, key, measure, tabs=True)
            if not tools:
                # An explicitly empty list is a closed value: no collector runs
                # for this lane and measure, so the dispatcher gets the
                # reserved `none` rung rather than falling back to the ladder.
                lines.append(f"{name}\t{column}\tnone")
                continue
            for tool in tools:
                lines.append(
                    f"{name}\t{column}\t{_field(config, key, tool, tabs=True)}"
                )
    return lines


def excludes(config: dict[str, Any]) -> list[str]:
    patterns = (config.get("scope") or {}).get("exclude")
    if patterns is None:
        patterns = []
    # `scope.exclude` is a closed list. A scalar (`exclude: "vendor/**"`, the
    # shape setup-apply.py writes for a one-glob value) iterates as characters,
    # so the dispatcher would receive `v`, `e`, `n`, ... as globs: the audit
    # exits 0 having measured the directory it was told to drop, and having
    # possibly dropped unrelated single-character paths.
    if not isinstance(patterns, list):
        layer = (config.get("_layers") or {}).get("scope.exclude", "bundled default")
        raise ConfigTypeError(
            f"scope.exclude (layer {layer}) must be a list of globs or null, "
            f"got {type(patterns).__name__} {patterns!r}"
        )
    return [_field(config, "scope.exclude", p) for p in patterns if str(p).strip()]


def emit_or_fail(config: dict[str, Any], fmt: str) -> int:
    """Write one format, turning a refused field into exit 2 with its message.

    The `--from-json` path never runs `resolve()`, so a field guard that only
    fired there would be skipped by exactly the caller the dispatcher uses.
    Both entry points come through here instead.
    """
    try:
        emit(config, fmt)
    except ConfigTypeError as exc:
        print(f"resolve-config.py: {exc}", file=sys.stderr)
        return 2
    return 0


def emit(config: dict[str, Any], fmt: str) -> None:
    if fmt == "dispatch-args":
        sys.stdout.write("".join(line + "\n" for line in dispatch_args(config)))
    elif fmt == "ladder-overrides":
        sys.stdout.write("".join(line + "\n" for line in ladder_overrides(config)))
    elif fmt == "excludes":
        sys.stdout.write("".join(line + "\n" for line in excludes(config)))
    else:
        print(json.dumps(config, indent=2))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="resolve-config.py", add_help=True)
    parser.add_argument("layers", nargs="*")
    parser.add_argument(
        "--defaults", default=os.path.join(SCRIPT_DIR, "config-defaults.json")
    )
    parser.add_argument("--ladder")
    parser.add_argument(
        "--home", default=os.environ.get("HOME") or os.path.expanduser("~")
    )
    parser.add_argument("--repo-root")
    parser.add_argument("--from-json")
    parser.add_argument(
        "--format",
        choices=("json", "dispatch-args", "ladder-overrides", "excludes"),
        default="json",
    )
    args = parser.parse_args(argv)
    if args.from_json:
        try:
            with open(args.from_json, encoding="utf-8") as handle:
                config = json.load(handle)
        except (OSError, json.JSONDecodeError) as exc:
            print(f"resolve-config.py: {args.from_json}: {exc}", file=sys.stderr)
            return 2
        return emit_or_fail(config, args.format)
    if len(args.layers) > 3:
        print(
            "resolve-config.py: at most three positional layer files (user, team, local)",
            file=sys.stderr,
        )
        return 2
    root = (args.repo_root or repo_root()).replace("\\", "/")
    if args.layers:
        layer_files = [(LAYER_NAMES[i], path) for i, path in enumerate(args.layers)]
        for _, path in layer_files:
            if not os.path.isfile(path):
                print(
                    f"resolve-config.py: layer file does not exist: {path}",
                    file=sys.stderr,
                )
                return 2
        ecosystem_files: dict[str, list[tuple[str, str]]] = {}
    else:
        layer_files = layer_paths(args.home, root, SURFACE)
        with open(args.defaults, encoding="utf-8") as handle:
            lane_names = list((json.load(handle).get("lanes") or {}).keys())
        ecosystem_files = {
            lane: layer_paths(args.home, root, os.path.join("ecosystems", lane))
            for lane in lane_names
        }
    try:
        config = resolve(args.defaults, layer_files, ecosystem_files, args.ladder)
    except yaml_subset.YamlSubsetError as exc:
        print(
            f"resolve-config.py: a config layer is outside the YAML subset: {exc}",
            file=sys.stderr,
        )
        return 2
    except ConfigTypeError as exc:
        print(f"resolve-config.py: {exc}", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"resolve-config.py: {exc}", file=sys.stderr)
        return 2
    for warning in config.get("_warnings", []):
        print(f"resolve-config.py: warning: {warning}", file=sys.stderr)
    return emit_or_fail(config, args.format)


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "resolve-config.py needs Python %d.%d or later" % MIN_PYTHON,
            file=sys.stderr,
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
