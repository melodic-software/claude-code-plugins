---
bump: minor
---

### Added

- `scan --root-children` on a mount point that is not a volume root, such as a tmpfs `/tmp` on WSL, now lists the mount's immediate children read-only. Loose files are admitted, nested mounts are withheld, and nothing is walked. The output sets `mount_point_target: true`, and under `--quiet` the full listing goes to the `--output` file. A `--root-child` selection on a mount point is refused: scan an admitted child directory as its own target. No snapshot of a mount point is written, so removal stays closed. Without `--root-children`, the refusal of a mount-point target now carries a `hint` that names the flag ([#9572](https://github.com/melodic-software/claude-code-plugins/issues/9572)).
