
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$workingDirectory = $null
$failed = $false
$scriptName = $null

function Get-WorkingDirectory
{
    #if ( $WhenGivenARelativePath )
    #{
    #    $itRanPath = Join-Path -Path (Join-Path -Path $InWorkingDirectory -ChildPath $relativePath) -ChildPath 'run'
    #}
    #else
    #{
    #    $itRanPath = Join-Path -Path $InWorkingDirectory -ChildPath 'run'
    #}

    if( $workingDirectory )
    {
        return $workingDirectory
    }

    return $TestDrive.FullName
}

function Get-OutputFilePath
{
    $path = (Join-Path -Path (Get-WorkingDirectory) -ChildPath 'run')
    if( -not [IO.Path]::IsPathRooted($path) )
    {
        $path = Join-Path -Path $TestDrive.FullName -ChildPath $path
    }
    return $path
}

function GivenAFailingScript
{
    GivenAScript 'exit 1'
}

function GivenAPassingScript
{
    GivenAScript ''
}

function GivenAScript
{
    param(
        [string]
        $Script
    )

    $script:scriptName = 'myscript.ps1'
    $scriptPath = Join-Path -Path $TestDrive.FullName -ChildPath $scriptName
        
    @"

New-Item -Path '$( Get-OutputFilePath | Split-Path -Leaf)' -ItemType 'File'

$($Script)
"@ | Set-Content -Path $scriptPath
}

function GivenLastExitCode
{
    param(
        $ExitCode
    )

    $Global:LASTEXITCODE = $ExitCode
}

function GivenNoWorkingDirectory
{
    $script:workingDirectory = $null
}

function GivenWorkingDirectory
{
    param(
        [string]
        $Path,

        [Switch]
        $ThatDoesNotExist
    )

    $script:workingDirectory = $Path

    $absoluteWorkingDir = $workingDirectory
    if( -not [IO.Path]::IsPathRooted($absoluteWorkingDir) )
    {
        $absoluteWorkingDir = Join-Path -Path $TestDrive.FullName -ChildPath $absoluteWorkingDir
    }

    if( -not $ThatDoesNotExist -and -not (Test-Path -Path $absoluteWorkingDir -PathType Container) )
    {
        New-Item -Path $absoluteWorkingDir -ItemType 'Directory'
    }

}

function WhenTheTaskRuns
{
    [CmdletBinding()]
    param(
        [Switch]
        $InCleanMode
    )

    $taskParameter = @{
                        Path = @(
                                $scriptName
                            )
                        }
    $workingDirectory = Get-WorkingDirectory
    if( $workingDirectory )
    {
        $taskParameter['WorkingDirectory'] = $workingDirectory
    }

    $context = New-WhsCITestContext -ForDeveloper
    
    $failed = $false
    $CleanParam = @{ }
    if( $InCleanMode )
    {
        $CleanParam['Clean'] = $True
    }

    $script:failed = $false
    try
    {
        Invoke-WhsCIPowerShellTask -TaskContext $context -TaskParameter $taskParameter @CleanParam
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $script:failed = $true
    }
}

function ThenTheLastErrorMatches
{
    param(
        $Pattern
    )

    It ("last error message should match /{0}/" -f $Pattern)  {
        $Global:Error[0] | Should -Match $Pattern
    }
}

function ThenTheLastErrorDoesNotMatch
{
    param(
        $Pattern
    )

    It ("last error message should not match /{0}/" -f $Pattern)  {
        $Global:Error[0] | Should -Not -Match $Pattern
    }
}

function ThenTheScriptRan
{
    It 'the script should run' {
        Get-OutputFilePath | Should -Exist
    }
}

function ThenTheScriptDidNotRun
{
    It 'the script should not run' {
        Get-OutputFilePath | Should -Not -Exist
    }
}

function ThenTheTaskFails
{
    It 'the task should fail' {
        $failed | Should -Be $true
    }
}

function ThenTheTaskPasses
{
    It 'the task should pass' {
        $failed | Should -Be $false
    }
}

Describe 'Invoke-WhsCIPowerShellTask.when script passes' {
    GivenAPassingScript
    GivenNoWorkingDirectory
    WhenTheTaskRuns
    ThenTheScriptRan
    ThenTheTaskPasses
}

Describe 'Invoke-WhsCIPowerShellTask.when script fails' {
    GivenNoWorkingDirectory
    GivenAFailingScript
    WhenTheTaskRuns -ErrorAction SilentlyContinue
    ThenTheScriptRan
    ThenTheTaskFails
}

Describe 'Invoke-WhsCIPowerShellTask.when script passes after a previous command fails' {
    GivenNoWorkingDirectory
    GivenAPassingScript
    GivenLastExitCode 1
    WhenTheTaskRuns
    ThenTheScriptRan
    ThenTheTaskPasses
}

Describe 'Invoke-WhsCIPowerShellTask.when script throws a terminating exception' {
    GivenAScript @'
throw 'fubar!'
'@ 
    WhenTheTaskRuns -ErrorAction SilentlyContinue
    ThenTheTaskFails
    ThenTheScriptRan
    ThenTheLastErrorMatches 'fubar'
}

Describe 'Invoke-WhsCIPowerShellTask.when script''s error action preference is Stop' {
    GivenAScript @'
$ErrorActionPreference = 'Stop'
Write-Error 'snafu!'
throw 'fubar'
'@ 
    WhenTheTaskRuns -ErrorAction SilentlyContinue
    ThenTheTaskFails
    ThenTheScriptRan
    ThenTheLastErrorMatches 'snafu'
    ThenTheLastErrorDoesNotMatch 'fubar'
    ThenTheLastErrorDoesNotMatch 'exiting\ with\ code'
}

Describe 'Invoke-WhsCIBuild.when PowerShell task defined with an absolute working directory' {
    GivenWorkingDirectory (Join-Path -path $TestDrive.FullName -ChildPath 'bin')
    GivenAPassingScript
    WhenTheTaskRuns
    ThenTheTaskPasses
    ThenTheScriptRan
}

Describe 'Invoke-WhsCIBuild.when PowerShell task defined with a relative working directory' {
    GivenWorkingDirectory 'bin'
    GivenAPassingScript
    WhenTheTaskRuns
    ThenTheTaskPasses
    ThenTheScriptRan
}

Describe 'Invoke-WhsCIPowerShellTask.when working directory does not exist' {
    GivenWorkingDirectory 'C:\I\Do\Not\Exist' -ThatDoesNotExist
    GivenAPassingScript
    WhenTheTaskRuns  -ErrorAction SilentlyContinue
    ThenTheTaskFails
}

Describe 'Invoke-WhsCIPowerShellTask.when Clean switch is active' {
    GivenNoWorkingDirectory
    GivenAPassingScript
    WhenTheTaskRuns -InCleanMode
    ThenTheTaskPasses
    ThenTheScriptDidNotRun
}