
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Invoke-WhiskeyDotNetCommand.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Write-WhiskeyCommand.ps1' -Resolve)

$argumentList = $null
$commandName = $null
$dotNetPath = $null
$failed = $false
$projectPath = $null
$taskContext = $null

function Init
{
    param(
        [Switch]
        $SkipDotNetMock
    )
    $script:argumentList = $null
    $script:commandName = $null
    $script:dotNetPath = $null
    $script:failed = $false
    $script:projectPath = $null
    $script:taskContext = $null

    if( -not $SkipDotNetMock )
    {
        Mock -CommandName 'Invoke-Command' -MockWith $SuccessCommandScriptBlock
    }
    Mock -CommandName 'Write-WhiskeyCommand'
}

function GivenArgumentList
{
    param(
        $Arguments
    )

    $script:argumentList = $Arguments
}

function GivenCommandName
{
    Param(
        $Name
    )
    $script:commandName = $Name
}

function GivenDotNetPath
{
    Param(
        $Path
    )

    $script:dotNetPath = $Path
    Mock -CommandName 'Resolve-Path' -MockWith { $Path }
}

function GivenNonExistentDotNetPath
{
    Param(
        $Path
    )

    $script:dotNetPath = $Path
}

function GivenProjectPath
{
    param(
        $Path
    )

    $script:projectPath = $Path
}

function ThenErrorMessage
{
    Param(
        $ExpectedError
    )

    It ('should write an error matching /{0}/' -f $ExpectedError) {
        $Global:Error | Should -Match $ExpectedError
    }
}

function ThenLogFileName
{
    param(
        $LogFileName
    )

    $logFilePath = Join-Path -Path $taskContext.OutputDirectory.FullName -ChildPath $LogFileName
    $expectedLoggerArg = ('/filelogger9 /flp9:LogFile={0};Verbosity=d' -f $logFilePath)

    It 'should log dotnet output to a file in the task output directory' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ParameterFilter {
            # $DebugPreference = 'Continue'
            $actualLoggerArg = $ArgumentList[3] -join ' '
            Write-Debug ('LoggerArg  EXPECTED  {0}' -f $expectedLoggerArg)
            Write-Debug ('           ACTUAL    {0}' -f $actualLoggerArg)
            $actualLoggerArg -eq $expectedLoggerArg
        }
    }
}

function ThenNoErrors
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenRanCommand
{
    param(
        $ExpectedCommand
    )

    It 'should run the given .NET SDK command' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ParameterFilter {
            # $DebugPreference = 'Continue'
            $actualCommand = $ArgumentList[1]
            Write-Debug ('Name  EXPECTED  {0}' -f $ExpectedCommand)
            Write-Debug ('      ACTUAL    {0}' -f $actualCommand)
            $actualCommand -eq $ExpectedCommand
        }
    }
}

function ThenRanWithArguments
{
    param(
        [string[]]
        $ExpectedArguments
    )

    It 'should run with the given arguments' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ParameterFilter {
            # $DebugPreference = 'Continue'
            $ExpectedArguments = $ExpectedArguments -join ','
            $actualArguments = $ArgumentList[2] -join ','
            Write-Debug ('ArgumentList  EXPECTED  {0}' -f $ExpectedArguments)
            Write-Debug ('              ACTUAL    {0}' -f $actualArguments)
            $actualArguments -eq $ExpectedArguments
        }
    }
}

function ThenRanWithPath
{
    param(
        $ExpectedPath
    )

    It 'should run with the given dotnet.exe path' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ParameterFilter {
            # $DebugPreference = 'Continue'
            $actualDotNetPath = $ArgumentList[0]
            Write-Debug ('DotNetPath  EXPECTED  {0}' -f $ExpectedPath)
            Write-Debug ('            ACTUAL    {0}' -f $actualDotNetPath)
            $actualDotNetPath -eq $ExpectedPath
        }
    }
}

function ThenRanWithProject
{
    param(
        $ExpectedProjectPath
    )

    It 'should run the command with the given project path' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ParameterFilter {
            # $DebugPreference = 'Continue'
            $actualProjectPath = $ArgumentList[4]
            Write-Debug ('ProjectPath  EXPECTED  {0}' -f $ExpectedProjectPath)
            Write-Debug ('             ACTUAL    {0}' -f $actualProjectPath)
            $actualProjectPath -eq $ExpectedProjectPath
        }
    }
}

