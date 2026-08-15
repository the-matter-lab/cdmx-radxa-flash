#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 4096)]
    [int]$DiskNumber
)

$ErrorActionPreference = "Stop"
$AllowedBusTypes = @("USB", "SD", "MMC")

function Get-CDMXTargetDisk {
    Get-Disk -Number $DiskNumber -ErrorAction Stop
}

function Assert-CDMXTargetDisk {
    param([Parameter(Mandatory = $true)]$Disk)

    $BusType = $Disk.BusType.ToString().ToUpperInvariant()
    if ($Disk.IsBoot -or $Disk.IsSystem) {
        throw "Refusing to prepare Windows boot/system disk $DiskNumber."
    }
    if ($AllowedBusTypes -notcontains $BusType) {
        throw "Refusing disk $DiskNumber because its bus type is '$BusType', not USB, SD, or MMC."
    }
}

function Dismount-CDMXTargetVolumes {
    $Partitions = @(Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue)
    foreach ($Partition in $Partitions) {
        # AccessPaths also contains the volume GUID. mountvol /p needs an
        # assigned drive/folder mount point; hidden or unknown filesystems have
        # no such path and do not need dismounting for a physical-disk write.
        $MountPoints = @($Partition.AccessPaths | Where-Object {
            $_ -and $_ -notmatch '^\\\\\?\\Volume\{'
        })
        if ($MountPoints.Count -eq 0) {
            continue
        }

        # /p requires the volume's last mount point. Remove any additional
        # paths first, then dismount the volume and make it unmountable.
        for ($Index = 1; $Index -lt $MountPoints.Count; $Index += 1) {
            & mountvol.exe $MountPoints[$Index] /d
            if ($LASTEXITCODE -ne 0) {
                throw "mountvol could not remove mount point '$($MountPoints[$Index])'."
            }
        }
        & mountvol.exe $MountPoints[0] /p
        if ($LASTEXITCODE -ne 0) {
            throw "mountvol could not dismount '$($MountPoints[0])'."
        }
    }
}

try {
    $Disk = Get-CDMXTargetDisk
    Assert-CDMXTargetDisk -Disk $Disk

    # This script is intentionally idempotent. The imager calls it before the
    # raw write and again before writing equipoN to the small FAT partition.
    # Several Windows SD readers reject Set-Disk -IsReadOnly on a disk that is
    # already offline, even when the requested value is already false.
    if ($Disk.IsOffline -and -not $Disk.IsReadOnly) {
        return
    }

    if ($Disk.IsOffline) {
        Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction Stop
        $Disk = Get-CDMXTargetDisk
        Assert-CDMXTargetDisk -Disk $Disk
    }

    if ($Disk.IsReadOnly) {
        Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction Stop
        $Disk = Get-CDMXTargetDisk
        Assert-CDMXTargetDisk -Disk $Disk
        if ($Disk.IsReadOnly) {
            throw "The card is still read-only. Unlock the adapter's physical write-protect switch."
        }
    }

    if (-not $Disk.IsOffline) {
        try {
            Set-Disk -Number $DiskNumber -IsOffline $true -ErrorAction Stop
        }
        catch {
            # Some removable-media drivers (especially integrated SD slots)
            # do not implement whole-disk offline state. Windows supports the
            # equivalent safe path by dismounting each mounted volume with
            # mountvol /p before the raw physical-drive write.
            Dismount-CDMXTargetVolumes
        }
    }

    $Disk = Get-CDMXTargetDisk
    Assert-CDMXTargetDisk -Disk $Disk
    if (-not $Disk.IsOffline) {
        # Whole-disk offline is preferred, but readers that do not support it
        # have already had every assigned volume dismounted above.
        return
    }
}
catch {
    throw "Could not prepare removable disk $DiskNumber for writing. $($_.Exception.Message)"
}
