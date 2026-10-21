#Requires -Version 7.4

<#
.SYNOPSIS
Lists the scheduled tasks that start at logon.

.DESCRIPTION
Returns { ReadState, Complete, Tasks }, each task
{ TaskPath, TaskName, Command, Enabled }. A task counts when any of its triggers
is a logon trigger. Command joins each action's executable and arguments, or
names the COM handler for a handler action.

Complete is $false without elevation, when the list is partial; why is the
startup-items row of Get-ElevationMatrix.ps1.
#>

. (Join-Path $PSScriptRoot 'Test-IsElevated.ps1')

$script:LogonTriggerClass = 'MSFT_TaskLogonTrigger'

function Get-LogonTaskInventory {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $complete = [bool](Test-IsElevated)
    try {
        $all = @(Get-ScheduledTask -ErrorAction Stop)
    } catch [System.UnauthorizedAccessException] {
        return [pscustomobject]@{ ReadState = 'denied'; Complete = $complete; Tasks = @() }
    } catch {
        Write-Verbose "Get-LogonTaskInventory: Get-ScheduledTask failed. $($_.Exception.Message)"
        return [pscustomobject]@{ ReadState = 'error'; Complete = $complete; Tasks = @() }
    }

    $tasks = foreach ($task in $all) {
        $atLogon = @($task.Triggers | Where-Object { $_ -and $_.CimClass.CimClassName -eq $script:LogonTriggerClass })
        if ($atLogon.Count -eq 0) { continue }
        $commands = foreach ($action in @($task.Actions | Where-Object { $_ })) {
            $execute = $action.PSObject.Properties['Execute'] ? $action.Execute : $null
            if ($execute) {
                $arguments = $action.PSObject.Properties['Arguments'] ? $action.Arguments : $null
                "$execute $arguments".Trim()
            } elseif ($action.PSObject.Properties['ClassId'] -and $action.ClassId) {
                "COM handler $($action.ClassId)"
            }
        }
        [pscustomobject]@{
            TaskPath = $task.TaskPath
            TaskName = $task.TaskName
            Command  = (@($commands) -join '; ')
            Enabled  = ([string]$task.State -ne 'Disabled')
        }
    }
    return [pscustomobject]@{ ReadState = 'ok'; Complete = $complete; Tasks = @($tasks) }
}
