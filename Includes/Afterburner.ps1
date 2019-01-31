
# Initialize MSI Afterburner interface
$baseFolder = Split-Path -parent $script:MyInvocation.MyCommand.Path

try {
    Add-Type -Path $baseFolder\MSIAfterburner.NET.dll
} catch {
    Write-Log $_.Exception.Message -Severity Warn
    Write-Log "Failed to load Afterburner interface library" -Severity Error
    Exit
}

try {
    $global:abMonitor = New-Object MSI.Afterburner.HardwareMonitor
} catch {
    Write-Log $_.Exception.Message -Severity Warn
    Write-Log "Failed to create MSI Afterburner Monitor object. Falling back to standard monitoring." -Severity Warn
    $abMonitor = $false
    Start-Sleep -Seconds 5
}

try {
    $global:abControl = New-Object MSI.Afterburner.ControlMemory
} catch {
    Write-Log $_.Exception.Message -Severity Warn
    Write-Log "Failed to create MSI Afterburner Control object. PowerLimits will not be available" -Severity Warn
    $abControl = $false
    Start-Sleep -Seconds 5
}

function Set-AfterburnerPowerLimit ([int]$PowerLimitPercent, $DeviceGroup) {

    try {
        $abMonitor.ReloadAll()
        $abControl.ReloadAll()
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        throw "Failed to communicate with MSI Afterburner"
    }

    if ($DeviceGroup.DevicesArray.Length -gt 0) {

        $PowerLimit = $PowerLimitPercent

        $Pattern = @{
            AMD    = '*Radeon*'
            NVIDIA = '*GeForce*'
            Intel  = '*Intel*'
        }

        $Devices = @($abMonitor.GpuEntries | Where-Object Device -like $Pattern.$($DeviceGroup.Type) | Select-Object -ExpandProperty Index)[$DeviceGroup.DevicesArray]

        foreach ($device in $Devices) {
            if ($abControl.GpuEntries[$device].PowerLimitCur -ne $PowerLimit) {

                # Stay within HW limitations
                $PowerLimit = [math]::Min($abControl.GpuEntries[$device].PowerLimitMax, $PowerLimit)
                $PowerLimit = [math]::Max($abControl.GpuEntries[$device].PowerLimitMin, $PowerLimit)

                $abControl.GpuEntries[$device].PowerLimitCur = $PowerLimit
            }
        }
        $abControl.CommitChanges()
    }
}

function Get-AfterburnerDevices ($Type) {
    try {
        $abControl.ReloadAll()
    } catch {
        Write-Log $_.Exception.Message -Severity Warn
        Write-Log "Failed to communicate with MSI Afterburner" -Severity Error
        Exit
    }

    if (@('AMD', 'NVIDIA', 'Intel') -contains $Type) {
        $Pattern = @{
            AMD    = "*Radeon*"
            NVIDIA = "*GeForce*"
            Intel  = "*Intel*"
        }
        @($abMonitor.GpuEntries) | Where-Object Device -like $Pattern.$Type | ForEach-Object {
            $abIndex = $_.Index
            $abMonitor.Entries | Where-Object {
                $_.GPU -eq $abIndex -and
                $_.SrcName -match "(GPU\d+ )?" -and
                $_.SrcName -notmatch "CPU"
            } | Format-Table
            @($abControl.GpuEntries)[$abIndex]
        }
    } elseif ($Type -eq 'CPU') {
        $abMonitor.Entries | Where-Object {
            $_.GPU -eq [uint32]"0xffffffff" -and
            $_.SrcName -match "CPU"
        } | Format-Table
    }
}
