Add-Type -Path $PSScriptRoot\Includes\OpenCL\*.cs

function Set-NvidiaPowerLimit ([int]$PowerLimitPercent, [string]$Devices) {

    if ($PowerLimitPercent -eq 0) { return }
    foreach ($Device in @($Devices -split ',')) {

        # $Command = (Resolve-Path -Path '.\includes\nvidia-smi.exe').Path
        # $Arguments = @(
        #     "-i $Device"
        #     "--query-gpu=power.default_limit"
        #     "--format=csv,noheader"
        # )
        # $PowerDefaultLimit = [int](((& $Command $Arguments) -replace 'W').Trim())

        $xpr = ".\includes\nvidia-smi.exe -i " + $Device + " --query-gpu=power.default_limit --format=csv,noheader"
        $PowerDefaultLimit = [int]((invoke-expression $xpr) -replace 'W', '')

        #powerlimit change must run in admin mode
        $NewProcess = New-Object System.Diagnostics.ProcessStartInfo ".\includes\nvidia-smi.exe"
        $NewProcess.Verb = "runas"
        #$NewProcess.UseShellExecute = $false
        $NewProcess.Arguments = "-i $Device -pl $([Math]::Floor([int]($PowerDefaultLimit -replace ' W', '') * ($PowerLimitPercent / 100)))"
        [System.Diagnostics.Process]::Start($NewProcess) | Out-Null
    }
    Remove-Variable NewProcess
}

function Send-ErrorsToLog ($LogFile) {

    for ($i = 0; $i -lt $error.count; $i++) {
        if ($error[$i].InnerException.Paramname -ne "scopeId") {
            # errors in debug
            $Msg = "###### ERROR ##### " + [string]($error[$i]) + ' ' + $error[$i].ScriptStackTrace
            Write-Log $msg -Severity Error -NoEcho
        }
    }
    $error.clear()
}

function Edit-ForEachDevice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigFileArguments,
        [Parameter(Mandatory = $false)]
        $Devices
    )

    #search string to replace
    $ConfigFileArguments = $ConfigFileArguments -replace [Environment]::NewLine, "#NL#" #replace carriage return for Select-string search (only search in each line)

    $Match = $ConfigFileArguments | Select-String -Pattern "#ForEachDevice#.*?#EndForEachDevice#"
    if ($null -ne $Match) {

        $Match.Matches | ForEach-Object {
            $Base = $_.value -replace "#ForEachDevice#" -replace "#EndForEachDevice#"
            $Index = 0
            $Final = $Devices.Devices -split ',' | ForEach-Object {
                $Base -replace "#DeviceID#", $_ -replace "#DeviceIndex#", $Index
                $Index++
            }
            $ConfigFileArguments = $ConfigFileArguments.Substring(0, $_.index) + $Final + $ConfigFileArguments.Substring($_.index + $_.Length, $ConfigFileArguments.Length - ($_.index + $_.Length))
        }
    }

    $Match = $ConfigFileArguments | Select-String -Pattern "#RemoveLastCharacter#"
    if ($null -ne $Match) {
        $Match.Matches | ForEach-Object {
            $ConfigFileArguments = $ConfigFileArguments.Substring(0, $_.index - 1) + $ConfigFileArguments.Substring($_.index + $_.Length, $ConfigFileArguments.Length - ($_.index + $_.Length))
        }
    }

    $ConfigFileArguments = $ConfigFileArguments -replace "#NL#", [Environment]::NewLine #replace carriage return for Select-string search (only search in each line)
    $ConfigFileArguments
}

function Get-NextFreePort {
    param(
        [Parameter(Mandatory = $true)]
        [int]$LastUsedPort
    )

    if ($LastUsedPort -lt 2000) {$FreePort = 2001} else {$FreePort = $LastUsedPort + 1} #not allow use of <2000 ports
    while (Test-TCPPort -Server 127.0.0.1 -Port $FreePort -timeout 100) {$FreePort = $LastUsedPort + 1}
    $FreePort
}

function Test-TCPPort {
    param([string]$Server, [int]$Port, [int]$Timeout)

    $Connection = New-Object System.Net.Sockets.TCPClient

    try {
        $Connection.SendTimeout = $Timeout
        $Connection.ReceiveTimeout = $Timeout
        $Connection.Connect($Server, $Port) | out-Null
        $Connection.Close
        $Connection.Dispose
        return $true #port is occupied
    } catch {
        $Error.Remove($error[$Error.Count - 1])
        return $false #port is free
    }
}

function Exit-Process {
    param(
        [Parameter(Mandatory = $true)]
        $Process
    )

    $sw = [Diagnostics.Stopwatch]::new()
    try {
        $Process.CloseMainWindow() | Out-Null
        $sw.Start()
        do {
            if ($sw.Elapsed.TotalSeconds -gt 1) {
                Stop-Process -InputObject $Process -Force
            }
            if (-not $Process.HasExited) {
                Start-Sleep -Milliseconds 1
            }
        } while (-not $Process.HasExited)
    } finally {
        $sw.Stop()
        if (-not $Process.HasExited) {
            Stop-Process -InputObject $Process -Force
        }
    }
    Remove-Variable sw
}

