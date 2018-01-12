Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dependency = $null
$devDependency = $null
$failed = $false

function Init
{
    $Global:Error.Clear()
    $script:dependency = $null
    $script:devDependency = $null
    $script:failed = $false
    Install-Node
}

function GivenPackageJson
{
    $packageJsonPath = Join-Path -Path $TestDrive.FullName -ChildPath 'package.json'

    @"
{
    "name": "NpmPrune-Test-App",
    "version": "0.0.1",
    "description": "test",
    "repository": "bitbucket:example/repo",
    "private": true,
    "license": "MIT",
    "dependencies": {
        $($script:dependency -join ',')
    },
    "devDependencies": {
        $($script:devDependency -join ',')
    }
} 
"@ | Set-Content -Path $packageJsonPath -Force
}

function GivenDependency 
{
    param(
        [object[]]
        $Dependency 
    )
    $script:dependency = $Dependency
}

function GivenDevDependency 
{
    param(
        [object[]]
        $DevDependency 
    )
    $script:devDependency = $DevDependency
}

function GivenNodeModulesInstalled
{
    Push-Location $TestDrive.FullName
    try
    {
        & '.node\node.exe' '.node\node_modules\npm\bin\npm-cli.js' 'install'
    }
    finally
    {
        Pop-Location
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param()

    $taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $TestDrive.FullName

    $taskParameter = @{ }

    try
    {
        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NpmPrune'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenPackage
{
    param(
        [Parameter(Position=0)]
        [string]
        $PackageName,
        
        [Parameter(Mandatory=$true,ParameterSetName='Exists')]
        [switch]
        $Exists,

        [Parameter(Mandatory=$true,ParameterSetName='DoesNotExist')]
        [switch]
        $DoesNotExist
    )

    $packagePath = Join-Path -Path $TestDrive.FullName -ChildPath ('node_modules\{0}' -f $PackageName)

    If ($Exists)
    {
        It ('should not prune package ''{0}''' -f $PackageName) {
            $packagePath | Should -Exist
        }
    }
    else
    {
        It ('should prune package ''{0}''' -f $PackageName) {
            $packagePath | Should -Not -Exist
        }
    }
}

function ThenTaskSucceeded
{
    It 'should not write any errors' {
        $Global:Error | Where-Object { $_ -notmatch '\bnpm\ (notice|WARN)\b' } | Should -BeNullOrEmpty
    }

    It 'should not fail' {
        $failed | Should -Be $false
    }
}

Describe 'NpmPrune.when pruning packages' {
    try
    {
        Init
        GivenDependency '"wrappy": "^1.0.2"'
        GivenDevDependency '"pify": "^3.0.0"'
        GivenPackageJson
        GivenNodeModulesInstalled
        WhenRunningTask
        ThenPackage 'wrappy' -Exists
        ThenPackage 'pify' -DoesNotExist
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}
