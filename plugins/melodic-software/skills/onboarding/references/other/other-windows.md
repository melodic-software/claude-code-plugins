# Other

## Bun

[https://bun.com/docs/installation#windows](https://bun.com/docs/installation#windows)

```powershell
powershell -c "irm bun.sh/install.ps1|iex"
```

## JQ

[https://jqlang.org/](https://jqlang.org/)

```powershell
winget install --id jqlang.jq -e --source winget
```

## .NET

- [https://learn.microsoft.com/en-us/dotnet/core/install/windows?WT.mc_id=dotnet-35129-website#install-with-windows-package-manager-winget](https://learn.microsoft.com/en-us/dotnet/core/install/windows?WT.mc_id=dotnet-35129-website#install-with-windows-package-manager-winget)

- [https://learn.microsoft.com/en-us/dotnet/core/install/windows?WT.mc_id=dotnet-35129-website#install-with-windows-package-manager-winget](https://learn.microsoft.com/en-us/dotnet/core/install/windows?WT.mc_id=dotnet-35129-website#install-with-windows-package-manager-winget)

### SDK

```powershell
winget search Microsoft.DotNet.SDK
winget install --id Microsoft.DotNet.SDK.10 -e --source winget
```

### Runtime

```powershell
winget search Microsoft.DotNet.Runtime
winget search Microsoft.DotNet.HostingBundle
winget search Microsoft.DotNet.AspNetCore
winget search Microsoft.DotNet.DesktopRuntime
winget install --id Microsoft.DotNet.Runtime.10 -e --source winget
```