function Get-DevicesInformation ($Types) {
    $Devices = @()
    if ($abMonitor) {$abMonitor.ReloadAll()}
    if ($abControl) {$abControl.ReloadAll()}

    #AMD
    if ($Types | Where-Object Type -eq 'AMD') {
        if ($abMonitor) {
            foreach ($Type in @('AMD')) {
                $DeviceId = 0
                $Pattern = @{
                    AMD    = '*Radeon*'
                    NVIDIA = '*GeForce*'
                    Intel  = '*Intel*'
                }
                @($abMonitor.GpuEntries | Where-Object Device -like $Pattern.$Type) | ForEach-Object {
                    $CardData = $abMonitor.Entries | Where-Object GPU -eq $_.Index
                    $Group = $($Types | Where-Object Type -eq $Type | Where-Object DevicesArray -contains $DeviceId).GroupName
                    $Card = @{
                        Type              = $Type
                        Id                = $DeviceId
                        Group             = $Group
                        AdapterId         = [int]$_.Index
                        Name              = $_.Device
                        Utilization       = [int]$($CardData | Where-Object SrcName -match "^(GPU\d* )?usage$").Data
                        UtilizationMem    = [int]$($mem = $CardData | Where-Object SrcName -match "^(GPU\d* )?memory usage$"; if ($mem.MaxLimit) {$mem.Data / $mem.MaxLimit * 100})
                        Clock             = [int]$($CardData | Where-Object SrcName -match "^(GPU\d* )?core clock$").Data
                        ClockMem          = [int]$($CardData | Where-Object SrcName -match "^(GPU\d* )?memory clock$").Data
                        FanSpeed          = [int]$($CardData | Where-Object SrcName -match "^(GPU\d* )?fan speed$").Data
                        Temperature       = [int]$($CardData | Where-Object SrcName -match "^(GPU\d* )?temperature$").Data
                        PowerDraw         = [int]$($CardData | Where-Object {$_.SrcName -match "^(GPU\d* )?power$" -and $_.SrcUnits -eq 'W'}).Data
                        PowerLimitPercent = [int]$($abControl.GpuEntries[$_.Index].PowerLimitCur)
                        PCIBus            = [int]$($null = $_.GpuId -match "&BUS_(\d+)&"; $matches[1])
                    }
                    $Devices += [PSCustomObject]$Card
                    $DeviceId++
                }
            }
        } else {
            #ADL
            $DeviceId = 0

            $Command = ".\Includes\OverdriveN.exe"
            $AdlResult = & $Command | Where-Object {$_ -notlike "*&???" -and $_ -ne "ADL2_OverdriveN_Capabilities_Get is failed"}
            $AmdCardsTDP = Get-Content .\Includes\amd-cards-tdp.json | ConvertFrom-Json

            if ($null -ne $AdlResult) {
                $AdlResult | ForEach-Object {

                    $AdlResultSplit = $_ -split (",")
                    $Group = ($Types | Where-Object type -eq 'AMD' | Where-Object DevicesArray -contains $DeviceId).groupname

                    $CardName = $($AdlResultSplit[8] `
                            -replace 'ASUS' `
                            -replace 'AMD' `
                            -replace '\(?TM\)?' `
                            -replace 'Series' `
                            -replace 'Graphics' `
                            -replace "\s+", ' '
                    ).Trim()

                    $CardName = $CardName -replace '.*Radeon.*([4-5]\d0).*', 'Radeon RX $1'     # RX 400/500 series
                    $CardName = $CardName -replace '.*\s(Vega).*(56|64).*', 'Radeon Vega $2'    # Vega series
                    $CardName = $CardName -replace '.*\s(R\d)\s(\w+).*', 'Radeon $1 $2'         # R3/R5/R7/R9 series
                    $CardName = $CardName -replace '.*\s(HD)\s?(\w+).*', 'Radeon HD $2'         # HD series

                    $Card = [PSCustomObject]@{
                        Type              = 'AMD'
                        Id                = $DeviceId
                        Group             = $Group
                        AdapterId         = [int]$AdlResultSplit[0]
                        FanSpeed          = [int]([int]$AdlResultSplit[1] / [int]$AdlResultSplit[2] * 100)
                        Clock             = [int]([int]($AdlResultSplit[3] / 100))
                        ClockMem          = [int]([int]($AdlResultSplit[4] / 100))
                        Utilization       = [int]$AdlResultSplit[5]
                        Temperature       = [int]$AdlResultSplit[6] / 1000
                        PowerLimitPercent = 100 + [int]$AdlResultSplit[7]
                        PowerDraw         = $AmdCardsTDP.$CardName * ((100 + [double]$AdlResultSplit[7]) / 100) * ([double]$AdlResultSplit[5] / 100)
                        Name              = $CardName
                    }
                    $Devices += $Card
                    $DeviceId++
                }
            }
            Clear-Variable AmdCardsTDP
        }
    }

    #NVIDIA
    if ($Types | Where-Object Type -eq 'NVIDIA') {
        $DeviceId = 0
        $Command = '.\includes\nvidia-smi.exe'
        $Arguments = @(
            '--query-gpu=gpu_name,utilization.gpu,utilization.memory,temperature.gpu,power.draw,power.limit,fan.speed,pstate,clocks.current.graphics,clocks.current.memory,power.max_limit,power.default_limit'
            '--format=csv,noheader'
        )
        & $Command $Arguments  | ForEach-Object {
            $SMIresultSplit = $_ -split (",")
            if ($SMIresultSplit.count -gt 10) {
                #less is error or no NVIDIA gpu present

                $Group = ($Types | Where-Object type -eq 'NVIDIA' | Where-Object DevicesArray -contains $DeviceId).groupname

                $Card = [PSCustomObject]@{
                    Type              = 'NVIDIA'
                    Id                = $DeviceId
                    Group             = $Group
                    Name              = $SMIresultSplit[0]
                    Utilization       = if ($SMIresultSplit[1] -like "*Supported*") {100} else {[int]($SMIresultSplit[1] -replace '%', '')} #If we dont have real Utilization, at least make the watchdog happy
                    UtilizationMem    = if ($SMIresultSplit[2] -like "*Supported*") {$null} else {[int]($SMIresultSplit[2] -replace '%', '')}
                    Temperature       = if ($SMIresultSplit[3] -like "*Supported*") {$null} else {[int]($SMIresultSplit[3] -replace '%', '')}
                    PowerDraw         = if ($SMIresultSplit[4] -like "*Supported*") {$null} else {[int]($SMIresultSplit[4] -replace 'W', '')}
                    PowerLimit        = if ($SMIresultSplit[5] -like "*Supported*" -or $SMIresultSplit[5] -like "*error*") {$null} else {[int]($SMIresultSplit[5] -replace 'W', '')}
                    FanSpeed          = if ($SMIresultSplit[6] -like "*Supported*" -or $SMIresultSplit[6] -like "*error*") {$null} else {[int]($SMIresultSplit[6] -replace '%', '')}
                    Pstate            = $SMIresultSplit[7]
                    Clock             = if ($SMIresultSplit[8] -like "*Supported*") {$null} else {[int]($SMIresultSplit[8] -replace 'Mhz', '')}
                    ClockMem          = if ($SMIresultSplit[9] -like "*Supported*") {$null} else {[int]($SMIresultSplit[9] -replace 'Mhz', '')}
                    PowerMaxLimit     = if ($SMIresultSplit[10] -like "*Supported*") {$null} else {[int]($SMIresultSplit[10] -replace 'W', '')}
                    PowerDefaultLimit = if ($SMIresultSplit[11] -like "*Supported*") {$null} else {[int]($SMIresultSplit[11] -replace 'W', '')}
                }
                if ($Card.PowerDefaultLimit -gt 0) { $Card | Add-Member PowerLimitPercent ([math]::Floor(($Card.PowerLimit * 100) / $Card.PowerDefaultLimit))}
                $Devices += $Card
                $DeviceId++
            }
        }
    }

    # CPU
    if ($Types | Where-Object Type -eq 'CPU') {

        $CpuResult = @(Get-CimInstance Win32_Processor)

        ### Not sure how Afterburner results look with more than 1 CPU
        if ($abMonitor) {
            $CpuData = @{
                Clock       = $($abMonitor.Entries | Where-Object SrcName -match '^(CPU\d* )clock' | Measure-Object -Property Data -Maximum).Maximum
                Utilization = $($abMonitor.Entries | Where-Object SrcName -match '^(CPU\d* )usage'| Measure-Object -Property Data -Average).Average
                PowerDraw   = $($abMonitor.Entries | Where-Object SrcName -eq 'CPU power').Data
                Temperature = $($abMonitor.Entries | Where-Object SrcName -match "^(CPU\d* )temperature" | Measure-Object -Property Data -Maximum).Maximum
            }
        } else {
            $CpuData = @{}
        }

        $CpuResult | ForEach-Object {
            if (-not $CpuData.Utilization) {
                # Get-Counter is more accurate and is preferable, but currently not available in Poweshell 6
                if (Get-Command "Get-Counter" -Type Cmdlet -errorAction SilentlyContinue) {
                    # Language independent version of Get-Counter '\Processor(_Total)\% Processor Time'
                    $CpuData.Utilization = (Get-Counter -Counter '\238(_Total)\6').CounterSamples.CookedValue
                } else {
                    $Error.Remove($Error[$Error.Count - 1])
                    $CpuData.Utilization = $_.LoadPercentage
                }
            }
            if (-not $CpuData.PowerDraw) {
                if (-not $CpuTDP) {$CpuTDP = Get-Content ".\Includes\cpu-tdp.json" | ConvertFrom-Json}
                $CpuData.PowerDraw = $CpuTDP.($_.Name.Trim()) * $CpuData.Utilization / 100
            }
            if (-not $CpuData.Clock) {$CpuData.Clock = $_.MaxClockSpeed}
            $Devices += [PSCustomObject]@{
                Type        = 'CPU'
                Group       = 'CPU'
                Id          = [int]($_.DeviceID -replace "[^0-9]")
                Name        = $_.Name.Trim()
                Cores       = [int]$_.NumberOfCores
                Threads     = [int]$_.NumberOfLogicalProcessors
                CacheL3     = [int]($_.L3CacheSize / 1024)
                Clock       = [int]$CpuData.Clock
                Utilization = [int]$CpuData.Utilization
                PowerDraw   = [int]$CpuData.PowerDraw
                Temperature = [int]$CpuData.Temperature
            }
        }
    }
    $Devices
}

function Out-DevicesInformation ($Devices) {

    $Devices | Where-Object Type -ne 'CPU' | Sort-Object Type | Format-Table -Wrap (
        @{Label = "Id"; Expression = {$_.Id}; Align = 'right'},
        @{Label = "Group"; Expression = {$_.Group}; Align = 'right'},
        @{Label = "Name"; Expression = {$_.Name}},
        @{Label = "Load"; Expression = {[string]$_.Utilization + "%"}; Align = 'right'},
        @{Label = "Mem"; Expression = {[string]$_.UtilizationMem + "%"}; Align = 'right'},
        @{Label = "Temp"; Expression = {$_.Temperature}; Align = 'right'},
        @{Label = "Fan"; Expression = {[string]$_.FanSpeed + "%"}; Align = 'right'},
        @{Label = "Power"; Expression = {[string]$_.PowerDraw + "W"}; Align = 'right'},
        @{Label = "PwLim"; Expression = {[string]$_.PowerLimitPercent + '%'}; Align = 'right'},
        @{Label = "Pstate"; Expression = {$_.pstate}; Align = 'right'},
        @{Label = "Clock"; Expression = {[string]$_.Clock + "Mhz"}; Align = 'right'},
        @{Label = "ClkMem"; Expression = {[string]$_.ClockMem + "Mhz"}; Align = 'right'}
    ) -groupby Type | Out-Host

    $Devices | Where-Object Type -eq 'CPU' | Format-Table -Wrap (
        @{Label = "Id"; Expression = {$_.Id}; Align = 'right'},
        @{Label = "Group"; Expression = {$_.Group}; Align = 'right'},
        @{Label = "Name"; Expression = {$_.Name}},
        @{Label = "Cores"; Expression = {$_.Cores}},
        @{Label = "Threads"; Expression = {$_.Threads}},
        @{Label = "CacheL3"; Expression = {[string]$_.CacheL3 + "MB"}; Align = 'right'},
        @{Label = "Clock"; Expression = {[string]$_.Clock + "Mhz"}; Align = 'right'},
        @{Label = "Load"; Expression = {[string]$_.Utilization + "%"}; Align = 'right'},
        @{Label = "Temp"; Expression = {$_.Temperature}; Align = 'right'},
        @{Label = "Power*"; Expression = {[string]$_.PowerDraw + "W"}; Align = 'right'}
    ) -groupby Type | Out-Host
}

