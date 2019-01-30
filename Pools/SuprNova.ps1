param(
    [Parameter(Mandatory = $false)]
    [String]$Querymode = $null,
    [Parameter(Mandatory = $false)]
    [PSCustomObject]$Info
)

$Name = (Get-Item $script:MyInvocation.MyCommand.Path).BaseName
$ActiveOnManualMode = $true
$ActiveOnAutomaticMode = $false
$ActiveOnAutomatic24hMode = $false
$WalletMode = "ApiKey"
$RewardType = "PPLS"
$Result = @()

if ($Querymode -eq "Info") {
    $Result = [PSCustomObject]@{
        Disclaimer               = "Must register and set wallet for each coin on web"
        ActiveOnManualMode       = $ActiveOnManualMode
        ActiveOnAutomaticMode    = $ActiveOnAutomaticMode
        ActiveOnAutomatic24hMode = $ActiveOnAutomatic24hMode
        ApiData                  = $true
        WalletMode               = $WalletMode
        RewardType               = $RewardType
    }
}

if ($Querymode -eq "ApiKey") {
    $Request = Invoke-APIRequest -Url $("https://" + $Info.Symbol + ".suprnova.cc/index.php?page=api&action=getuserbalance&api_key=" + $Info.ApiKey + "&id=") -Retry 3 |
        Select-Object -ExpandProperty getuserbalance | Select-Object -ExpandProperty data

    if ($Request) {
        $Result = [PSCustomObject]@{
            Pool     = $name
            Currency = $Info.Symbol
            Balance  = $Request.confirmed + $Request.unconfirmed
        }
    }
}

if ($Querymode -eq "Speed") {
    $Request = Invoke-APIRequest -Url $("https://" + $Info.Symbol + ".suprnova.cc/index.php?page=api&action=getuserworkers&api_key=" + $Info.ApiKey) -Retry 1 |
        Select-Object -ExpandProperty getuserworkers | Select-Object -ExpandProperty data

    if ($Request) {
        $Request | ForEach-Object {
            $Result += [PSCustomObject]@{
                PoolName   = $name
                Diff       = $_.difficulty
                WorkerName = ($_.UserName -split "\.")[1]
                HashRate   = $_.HashRate
            }
        }
    }
}

