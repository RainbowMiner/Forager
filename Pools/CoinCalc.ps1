<#
THIS IS A ADVANCED POOL.

THIS IS A VIRTUAL POOL, STATISTICS ARE TAKEN FROM CoinCalculators.io AND RECALCULATED WITH YOUR BENCHMARKS HashRate,
YOU CAN SET DESTINATION POOL YOU WANT FOR EACH COIN, BUT REMEMBER YOU MUST HAVE AN ACOUNT IF DESTINATION POOL IS NOT ANONYMOUS
#>

param(
    [Parameter(Mandatory = $true)]
    [String]$Querymode = $null,
    [Parameter(Mandatory = $false)]
    [PSCustomObject]$Info
)

# . .\..\Include.ps1

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName
$ActiveOnManualMode = $true
$ActiveOnAutomaticMode = $true
$ActiveOnAutomatic24hMode = $true
$WalletMode = "Mixed"
$RewardType = "PPS"
$Result = @()

if ($Querymode -eq "Info") {
    $Result = [PSCustomObject]@{
        Disclaimer               = "Based on CoinCalculators statistics, you must have accounts and wallets for each coin"
        ActiveOnManualMode       = $ActiveOnManualMode
        ActiveOnAutomaticMode    = $ActiveOnAutomaticMode
        ActiveOnAutomatic24hMode = $ActiveOnAutomatic24hMode
        ApiData                  = $true
        WalletMode               = $WalletMode
        RewardType               = $RewardType
    }
}

if (($Querymode -eq "Speed")) {
    if ($PoolRealName -ne $null) {
        $Info.PoolName = $PoolRealName
        $Result = Get-Pools -Querymode "Speed" -PoolsFilterList $Info.PoolName -Info $Info
    }
}

if (($Querymode -eq "Wallet") -or ($Querymode -eq "ApiKey")) {
    if ($PoolRealName -ne $null) {
        $Info.PoolName = $PoolRealName
        $Result = Get-Pools -Querymode $info.WalletMode -PoolsFilterList $Info.PoolName -Info $Info | select-object Pool, Currency, Balance
    }
}

if (@("Core", "Menu") -contains $Querymode) {

    #Look for pools
    $ConfigOrder = $PoolConfig.$Name.PoolOrder -split ','
    $Pools = foreach ($PoolToSearch in $ConfigOrder) {
        $PoolsTmp = Get-Pools -Querymode "Core" -PoolsFilterList $PoolToSearch -location $Info.Location
        #Filter by minworkes variable (must be here for not selecting now a pool and after that discarded on core.ps1 filter)
        $PoolsTmp | Where-Object {
            $_.PoolWorkers -eq $null -or
            $_.PoolWorkers -ge $(if ($PoolConfig.$PoolToSearch.MinWorkers) {$PoolConfig.$PoolToSearch.MinWorkers} else {$Config.MinWorkers})
        }
    }

    $Url = "https://www.coincalculators.io/api/allcoins.aspx?hashrate=1000&difficultytime=0"
    # $Response = Get-Content .\WIP\CoinCalculators.json | ConvertFrom-Json
    $Response = Invoke-APIRequest -Url $Url -Age 10     ### Requests limited to 500 per day from a single IP
    if (-not $Response) {
        Write-Warning "$Name API NOT RESPONDING...ABORTING"
        Exit
    }
    foreach ($Coin in $Response) {
        $Coin.Name = Get-CoinUnifiedName $Coin.Name

        # Algo fixes
        switch ($Coin.Algorithm) {
            'WildKeccak' {$Coin.Algorithm += $Coin.Symbol }
            'Argon2d' {$Coin.Algorithm += $Coin.Symbol }
        }
        $Coin.Algorithm = Get-AlgoUnifiedName $Coin.Algorithm
    }

    #join pools and coins
    ForEach ($Pool in $Pools) {

        $Pool.Algorithm = Get-AlgoUnifiedName $Pool.Algorithm
        $Pool.Info = Get-CoinUnifiedName $Pool.Info

        if (($Result | Where-Object {$_.Info -eq $Pool.Info -and $_.Algorithm -eq $Pool.Algorithm}).count -eq 0) {
            #look that this coin is not included in result

            $Response | Where-Object {$_.Name -eq $Pool.Info -and $_.Algorithm -eq $Pool.Algorithm} | ForEach-Object {
                $Result += [PSCustomObject]@{
                    Info                  = $Pool.Info
                    Algorithm             = $Pool.Algorithm
                    Price                 = [decimal]($_.rewardsInDay * $_.price_btc / $_.yourHashrate)
                    Price24h              = [decimal]($_.rewardsInDay * $_.price_btc / $_.currentDifficulty * $_.difficulty24 / $_.yourHashrate)
                    Symbol                = $_.Symbol
                    Host                  = $Pool.Host
                    HostSSL               = $Pool.HostSSL
                    Port                  = $Pool.Port
                    PortSSL               = $Pool.PortSSL
                    Location              = $Pool.Location
                    SSL                   = $Pool.SSL
                    Fee                   = $Pool.Fee
                    User                  = $Pool.User
                    Pass                  = $Pool.Pass
                    Protocol              = $Pool.Protocol
                    ProtocolSSL           = $Pool.ProtocolSSL
                    WalletMode            = $Pool.WalletMode
                    EthStMode             = $Pool.EthStMode
                    WalletSymbol          = $Pool.WalletSymbol
                    PoolName              = $Pool.PoolName
                    PoolWorkers           = $Pool.PoolWorkers
                    PoolHashRate          = $Pool.PoolHashRate
                    RewardType            = $Pool.RewardType
                    ActiveOnManualMode    = $ActiveOnManualMode
                    ActiveOnAutomaticMode = $ActiveOnAutomaticMode
                }
            }
        }
    } #end foreach pool
    Remove-Variable Pools
}

$Result | ConvertTo-Json | Set-Content $Info.SharedFile
Remove-Variable Result
