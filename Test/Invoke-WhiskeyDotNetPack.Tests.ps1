
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Resolve-WhiskeyDotNetSdkVersion.ps1')

$argument = $null
$dotNetOutput = $null
$failed = $false
$path = $null
$taskContext = $null
$symbols = $null
$verbosity = $null

function Init
{
    $script:argument = $null
    $script:dotNetOutput = $null
    $script:failed = $false
    $script:path = $null
    $script:taskContext = $null
    $script:symbols = $null
    $script:verbosity = $null
}

function GivenArgument
{
    param(
        $Argument
    )

    $script:argument = $Argument
}

function GivenBuiltDotNetCoreProject
{
    [CmdletBinding(DefaultParameterSetName='ForDeveloper')]
    param(
        [Parameter(Position=0)]
        [string[]]
        $Name,

        [Parameter(ParameterSetName='ForDeveloper')]
        [switch]
        $ForDeveloper,

        [Parameter(ParameterSetName='ForBuildServer')]
        [switch]
        $ForBuildServer
    )

    foreach ($project in $Name)
    {
        $csprojPath = Join-Path -Path $TestDrive.FullName -ChildPath $project
@'
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <TargetFramework>netcoreapp2.0</TargetFramework>
    </PropertyGroup>
</Project>
'@ | Set-Content -Path $csprojPath

    }

    $developerOrBuildServer = @{ 'ForDeveloper' = $true }
    if ($ForBuildServer)
    {
        $developerOrBuildServer = @{ 'ForBuildServer' = $true }
    }

    $context = New-WhiskeyTestContext @developerOrBuildServer -ForBuildRoot $TestDrive.FullName
    $parameter = @{
        'Path' = $Name
        'SdkVersion' = '2.*'
    }

    Invoke-WhiskeyTask -TaskContext $context -Parameter $parameter -Name 'DotNetBuild' | Out-Null
}

function GivenFailingDotNetCoreProject
{
    param(
        $Name
    )

        $csprojPath = Join-Path -Path $TestDrive.FullName -ChildPath $Name
@'
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
    </PropertyGroup>
</Project>
'@ | Set-Content -Path $csprojPath

}

function GivenPath
{
    param(
        [string[]]
        $Path
    )

    $script:path = $Path
}

function GivenSymbols
{
    param(
        $Symbols
    )

    $script:symbols = $Symbols
}

function GivenVerbosity
{
    param(
        $Level
    )

    $script:verbosity = $Level
}

function ThenCreatedPackage
{
    param(
        [string]
        $Name,

        [switch]
        $WithSymbols
    )

    $packagePath = Join-Path -Path $TestDrive.FullName -ChildPath ('.output\{0}.{1}.nupkg' -f $Name,$taskContext.Version.SemVer1.ToString())

    It 'should create NuGet package with correct version' {
        $packagePath | Should -Exist
    }

    if ($WithSymbols)
    {
        $symbolsPackage = Join-Path -Path $TestDrive.FullName -ChildPath ('.output\{0}.{1}.symbols.nupkg' -f $Name,$taskContext.Version.SemVer1.ToString())

        It 'should create the NuGet symbols package' {
            $symbolsPackage | Should -Exist
        }
    }
}

function ThenOutput
{
    param(
        [string]
        $Contains,

        [string]
        $DoesNotContain
    )

    if ($Contains)
    {
        It ('output should contain ''{0}''' -f $Contains) {
            $dotNetOutput | Should -Match $Contains
        }
    }
    else
    {
        It ('output should not contain ''{0}''' -f $DoesNotContain) {
            $dotNetOutput | Should -Not -Match $DoesNotContain
        }
    }
}

function ThenTaskFailedWithError
{
    param(
        $ExpectedError
    )

    It 'task should fail' {
        $failed | Should -Be $true
    }

    It 'should write an error' {
        $Global:Error | Should -Match $ExpectedError
    }
}

function ThenTaskSuccess
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'task should succeed' {
        $failed | Should -Be $false
    }
}

function ThenVerbosityIs
{
    param(
        [switch]
        $Minimal,

        [switch]
        $Detailed,

        [switch]
        $Diagnostic
    )

    if ($Minimal)
    {
        $minLines = 3
        $maxLines = 30
    }
    elseif ($Detailed)
    {
        $minLines = 35
        $maxLines = 3000
    }
    elseif ($Diagnostic)
    {
        $minLines = 30000
        $maxLines = 10000000
    }

    $outputLines = $dotNetOutput | Measure-Object | Select-Object -ExpandProperty 'Count'

    It 'should run with correct verbosity' {
        $outputLines | Should -BeGreaterThan $minLines
        $outputLines | Should -BeLessThan $maxLines
    }
}

