param(
    [Parameter(Mandatory = $true)]
    [String]$Querymode = $null,
    [Parameter(Mandatory = $false)]
    [PSCustomObject]$Info
)

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName
$ActiveOnManualMode = $true
$ActiveOnAutomaticMode = $false
$WalletMode = "None"
$RewardType = "PPLS"
$Result = @()

if ($Querymode -eq "Info") {
    $Result = [PSCustomObject]@{
        Disclaimer            = "Must set wallet for each coin on web, set login on config.ini file"
        ActiveOnManualMode    = $ActiveOnManualMode
        ActiveOnAutomaticMode = $ActiveOnAutomaticMode
        ApiData               = $true
        WalletMode            = $WalletMode
        RewardType            = $RewardType
    }
}

if (($Querymode -eq "Core" ) -or ($Querymode -eq "Menu")) {
    $Pools = @()

    # $Pools += [PSCustomObject]@{coin = "HPPcoin"; algo = "Lyra2h"; symbol = "HPP"; server = "pool.hppcoin.com"; port = 3008; fee = 0.02; user = "$UserName.#WorkerName#"}
    # $Pools += [PSCustomObject]@{coin = "HPPcoin"; algo = "Lyra2h"; symbol = "HPP"; server = "pool.hppcoin.com"; port = 3008; fee = 0.02; user = "$UserName.#WorkerName#"}
    $Pools += [PSCustomObject]@{coin = "Dallar"; algo = "Throestl"; symbol = "DAL"; server = "pool.dallar.org"; port = 3032; fee = 0.01; user = $Wallets.DAL}
    $Pools += [PSCustomObject]@{coin = "Pascalcoin"; algo = "RandomHash"; symbol = "PASC"; server = "mine.pool.pascalpool.org"; port = 3333; fee = 0.01; user = $Wallets.PASC}

    $Pools | ForEach-Object {
        $Result += [PSCustomObject]@{
            Algorithm             = $_.Algo
            Info                  = $_.Coin
            Protocol              = "stratum+tcp"
            Host                  = $_.Server
            Port                  = $_.Port
            User                  = $_.User
            Pass                  = if ([string]::IsNullOrEmpty($_.Pass)) {"x"} else {$_.Pass}
            Location              = "EU"
            SSL                   = $false
            Symbol                = $_.symbol
            ActiveOnManualMode    = $ActiveOnManualMode
            ActiveOnAutomaticMode = $ActiveOnAutomaticMode
            PoolName              = $Name
            WalletMode            = $WalletMode
            Fee                   = $_.Fee
            RewardType            = $RewardType
        }
    }
    Remove-Variable Pools
}

$Result | ConvertTo-Json | Set-Content $Info.SharedFile
Remove-Variable result
