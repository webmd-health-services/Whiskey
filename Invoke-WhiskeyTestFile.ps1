[CmdletBinding()]
param(
    [String] $Path,
    [String] $PesterVersion
)

Set-Location $PSScriptRoot

$testFile = Get-Item -Path $Path
if (-not $testFile)
{
    exit 1
}

$outputPath = Join-Path -Path $PSScriptRoot -ChildPath '.output'
$outputPath = Join-Path -Path $outputPath -ChildPath "pester-$($testFile.Name).xml"

Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PSModules\Pester') `
              -MaximumVersion "${PesterVersion}.99.99" `
              -Verbose:$false

if ($pesterVersion -eq 4)
{
    Invoke-Pester -Script $testFile.FullName -OutputFile $outputPath -OutputFormat 'NUnitXml'

    $outputFileContent = Get-Content -Path $outputPath -Raw
    $result = [xml]$outputFileContent

    if (-not $result)
    {
        Write-Error -Message "Unable to parse Pester output XML report ""${outputPath}""."
        return
    }

    $testErrors = $result.DocumentElement.errors
    $failures = $result.DocumentElement.failures
    if ($testErrors -ne '0' -or $failures -ne '0')
    {
        exit 1
    }
}
else
{
    $pesterCfg = New-PesterConfiguration @{
        Run = @{
            Path = $testFile.FullName;
            ExitCode = $true
        }
        TestResult = @{
            Enabled = $true;
            OutputPath = $outputPath;
            # TestSuiteName = 'Whiskey';
        };
        Output = @{
            Verbosity = 'Detailed';
        }
    }
    Invoke-Pester -Configuration $pesterCfg
}
