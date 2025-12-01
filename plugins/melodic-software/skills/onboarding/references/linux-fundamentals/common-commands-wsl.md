# Common Commands WSL

WSL runs Linux (Ubuntu), so the command reference is identical to native Linux.

**Follow the Linux guide:** [Common Commands Linux](common-commands-linux.md)

---

## WSL-Specific Notes

- Your WSL home directory is `/home/username`, not `/mnt/c/Users/username`
- Access Windows file system via `/mnt/c/` (C: drive), `/mnt/d/` (D: drive), etc.
- Commands run inside WSL operate on the Linux file system unless you explicitly navigate to `/mnt/`
