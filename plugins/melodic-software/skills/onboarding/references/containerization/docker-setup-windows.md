# Docker Setup

## Prerequisites

Docker Desktop on Windows requires WSL2 (Windows Subsystem for Linux 2) as its backend. If you haven't installed WSL yet, complete the WSL setup first:

- [WSL Setup Windows](../wsl/wsl-setup-windows.md)

## Installation

- [https://www.docker.com/products/docker-desktop/](https://www.docker.com/products/docker-desktop/)
- [https://docs.docker.com/desktop/setup/install/windows-install/](https://docs.docker.com/desktop/setup/install/windows-install/)

```powershell
winget install --id Docker.DockerDesktop -e --source winget
```

Restart your computer after installation.

### CLI

- [https://www.docker.com/products/cli/](https://www.docker.com/products/cli/)
- [https://github.com/docker/cli](https://github.com/docker/cli)

## Podman Installation

This is an alternative to Docker Desktop.

- [https://podman.io/docs/installation](https://podman.io/docs/installation)
- [https://github.com/containers/podman/blob/main/docs/tutorials/podman-for-windows.md](https://github.com/containers/podman/blob/main/docs/tutorials/podman-for-windows.md)
- [https://podman-desktop.io/docs/installation/windows-install](https://podman-desktop.io/docs/installation/windows-install)

```powershell
winget install --id RedHat.Podman-Desktop -e --source winget
```
