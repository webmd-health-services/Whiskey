#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$argument = $null
$failed = $false
$path = $null
$successExitCode = $null
$workingDirectory = $null
$defaultProperty = $null

function Get-BuildRoot
{
   $buildRoot = (Join-Path -Path $TestDrive.FullName -ChildPath 'BuildRoot')
   New-Item -Path $buildRoot -ItemType 'Directory' -Force | Out-Null

   return $buildRoot
}

function Init
{
    $Global:Error.Clear()
    $script:argument = $null
    $script:failed = $false
    $script:path = $null
    $script:successExitCode = $null
    $script:workingDirectory = $null
    $script:defaultProperty = $null
}

function GivenArgument
{
    param(
        $Argument
    )

    $script:argument = $Argument
}

function GivenADirectory
{
    param(
        $DirectoryPath
    )

    New-Item -Path (Join-Path -Path (Get-BuildRoot) -ChildPath $DirectoryPath) -ItemType 'Directory' -Force | Out-Null
}

function GivenPowerShellFile
{
    param(
        $Path,
        $ExitCode
    )

    $parentPath = $Path | Split-Path
    if ($parentPath)
    {
        GivenADirectory $parentPath
    }

    $Content = @"
#`$DebugPreference = 'Continue'
Write-Debug `$PWD.Path
Write-Debug ([IO.Directory]::GetCurrentDirectory())
'ItRan' | Set-Content 'ItRan.txt'
`$args | Set-Content 'Arguments.txt'
`$PWD.Path | Set-Content 'WorkingDirectory.txt'
exit $ExitCode
"@

    Set-Content -Path (Join-Path -Path (Get-BuildRoot) -ChildPath $Path) -Value $Content
}

function GivenPath
{
    param(
        $Path
    )

    $script:path = $Path
}

function GivenWorkingDirectory
{
    param(
        $WorkingDirectory
    )

    $script:workingDirectory = $WorkingDirectory
}

function GivenSuccessExitCode
{
    param(
        $SuccessExitCode
    )

    $script:successExitCode = $SuccessExitCode
}

function GivenTaskDefaultProperty
{
    param(
        $Property
    )

    $script:defaultProperty = $Property
}

function WhenRunningExecutable
{
    [CmdletBinding()]
    param(
        [Switch]
        $InCleanMode,

        [Switch]
        $InInitializeMode
    )

    $TaskParameter = @{}

    if( $path )
    {
        $TaskParameter['Path'] = $path
    }

    if ( $argument )
    {
        $TaskParameter['Argument'] = $argument
    }

    if ( $workingDirectory )
    {
        $TaskParameter['WorkingDirectory'] = $workingDirectory
    }

    if ( $successExitCode )
    {
        $TaskParameter['SuccessExitCode'] = $successExitCode
    }

    if ( $defaultProperty )
    {
        $TaskParameter[''] = $defaultProperty
    }

    $context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot (Get-BuildRoot) -InCleanMode:$InCleanMode -InInitMode:$InInitializeMode

    try 
    {
        Invoke-WhiskeyTask -TaskContext $context -Parameter $TaskParameter -Name 'Exec'
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $script:failed = $true
    }
}

function ThenExecutableRan
{
    $taskDir = Get-BuildRoot
    if( $workingDirectory )
    {
        $taskDir = Join-Path -Path $taskDir -ChildPath $workingDirectory
    }

    $executableRanResult = Get-ChildItem -Path $taskDir -Filter 'ItRan.txt' -Recurse

    It 'should run the executable' {
         $executableRanResult | Should -Not -BeNullOrEmpty
    }
}

function ThenSpecifiedArgumentsWerePassed
{
    param(
        [string[]]
        $Arguments = @()
    )

    [string[]]$argumentsResult = Get-ChildItem -Path (Get-BuildRoot) -Filter 'Arguments.txt' -Recurse | Get-Content
    if( -not $argumentsResult )
    {
        $argumentsResult = @()
    }

    if ( -not $Arguments )
    {
        It 'should not pass any arguments' {
            $argumentsResult | Should -BeNullOrEmpty
        }
    }
    else
    {
        It ('should pass these arguments: "{0}"' -f ($Arguments -join '","')) {
            $argCount = $argumentsResult.Length
            $argCount | Should -Be $Arguments.Length
            for( $idx = 0; $idx -lt $argCount; ++$idx )
            {
                $argumentsResult[$idx] | Should -Be $Arguments[$idx]
            }
        }

    }
}

function ThenRanInWorkingDirectory
{
    param(
        $WorkingDirectory = $script:workingDirectory
    )

    $WorkingDirectory = Join-Path -Path (Get-BuildRoot) -ChildPath $WorkingDirectory -Resolve
    $workDirPath = Join-Path -Path $WorkingDirectory -ChildPath 'WorkingDirectory.txt'

    It ('should run in working directory of: "{0}"' -f $WorkingDirectory) {
        $workDirPath | Should -Exist
        Get-Content -Path $workDirPath | Should -Be $WorkingDirectory
    }

}

function ThenTaskSuccess
{
    It 'task should complete successfully' {
        $failed | Should -Be $false
    }
}

function ThenTaskFailedWithMessage
{
    param(
        $Message
    )

    It 'task should fail' {
        $failed | Should -Be $true
    }

    It ('error message should match "{0}"' -f $Message) {
        $Global:Error[0] | Should -Match $Message
    }
}

Describe 'Exec.when running an executable with no arguments' {
    Init
    GivenPowerShellFile 'exec.ps1' '0'
    GivenPath 'exec.ps1'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed 
    ThenTaskSuccess
}

Describe 'Exec.when running an executable with an argument' {
    Init
    GivenPowerShellFile 'exec.ps1' '0'
    GivenPath 'exec.ps1'
    GivenArgument 'Arg1'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed 'Arg1'
    ThenTaskSuccess
}

Describe 'Exec.when running an executable with multiple arguments' {
    Init
    GivenPowerShellFile 'exec.ps1' '0'
    GivenPath 'exec.ps1'
    GivenArgument 'Arg1','Arg2'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed 'Arg1','Arg2'
    ThenTaskSuccess
}

Describe 'Exec.when utilizing default task property to define executable and arguments' {
    Init
    GivenPowerShellFile 'exec.ps1' '0'
    GivenTaskDefaultProperty '.\exec.ps1 Arg1 Arg2 "Arg 3" ''Arg 4'''
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed 'Arg1', 'Arg2', 'Arg 3', 'Arg 4'
    ThenTaskSuccess
}

Describe 'Exec.when missing Path parameter' {
    Init
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage '"Path" is mandatory.'
}

Describe 'Exec.when given bad path' {
    Init
    GivenPath 'nonexistent.exe'
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'Executable "nonexistent.exe" does not exist.'
}

Describe 'Exec.when Path has spaces' {
    Init
    GivenPowerShellFile 'e x e c.ps1' '0'
    GivenPath 'e x e c.ps1'
    WhenRunningExecutable
    ThenExecutableRan
    ThenRanInWorkingDirectory '.'
    ThenTaskSuccess
}

Describe 'Exec.when given success exit codes' {
    Init
    GivenPowerShellFile 'exec.ps1' '123'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '123'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Exec.when executable exits with non-success exit code' {
    Init
    GivenPowerShellFile 'exec.ps1' '42'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '0','1','123'
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed 
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Exec.when given a range ".." of success exit codes' {
    Init
    GivenPowerShellFile 'exec.ps1' '123'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '120..130'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Exec.when given a range ".." and exits with code outside success range' {
    Init
    GivenPowerShellFile 'exec.ps1' '133'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '120..130'
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Exec.when given a range ">=" of success exit codes' {
    Init
    GivenPowerShellFile 'exec.ps1' '500'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '>=500'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Exec.when given a range ">=" and exits with code outside success range' {
    Init
    GivenPowerShellFile 'exec.ps1' '85'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '>=500'
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Exec.when given a range "<=" of success exit codes' {
    Init
    GivenPowerShellFile 'exec.ps1' '9'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '<= 9'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Exec.when given a range "<=" and exits with code outside success range' {
    Init
    GivenPowerShellFile 'exec.ps1' '10'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '<= 9'
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Exec.when given a range ">" of success exit codes' {
    Init
    GivenPowerShellFile 'exec.ps1' '91'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '>90'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Exec.when given a range ">" and exits with code outside success range' {
    Init
    GivenPowerShellFile 'exec.ps1' '90'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '>90'
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Exec.when given a range "<" of success exit codes' {
    Init
    GivenPowerShellFile 'exec.ps1' '89'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '<90'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Exec.when given a range "<" and exits with code outside success range' {
    Init
    GivenPowerShellFile 'exec.ps1' '90'
    GivenPath 'exec.ps1'
    GivenSuccessExitCode '<90'
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Exec.when given a working directory' {
    Init
    GivenADirectory 'workdir'
    GivenPowerShellFile 'workdir\exec.ps1' '0'
    GivenPath 'exec.ps1'
    GivenWorkingDirectory 'workdir'
    WhenRunningExecutable
    ThenExecutableRan
    ThenRanInWorkingDirectory
    ThenTaskSuccess
}

Describe 'Exec.when given bad working directory' {
    Init
    GivenADirectory 'workdir'
    GivenPowerShellFile 'exec.ps1' '0'
    GivenPath 'exec.ps1'
    GivenWorkingDirectory 'badworkdir'
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage 'Build.+WorkingDirectory.+does not exist.'    
}

Describe 'Exec.when running in Clean mode' {
    Init
    GivenPowerShellFile 'exec.ps1' '0'
    GivenPath 'exec.ps1'
    WhenRunningExecutable -InCleanMode
    ThenTaskSuccess
    ThenExecutableRan
}

Describe 'Exec.when running in Initialize mode' {
    Init
    GivenPowerShellFile 'exec.ps1' '0'
    GivenPath 'exec.ps1'
    WhenRunningExecutable -InInitializeMode
    ThenTaskSuccess
    ThenExecutableRan
}

Describe 'Exec.when path has wildcards and resolves to multiple files' {
    Init
    GivenPowerShellFile 'exec1.ps1' '1'
    GivenPowerShellFile 'exec2.ps1' '2'
    GivenPath 'exec*.ps1'
    WhenRunningExecutable -ErrorAction SilentlyContinue
    ThenTaskFailedWithMessage ([regex]::Escape('contains wildcards and resolves to the following files'))
}