function Get-Devices {
    $OCLPlatforms = @([OpenCl.Platform]::GetPlatformIds())
    $PlatformId = 0
    $OCLDevices = @($OCLPlatforms | ForEach-Object {
            $Devs = [OpenCl.Device]::GetDeviceIDs($_, [OpenCl.DeviceType]::All)
            $Devs | Add-Member PlatformId $PlatformId
            $Devs | ForEach-Object {
                $_ | Add-Member DeviceIndex $([array]::indexof($Devs, $_))
            }
            $PlatformId++
            $Devs
        })

    # # start fake
    # $OCLDevices = @()
    # $OCLDevices += [PSCustomObject]@{Name = 'Ellesmere'; Vendor = 'Advanced Micro Devices, Inc.'; GlobalMemSize = 8GB; PlatformId = 0; Type = 'Gpu'; DeviceIndex = 0}
    # $OCLDevices += [PSCustomObject]@{Name = 'Ellesmere'; Vendor = 'Advanced Micro Devices, Inc.'; GlobalMemSize = 8GB; PlatformId = 0; Type = 'Gpu'; DeviceIndex = 1}
    # $OCLDevices += [PSCustomObject]@{Name = 'Ellesmere'; Vendor = 'Advanced Micro Devices, Inc.'; GlobalMemSize = 4GB; PlatformId = 0; Type = 'Gpu'; DeviceIndex = 2}
    # $OCLDevices += [PSCustomObject]@{Name = 'GeForce 1060'; Vendor = 'NVIDIA Corporation'; GlobalMemSize = 3GB; PlatformId = 1; Type = 'Gpu'; DeviceIndex = 1}
    # $OCLDevices += [PSCustomObject]@{Name = 'GeForce 1060'; Vendor = 'NVIDIA Corporation'; GlobalMemSize = 3GB; PlatformId = 1; Type = 'Gpu'; DeviceIndex = 2}
    # # end fake


    $Vendors = @{
        "Advanced Micro Devices, Inc." = "AMD"
        "NVIDIA Corporation"           = "NVIDIA"
        # "Intel(R) Corporation"         = "INTEL" #Nothing to be mined on Intel iGPU
        # "Intel Corporation"            = "INTEL" #Nothing to be mined on Intel iGPU
        # "GenuineIntel"                 = 'CPU'
        # "AuthenticAMD"                 = 'CPU'
    }
    # $OCLDevices | Where-Object Type -eq 'Gpu' | Group-Object PlatformId, Name, GlobalMemSize, MaxComputeUnits | ForEach-Object {
    #     $Devices = $_.Group | Select-Object -Property PlatformId, Name, Vendor, GlobalMemSize, MaxComputeUnits -First 1
    #     if ($Vendors.($Devices.Vendor)) {
    #         $Devices | Add-Member Devices $($_.Group.DeviceIndex -join ',')
    #         $Devices | Add-Member Type $Vendors.($Devices.Vendor)
    #         $Devices | Add-Member GroupName $(($Devices.Name -replace "[^A-Z0-9]") + '_' + [int]($Devices.GlobalMemSize / 1GB) + 'gb_' + $Devices.MaxComputeUnits)

    #         $Devices | Select-Object -Property GroupName, Type, Name, PlatformId, Devices, Enabled
    #     }
    # }
    if ($Config.GpuGroupByType) {
        $OCLDevices | Where-Object Type -eq 'Gpu' | Group-Object PlatformId, Name | ForEach-Object {
            $Devices = $_.Group | Select-Object -Property PlatformId, Name, Vendor -First 1
            if ($Vendors.($Devices.Vendor)) {
                $Devices | Add-Member Devices $($_.Group.DeviceIndex -join ',')
                $Devices | Add-Member Type $Vendors.($Devices.Vendor)
                $Devices | Add-Member GroupName $Vendors.($Devices.Vendor)
                $Devices | Add-Member Enabled $true

                $Devices | Select-Object -Property GroupName, Type, Name, PlatformId, Devices, Enabled
            }
        }
    } else {
        $OCLDevices | Where-Object Type -eq 'Gpu' | Group-Object PlatformId, Name, GlobalMemSize | ForEach-Object {
            $Devices = $_.Group | Select-Object -Property PlatformId, Name, Vendor, GlobalMemSize -First 1
            if ($Vendors.($Devices.Vendor)) {
                $Devices | Add-Member Devices $($_.Group.DeviceIndex -join ',')
                $Devices | Add-Member Type $Vendors.($Devices.Vendor)
                $Devices | Add-Member GroupName $(($Devices.Name -replace "[^A-Z0-9]") + '_' + [int]($Devices.GlobalMemSize / 1GB) + 'gb')
                $Devices | Add-Member Enabled $true

                $Devices | Select-Object -Property GroupName, Type, Name, PlatformId, Devices, Enabled
            }
        }
    }
}

function Get-MiningTypes () {
    param(
        [Parameter(Mandatory = $false)]
        [array]$Filter = $null,
        [Parameter(Mandatory = $false)]
        [switch]$All = $false
    )

    if ($null -eq $Filter) {$Filter = @()} # to allow comparation after

    $OCLPlatforms = [OpenCl.Platform]::GetPlatformIds()
    $PlatformId = 0
    $OCLDevices = @($OCLPlatforms | ForEach-Object {
            $Devs = [OpenCl.Device]::GetDeviceIDs($_, [OpenCl.DeviceType]::All)
            $Devs | Add-Member PlatformId $PlatformId
            $Devs | ForEach-Object {
                $_ | Add-Member DeviceIndex $([array]::indexof($Devs, $_))
            }
            $PlatformId++
            $Devs
        })

    $global:Devices = Get-Content .\Config\Devices.json | ConvertFrom-Json
    $Types0 = $null

    if ($null -eq $Types0 -or $All) {
        # Autodetection on, must add types manually
        [array]$Types0 = Get-Devices

        $Types0 += [PSCustomObject]@{
            GroupName  = 'CPU'
            Type       = 'CPU'
            PlatformId = 0
            Enabled    = $true
        }
        $Types0 | ConvertTo-Json | Set-Content .\Config\Devices.autodetect.json
    }

    if ($Types0 | Where-Object {$_.Enabled -and $_.Type -eq 'CPU'}) {

        $SysResult = Get-CimInstance Win32_ComputerSystem
        $CpuResult = Get-CimInstance Win32_Processor
        $Features = $(switch -regex ((& .\Includes\CHKCPU32.exe /x) -split "</\w+>") {"^\s*<_?(\w+)>(\d+).*" {@{$Matches[1] = [int]$Matches[2]}}})
        $RealCores = [int[]](0..($CpuResult.NumberOfLogicalProcessors - 1))
        if ($CpuResult.NumberOfLogicalProcessors -gt $CpuResult.NumberOfCores) {
            $RealCores = $RealCores | Where-Object {-not ($_ % 2)}
        }
        $Types0 | Where-Object {$_.Enabled -and $_.Type -eq 'CPU'} | ForEach-Object {
            $_ | Add-Member Devices   ($RealCores -join ',')
            $_ | Add-Member MemoryGB  ([int]($SysResult.TotalPhysicalMemory / 1GB))
            $_ | Add-Member Features  $Features
        }
    }

    $TypeID = 0
    $Types = $Types0 | Where-Object Enabled | ForEach-Object {
        if (-not $Filter -or (Compare-Object $_.GroupName $Filter -IncludeEqual -ExcludeDifferent)) {

            $_ | Add-Member ID $TypeID
            $TypeID++

            $_ | Add-Member DevicesArray    @([int[]]($_.Devices -split ','))                               # @(0,1,2,10,11,12)
            $_ | Add-Member DevicesClayMode (($_.DevicesArray | ForEach-Object {'{0:X}' -f $_}) -join '')   # 012ABC
            $_ | Add-Member DevicesETHMode  ($_.DevicesArray -join ' ')                                     # 0 1 2 10 11 12
            $_ | Add-Member DevicesNsgMode  (($_.DevicesArray | ForEach-Object { "-d " + $_}) -join ' ')    # -d 0 -d 1 -d 2 -d 10 -d 11 -d 12
            $_ | Add-Member DevicesCount    ($_.DevicesArray.count)                                         # 6

            switch ($_.Type) {
                AMD { $Pattern = 'Advanced Micro Devices, Inc.' }
                NVIDIA { $Pattern = 'NVIDIA Corporation' }
                INTEL { $Pattern = 'Intel(R) Corporation' }
                CPU { $Pattern = '' }
            }
            $_ | Add-Member OCLDevices @($OCLDevices | Where-Object {$_.Vendor -eq $Pattern -and $_.Type -eq 'Gpu'})[$_.DevicesArray]
            if ($null -eq $_.PlatformId) {$_ | Add-Member PlatformId ($_.OCLDevices.PlatformId | Select-Object -First 1)}
            if ($null -eq $_.MemoryGB) {$_ | Add-Member MemoryGB ([int](($_.OCLDevices | Measure-Object -Property GlobalMemSize -Minimum | Select-Object -ExpandProperty Minimum) / 1GB ))}
            if ($null -eq $_.DevicesMask) {$_ | Add-Member DevicesMask ('{0:X}' -f [int]($_.DevicesArray | ForEach-Object { [System.Math]::Pow(2, $_) } | Measure-Object -Sum).Sum)}


            if ($_.PowerLimits.Count -eq 0) {
                $_ | Add-Member PowerLimits @(0)
            } elseif (
                $_.Type -eq 'Intel' -or
                ($_.Type -eq 'AMD' -and -not $abControl)
            ) {
                $_.PowerLimits = @(0)
            } else {
                $_.PowerLimits = @([int[]]($_.PowerLimits -split ',') | Sort-Object -Descending -Unique)
            }

            if ($_.Algorithms.Count -eq 0) {$_ | Add-Member Algorithms $Devices.($_.GroupName).Algorithms}
            if ($_.Algorithms.Count -eq 1) {$_.Algorithms = @($_.Algorithms -split ',') }

            $_
        }
    }
    $Types #return
}

