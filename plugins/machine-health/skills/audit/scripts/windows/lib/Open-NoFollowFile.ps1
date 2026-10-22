#Requires -Version 7.4

<#
.SYNOPSIS
Open a file without following a reparse point, and read its identity from the
open handle.

.DESCRIPTION
Open-NoFollowFile calls CreateFileW with OPEN_EXISTING and
FILE_FLAG_OPEN_REPARSE_POINT, so it never creates a file and a symbolic link
or junction at the path is opened as itself instead of its target. It omits
FILE_FLAG_BACKUP_SEMANTICS, so a directory, junctions included, fails to open.

Get-FileIdentity reads GetFileInformationByHandle: the file ID is the volume
serial number and the 64-bit file index, as 'XXXXXXXX-XXXXXXXXXXXXXXXX'
(uppercase hex), plus the reparse-point and directory attribute bits.
#>

if (-not ('MachineHealth.NoFollowFileNative' -as [type])) {
    Add-Type -Namespace 'MachineHealth' -Name 'NoFollowFileNative' -UsingNamespace 'Microsoft.Win32.SafeHandles' -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)]
public struct ByHandleFileInformation {
    public uint FileAttributes;
    public uint CreationTimeLow;
    public uint CreationTimeHigh;
    public uint LastAccessTimeLow;
    public uint LastAccessTimeHigh;
    public uint LastWriteTimeLow;
    public uint LastWriteTimeHigh;
    public uint VolumeSerialNumber;
    public uint FileSizeHigh;
    public uint FileSizeLow;
    public uint NumberOfLinks;
    public uint FileIndexHigh;
    public uint FileIndexLow;
}

[DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
public static extern SafeFileHandle CreateFileW(string lpFileName, uint dwDesiredAccess, uint dwShareMode,
    IntPtr lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, IntPtr hTemplateFile);

[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetFileInformationByHandle(SafeFileHandle hFile, out ByHandleFileInformation lpFileInformation);
'@
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
    $nativePath = if ($fullPath.StartsWith('\\?\')) {
        $fullPath
    } elseif ($fullPath.StartsWith('\\')) {
        '\\?\UNC\' + $fullPath.Substring(2)
    } else {
        '\\?\' + $fullPath
    }
    $openExisting = 3
    $openReparsePoint = 0x00200000
    if ($Access -eq 'ReadWrite') {
        $desired = 0xC0000000u          # GENERIC_READ | GENERIC_WRITE
        $share = [uint32]1              # FILE_SHARE_READ
    } else {
        $desired = [uint32]0x80         # FILE_READ_ATTRIBUTES
        $share = [uint32]7              # FILE_SHARE_READ | WRITE | DELETE
    }

    $handle = [MachineHealth.NoFollowFileNative]::CreateFileW($nativePath, $desired, $share, [IntPtr]::Zero,
        $openExisting, $openReparsePoint, [IntPtr]::Zero)
    if ($handle.IsInvalid) {
        $code = [System.Runtime.InteropServices.Marshal]::GetLastPInvokeError()
        $handle.Dispose()
        throw [System.ComponentModel.Win32Exception]::new($code, "Cannot open '$fullPath' without following reparse points (Win32 error $code).")
    }
    return $handle
}

function Get-FileIdentity {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [Microsoft.Win32.SafeHandles.SafeFileHandle] $Handle
    )

    $info = [MachineHealth.NoFollowFileNative+ByHandleFileInformation]::new()
    if (-not [MachineHealth.NoFollowFileNative]::GetFileInformationByHandle($Handle, [ref]$info)) {
        $code = [System.Runtime.InteropServices.Marshal]::GetLastPInvokeError()
        throw [System.ComponentModel.Win32Exception]::new($code, "Cannot read the file information (Win32 error $code).")
    }
    return [pscustomobject]@{
        FileId         = '{0:X8}-{1:X8}{2:X8}' -f $info.VolumeSerialNumber, $info.FileIndexHigh, $info.FileIndexLow
        IsReparsePoint = [bool]($info.FileAttributes -band 0x400)
        IsDirectory    = [bool]($info.FileAttributes -band 0x10)
    }
}
