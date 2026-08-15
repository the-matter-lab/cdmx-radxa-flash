#requires -Version 5.1
$ErrorActionPreference = "Stop"

$PrepareScript = (Resolve-Path "$PSScriptRoot\..\..\host\windows\prepare-disk.ps1").Path
$Failures = 0

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Expected,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()]$Actual,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $ExpectedJson = ConvertTo-Json -InputObject @($Expected) -Compress
    $ActualJson = ConvertTo-Json -InputObject @($Actual) -Compress
    if ($ExpectedJson -ne $ActualJson) {
        Write-Host "not ok - $Label (expected $ExpectedJson, got $ActualJson)"
        $script:Failures += 1
    }
    else {
        Write-Host "ok - $Label"
    }
}

function Invoke-PrepareCase {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][bool]$Offline,
        [Parameter(Mandatory = $true)][bool]$ReadOnly,
        [Parameter(Mandatory = $true)][string]$BusType,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ExpectedCalls,
        [bool]$OfflineUnsupported = $false,
        [object[]]$AccessPaths = @()
    )

    $global:MockDisk = [pscustomobject]@{
        Number = 8
        BusType = $BusType
        IsBoot = $false
        IsSystem = $false
        IsOffline = $Offline
        IsReadOnly = $ReadOnly
    }
    $global:SetDiskCalls = [System.Collections.Generic.List[string]]::new()
    $global:MountvolCalls = [System.Collections.Generic.List[string]]::new()
    $global:OfflineUnsupported = $OfflineUnsupported
    $global:AccessPaths = $AccessPaths

    function global:Get-Disk {
        param([int]$Number, [string]$ErrorAction)
        if ($Number -ne 8) { throw "unexpected disk number $Number" }
        return $global:MockDisk
    }
    function global:Set-Disk {
        param(
            [int]$Number,
            [Nullable[bool]]$IsOffline,
            [Nullable[bool]]$IsReadOnly,
            [string]$ErrorAction
        )
        if ($Number -ne 8) { throw "unexpected disk number $Number" }
        if ($PSBoundParameters.ContainsKey("IsOffline")) {
            $global:SetDiskCalls.Add("offline:$IsOffline")
            if ([bool]$IsOffline -and $global:OfflineUnsupported) {
                throw "whole-disk offline is not supported by this reader"
            }
            $global:MockDisk.IsOffline = [bool]$IsOffline
        }
        if ($PSBoundParameters.ContainsKey("IsReadOnly")) {
            $global:SetDiskCalls.Add("readonly:$IsReadOnly")
            $global:MockDisk.IsReadOnly = [bool]$IsReadOnly
        }
    }
    function global:Get-Partition {
        param([int]$DiskNumber, [string]$ErrorAction)
        if ($DiskNumber -ne 8) { throw "unexpected disk number $DiskNumber" }
        if ($global:AccessPaths.Count -gt 0) {
            return [pscustomobject]@{ AccessPaths = $global:AccessPaths }
        }
        return @()
    }
    function global:mountvol.exe {
        param([string]$MountPoint, [string]$Operation)
        $global:MountvolCalls.Add("$MountPoint $Operation")
        $global:LASTEXITCODE = 0
    }

    try {
        & $PrepareScript -DiskNumber 8
        Assert-Equal -Expected $ExpectedCalls -Actual $global:SetDiskCalls.ToArray() -Label $Label
        if ($OfflineUnsupported) {
            Assert-Equal -Expected @("E:\ /p") -Actual $global:MountvolCalls.ToArray() -Label "$Label uses volume fallback"
        }
    }
    finally {
        Remove-Item Function:\Get-Disk -ErrorAction SilentlyContinue
        Remove-Item Function:\Set-Disk -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-Partition -ErrorAction SilentlyContinue
        Remove-Item Function:\mountvol.exe -ErrorAction SilentlyContinue
    }
}

Invoke-PrepareCase -Label "already-offline USB reader is a no-op" -Offline $true -ReadOnly $false -BusType USB -ExpectedCalls @()
Invoke-PrepareCase -Label "online USB reader is taken offline once" -Offline $false -ReadOnly $false -BusType USB -ExpectedCalls @("offline:True")
Invoke-PrepareCase -Label "read-only SD reader is unlocked then taken offline" -Offline $false -ReadOnly $true -BusType SD -ExpectedCalls @("readonly:False", "offline:True")
Invoke-PrepareCase -Label "offline read-only MMC reader is safely cycled" -Offline $true -ReadOnly $true -BusType MMC -ExpectedCalls @("offline:False", "readonly:False", "offline:True")
Invoke-PrepareCase -Label "native SD reader without disk-offline support is dismounted" -Offline $false -ReadOnly $false -BusType SD -ExpectedCalls @("offline:True") -OfflineUnsupported $true -AccessPaths @("E:\")

if ($Failures -gt 0) {
    throw "$Failures Windows disk preparation test(s) failed"
}
Write-Host "all Windows disk preparation tests passed"
