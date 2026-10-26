#Requires -Version 7.4

<#
.SYNOPSIS
The elevated pass's bootstrap: pin the environment, check the pass's files against
the launcher's manifest, copy them into a folder only Administrators can write, and
run the orchestrator from that copy.

.DESCRIPTION
New-ElevatedLaunch writes the text of every function in this file into the launcher
script, so the shown hash covers them; the elevated process never loads this file.
Each function therefore uses only .NET and the language itself, and none calls into
another lib file.

Invoke-ElevatedBootstrap returns the exit code: 4 when a manifest entry is missing,
unreadable or does not hash to its value (nothing is copied and nothing runs), else
the orchestrator's. Mechanism: reference/windows/elevation-matrix.md, "How to run
elevated".
#>

function Test-ElevatedPassPath {
    <#
    .SYNOPSIS
    Whether a manifest key is a path below the skill root: backslash-separated, no
    rooted path, no empty segment, no segment starting with a dot.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $RelativePath)

    return $RelativePath -cmatch '^(?:[A-Za-z0-9][A-Za-z0-9._-]*\\)*[A-Za-z0-9][A-Za-z0-9._-]*\z'
}

function Get-SystemEnvironmentVariable {
    <#
    .SYNOPSIS
    The system variables only, from CreateEnvironmentBlock with no user token.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    if (-not ('MachineHealth.SystemEnvironmentNative' -as [type])) {
        Add-Type -Namespace 'MachineHealth' -Name 'SystemEnvironmentNative' -MemberDefinition @'
[DllImport("userenv.dll", SetLastError = true)]
public static extern bool CreateEnvironmentBlock(out IntPtr environment, IntPtr token, bool inherit);
[DllImport("userenv.dll", SetLastError = true)]
public static extern bool DestroyEnvironmentBlock(IntPtr environment);
'@
    }
    $block = [IntPtr]::Zero
    if (-not [MachineHealth.SystemEnvironmentNative]::CreateEnvironmentBlock([ref]$block, [IntPtr]::Zero, $false)) {
        throw [System.ComponentModel.Win32Exception]::new([System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    try {
        # Null-terminated "name=value" strings, ending with an empty one.
        $variables = @{}
        $offset = 0
        while ($true) {
            $entry = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([IntPtr]::Add($block, $offset))
            if ([string]::IsNullOrEmpty($entry)) { break }
            $offset += ($entry.Length + 1) * 2
            $separator = $entry.IndexOf('=')
            # A name starting with '=' is a drive's current directory, not a variable.
            if ($separator -gt 0) { $variables[$entry.Substring(0, $separator)] = $entry.Substring($separator + 1) }
        }
        return $variables
    } finally {
        [void][MachineHealth.SystemEnvironmentNative]::DestroyEnvironmentBlock($block)
    }
}

function Get-ElevatedPassEnvironment {
    <#
    .SYNOPSIS
    The process variables the elevated pass sets: Path and each name HKCU\Environment
    defines take their system value, or $null (removed) when the system defines none,
    and PSModulePath holds only machine-wide module folders.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [string[]] $UserVariableName,
        [Parameter(Mandatory = $true)] [hashtable] $SystemVariable,
        [Parameter(Mandatory = $true)] [string] $PSHomePath,
        [Parameter(Mandatory = $true)] [string] $ProgramFilesPath
    )

    # Path always, since a user value can reach it from outside HKCU\Environment too.
    $pinned = [ordered]@{ Path = $SystemVariable['Path'] }
    foreach ($name in $UserVariableName) {
        if ($name -ne 'PSModulePath') { $pinned[$name] = $SystemVariable[$name] }
    }
    # PowerShell 7's AllUsers and $PSHOME folders, then the system value's own folders; never a user folder.
    $folders = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $candidates = @([System.IO.Path]::Join($ProgramFilesPath, 'PowerShell\Modules'), [System.IO.Path]::Join($PSHomePath, 'Modules')) +
        @("$($SystemVariable['PSModulePath'])".Split(';', [StringSplitOptions]::RemoveEmptyEntries))
    foreach ($folder in $candidates) {
        if ($seen.Add($folder.TrimEnd('\'))) { $folders.Add($folder) }
    }
    $pinned['PSModulePath'] = $folders -join ';'
    return $pinned
}

function New-ElevatedStagingFolder {
    <#
    .SYNOPSIS
    Create a new, randomly named folder under ProgramData that only Administrators and
    SYSTEM can open, owned by Administrators, and return its path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Add-Type -AssemblyName 'System.IO.FileSystem.AccessControl'
    $parent = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    $path = [System.IO.Path]::Join($parent, "machine-health-elevated-$([guid]::NewGuid().ToString('N'))")
    if ([System.IO.Directory]::Exists($path)) { throw "Refused: '$path' already exists." }
    $admins = [System.Security.Principal.SecurityIdentifier]::new(
        [System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $system = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
    $security = [System.Security.AccessControl.DirectorySecurity]::new()
    $security.SetOwner($admins)
    $security.SetAccessRuleProtection($true, $false)
    foreach ($sid in $admins, $system) {
        $security.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid,
                [System.Security.AccessControl.FileSystemRights]::FullControl,
                [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
                [System.Security.AccessControl.PropagationFlags]::None, [System.Security.AccessControl.AccessControlType]::Allow))
    }
    # The folder is created with this security descriptor, so it is never open to the standard token.
    $folder = [System.IO.FileSystemAclExtensions]::CreateDirectory($security, $path)
    $owner = [System.IO.FileSystemAclExtensions]::GetAccessControl($folder).GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($owner -ne $admins -or $folder.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
        throw "Refused: '$path' is not a new folder owned by Administrators."
    }
    return $folder.FullName
}

function Invoke-ElevatedBootstrap {
    <#
    .SYNOPSIS
    Pin the environment, read each manifest file once from -SourceRoot, refuse on any
    hash mismatch, write those bytes into a new staging folder and run the
    orchestrator from it; the staging folder is removed afterwards.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)] [string] $SourceRoot,
        # Path under the skill root (backslash-separated) -> uppercase hex SHA-256.
        [Parameter(Mandatory = $true)] [System.Collections.IDictionary] $Manifest,
        [Parameter(Mandatory = $true)] [string] $OutputBase,
        [Parameter(Mandatory = $true)] [string] $StateBase,
        [Parameter(Mandatory = $true)] [string] $ResultPath,
        [Parameter(Mandatory = $true)] [string] $ResultFileId,
        # Test seam: returns a new folder in place of New-ElevatedStagingFolder. The launcher never passes it.
        [scriptblock] $NewStagingFolder = { New-ElevatedStagingFolder }
    )

    # Module folders first, through .NET alone, so the cmdlets below load from $PSHOME only.
    [Environment]::SetEnvironmentVariable('PSModulePath', [System.IO.Path]::Join($PSHOME, 'Modules'))
    $pinned = Get-ElevatedPassEnvironment -SystemVariable (Get-SystemEnvironmentVariable) -PSHomePath $PSHOME `
        -UserVariableName ([string[]]@([Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::User).Keys)) `
        -ProgramFilesPath ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
    foreach ($name in $pinned.Keys) { [Environment]::SetEnvironmentVariable($name, $pinned[$name]) }

    $orchestrator = 'scripts\windows\Invoke-MachineHealthCheck.ps1'
    if (-not $Manifest.Contains($orchestrator)) {
        [Console]::Error.WriteLine("[machine-health] elevated pass refused: the manifest lists no '$orchestrator'.")
        return 4
    }
    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($relative in @($Manifest.Keys)) {
        if (-not (Test-ElevatedPassPath $relative)) {
            [Console]::Error.WriteLine("[machine-health] elevated pass refused: '$relative' is not a path under the skill root.")
            return 4
        }
        try {
            $bytes = [System.IO.File]::ReadAllBytes([System.IO.Path]::Join($SourceRoot, $relative))
        } catch {
            [Console]::Error.WriteLine("[machine-health] elevated pass refused: '$relative' could not be read: $($_.Exception.Message)")
            return 4
        }
        if ([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)) -cne $Manifest[$relative]) {
            [Console]::Error.WriteLine("[machine-health] elevated pass refused: '$relative' changed after the launcher was prepared.")
            return 4
        }
        $files.Add([pscustomobject]@{ Relative = $relative; Bytes = $bytes })
    }

    $staging = [string](& $NewStagingFolder)
    try {
        # The verified bytes themselves are written, so a later change to the source reaches nothing.
        foreach ($file in $files) {
            $target = [System.IO.Path]::Join($staging, $file.Relative)
            [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target))
            [System.IO.File]::WriteAllBytes($target, $file.Bytes)
        }
        $null = & ([System.IO.Path]::Join($staging, $orchestrator)) -OutputBase $OutputBase -StateBase $StateBase `
            -RunMode on-demand -SkipBanner -ResultPath $ResultPath -ResultFileId $ResultFileId
        return [int]$LASTEXITCODE
    } finally {
        try {
            [System.IO.Directory]::Delete($staging, $true)
        } catch {
            [Console]::Error.WriteLine("[machine-health] elevated pass left '$staging': $($_.Exception.Message)")
        }
    }
}
