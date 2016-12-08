
.\init.ps1

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Pester' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath 'Carbon\Import-Carbon.ps1' -Resolve)

$outputRoot = Join-Path -Path $PSScriptRoot -ChildPath '.output'
Install-Directory -Path $outputRoot

$outputXml = Join-Path -Path $outputRoot -ChildPath 'pester.xml'
$testRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Test' -Resolve
$result = Invoke-Pester -Script $testRoot -OutputFormat NUnitXml -OutputFile $outputXml -PassThru

exit $result.FailedCount
