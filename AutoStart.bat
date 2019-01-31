@echo off

cd /d %~dp0

set Mode=Automatic
set Pools=NiceHash,Zpool,BlockMasters,NLPool,ZergPool,WhatToMine,CoinCalc,Custom

REM powershell -version 5.0 -noexit -executionpolicy bypass -command "& .\Core.ps1 -MiningMode %Mode% -PoolsName %Pools%"
pwsh -noexit -executionpolicy bypass -command "& .\Core.ps1 -MiningMode %Mode% -PoolsName %Pools%"

pause