Function Write-Log {
    param(
        [Parameter()]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warn', 'Error', 'Debug')]
        [string]$Severity = 'Info',

        [Parameter()]
        [switch]$NoEcho = $false
    )
    if ($Message) {
        $LogFile.WriteLine("$(Get-Date -f "HH:mm:ss.ff")`t$Severity`t$Message")
        if ($NoEcho -eq $false) {
            switch ($Severity) {
                Info { Write-Host $Message -ForegroundColor Green }
                Warn { Write-Warning $Message }
                Error { Write-Error $Message }
            }
        }
    }
}
Set-Alias Log Write-Log


Function Read-KeyboardTimed {
    param(
        [Parameter(Mandatory = $true)]
        [int]$SecondsToWait,
        [Parameter(Mandatory = $true)]
        [array]$ValidKeys
    )

    $LoopStart = Get-Date
    $KeyPressed = $null

    while ((New-TimeSpan $LoopStart (Get-Date)).Seconds -le $SecondsToWait -and $ValidKeys -notcontains $KeyPressed) {
        if ($host.UI.RawUI.KeyAvailable) {
            $Key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp")
            $KeyPressed = $Key.character
            while ($Host.UI.RawUI.KeyAvailable) {$host.UI.RawUI.FlushInputBuffer()} #keyb buffer flush
        }
        Start-Sleep -Milliseconds 30
    }
    $KeyPressed
}

# function Clear-ScreenZone {
#     param(
#         [Parameter(Mandatory = $true)]
#         [int]$startY,
#         [Parameter(Mandatory = $true)]
#         [int]$endY
#     )

#     $BlankLine = " " * $Host.UI.RawUI.WindowSize.Width

#     Set-ConsolePosition 0 $start

#     for ($i = $startY; $i -le $endY; $i++) {
#         $BlankLine | Out-Host
#     }
# }

function Invoke-TCPRequest {
    param(
        [Parameter(Mandatory = $false)]
        [String]$Server = "localhost",
        [Parameter(Mandatory = $true)]
        [String]$Port,
        [Parameter(Mandatory = $true)]
        [String]$Request,
        [Parameter(Mandatory = $false)]
        [Int]$Timeout = 5 #seconds
    )

    try {
        $Client = New-Object System.Net.Sockets.TcpClient $Server, $Port
        $Stream = $Client.GetStream()
        $Writer = New-Object System.IO.StreamWriter $Stream
        $Reader = New-Object System.IO.StreamReader $Stream
        $client.SendTimeout = $Timeout * 1000
        $client.ReceiveTimeout = $Timeout * 1000
        $Writer.AutoFlush = $true

        $Writer.WriteLine($Request)
        $Response = $Reader.ReadLine()
    } catch { $Error.Remove($error[$Error.Count - 1])}
    finally {
        if ($Reader) {$Reader.Close()}
        if ($Writer) {$Writer.Close()}
        if ($Stream) {$Stream.Close()}
        if ($Client) {$Client.Close()}
    }
    $response
}

function Get-TCPResponse {
    param(
        [Parameter(Mandatory = $false)]
        [String]$Server = "localhost",
        [Parameter(Mandatory = $true)]
        [String]$Port,
        [Parameter(Mandatory = $false)]
        [Int]$Timeout = 5, #seconds
        [Parameter(Mandatory = $false)]
        [String]$Request
    )

    try {
        $Client = New-Object System.Net.Sockets.TcpClient $Server, $Port
        $Stream = $Client.GetStream()
        if ($Request) { $Writer = New-Object System.IO.StreamWriter $Stream }
        $Reader = New-Object System.IO.StreamReader $Stream
        $Client.SendTimeout = $Timeout * 1000
        $Client.ReceiveTimeout = $Timeout * 1000
        if ($Request) {
            $Writer.AutoFlush = $true
            $Writer.Write($Request)
        }

        $Response = $Reader.ReadToEnd()
    } catch { $Error.Remove($error[$Error.Count - 1])}
    finally {
        if ($Reader) {$Reader.Close()}
        if ($Writer) {$Writer.Close()}
        if ($Stream) {$Stream.Close()}
        if ($Client) {$Client.Close()}
    }
    $response
}

function Invoke-HTTPRequest {
    param(
        [Parameter(Mandatory = $false)]
        [String]$Server = "localhost",
        [Parameter(Mandatory = $true)]
        [String]$Port,
        [Parameter(Mandatory = $false)]
        [String]$Path,
        [Parameter(Mandatory = $false)]
        [Int]$Timeout = 5 #seconds
    )

    try {
        $response = Invoke-WebRequest "http://$($Server):$Port$Path" -UseBasicParsing -TimeoutSec $timeout
    } catch {$Error.Remove($error[$Error.Count - 1])}

    $response
}

function Invoke-APIRequest {
    param(
        [Parameter(Mandatory = $true)]
        [String]$Url = "http://localhost/",
        [Parameter(Mandatory = $false)]
        [Int]$Timeout = 5, # Request timeout in seconds
        [Parameter(Mandatory = $false)]
        [Int]$Retry = 3, # Amount of retries for request from origin
        [Parameter(Mandatory = $false)]
        [Int]$MaxAge = 10, # Max cache age if request failed, in minutes
        [Parameter(Mandatory = $false)]
        [Int]$Age = 3 # Cache age after which to request from origin, in minutes
    )
    $UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.101 Safari/537.36'
    $CachePath = '.\Cache\'
    $CacheFile = $CachePath + [System.Web.HttpUtility]::UrlEncode($Url) + '.json'

    if (-not (Test-Path -Path $CachePath)) { New-Item -Path $CachePath -ItemType directory -Force | Out-Null }
    if (Test-Path -LiteralPath $CacheFile -NewerThan (Get-Date).AddMinutes( - $Age)) {
        $Response = Get-Content -Path $CacheFile | ConvertFrom-Json
    } else {
        while ($Retry -gt 0) {
            try {
                $Retry--
                $Response = Invoke-RestMethod -Uri $Url -UserAgent $UserAgent -UseBasicParsing -TimeoutSec $Timeout
                if ($Response) {$Retry = 0}
            } catch {
                Start-Sleep -Seconds 2
                $Error.Remove($error[$Error.Count - 1])
            }
        }
        if ($Response) {
            if ($CacheFile.Length -lt 250) {$Response | ConvertTo-Json -Depth 100 | Set-Content -Path $CacheFile}
        } elseif (Test-Path -LiteralPath $CacheFile -NewerThan (Get-Date).AddMinutes( - $MaxAge)) {
            $Response = Get-Content -Path $CacheFile | ConvertFrom-Json
        } else {
            $Response = $null
        }
    }
    $Response
}

