Import-Module .\Include.psm1

$global:Config = Get-Content .\Config\config.json | ConvertFrom-Json
if ($Config.Afterburner) {
    . .\Includes\Afterburner.ps1
}
Out-DevicesInformation (Get-DevicesInformation (Get-MiningTypes -All))

$Groups = Get-MiningTypes -All | Where-Object Type -ne 'CPU' | Select-Object GroupName,Type,Devices,@{Name = 'PowerLimits'; Expression = {$_.PowerLimits -join ','}} | ConvertTo-Json -Compress

Write-Host "Suggested GpuGroups string:"
Write-Host "GpuGroups = $Groups" -ForegroundColor Yellow
