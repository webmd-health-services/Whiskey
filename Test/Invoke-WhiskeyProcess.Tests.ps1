
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$argument = $null
$failed = $false
$path = $null
$successExitCode = $null
$workingDirectory = $null

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

function GivenExecutableFile
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
@ECHO OFF
echo ItRan > ItRan.txt
echo|set /p="%*" > Arguments.txt
echo|set /p="%cd%" > WorkingDirectory.txt
{0}
"@ -f $ExitCode

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

function WhenRunningProcess
{
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

    $context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot (Get-BuildRoot)

    # This is normally done by Invoke-WhiskeyBuild, which we're skipping past by invoking WhiskeyTask directly
    Push-Location -Path (Get-BuildRoot)

    Try 
    {
        Invoke-WhiskeyTask -TaskContext $context -Parameter $TaskParameter -Name 'Process'
    }
    Catch
    {
        $script:failed = $true
    }

    Pop-Location
}

function ThenProcessRan
{
    $processRanResult = Get-ChildItem -Path (Get-BuildRoot) -Filter 'ItRan.txt' -Recurse

    It 'should run the process' {
         $processRanResult | Should -Not -BeNullOrEmpty
    }
}

function ThenSpecifiedArgumentsWerePassed
{
    $argumentsResult = Get-ChildItem -Path (Get-BuildRoot) -Filter 'Arguments.txt' -Recurse | Get-Content

    if ( -not $script:argument )
    {
        It 'should not pass any arguments' {
            $argumentsResult | Should -BeNullOrEmpty
        }
    }
    else
    {
        It ('should pass these arguments: ''{0}''' -f ($script:argument -join ''',''')) {
            $argumentsResult | Should -Be ($script:argument -join ' ')
        }

    }
}

function ThenRanInWorkingDirectory
{
    param(
        $WorkingDirectory = $script:workingDirectory
    )

    $workingDirectoryFull = Join-Path -Path (Get-BuildRoot) -ChildPath $workingDirectory -Resolve
    $workingDirectoryResult = Get-ChildItem -Path (Get-BuildRoot) -Filter 'WorkingDirectory.txt' -Recurse | Get-Content

    It ('should run in working directory of: ''{0}''' -f $WorkingDirectory) {
        $workingDirectoryResult | Should -Be $WorkingDirectoryFull
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

    It ('error message should match ''{0}''' -f $Message) {
        $Global:Error[0] | Should -Match $Message
    }
}

Describe 'Invoke-WhiskeyProcess.when running a process with no arguments' {
    Init
    GivenExecutableFile 'process.bat' 'exit 0'
    GivenPath 'process.bat'
    WhenRunningProcess
    ThenProcessRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyProcess.when running a process with an argument' {
    Init
    GivenExecutableFile 'process.bat' 'exit 0'
    GivenPath 'process.bat'
    GivenArgument 'Arg1'
    WhenRunningProcess
    ThenProcessRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyProcess.when running a process with multiple arguments' {
    Init
    GivenExecutableFile 'process.bat' 'exit 0'
    GivenPath 'process.bat'
    GivenArgument 'Arg1','Arg2'
    WhenRunningProcess
    ThenProcessRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyProcess.when missing Path parameter' {
    Init
    WhenRunningProcess
    ThenTaskFailedWithMessage '''Path'' is mandatory.'
}

Describe 'Invoke-WhiskeyProcess.when given bad path' {
    Init
    GivenPath 'nonexistent.exe'
    WhenRunningProcess
    ThenTaskFailedWithMessage 'Executable ''nonexistent.exe'' does not exist.'
}

Describe 'Invoke-WhiskeyProcess.when Path has spaces' {
    Init
    GivenExecutableFile 'sub dir\process.bat' 'exit 0'
    GivenPath 'sub dir\process.bat'
    WhenRunningProcess
    ThenProcessRan
    ThenRanInWorkingDirectory '.'
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyProcess.when given success exit codes' {
    Init
    GivenExecutableFile 'process.bat' 'exit 123'
    GivenPath 'process.bat'
    GivenSuccessExitCode 123
    WhenRunningProcess
    ThenProcessRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyProcess.when process exits with non-success exit code' {
    Init
    GivenExecutableFile 'process.bat' 'exit 42'
    GivenPath 'process.bat'
    GivenSuccessExitCode 0,1,123
    WhenRunningProcess
    ThenProcessRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'not one of the expected ''SuccessExitCode'''
}

Describe 'Invoke-WhiskeyProcess.when given a working directory' {
    Init
    GivenADirectory 'workdir'
    GivenExecutableFile 'process.bat' 'exit 0'
    GivenPath 'process.bat'
    GivenWorkingDirectory 'workdir'
    WhenRunningProcess
    ThenProcessRan
    ThenRanInWorkingDirectory
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyProcess.when given bad working directory' {
    Init
    GivenADirectory 'workdir'
    GivenExecutableFile 'process.bat' 'exit 0'
    GivenPath 'process.bat'
    GivenWorkingDirectory 'badworkdir'
    WhenRunningProcess
    ThenTaskFailedWithMessage 'Could not locate the directory'    
}

Describe 'Invoke-WhiskeyProcess.when running process located by the Path environment variable' {
    Init
    GivenPath 'cmd.exe'
    GivenArgument '/C','echo ItRan > ItRan.txt & echo|set /p="%cd%" > WorkingDirectory.txt & exit 0'
    WhenRunningProcess
    ThenProcessRan
    ThenRanInWorkingDirectory '.'
    ThenTaskSuccess
}
