#Requires -Version 7.4

<#
.SYNOPSIS
Open a file without following a reparse point, and read its identity from the
open handle.

.DESCRIPTION
Open-NoFollowFile calls CreateFileW with OPEN_EXISTING (never creates),
FILE_FLAG_OPEN_REPARSE_POINT (a link at the path opens as itself) and
SECURITY_SQOS_PRESENT with anonymous impersonation (a named pipe server at
the path cannot impersonate the caller), without FILE_FLAG_BACKUP_SEMANTICS
(a directory fails to open). A handle whose GetFileType is not
FILE_TYPE_DISK is closed and refused.

Get-FileIdentity reads GetFileInformationByHandleEx: FileIdInfo gives the
64-bit volume serial and 128-bit file ID, formatted as the pattern
Test-FileIdFormat holds; FileAttributeTagInfo gives the reparse-point bit.
#>

if (-not ('MachineHealth.NoFollowFileNative' -as [type])) {
    Add-Type -Namespace 'MachineHealth' -Name 'NoFollowFileNative' -UsingNamespace 'Microsoft.Win32.SafeHandles' -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct FileIdInfo {
    public ulong VolumeSerialNumber;
    public ulong FileIdLow;
    public ulong FileIdHigh;
}

[StructLayout(LayoutKind.Sequential)]
public struct FileAttributeTagInfo {
    public uint FileAttributes;
    public uint ReparseTag;
}

[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern SafeFileHandle CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
    IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern uint GetFileType(SafeFileHandle hFile);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetFileInformationByHandleEx(SafeFileHandle hFile, int fileInformationClass,
    out FileIdInfo lpFileInformation, uint dwBufferSize);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetFileInformationByHandleEx(SafeFileHandle hFile, int fileInformationClass,
    out FileAttributeTagInfo lpFileInformation, uint dwBufferSize);
'@
}

# FILE_FLAG_OPEN_REPARSE_POINT | SECURITY_SQOS_PRESENT; SECURITY_ANONYMOUS is 0.
$script:NoFollowOpenFlags = [uint32](0x00200000 -bor 0x00100000)

function Test-FileIdFormat {
    <#
    .SYNOPSIS
    True when -Value is a file ID as Get-FileIdentity formats it: 16 uppercase
    hex digits of volume serial, a hyphen, 32 of file ID.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $Value)

    return $Value -cmatch '^[0-9A-F]{16}-[0-9A-F]{32}\z'
}

function Open-NoFollowFile {
    [CmdletBinding()]
    [OutputType([Microsoft.Win32.SafeHandles.SafeFileHandle])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        # Attributes: identity reads only, every sharing mode allowed.
        # ReadWrite: the writer's handle; other handles may only read meanwhile.
        [ValidateSet('Attributes', 'ReadWrite')] [string] $Access = 'Attributes'
    )

    $fullPath = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path))
    # The extended-length form, so a path past MAX_PATH opens as it does through .NET.
    $nativePath = if ($fullPath.StartsWith('\\?\') -or $fullPath.StartsWith('\\.\')) {
        $fullPath
    } elseif ($fullPath.StartsWith('\\')) {
        '\\?\UNC\' + $fullPath.Substring(2)
    } else {
        '\\?\' + $fullPath
    }
    $openExisting = 3
    if ($Access -eq 'ReadWrite') {
        $desired = 0xC0000000u          # GENERIC_READ | GENERIC_WRITE
        $share = [uint32]1              # FILE_SHARE_READ
    } else {
        $desired = [uint32]0x80         # FILE_READ_ATTRIBUTES
        $share = [uint32]7              # FILE_SHARE_READ | WRITE | DELETE
    }

    $handle = [MachineHealth.NoFollowFileNative]::CreateFileW($nativePath, $desired, $share, [IntPtr]::Zero,
        $openExisting, $script:NoFollowOpenFlags, [IntPtr]::Zero)
    if ($handle.IsInvalid) {
        $code = [System.Runtime.InteropServices.Marshal]::GetLastPInvokeError()
        $handle.Dispose()
        throw [System.ComponentModel.Win32Exception]::new($code, "Cannot open '$fullPath' without following reparse points (Win32 error $code).")
    }
    $fileTypeDisk = 1
    if ([MachineHealth.NoFollowFileNative]::GetFileType($handle) -ne $fileTypeDisk) {
        $handle.Dispose()
        throw "Cannot open '$fullPath': it is not a disk file."
    }
    return $handle
}

function Get-FileIdentity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [Microsoft.Win32.SafeHandles.SafeFileHandle] $Handle
    )

    $fileIdInfoClass = 18
    $attributeTagInfoClass = 9
    $id = [MachineHealth.NoFollowFileNative+FileIdInfo]::new()
    $tag = [MachineHealth.NoFollowFileNative+FileAttributeTagInfo]::new()
    if (-not [MachineHealth.NoFollowFileNative]::GetFileInformationByHandleEx($Handle, $fileIdInfoClass, [ref]$id, 24) -or
        -not [MachineHealth.NoFollowFileNative]::GetFileInformationByHandleEx($Handle, $attributeTagInfoClass, [ref]$tag, 8)) {
        $code = [System.Runtime.InteropServices.Marshal]::GetLastPInvokeError()
        throw [System.ComponentModel.Win32Exception]::new($code, "Cannot read the file information (Win32 error $code).")
    }
    return [pscustomobject]@{
        FileId         = '{0:X16}-{1:X16}{2:X16}' -f $id.VolumeSerialNumber, $id.FileIdHigh, $id.FileIdLow
        IsReparsePoint = [bool]($tag.FileAttributes -band 0x400)
    }
}