function Get-LiveHashRate {
    param(
        [Parameter(Mandatory = $true)]
        [Object]$Miner
    )

    try {
        switch ($Miner.Api) {

            "xgminer" {
                $Message = @{command = "summary"; parameter = ""} | ConvertTo-Json -Compress
                $Request = Invoke-TCPRequest -Port $Miner.ApiPort -Request $Message

                if ($Request) {
                    $Data = $Request.Substring($Request.IndexOf("{"), $Request.LastIndexOf("}") - $Request.IndexOf("{") + 1) -replace " ", "_" | ConvertFrom-Json

                    $HashRate = @(
                        [double]$Data.SUMMARY.HS_5s
                        [double]$Data.SUMMARY.KHS_5s * 1e3
                        [double]$Data.SUMMARY.MHS_5s * 1e6
                        [double]$Data.SUMMARY.GHS_5s * 1e9
                        [double]$Data.SUMMARY.THS_5s * 1e12
                        [double]$Data.SUMMARY.PHS_5s * 1e15
                    ) | Where-Object {$_ -gt 0} | Select-Object -First 1

                    if (-not $HashRate) {
                        $HashRate = @(
                            [double]$Data.SUMMARY.HS_av
                            [double]$Data.SUMMARY.KHS_av * 1e3
                            [double]$Data.SUMMARY.MHS_av * 1e6
                            [double]$Data.SUMMARY.GHS_av * 1e9
                            [double]$Data.SUMMARY.THS_av * 1e12
                            [double]$Data.SUMMARY.PHS_av * 1e15
                        ) | Where-Object {$_ -gt 0} | Select-Object -First 1
                    }
                }
            }

            "ccminer" {
                $Request = Invoke-TCPRequest -Port $Miner.ApiPort -Request "summary"
                if ($Request) {
                    $Data = $Request -split ";" | ConvertFrom-StringData
                    $HashRate = @(
                        [double]$Data.HS
                        [double]$Data.KHS * 1e3
                        [double]$Data.MHS * 1e6
                        [double]$Data.GHS * 1e9
                        [double]$Data.THS * 1e12
                        [double]$Data.PHS * 1e15
                    ) | Where-Object {$_ -gt 0} | Select-Object -First 1
                }
            }

            "ewbf" {
                $Message = @{id = 1; method = "getstat"} | ConvertTo-Json -Compress
                $Request = Invoke-TCPRequest -Port $Miner.ApiPort -Request $Message
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $HashRate = [double](($Data.result.speed_sps) | Measure-Object -Sum).Sum
                }
            }

            "Claymore" {
                $Message = @{id = 0; jsonrpc = "2.0"; method = "miner_getstat1"} | ConvertTo-Json -Compress
                $Request = Invoke-TCPRequest -Port $Miner.ApiPort -Request $Message
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $Multiplier = 1
                    if ($Data.result[0] -notmatch "^TT-Miner") {
                        switch -wildcard ($Miner.Algorithm) {
                            Ethash* { $Multiplier *= 1000 }
                            NeoScrypt* { $Multiplier *= 1000 }
                            ProgPOW* { $Multiplier *= 1000 }
                            Ubqhash* { $Multiplier *= 1000 }
                        }
                    }

                    $HashRate = @(
                        [double]$Data.result[2].Split(";")[0] * $Multiplier
                        [double]$Data.result[4].Split(";")[0] * $Multiplier
                    )
                }
            }

            "wrapper" {
                $wrpath = ".\Wrapper_$($Miner.ApiPort).txt"
                $HashRate = [double]$(if (Test-Path -path $wrpath) {Get-Content $wrpath} else {0})
            }

            "castXMR" {
                $Request = Invoke-HTTPRequest -Port $Miner.ApiPort
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $HashRate = [double]($Data.devices.hash_rate | Measure-Object -Sum).Sum / 1000
                }
            }

            "XMrig" {
                $Request = Invoke-HTTPRequest -Port $Miner.ApiPort -Path "/api.json"
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $HashRate = [double]$Data.HashRate.total[0]
                }
            }

            "BMiner" {
                $Request = Invoke-HTTPRequest -Port $Miner.ApiPort -Path "/api/v1/status/solver"
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $HashRate = $Data.devices |
                        Get-Member -MemberType NoteProperty |
                        ForEach-Object {$Data.devices.($_.name).solvers} |
                        Group-Object algorithm |
                        ForEach-Object {
                        @(
                            $_.group.speed_info.hash_rate | Measure-Object -Sum | Select-Object -ExpandProperty Sum
                            $_.group.speed_info.solution_rate | Measure-Object -Sum | Select-Object -ExpandProperty Sum
                        ) | Where-Object {$_ -gt 0}
                    }
                }
            }

            "SRB" {
                $Request = Invoke-HTTPRequest -Port $Miner.ApiPort
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $HashRate = @(
                        [double]$Data.HashRate_total_now
                        [double]$Data.HashRate_total_5min
                    ) | Where-Object {$_ -gt 0} | Select-Object -First 1
                }
            }

            "JCE" {
                $Request = Invoke-HTTPRequest -Port $Miner.ApiPort
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $HashRate = [double]$Data.HashRate.total
                }
            }

            "LOL" {
                $Request = Invoke-HTTPRequest -Port $Miner.ApiPort -Path "/summary"
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $HashRate = [double]$Data.'Session'.'Performance_Summary'
                }
            }

            "MiniZ" {
                $Message = @{id = 0; method = "getstat"} | ConvertTo-Json -Compress
                $Request = Invoke-TCPRequest -Port $Miner.ApiPort -Request $Message
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $HashRate = [double](($Data.result.speed_sps) | Measure-Object -Sum).Sum
                }
            }

            "GMiner" {
                $Request = Invoke-HTTPRequest -Port $Miner.ApiPort -Path "/api/v1/status"
                if ($Request) {
                    $Data = $Request | ConvertFrom-Json
                    $HashRate = [double]$Data.miner.total_hashrate
                }
            }

            "Mkx" {
                $Request = Get-TCPResponse -Port $Miner.ApiPort -Request 'stats'
                if ($Request) {
                    $Data = $Request.Substring($Request.IndexOf("{"), $Request.LastIndexOf("}") - $Request.IndexOf("{") + 1) | ConvertFrom-Json
                    $HashRate = [double]$Data.gpus.hashrate * 1e6
                }
            }
        } #end switch

        $HashRate
    } catch {}
}

function ConvertTo-Hash {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Hash
    )

    $Return = switch ([math]::truncate([math]::log($Hash, 1e3))) {
        1 {"{0:g4} kh" -f ($Hash / 1e3)}
        2 {"{0:g4} mh" -f ($Hash / 1e6)}
        3 {"{0:g4} gh" -f ($Hash / 1e9)}
        4 {"{0:g4} th" -f ($Hash / 1e12)}
        5 {"{0:g4} ph" -f ($Hash / 1e15)}
        default {"{0:g4} h" -f ($Hash)}
    }
    $Return
}

function Start-SubProcess {
    param(
        [Parameter(Mandatory = $true)]
        [String]$FilePath,
        [Parameter(Mandatory = $false)]
        [String]$ArgumentList = "",
        [Parameter(Mandatory = $false)]
        [String]$WorkingDirectory = "",
        [ValidateRange(-2, 3)]
        [Parameter(Mandatory = $false)]
        [Int]$Priority = 0,
        [Parameter(Mandatory = $false)] <# UselessGuru #>
        [String]$MinerWindowStyle = "Minimized", <# UselessGuru #>
        [Parameter(Mandatory = $false)] <# UselessGuru #>
        [String]$UseAlternateMinerLauncher = $true <# UselessGuru #>
    )

    $PriorityNames = @{
        -2 = "Idle"
        -1 = "BelowNormal"
        0  = "Normal"
        1  = "AboveNormal"
        2  = "High"
        3  = "RealTime"
    }

    if ($UseAlternateMinerLauncher) {

        $ShowWindow = @{
            Normal    = "SW_SHOW"
            Maximized = "SW_SHOWMAXIMIZE"
            Minimized = "SW_SHOWMINNOACTIVE"
        }

        $Job = Start-Job `
            -InitializationScript ([scriptblock]::Create("Set-Location('$(Get-Location)');. .\Includes\CreateProcess.ps1")) `
            -ArgumentList $PID, $FilePath, $ArgumentList, $ShowWindow.$MinerWindowStyle, $PriorityNames.$Priority, $WorkingDirectory {
            param($ControllerProcessID, $FilePath, $ArgumentList, $ShowWindow, $Priority, $WorkingDirectory)

            . .\Includes\CreateProcess.ps1
            $ControllerProcess = Get-Process -Id $ControllerProcessID
            if (-not $ControllerProcess) {return}

            $ProcessParams = @{
                Binary           = $FilePath
                Arguments        = $ArgumentList
                CreationFlags    = [CreationFlags]::CREATE_NEW_CONSOLE
                ShowWindow       = $ShowWindow
                StartF           = [STARTF]::STARTF_USESHOWWINDOW
                Priority         = $Priority
                WorkingDirectory = $WorkingDirectory
            }
            $Process = Invoke-CreateProcess @ProcessParams
            if (-not $Process) {
                [PSCustomObject]@{
                    ProcessId = $null
                }
                return
            }

            [PSCustomObject]@{
                ProcessId     = $Process.Id
                ProcessHandle = $Process.Handle
            }

            $null = $ControllerProcess.Handle
            $null = $Process.Handle

            do {
                if ($ControllerProcess.WaitForExit(1000)) {
                    $null = $Process.CloseMainWindow()
                }
            }
            while ($Process.HasExited -eq $false)
        }
    } else {
        $Job = Start-Job -ArgumentList $PID, $FilePath, $ArgumentList, $WorkingDirectory, $MinerWindowStyle {
            param($ControllerProcessID, $FilePath, $ArgumentList, $WorkingDirectory, $MinerWindowStyle)

            $ControllerProcess = Get-Process -Id $ControllerProcessID
            if (-not $ControllerProcess) {
                return
            }

            $ProcessParam = @{
                FilePath         = $FilePath
                WindowStyle      = $MinerWindowStyle
                ArgumentList     = $(if ($ArgumentList) {$ArgumentList})
                WorkingDirectory = $(if ($WorkingDirectory) {$WorkingDirectory})
            }

            $Process = Start-Process @ProcessParam -PassThru
            if (-not $Process) {
                [PSCustomObject]@{
                    ProcessId = $null
                }
                return
            }

            [PSCustomObject]@{
                ProcessId     = $Process.Id
                ProcessHandle = $Process.Handle
            }

            $null = $ControllerProcess.Handle
            $null = $Process.Handle

            do {
                if ($ControllerProcess.WaitForExit(1000)) {
                    $null = $Process.CloseMainWindow()
                }
            }
            while ($Process.HasExited -eq $false)

        }
    }

    do {
        Start-Sleep -Seconds 1
        $JobOutput = Receive-Job $Job
    }
    while (-not $JobOutput)

    if ($JobOutput.ProcessId -gt 0) {
        $Process = Get-Process | Where-Object Id -eq $JobOutput.ProcessId
        $null = $Process.Handle
        $Process

        if ($Process) {$Process.PriorityClass = $PriorityNames.$Priority}
    }
}