if (($Querymode -eq "Core" ) -or ($Querymode -eq "Menu")) {

    if (-not $Config.UserName -and -not $PoolConfig.$Name.UserName) {
        Write-Warning "$Name UserName not defined"
        Exit
    }

    $Pools = @()
    $Pools += [PSCustomObject]@{coin = "ANONCoin"; algo = "Equihash144"; symbol = "ANON"; server = "anon.suprnova.cc"; port = 7060; location = "US"};
    $Pools += [PSCustomObject]@{coin = "BitcoinGold"; algo = "Equihash144"; symbol = "BTG"; server = "btg.suprnova.cc"; port = 8866; location = "US"; portSSL = 8817};
    $Pools += [PSCustomObject]@{coin = "BitcoinInterest"; algo = "ProgPOW"; symbol = "BCI"; server = "bci.suprnova.cc"; port = 9166; location = "US"; portSSL = 8168};
    $Pools += [PSCustomObject]@{coin = "BitcoinZ"; algo = "Equihash144"; symbol = "BTCZ"; server = "btcz.suprnova.cc"; port = 6586; location = "US"};
    $Pools += [PSCustomObject]@{coin = "BitCore"; algo = "Bitcore"; symbol = "BTX"; server = "btx.suprnova.cc"; port = 3629; location = "US"};
    $Pools += [PSCustomObject]@{coin = "BitSend"; algo = "Xevan"; symbol = "BSD"; server = "bsd.suprnova.cc"; port = 8686; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Credits"; algo = "Argon2d250"; symbol = "CRDS"; server = "crds.suprnova.cc"; port = 2771; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Criptoreal"; algo = "Lyra2Z"; symbol = "CRS"; server = "crs.suprnova.cc"; port = 4155; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Dynamic"; algo = "Argon2d500"; symbol = "DYN"; server = "dyn.suprnova.cc"; port = 5960; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Ethereum"; algo = "Ethash"; symbol = "ETH"; server = "eth.suprnova.cc"; port = 5000; location = "US"};
    $Pools += [PSCustomObject]@{coin = "EuropeCoin"; algo = "HOdl"; symbol = "ERC"; server = "erc.suprnova.cc"; port = 7674; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Garlicoin"; algo = "Allium"; symbol = "GRLC"; server = "grlc.suprnova.cc"; port = 8600; location = "US"};
    $Pools += [PSCustomObject]@{coin = "GenX"; algo = "Equihash192"; symbol = "GENX"; server = "genx.suprnova.cc"; port = 9983; location = "US"};
    $Pools += [PSCustomObject]@{coin = "HODLcoin"; algo = "HOdl"; symbol = "HODL"; server = "hodl.suprnova.cc"; port = 4693; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Kreds"; algo = "Lyra2v2"; symbol = "KREDS"; server = "kreds.suprnova.cc"; port = 7196; location = "US"};
    $Pools += [PSCustomObject]@{coin = "MonaCoin"; algo = "Lyra2v2"; symbol = "MONA"; server = "mona.suprnova.cc"; port = 2995; location = "US"; portSSL = 3001; SSL = $true};
    $Pools += [PSCustomObject]@{coin = "MUNCoin"; algo = "Skunk"; symbol = "MUN"; server = "mun.suprnova.cc"; port = 8963; location = "US"};
    $Pools += [pscustomobject]@{coin = "NixPlatform"; algo = "Lyra2v2"; symbol = "NIX"; server = "nix.suprnova.cc"; port = 4930; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Pigeon"; algo = "X16s"; symbol = "PGN"; server = "pign.suprnova.cc"; port = 4096; location = "US"; walletSymbol = "PIGN"};
    $Pools += [PSCustomObject]@{coin = "Polytimos"; algo = "Polytimos"; symbol = "POLY"; server = "poly.suprnova.cc"; port = 7935; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Race"; algo = "Lyra2v2"; symbol = "RACE"; server = "race.suprnova.cc"; port = 5650; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Raven"; algo = "X16r"; symbol = "RVN"; server = "rvn.suprnova.cc"; port = 6666; location = "US"};
    $Pools += [PSCustomObject]@{coin = "ROIcoin"; algo = "HOdl"; symbol = "ROI"; server = "roi.suprnova.cc"; port = 4699; location = "US"};
    $Pools += [PSCustomObject]@{coin = "SafeCash"; algo = "Equihash144"; symbol = "SCASH"; server = "scash.suprnova.cc"; port = 8983; location = "US"};
    $Pools += [PSCustomObject]@{coin = "SafeCoin"; algo = "Equihash144"; symbol = "SAFE"; server = "safe.suprnova.cc"; port = 3131; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Straks"; algo = "Lyra2v2"; symbol = "STAK"; server = "stak.suprnova.cc"; port = 7706; location = "US"; portSSL = 7710; SSL = $true};
    $Pools += [PSCustomObject]@{coin = "UBIQ"; algo = "Ethash"; symbol = "UBQ"; server = "ubiq.suprnova.cc"; port = 3030; location = "US"; walletSymbol = "UBIQ"};
    $Pools += [pscustomobject]@{coin = "Veil"; algo = "X16rt"; symbol = "VEIL"; server = "veil.suprnova.cc"; port = 7220; location = "US"};
    $Pools += [pscustomobject]@{coin = "Verge"; algo = "Lyra2v2"; symbol = "XVG"; server = "xvg-lyra.suprnova.cc"; port = 2595; location = "US"; walletSymbol = "XVG-LYRA"};
    $Pools += [pscustomobject]@{coin = "Verge"; algo = "X17"; symbol = "XVG"; server = "xvg-x17.suprnova.cc"; port = 7477; location = "US"; walletSymbol = "XVG-17"};
    $Pools += [PSCustomObject]@{coin = "Vertcoin"; algo = "Lyra2v2"; symbol = "VTC"; server = "vtc.suprnova.cc"; port = 5678; location = "US"; portSSL = 5676; SSL = $true};
    $Pools += [PSCustomObject]@{coin = "XDNA"; algo = "Hex"; symbol = "XDNA"; server = "xdna.suprnova.cc"; port = 4919; location = "US"};
    $Pools += [PSCustomObject]@{coin = "Zero"; algo = "Equihash192"; symbol = "ZER"; server = "zero.suprnova.cc"; port = 6568; location = "US"; walletSymbol = "ZERO"};

    $Pools | ForEach-Object {

        $Result += [PSCustomObject]@{
            Algorithm             = $_.Algo
            Info                  = $_.Coin
            Protocol              = "stratum+tcp"
            ProtocolSSL           = $(if ($_.Algo -eq "Lyra2v2") {"stratum+tls"} else {"ssl"})
            Host                  = $_.server
            HostSSL               = $(if (-not $_.serverSSL) {$_.serverSSL} else {$_.server})
            Port                  = $_.Port
            PortSSL               = $_.PortSSL
            User                  = $(if ($PoolConfig.$Name.UserName) {$PoolConfig.$Name.UserName} else {$Config.UserName}) + ".#WorkerName#"
            Pass                  = "x"
            Location              = $_.Location
            SSL                   = [bool]$_.SSL
            Symbol                = $_.symbol
            ActiveOnManualMode    = $ActiveOnManualMode
            ActiveOnAutomaticMode = $ActiveOnAutomaticMode
            PoolName              = $Name
            WalletMode            = $WalletMode
            WalletSymbol          = if ($_.WalletSymbol) {$_.WalletSymbol} else {$_.Symbol}
            Fee                   = 0.01
            EthStMode             = 3
            RewardType            = $RewardType
        }
    }
    Remove-Variable Pools
}

$Result | ConvertTo-Json | Set-Content $Info.SharedFile
Remove-Variable Result