function ThenWroteCommandInfo
{
    It 'should write the command string to the console' {
        Assert-MockCalled -CommandName 'Write-WhiskeyCommand'
    }
}

function WhenRunningDotNetCommand
{
    [CmdletBinding()]
    Param()

    $optionalParams = @{ }
    if ($argumentList)
    {
        $optionalParams['ArgumentList'] = $argumentList
    }
    if ($projectPath)
    {
        $optionalParams['ProjectPath'] = $projectPath
    }

    $Global:Error.Clear()

    try
    {
        $script:taskContext = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $TestDrive.FullName
        Invoke-WhiskeyDotNetCommand -TaskContext $taskContext -DotNetPath $dotNetPath -Name $commandName @optionalParams
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'Invoke-WhiskeyDotNetCommand.when DotNetPath does not exist' {
    Init
    GivenNonExistentDotNetPath 'C:\some\nonexistent\dotnet.exe'
    GivenCommandName 'build'
    WhenRunningDotNetCommand -ErrorAction SilentlyContinue
    ThenErrorMessage ([regex]::Escape('"C:\some\nonexistent\dotnet.exe" does not exist.'))
}

Describe 'Invoke-WhiskeyDotNetCommand.when running with minimum parameters' {
    Init
    GivenDotNetPath 'C:\dotnet\dotnet.exe'
    GivenCommandName 'build'
    WhenRunningDotNetCommand
    ThenWroteCommandInfo
    ThenRanWithPath 'C:\dotnet\dotnet.exe'
    ThenRanCommand 'build'
    ThenLogFileName 'dotnet.build.log'
    ThenNoErrors
}

Describe 'Invoke-WhiskeyDotNetCommand.when running with additional arguments' {
    Init
    GivenDotNetPath 'C:\dotnet\dotnet.exe'
    GivenCommandName 'publish'
    GivenArgumentList '--output=C:\output','--verbosity=diagnostic'
    WhenRunningDotNetCommand
    ThenWroteCommandInfo
    ThenRanWithPath 'C:\dotnet\dotnet.exe'
    ThenRanCommand 'publish'
    ThenRanWithArguments '--output=C:\output','--verbosity=diagnostic'
    ThenLogFileName 'dotnet.publish.log'
    ThenNoErrors
}

Describe 'Invoke-WhiskeyDotNetCommand.when given path to a project file' {
    Init
    GivenDotNetPath 'C:\dotnet\dotnet.exe'
    GivenCommandName 'test'
    GivenProjectPath 'C:\build\src\DotNetCore.csproj'
    WhenRunningDotNetCommand
    ThenLogFileName 'dotnet.test.DotNetCore.csproj.log'
    ThenRanWithProject 'C:\build\src\DotNetCore.csproj'
}

Describe 'Invoke-WhiskeyDotNetCommand.when dotnet command exits with non-zero exit code' {
    Init
    GivenDotNetPath 'C:\dotnet\dotnet.exe'
    GivenCommandName 'build'
    Mock -CommandName 'Invoke-Command' -MockWith $FailureCommandScriptBlock
    WhenRunningDotNetCommand -ErrorAction SilentlyContinue
    ThenErrorMessage 'dotnet\.exe"\ failed\ with\ exit\ code\ \d+'
}

$realDotNetPath = Get-Command -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\.dotnet\dotnet') |
                    Select-Object -ExpandProperty Source
Describe 'Invoke-WhiskeyDotNetCommand.when actually running dotnet executable' {
    Init -SkipDotNetMock
    GivenDotNetPath $realDotNetPath
    GivenCommandName '--version'
    WhenRunningDotNetCommand 
    ThenNoErrors
}

Describe 'Invoke-WhiskeyDotNetCommand.when actually running dotnet executable with failing command' {
    Init -SkipDotNetMock
    GivenDotNetPath $realDotNetPath
    GivenCommandName 'nfzhhih3sov'
    WhenRunningDotNetCommand  -ErrorAction SilentlyContinue
    ThenErrorMessage ('failed\ with\ exit\ code')
}