function WhenRunningDotNetPack
{
    [CmdletBinding(DefaultParameterSetName='ForDeveloper')]
    param(
        [Parameter(ParameterSetName='ForDeveloper')]
        [switch]
        $ForDeveloper,

        [Parameter(ParameterSetName='ForBuildServer')]
        [switch]
        $ForBuildServer
    )

    $developerOrBuildServer = @{ 'ForDeveloper' = $true }
    if ($ForBuildServer)
    {
        $developerOrBuildServer = @{ 'ForBuildServer' = $true }
    }

    $script:taskContext = New-WhiskeyTestContext @developerOrBuildServer -ForBuildRoot $TestDrive.FullName
    $taskParameter = @{ 'SdkVersion' = '2.*' }

    if ($argument)
    {
        $taskParameter['Argument'] = $argument
    }

    if ($path)
    {
        $taskParameter['Path'] = $Path
    }

    if ($symbols)
    {
        $taskParameter['Symbols'] = $symbols
    }

    if ($verbosity)
    {
        $taskParameter['Verbosity'] = $verbosity
    }

    try
    {
        $Global:Error.Clear()
        $script:dotNetOutput = Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'DotNetPack'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'DotNetPack.when not given any Paths' {
    Context 'By Developer' {
        Init
        GivenBuiltDotNetCoreProject 'DotNetCore.csproj' -ForDeveloper
        WhenRunningDotNetPack -ForDeveloper
        ThenCreatedPackage 'DotNetCore'
        ThenVerbosityIs -Minimal
        ThenTaskSuccess
    }

    Context 'By BuildServer' {
        Init
        GivenBuiltDotNetCoreProject 'DotNetCore.csproj' -ForBuildServer
        WhenRunningDotNetPack -ForBuildServer
        ThenCreatedPackage 'DotNetCore'
        ThenVerbosityIs -Detailed
        ThenTaskSuccess
    }
}

Describe 'DotNetPack.when not given any Paths and no csproj or solution exists' {
    Init
    WhenRunningDotNetPack -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'failed\ with\ exit\ code'
}

Describe 'DotNetPack.when given Path to a csproj file' {
    Init
    GivenBuiltDotNetCoreProject 'DotNetCore.csproj'
    GivenPath 'DotNetCore.csproj'
    WhenRunningDotNetPack
    ThenCreatedPackage 'DotNetCore'
    ThenTaskSuccess
}

Describe 'DotNetPack.when given Path to nonexistent csproj file' {
    Init
    GivenPath 'nonexistent.csproj'
    WhenRunningDotNetPack -ErrorAction SilentlyContinue
    ThenTaskFailedWithError '\bdoes\ not\ exist\b'
}

Describe 'DotNetPack.when dotnet pack fails' {
    Init
    GivenFailingDotNetCoreProject 'FailingDotNetCore.csproj'
    GivenPath 'FailingDotNetCore.csproj'
    WhenRunningDotNetPack -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'failed\ with\ exit\ code'
}

Describe 'DotNetPack.when given multiple Paths to csproj files' {
    Init
    GivenBuiltDotNetCoreProject 'DotNetCore.csproj', 'DotNetCore2.csproj'
    GivenPath 'DotNetCore.csproj', 'DotNetCore2.csproj'
    WhenRunningDotNetPack
    ThenTaskSuccess
}

Describe 'DotNetPack.when given verbosity level' {
    Context 'By Developer' {
        Init
        GivenBuiltDotNetCoreProject 'DotNetCore.csproj' -ForDeveloper
        GivenVerbosity 'diagnostic'
        WhenRunningDotNetPack -ForDeveloper
        ThenCreatedPackage 'DotNetCore'
        ThenVerbosityIs -Diagnostic
        ThenTaskSuccess
    }

    Context 'By BuildServer' {
        Init
        GivenBuiltDotNetCoreProject 'DotNetCore.csproj' -ForBuildServer
        GivenVerbosity 'diagnostic'
        WhenRunningDotNetPack -ForBuildServer
        ThenCreatedPackage 'DotNetCore'
        ThenVerbosityIs -Diagnostic
        ThenTaskSuccess
    }
}

Describe 'DotNetPack.when given including symbols' {
    Init
    GivenBuiltDotNetCoreProject 'DotNetCore.csproj'
    GivenSymbols 'true'
    WhenRunningDotNetPack
    ThenCreatedPackage 'DotNetCore' -WithSymbols
    ThenTaskSuccess
}

Describe 'DotNetPack.when given additional argument ''-nologo''' {
    Init
    GivenBuiltDotNetCoreProject 'DotNetCore.csproj'
    GivenArgument '-nologo'
    WhenRunningDotNetPack
    ThenCreatedPackage 'DotNetCore'
    ThenOutput -DoesNotContain '\bCopyright\ \(C\)\ Microsoft\ Corporation\b'
    ThenTaskSuccess
}
