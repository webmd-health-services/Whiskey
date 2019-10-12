[CmdletBinding()]
param(
)

#Requires -Version 4
Set-StrictMode -Version 'Latest'

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Modules\Pester')

Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath ('Test\*.Tests.ps1')) |
    ForEach-Object {
        $startedAt = Get-Date
        $outputXmlPath = Join-Path -Path $PSScriptRoot -ChildPath ('.output\pester+{0}.xml' -f $_.Name)
        Invoke-Pester -Script $_.FullName -OutputFile $outputXmlPath -OutputFormat NUnitXml
        $duration = (Get-Date) - $startedAt

        $pesterXml = [xml](Get-Content -Raw -Path $outputXmlPath)
        $pesterDuration = [timespan]::FromSeconds( $pesterXml.SelectSingleNode('/test-results/test-suite').GetAttribute('time') )

        [pscustomobject]@{
            Name = ($_.Name -replace '\.Tests\.ps1$','');
            ClockTime = $duration;
            TestTime = $pesterDuration;
        }
    } |
    Tee-Object -Variable 'results'

$results |
    Export-Csv -Path (Join-Path -Path $PSScriptRoot -ChildPath '.output\pester.csv')
