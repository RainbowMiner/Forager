@echo off

REM powershell -version 5.0 -executionpolicy bypass -command "&.\DeviceList.ps1
pwsh -noexit -executionpolicy bypass -command "&.\DeviceList.ps1

pause
