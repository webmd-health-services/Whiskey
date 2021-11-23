
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$argumentList = $null
$commandName = $null
$dotNetPath = $null
$failed = $false
$projectPath = $null
$taskContext = $null
$testRoot = $null

function Init
{
    param(
        [switch]$SkipDotNetMock
    )
    $script:argumentList = $null
    $script:commandName = $null
    $script:dotNetPath = $null
    $script:failed = $false
    $script:projectPath = $null
    $script:taskContext = $null
    $script:testRoot = New-WhiskeyTestRoot

    if( -not $SkipDotNetMock )
    {
        Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -MockWith $SuccessCommandScriptBlock
    }
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
    Mock -CommandName 'Resolve-Path' -ModuleName 'Whiskey' -MockWith { $Path }
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

    $Global:Error[0] | Should -Match $ExpectedError
}

function ThenLogFileName
{
    param(
        $LogFileName
    )

    $logFilePath = Join-Path -Path $taskContext.OutputDirectory.FullName -ChildPath $LogFileName
    $expectedLoggerArg = ('/filelogger9 /flp9:LogFile={0};Verbosity=d' -f $logFilePath)

    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter {
        $ArgumentList | Out-String | Write-WhiskeyDebug
        $actualLoggerArg = $ArgumentList[3] -join ' '
        Write-WhiskeyDebug ('LoggerArg  EXPECTED  {0}' -f $expectedLoggerArg)
        Write-WhiskeyDebug ('           ACTUAL    {0}' -f $actualLoggerArg)
        $actualLoggerArg -eq $expectedLoggerArg
    }
}

function ThenNoErrors
{
    $Global:Error | Format-List * -Force | Out-String | Write-Verbose -Verbose
    $Global:Error | Should -BeNullOrEmpty
}

function ThenRanCommand
{
    param(
        $ExpectedCommand
    )

    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter {
        $actualCommand = $ArgumentList[1]
        Write-WhiskeyDebug ('Name  EXPECTED  {0}' -f $ExpectedCommand)
        Write-WhiskeyDebug ('      ACTUAL    {0}' -f $actualCommand)
        $actualCommand -eq $ExpectedCommand
    }
}

function ThenRanWithArguments
{
    param(
        [String[]]$ExpectedArguments
    )

    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter {
        $ExpectedArguments = $ExpectedArguments -join ','
        $actualArguments = $ArgumentList[2] -join ','
        Write-WhiskeyDebug ('ArgumentList  EXPECTED  {0}' -f $ExpectedArguments)
        Write-WhiskeyDebug ('              ACTUAL    {0}' -f $actualArguments)
        $actualArguments -eq $ExpectedArguments
    }
}

function ThenRanWithPath
{
    param(
        $ExpectedPath
    )

    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter {
        $ArgumentList | Out-String | Write-WhiskeyDebug
        $actualDotNetPath = $ArgumentList[0]
        Write-WhiskeyDebug ('DotNetPath  EXPECTED  {0}' -f $ExpectedPath)
        Write-WhiskeyDebug ('            ACTUAL    {0}' -f $actualDotNetPath)
        $actualDotNetPath -eq $ExpectedPath
    }
}

function ThenRanWithProject
{
    param(
        $ExpectedProjectPath
    )

    Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter {
        # $DebugPreference = 'Continue'
        $actualProjectPath = $ArgumentList[4]
        Write-WhiskeyDebug ('ProjectPath  EXPECTED  {0}' -f $ExpectedProjectPath)
        Write-WhiskeyDebug ('             ACTUAL    {0}' -f $actualProjectPath)
        $actualProjectPath -eq $ExpectedProjectPath
    }
}

