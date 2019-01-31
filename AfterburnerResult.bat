@echo off
cd /d %~dp0

REM powershell -version 5.0 -executionpolicy bypass -command "&.\AfterburnerResult.ps1
pwsh -noexit -executionpolicy bypass -command "&.\AfterburnerResult.ps1

pause
