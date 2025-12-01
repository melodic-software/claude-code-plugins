# Package Managers

## Winget

Built into Windows 10/11. No installation needed.

- [https://learn.microsoft.com/en-us/windows/package-manager/winget/](https://learn.microsoft.com/en-us/windows/package-manager/winget/)
- [https://github.com/microsoft/winget-cli](https://github.com/microsoft/winget-cli)

### Common Commands

```powershell
winget --help
winget search <appname>
winget install <appname>
```

---

## Chocolatey

[https://docs.chocolatey.org/en-us/choco/setup/#install-using-winget](https://docs.chocolatey.org/en-us/choco/setup/#install-using-winget)

```powershell
winget install --id Chocolatey.Chocolatey -e --source winget
```