function WhenRunningDotNetCommand
{
    [CmdletBinding()]
    param(
        [switch] $WithNoLogging
    )

    $parameter = $PSBoundParameters
    $parameter.Remove('WithNoLogging')
    $parameter['DotNetPath'] = $dotNetPath;
    $parameter['Name'] = $commandName;

    if ($argumentList)
    {
        $parameter['ArgumentList'] = $argumentList
    }

    if ($projectPath)
    {
        $parameter['ProjectPath'] = $projectPath
    }

    if( $WithNoLogging )
    {
        $parameter['NoLog'] = $true
    }

    $Global:Error.Clear()

    try
    {
        $script:taskContext = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $script:testRoot
        $parameter['TaskContext'] = $taskContext
        Invoke-WhiskeyPrivateCommand -Name 'Invoke-WhiskeyDotNetCommand' -Parameter $parameter 
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'Invoke-WhiskeyDotNetCommand.when DotNetPath does not exist' {
    It 'should fail' {
        Init
        GivenNonExistentDotNetPath 'C:\some\nonexistent\dotnet.exe'
        GivenCommandName 'build'
        WhenRunningDotNetCommand -ErrorAction SilentlyContinue
        ThenErrorMessage ([regex]::Escape('"C:\some\nonexistent\dotnet.exe" does not exist.'))
    }
}

Describe 'Invoke-WhiskeyDotNetCommand.when running with minimum parameters' {
    It 'should run the command' {
        Init
        GivenDotNetPath 'C:\dotnet\dotnet.exe'
        GivenCommandName 'build'
        WhenRunningDotNetCommand
        ThenRanWithPath 'C:\dotnet\dotnet.exe'
        ThenRanCommand 'build'
        ThenLogFileName 'dotnet.build.log'
        ThenNoErrors
    }
}

Describe 'Invoke-WhiskeyDotNetCommand.when running with additional arguments' {
    It 'should pass additional arguments' {
        Init
        GivenDotNetPath 'C:\dotnet\dotnet.exe'
        GivenCommandName 'publish'
        GivenArgumentList '--output=C:\output','--verbosity=diagnostic'
        WhenRunningDotNetCommand
        ThenRanWithPath 'C:\dotnet\dotnet.exe'
        ThenRanCommand 'publish'
        ThenRanWithArguments '--output=C:\output','--verbosity=diagnostic'
        ThenLogFileName 'dotnet.publish.log'
        ThenNoErrors
    }
}

Describe 'Invoke-WhiskeyDotNetCommand.when given path to a project file' {
    It 'should pass as the first argument' {
        Init
        GivenDotNetPath 'C:\dotnet\dotnet.exe'
        GivenCommandName 'test'
        GivenProjectPath 'C:\build\src\DotNetCore.csproj'
        WhenRunningDotNetCommand
        ThenLogFileName 'dotnet.test.DotNetCore.csproj.log'
        ThenRanWithProject 'C:\build\src\DotNetCore.csproj'
    }
}

Describe 'Invoke-WhiskeyDotNetCommand.when dotnet command exits with non-zero exit code' {
    It 'should fail' {
        Init
        GivenDotNetPath 'C:\dotnet\dotnet.exe'
        GivenCommandName 'build'
        Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -MockWith $FailureCommandScriptBlock
        WhenRunningDotNetCommand -ErrorAction SilentlyContinue
        ThenErrorMessage 'dotnet\.exe"\ failed\ with\ exit\ code\ \d+'
    }
}

$realDotNetPath = Get-Command -Name 'dotnet' | Select-Object -ExpandProperty Source
Write-Verbose -Message "[dotnet]  $($realDotNetPath)  $(& $realDotNetPath --version)" -Verbose
Describe 'Invoke-WhiskeyDotNetCommand.when actually running dotnet executable' {
    It 'should work with actual dotnet.exe' {
        Init -SkipDotNetMock
        GivenDotNetPath $realDotNetPath
        GivenCommandName '--version'
        WhenRunningDotNetCommand -WithNoLogging
        ThenNoErrors
    }
}

Describe 'Invoke-WhiskeyDotNetCommand.when actually running dotnet executable with failing command' {
    It 'should fail' {
        Init -SkipDotNetMock
        GivenDotNetPath $realDotNetPath
        GivenCommandName 'nfzhhih3sov'
        WhenRunningDotNetCommand -WithNoLogging  -ErrorAction SilentlyContinue
        ThenErrorMessage ('failed\ with\ exit\ code')
    }
}
