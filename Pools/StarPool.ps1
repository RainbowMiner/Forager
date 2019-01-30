﻿param(
    [Parameter(Mandatory = $true)]
    [String]$Querymode = $null,
    [Parameter(Mandatory = $false)]
    [PSCustomObject]$Info
)

#. .\..\Include.ps1

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName
$ActiveOnManualMode = $true
$ActiveOnAutomaticMode = $true
$ActiveOnAutomatic24hMode = $true
$WalletMode = 'Wallet'
$ApiUrl = 'https://www.starpool.biz/api'
$MineUrl = 'starpool.biz'
$Location = 'EU'
$RewardType = "PPS"
$Result = @()

if ($Querymode -eq "Info") {
    $Result = [PSCustomObject]@{
        Disclaimer               = "Autoexchange to BTC/LTC/DASH/CANN/DGB, No registration"
        ActiveOnManualMode       = $ActiveOnManualMode
        ActiveOnAutomaticMode    = $ActiveOnAutomaticMode
        ActiveOnAutomatic24hMode = $ActiveOnAutomatic24hMode
        ApiData                  = $True
        WalletMode               = $WalletMode
        RewardType               = $RewardType
    }
}

if ($Querymode -eq "Speed") {
    $Request = Invoke-APIRequest -Url $($ApiUrl + "/walletEx?address=" + $Info.user) -Retry 1

    if ($Request) {
        $Result = $Request.Miners | ForEach-Object {
            [PSCustomObject]@{
                PoolName   = $Name
                Version    = $_.version
                Algorithm  = Get-AlgoUnifiedName $_.Algo
                WorkerName = (($_.password -split 'id=')[1] -split ',')[0]
                Diff       = $_.difficulty
                Rejected   = $_.rejected
                HashRate   = $_.accepted
            }
        }
        Remove-Variable Request
    }
}

if ($Querymode -eq "Wallet") {
    $Request = Invoke-APIRequest -Url $($ApiUrl + "/wallet?address=" + $Info.user) -Retry 3

    if ($Request) {
        $Result = [PSCustomObject]@{
            Pool     = $Name
            Currency = $Request.currency
            Balance  = $Request.balance
        }
        Remove-Variable Request
    }
}

if (($Querymode -eq "Core" ) -or ($Querymode -eq "Menu")) {
    $Request = Invoke-APIRequest -Url $($ApiUrl + "/status") -Retry 3
    $RequestCurrencies = Invoke-APIRequest -Url $($ApiUrl + "/currencies") -Retry 3
    if (-not $Request) {
        Write-Warning "$Name API NOT RESPONDING...ABORTING"
        Exit
    }

    $Currency = if ($PoolConfig.$Name.Currency) {$PoolConfig.$Name.Currency} else {$Config.Currency}

    if (
        @('BTC', 'LTC', 'DASH', 'CANN', 'DGB') -notcontains $Currency -and
        -not ( $RequestCurrencies -and ($RequestCurrencies | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object { $_ -eq $Currency }))
    ) {
        Write-Warning "$Name $Currency may not be supported for payment"
    }

    if (-not $Wallets.$Currency) {
        Write-Warning "$Name $Currency wallet not defined"
        Exit
    }

    $Request | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object {
        $Request.$_.HashRate -gt 0
    } | ForEach-Object {

        $Algo = $Request.$_
        $Pool_Algo = Get-AlgoUnifiedName $Algo.name

        $Divisor = 1000000 * $Algo.mbtc_mh_factor

        $Result += [PSCustomObject]@{
            Algorithm             = $Pool_Algo
            Info                  = $Pool_Algo
            Price                 = [decimal]$Algo.estimate_current / $Divisor
            Price24h              = [decimal]$Algo.estimate_last24h / $Divisor
            Actual24h             = [decimal]$Algo.actual_last24h / 1000 / $Divisor
            Protocol              = "stratum+tcp"
            Host                  = $Algo.name + '.' + $MineUrl
            Port                  = $Algo.port
            User                  = $Wallets.$Currency
            Pass                  = "c=$Currency,id=#WorkerName#"
            Location              = $Location
            SSL                   = $false
            Symbol                = Get-CoinSymbol -Coin $Pool_Algo
            ActiveOnManualMode    = $ActiveOnManualMode
            ActiveOnAutomaticMode = $ActiveOnAutomaticMode
            PoolWorkers           = $Algo.workers
            PoolHashRate          = $Algo.HashRate
            WalletMode            = $WalletMode
            WalletSymbol          = $Currency
            PoolName              = $Name
            Fee                   = $Algo.fees / 100
            RewardType            = $RewardType
        }
    }
    Remove-Variable Request
}

$Result | ConvertTo-Json | Set-Content $Info.SharedFile
Remove-Variable Result
