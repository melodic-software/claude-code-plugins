# Windows Sandbox

- [Windows Sandbox Overview](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/)
- [Windows Sandbox Configuration](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file)

## Installation

Open PowerShell as **Administrator** and run the following command:

```powershell
Enable-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM" -All -Online
```

## Configuration

Windows Sandbox can be configured using `.wsb` configuration files. These XML files control sandbox behavior such as virtual GPU, networking, and mapped folders.

To use a configuration file, double-click it to start Windows Sandbox according to its settings. You can also invoke it via the command line as shown here:

```batch
C:\Temp> DefaultConfig.wsb
```

```xml
<Configuration>
  <VGpu>Enable</VGpu>
  <Networking>Enable</Networking>
  <MemoryInMB>4096</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>C:\Dev</HostFolder>
      <SandboxFolder>C:\Users\WDAGUtilityAccount\Desktop\Dev</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass</Command>
  </LogonCommand>
</Configuration>
```