function Expand-WebRequest {
    param(
        [Parameter(Mandatory = $true)]
        [String]$Uri,
        [Parameter(Mandatory = $true)]
        [String]$Path,
        [Parameter(Mandatory = $false)]
        [String]$SHA256
    )

    $DestinationFolder = $PSScriptRoot + $Path.Substring(1)
    $FileName = ([IO.FileInfo](Split-Path $Uri -Leaf)).name
    $CachePath = $PSScriptRoot + '\Downloads\'
    $FilePath = $CachePath + $Filename

    if (-not (Test-Path -LiteralPath $CachePath)) {$null = New-Item -Path $CachePath -ItemType directory}

    try {
        if (Test-Path -LiteralPath $FilePath) {
            if ($SHA256 -and (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash -ne $SHA256) {
                Write-Log "Existing file hash doesn't match. Will re-download." -Severity Warn
                Remove-Item $FilePath
            }
        }
        if (-not (Test-Path -LiteralPath $FilePath)) {
            (New-Object System.Net.WebClient).DownloadFile($Uri, $FilePath)
        }
        if (Test-Path -LiteralPath $FilePath) {
            if ($SHA256 -and (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash -ne $SHA256) {
                Write-Log "File hash doesn't match. Removing file." -Severity Warn
            } elseif (@('.msi', '.exe') -contains (Get-Item $FilePath).Extension) {
                Start-Process $FilePath "-qb" -Wait
            } else {
                $Command = 'x "' + $FilePath + '" -o"' + $DestinationFolder + '" -y -spe'
                Start-Process ".\includes\7z.exe" $Command -Wait
            }
        }
    } finally {
        # if (Test-Path $FilePath) {Remove-Item $FilePath}
    }
}

function Get-Pools {
    param(
        [Parameter(Mandatory = $true)]
        [String]$Querymode = 'core',
        [Parameter(Mandatory = $false)]
        [array]$PoolsFilterList = $null,
        [Parameter(Mandatory = $false)]
        [array]$CoinFilterList,
        [Parameter(Mandatory = $false)]
        [string]$Location = $null,
        [Parameter(Mandatory = $false)]
        [array]$AlgoFilterList,
        [Parameter(Mandatory = $false)]
        [PSCustomObject]$Info
    )
    #in detail mode returns a line for each pool/algo/coin combination, in info mode returns a line for pool

    $PoolsFolderContent = Get-ChildItem ($PSScriptRoot + '\Pools\*') -File -Include '*.ps1' | Where-Object {$PoolsFilterList.Count -eq 0 -or (Compare-Object $PoolsFilterList $_.BaseName -IncludeEqual -ExcludeDifferent | Measure-Object).Count -gt 0}

    if ($null -eq $Info) { $Info = [PSCustomObject]@{}
    }

    if ($null -eq ($Info | Get-Member -MemberType NoteProperty | Where-Object name -eq location)) {$Info | Add-Member Location $Location}

    $Info | Add-Member SharedFile [string]$null

    $ChildItems = $PoolsFolderContent | ForEach-Object {

        $Basename = $_.BaseName
        $SharedFile = $PSScriptRoot + "\Cache\" + $Basename + [string](Get-Random -minimum 0 -maximum 9999999) + ".tmp"
        $Info.SharedFile = $SharedFile

        if (Test-Path $SharedFile) {Remove-Item $SharedFile}
        & $_.FullName -Querymode $Querymode -Info $Info
        if (Test-Path $SharedFile) {
            $Content = Get-Content $SharedFile | ConvertFrom-Json
            Remove-Item $SharedFile
        } else { $Content = $null }
        $Content | ForEach-Object {[PSCustomObject]@{Name = $Basename; Content = $_}}
    }

    $AllPools = $ChildItems | ForEach-Object {if ($_.Content) {$_.Content | Add-Member @{Name = $_.Name} -PassThru}}

    $AllPools | Add-Member LocationPriority 9999

    #Apply filters
    $AllPools2 = @()
    if ($Querymode -eq "Core" -or $Querymode -eq "Menu" ) {
        foreach ($Pool in $AllPools) {
            #must have wallet
            if (-not $Pool.User) {continue}

            # Include pool algos and coins
            if (
                (
                    $PoolConfig.($Pool.PoolName).IncludeAlgos -and
                    @($PoolConfig.($Pool.PoolName).IncludeAlgos -split ',') -notcontains $Pool.Algorithm
                ) -or (
                    $PoolConfig.($Pool.PoolName).IncludeCoins -and
                    @($PoolConfig.($Pool.PoolName).IncludeCoins -split ',') -notcontains $Pool.Info
                )
            ) {
                Write-Log "Excluding $($Pool.Algorithm)/$($Pool.Info) on $($Pool.PoolName) due to Include filter" -Severity Debug
                continue
            }

            # Exclude pool algos and coins
            if (
                @($PoolConfig.($Pool.PoolName).ExcludeAlgos -split ',') -contains $Pool.Algorithm -or
                @($PoolConfig.($Pool.PoolName).ExcludeCoins -split ',') -contains $Pool.Info
            ) {
                Write-Log "Excluding $($Pool.Algorithm)/$($Pool.Info) on $($Pool.PoolName) due to Exclude filter" -Severity Debug
                continue
            }

            #must be in algo filter list or no list
            if ($AlgoFilterList) {$Algofilter = Compare-Object $AlgoFilterList $Pool.Algorithm -IncludeEqual -ExcludeDifferent}
            if ($AlgoFilterList.count -eq 0 -or $Algofilter) {

                #must be in coin filter list or no list
                if ($CoinFilterList) {$CoinFilter = Compare-Object $CoinFilterList $Pool.info -IncludeEqual -ExcludeDifferent}
                if ($CoinFilterList.count -eq 0 -or $CoinFilter) {
                    if ($Pool.Location -eq $Location) {$Pool.LocationPriority = 1}
                    elseif ($Pool.Location -eq 'EU' -and $Location -eq 'US') {$Pool.LocationPriority = 2}
                    elseif ($Pool.Location -eq 'US' -and $Location -eq 'EU') {$Pool.LocationPriority = 2}

                    ## factor actual24h if price differs by factor of 10
                    if ($Pool.Actual24h -gt 0) {
                        $factor = 0.2
                        if ($Pool.Price -gt ($Pool.Actual24h * 10)) {$Pool.Price = $Pool.Price * $factor + $Pool.Actual24h * (1 - $factor)}
                        if ($Pool.Price24h -gt ($Pool.Actual24h * 10)) {$Pool.Price24h = $Pool.Price24h * $factor + $Pool.Actual24h * (1 - $factor)}
                    }
                    ## Apply pool fees and pool factors
                    if ($Pool.Price) {
                        $Pool.Price *= 1 - [double]$Pool.Fee
                        $Pool.Price *= $(if ($PoolConfig.($Pool.PoolName).PoolProfitFactor) {[double]$PoolConfig.($Pool.PoolName).PoolProfitFactor} else {1})
                    }
                    if ($Pool.Price24h) {
                        $Pool.Price24h *= 1 - [double]$Pool.Fee
                        $Pool.Price24h *= $(if ($PoolConfig.($Pool.PoolName).PoolProfitFactor) {[double]$PoolConfig.($Pool.PoolName).PoolProfitFactor} else {1})
                    }
                    $AllPools2 += $Pool
                }
            }
        }
        $Return = $AllPools2
    } else { $Return = $AllPools }

    Remove-variable AllPools
    Remove-variable AllPools2

    $Return
}

# function Get-Config {

#     $Result = @{}
#     switch -regex -file config.ini {
#         "^\s*(\w+)\s*=\s*(.*)" {
#             $name, $value = $matches[1..2]
#             $Result[$name] = $value.Trim()
#         }
#     }
#     $Result # Return Value
# }

# Function Get-ConfigVariable {
#     param(
#         [Parameter(Mandatory = $true)]
#         [string]$VarName
#     )

#     $Result = (Get-Config).$VarName
#     $Result # Return Value
# }

function Get-BestHashRateAlgo {
    param(
        [Parameter(Mandatory = $true)]
        [String]$Algorithm
    )

    $Pattern = "*_" + $Algorithm + "_*_HashRate.csv"

    $BestHashRate = 0

    Get-ChildItem ($PSScriptRoot + "\Stats") -Filter $Pattern -File | ForEach-Object {
        $Content = ($_ | Get-Content | ConvertFrom-Csv )
        $Hrs = 0
        if ($null -ne $Content) {$Hrs = $($Content | Where-Object TimeSinceStartInterval -gt 60 | Measure-Object -property Speed -average).Average}

        if ($Hrs -gt $BestHashRate) {
            $BestHashRate = $Hrs
            $Miner = ($_.pschildname -split '_')[0]
        }
        $Miner = [PSCustomObject]@{
            HashRate = $BestHashRate
            Miner    = $Miner
        }
    }
    $Miner
}

function Set-ConsolePosition ([int]$x, [int]$y) {
    # Get current cursor position and store away
    $position = $host.ui.rawui.cursorposition
    # Store new X Co-ordinate away
    $position.x = $x
    $position.y = $y
    # Place modified location back to $HOST
    $host.ui.rawui.cursorposition = $position
    remove-variable position
}

function Get-ConsolePosition ([ref]$x, [ref]$y) {

    $position = $host.UI.RawUI.CursorPosition
    $x.value = $position.x
    $y.value = $position.y
    remove-variable position
}

function Out-HorizontalLine ([string]$Title) {

    $Width = $Host.UI.RawUI.WindowSize.Width
    if ([string]::IsNullOrEmpty($Title)) {$str = "-" * $Width}
    else {
        $str = ("-" * ($Width / 2 - ($Title.Length / 2) - 4)) + "  " + $Title + "  "
        $str += "-" * ($Width - $str.Length)
    }
    $str | Out-Host
}

function Set-WindowSize ([int]$Width, [int]$Height) {
    #zero not change this axis

    #Buffer must be always greater than windows size

    $BSize = $Host.UI.RawUI.BufferSize
    if ($Width -ne 0 -and $Width -gt $BSize.Width) {$BSize.Width = $Width}
    if ($Height -ne 0 -and $Height -gt $BSize.Height) {$BSize.Width = $Height}

    $Host.UI.RawUI.BufferSize = $BSize

    $WSize = $Host.UI.RawUI.WindowSize
    if ($Width -ne 0) {$WSize.Width = $Width}
    if ($Height -ne 0) {$WSize.Height = $Height}

    $Host.UI.RawUI.WindowSize = $WSize
}

function Get-AlgoUnifiedName ([string]$Algo) {

    $Algo = $Algo -ireplace '[^\w]'
    if ($Algo) {
        $Algos = Get-Content -Path ".\Includes\algorithms.json" | ConvertFrom-Json
        if ($Algos.$Algo) { $Algos.$Algo }
        else { $Algo }
    }
}

function Get-CoinUnifiedName ([string]$Coin) {

    if ($Coin) {
        $Coin = $Coin.Trim() -replace '[\s_]', '-'
        switch -wildcard ($Coin) {
            "Aur-*" { "Aurora" }
            "Auroracoin-*" { "Aurora" }
            "Bitcoin-*" { $_ -replace '-' }
            "Dgb-*" { "Digibyte" }
            "Digibyte-*" { "Digibyte" }
            "Ethereum-Classic" { "EthereumClassic" }
            "Haven-Protocol" { "Haven" }
            "Myriad-*" { "Myriad" }
            "Myriadcoin-*" { "Myriad" }
            "Shield-*" { "Verge" }
            "Verge-*" { "Verge" }
            Default { $Coin }
        }
    }
}

function Get-HashRates {
    param(
        [Parameter(Mandatory = $true)]
        [String]$Algorithm,
        [Parameter(Mandatory = $true)]
        [String]$MinerName,
        [Parameter(Mandatory = $true)]
        [String]$GroupName,
        [Parameter(Mandatory = $true)]
        [String]$Powerlimit,
        [Parameter(Mandatory = $false)]
        [String]$AlgoLabel
    )

    if ($AlgoLabel -eq "") {$AlgoLabel = 'X'}
    $Pattern = $PSScriptRoot + "\Stats\" + $MinerName + "_" + $Algorithm + "_" + $GroupName + "_" + $AlgoLabel + "_PL" + $PowerLimit + "_HashRate"

    if (-not (Test-Path -path "$Pattern.csv")) {
        if (Test-Path -path "$Pattern.txt") {
            $Content = (Get-Content -path "$Pattern.txt")
            try {$Content = $Content | ConvertFrom-Json} catch {
            } finally {
                if ($Content) {$Content | ConvertTo-Csv | Set-Content -Path "$Pattern.csv"}
                Remove-Item -path "$Pattern.txt"
            }
        }
    } else {
        $Content = (Get-Content -path "$Pattern.csv")
        try {$Content = $Content | ConvertFrom-Csv} catch {
            #if error from convert from json delete file
            Write-Log "Corrupted file $Pattern.csv, deleting" -Severity Warn
            Remove-Item -path "$Pattern.csv"
        }
    }

    if ($null -eq $Content) {$Content = @()}
    $Content
}

function Set-HashRates {
    param(
        [Parameter(Mandatory = $true)]
        [String]$Algorithm,
        [Parameter(Mandatory = $true)]
        [String]$MinerName,
        [Parameter(Mandatory = $true)]
        [String]$GroupName,
        [Parameter(Mandatory = $false)]
        [String]$AlgoLabel,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Value,
        [Parameter(Mandatory = $true)]
        [String]$Powerlimit
    )

    if ($AlgoLabel -eq "") {$AlgoLabel = 'X'}

    $Path = $PSScriptRoot + "\Stats\" + $MinerName + "_" + $Algorithm + "_" + $GroupName + "_" + $AlgoLabel + "_PL" + $PowerLimit + "_HashRate.csv"

    $Value | ConvertTo-Csv | Set-Content -Path $Path
}

function Get-Stats {
    param(
        [Parameter(Mandatory = $true)]
        [String]$Algorithm,
        [Parameter(Mandatory = $true)]
        [String]$MinerName,
        [Parameter(Mandatory = $true)]
        [String]$GroupName,
        [Parameter(Mandatory = $true)]
        [String]$Powerlimit,
        [Parameter(Mandatory = $false)]
        [String]$AlgoLabel
    )

    if ($AlgoLabel -eq "") {$AlgoLabel = 'X'}
    $Pattern = $PSScriptRoot + "\Stats\" + $MinerName + "_" + $Algorithm + "_" + $GroupName + "_" + $AlgoLabel + "_PL" + $PowerLimit + "_stats"

    if (-not (Test-Path -path "$Pattern.json")) {
        if (Test-Path -path "$Pattern.txt") {Rename-Item -Path "$Pattern.txt" -NewName "$Pattern.json"}
    } else {
        $Content = (Get-Content -path "$Pattern.json")
        try {$Content = $Content | ConvertFrom-Json} catch {
            #if error from convert from json delete file
            Write-Log "Corrupted file $Pattern.json, deleting" -Severity Warn
            Remove-Item -path "$Pattern.json"
        }
    }
    $Content
}
# function Get-AllStats {
#     $Stats = @()
#     if (-not (Test-Path "Stats")) {New-Item "Stats" -ItemType "directory" | Out-Null}
#     Get-ChildItem "Stats" -Filter "*_stats.json" | Foreach-Object {
#         $Name = $_.BaseName
#         $_ | Get-Content | ConvertFrom-Json | ForEach-Object {
#             $Values = $Name -split '_'
#             $Stats += @{
#                 MinerName  = $Values[0]
#                 Algorithm  = $Values[1]
#                 GroupName  = $Values[2]
#                 AlgoLabel  = $Values[3]
#                 PowerLimit = ($Values[4] -split 'PL')[-1]
#                 Stats      = $_
#             }
#         }
#     }
#     Return $Stats
# }


function Set-Stats {
    param(
        [Parameter(Mandatory = $true)]
        [String]$Algorithm,
        [Parameter(Mandatory = $true)]
        [String]$MinerName,
        [Parameter(Mandatory = $true)]
        [String]$GroupName,
        [Parameter(Mandatory = $false)]
        [String]$AlgoLabel,
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$value,
        [Parameter(Mandatory = $true)]
        [String]$Powerlimit
    )

    if ($AlgoLabel -eq "") {$AlgoLabel = 'X'}

    $Path = $PSScriptRoot + "\Stats\" + $MinerName + "_" + $Algorithm + "_" + $GroupName + "_" + $AlgoLabel + "_PL" + $PowerLimit + "_stats.json"

    $Value | ConvertTo-Json | Set-Content -Path $Path
}

function Start-Downloader {
    param(
        [Parameter(Mandatory = $true)]
        [String]$URI,
        [Parameter(Mandatory = $true)]
        [String]$ExtractionPath,
        [Parameter(Mandatory = $true)]
        [String]$Path,
        [Parameter(Mandatory = $false)]
        [String]$SHA256
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        try {
            if ($URI -and (Split-Path $URI -Leaf) -eq (Split-Path $Path -Leaf)) {
                # downloading a single file
                $null = New-Item (Split-Path $Path) -ItemType "Directory"
                (New-Object System.Net.WebClient).DownloadFile($URI, $Path)
                if ($SHA256 -and (Get-FileHash -Path $Path -Algorithm SHA256).Hash -ne $SHA256) {
                    Write-Log "File hash doesn't match. Removing file." -Severity Warn
                    Remove-Item $Path
                }
            } else {
                # downloading an archive or installer
                Write-Log "Downloading $URI" -Severity Info
                Expand-WebRequest -URI $URI -Path $ExtractionPath -SHA256 $SHA256 -ErrorAction Stop
            }
        } catch {
            $Message = "Cannot download $URI"
            Write-Log $Message -Severity Warn
        }
    }
}

function Clear-Files {

    $Now = Get-Date
    $Days = "3"

    $TargetFolder = ".\Logs"
    $Extension = "*.log"
    $LastWrite = $Now.AddDays( - $Days)
    $Files = Get-Childitem $TargetFolder -Include $Extension -Exclude "empty.txt" -File -Recurse | Where-Object {$_.LastWriteTime -le "$LastWrite"}
    $Files | ForEach-Object {Remove-Item $_.fullname}

    $TargetFolder = "."
    $Extension = "wrapper_*.txt"
    $Files = Get-Childitem $TargetFolder -Include $Extension -File -Recurse
    $Files | ForEach-Object {Remove-Item $_.fullname}

    $TargetFolder = "."
    $Extension = "*.tmp"
    $Files = Get-Childitem $TargetFolder -Include $Extension -File -Recurse
    $Files | ForEach-Object {Remove-Item $_.fullname}

    $TargetFolder = ".\Cache"
    $Extension = "*.json"
    $LastWrite = $Now.AddDays( - $Days)
    $Files = Get-Childitem $TargetFolder -Include $Extension -Exclude "empty.txt" -File -Recurse | Where-Object {$_.LastWriteTime -le "$LastWrite"}
    $Files | ForEach-Object {Remove-Item $_.fullname}
}

function Get-CoinSymbol ([string]$Coin) {

    switch -wildcard ($Coin) {
        "adzcoin" { "ADZ" }
        "auroracoin" { "AUR" }
        "bitcoin" { "BTC" }
        "bitcoincash" { "BCH" }
        "bitcoingold" { "BTG" }
        "bitcoinz" { "BTCZ" }
        "dash" { "DASH" }
        "decred" { "DCR" }
        "digibyte" { "DGB" }
        "electroneum" { "ETN" }
        "ethereum" { "ETH" }
        "ethereumclassic" { "ETC" }
        "expanse" { "EXP" }
        "feathercoin" { "FTC" }
        "gamecredits" { "GAME" }
        "geocoin" { "GEO" }
        "globalboosty" { "BSTY" }
        "groestlcoin" { "GRS" }
        "litecoin" { "LTC" }
        "litecoinz" { "LTZ" }
        "maxcoin" { "MAX" }
        "minex" { "MNX" }
        "monacoin" { "MONA" }
        "monero" { "XMR" }
        "musicoin" { "MUSIC" }
        "myriad" { "XMY" }
        "pascal" { "PASC" }
        "polytimos" { "POLY" }
        "safecoin" { "SAFE" }
        "sexcoin" { "SXC" }
        "siacoin" { "SC" }
        "snowgem" { "XSG" }
        "startcoin" { "START" }
        "verge" { "XVG" }
        "vertcoin" { "VTC" }
        "zcash" { "ZEC" }
        "zclassic" { "ZCL" }
        "zcoin" { "XZC" }
        "zencash" { "ZEN" }
        "zero" { "ZER" }
        Default { $Coin }
    }
}

# function Get-EquihashCoinPers {
#     [CmdletBinding()]
#     param(
#         [Parameter(Mandatory = $false)]
#         [String]$Coin = "",
#         [Parameter(Mandatory = $false)]
#         [String]$Default = "auto"
#     )
#     $Coins = Get-Content .\Includes\equihashcoins.json | ConvertFrom-Json
#     if ($Coin -and $Coins.ContainsKey($Coin)) {
#         $Coins[$Coin]
#     } else {
#         $Default
#     }
# }

function Test-DeviceGroupsConfig ($Types) {
    $Devices = Get-DevicesInformation $Types
    $Types | Where-Object Type -ne 'CPU' | ForEach-Object {
        $DetectedDevices = @()
        $DetectedDevices += $Devices | Where-Object Group -eq $_.GroupName
        if ($DetectedDevices.count -eq 0) {
            Write-Log "No Devices for group " + $_.GroupName + " was detected, activity based watchdog will be disabled for that group, this can happens if AMD beta blockchain drivers are installed or incorrect gpugroups config" -Severity Warn
            Start-Sleep -Seconds 5
        } elseif ($DetectedDevices.count -ne $_.DevicesCount) {
            Write-Log "Mismatching Devices for group " + $_.GroupName + " was detected, check gpugroups config and gpulist.bat" -Severity Warn
            Start-Sleep -Seconds 5
        }
    }
    $TotalMem = (($Types | Where-Object Type -ne 'CPU').OCLDevices.GlobalMemSize | Measure-Object -Sum).Sum / 1GB
    $TotalSwap = (Get-CimInstance Win32_PageFile | Select-Object -ExpandProperty FileSize | Measure-Object -Sum).Sum / 1GB
    if ($TotalMem -gt $TotalSwap) {
        Write-Log "Make sure you have at least $TotalMem GB swap configured" -Severity Warn
        Start-Sleep -Seconds 5
    }
}

function Start-Autoexec {
    [cmdletbinding()]
    param(
        [ValidateRange(-2, 3)]
        [Parameter(Mandatory = $false)]
        [Int]$Priority = 0
    )
    if (-not (Test-Path ".\Config\autoexec.txt") -and (Test-Path ".\Data\autoexec.default.txt")) {Copy-Item ".\Data\autoexec.default.txt" ".\Config\autoexec.txt" -Force -ErrorAction Ignore}
    [System.Collections.ArrayList]$Script:AutoexecCommands = @()
    foreach ($cmd in @(Get-Content ".\Config\autoexec.txt" -ErrorAction Ignore | Select-Object)) {
        if ($cmd -match "^[\s\t]*`"(.+?)`"(.*)$") {
            try {
                $Job = Start-SubProcess -FilePath "$($Matches[1])" -ArgumentList "$($Matches[2].Trim())" -WorkingDirectory (Split-Path "$($Matches[1])") -Priority $Priority
                if ($Job) {
                    $Job | Add-Member FilePath "$($Matches[1])" -Force
                    $Job | Add-Member Arguments "$($Matches[2].Trim())" -Force
                    $Job | Add-Member HasOwnMinerWindow $true -Force
                    Write-Log "Autoexec command started: $($Matches[1]) $($Matches[2].Trim())"
                    $Script:AutoexecCommands.Add($Job) >$null
                }
            } catch {}
        }
    }
}

function Stop-Autoexec {
    $Script:AutoexecCommands | Where-Object Process | Foreach-Object {
        Stop-SubProcess -Job $_ -Title "Autoexec command" -Name "$($_.FilePath) $($_.Arguments)"
    }
}