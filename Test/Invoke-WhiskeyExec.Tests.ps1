
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

function WhenRunningExecutable
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
        Invoke-WhiskeyTask -TaskContext $context -Parameter $TaskParameter -Name 'Exec'
    }
    Catch
    {
        $script:failed = $true
    }

    Pop-Location
}

function ThenExecutableRan
{
    $executableRanResult = Get-ChildItem -Path (Get-BuildRoot) -Filter 'ItRan.txt' -Recurse

    It 'should run the executable' {
         $executableRanResult | Should -Not -BeNullOrEmpty
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

Describe 'Invoke-WhiskeyExec.when running an executable with no arguments' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 0'
    GivenPath 'executable.bat'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when running an executable with an argument' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 0'
    GivenPath 'executable.bat'
    GivenArgument 'Arg1'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when running an executable with multiple arguments' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 0'
    GivenPath 'executable.bat'
    GivenArgument 'Arg1','Arg2'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when missing Path parameter' {
    Init
    WhenRunningExecutable
    ThenTaskFailedWithMessage '''Path'' is mandatory.'
}

Describe 'Invoke-WhiskeyExec.when given bad path' {
    Init
    GivenPath 'nonexistent.exe'
    WhenRunningExecutable
    ThenTaskFailedWithMessage 'Executable ''nonexistent.exe'' does not exist.'
}

Describe 'Invoke-WhiskeyExec.when Path has spaces' {
    Init
    GivenExecutableFile 'sub dir\executable.bat' 'exit 0'
    GivenPath 'sub dir\executable.bat'
    WhenRunningExecutable
    ThenExecutableRan
    ThenRanInWorkingDirectory '.'
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when given success exit codes' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 123'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '123'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when executable exits with non-success exit code' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 42'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '0','1','123'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Invoke-WhiskeyExec.when given a range ''..'' of success exit codes' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 123'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '120..130'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when given a range ''..'' and exits with code outside success range' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 133'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '120..130'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Invoke-WhiskeyExec.when given a range ''>='' of success exit codes' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 500'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '>=500'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when given a range ''>='' and exits with code outside success range' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 85'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '>=500'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Invoke-WhiskeyExec.when given a range ''<='' of success exit codes' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 9'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '<= 9'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when given a range ''<='' and exits with code outside success range' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 10'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '<= 9'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Invoke-WhiskeyExec.when given a range ''>'' of success exit codes' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 91'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '>90'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when given a range ''>'' and exits with code outside success range' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 90'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '>90'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Invoke-WhiskeyExec.when given a range ''<'' of success exit codes' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 89'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '<90'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when given a range ''>='' and exits with code outside success range' {
    Init
    GivenExecutableFile 'executable.bat' 'exit 90'
    GivenPath 'executable.bat'
    GivenSuccessExitCode '<90'
    WhenRunningExecutable
    ThenExecutableRan
    ThenSpecifiedArgumentsWerePassed
    ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
}

Describe 'Invoke-WhiskeyExec.when given a working directory' {
    Init
    GivenADirectory 'workdir'
    GivenExecutableFile 'executable.bat' 'exit 0'
    GivenPath 'executable.bat'
    GivenWorkingDirectory 'workdir'
    WhenRunningExecutable
    ThenExecutableRan
    ThenRanInWorkingDirectory
    ThenTaskSuccess
}

Describe 'Invoke-WhiskeyExec.when given bad working directory' {
    Init
    GivenADirectory 'workdir'
    GivenExecutableFile 'executable.bat' 'exit 0'
    GivenPath 'executable.bat'
    GivenWorkingDirectory 'badworkdir'
    WhenRunningExecutable
    ThenTaskFailedWithMessage 'Could not locate the directory'    
}

Describe 'Invoke-WhiskeyExec.when running executable located by the Path environment variable' {
    Init
    GivenPath 'cmd.exe'
    GivenArgument '/C','echo ItRan > ItRan.txt & echo|set /p="%cd%" > WorkingDirectory.txt & exit 0'
    WhenRunningExecutable
    ThenExecutableRan
    ThenRanInWorkingDirectory '.'
    ThenTaskSuccess
}
