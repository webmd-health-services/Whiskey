
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Resolve-WhiskeyDotnetSdkVersion.ps1')

$argument = $null
$dotnetOutput = $null
$failed = $false
$outputDirectory = $null
$path = $null
$taskContext = $null
$verbosity = $null

function Init
{
    $script:argument = $null
    $script:dotnetOutput = $null
    $script:failed = $false
    $script:outputDirectory = $null
    $script:path = $null
    $script:taskContext = $null
    $script:verbosity = $null
}

function GivenArgument
{
    param(
        $Argument
    )

    $script:argument = $Argument
}

function GivenDotNetCoreProject
{
    param(
        [string[]]
        $Name
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

function GivenOutputDirectory
{
    param(
        $Directory
    )

    $script:outputDirectory = $Directory
}

function GivenPath
{
    param(
        [string[]]
        $Path
    )

    $script:path = $Path
}

function GivenVerbosity
{
    param(
        $Level
    )

    $script:verbosity = $Level
}

function ThenBuiltCorrectVersion
{
    $builtAssemblies = Get-ChildItem -Path $TestDrive.FullName -Filter '*.dll' -Recurse | Select-Object -ExpandProperty 'FullName'

    It 'should build the correct version' {
        $builtAssemblies | Should -Not -BeNullOrEmpty

        foreach ($assembly in $builtAssemblies) {
            $builtVersion = Get-Item -Path $assembly | Select-Object -ExpandProperty 'VersionInfo' | Select-Object -ExpandProperty 'ProductVersion'
            $builtVersion | Should -Be $taskContext.Version.SemVer1.ToString()
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
            $dotnetOutput | Should -Match $Contains
        }
    }
    else
    {
        It ('output should not contain ''{0}''' -f $DoesNotContain) {
            $dotnetOutput | Should -Not -Match $DoesNotContain
        }
    }
}

function ThenProjectBuilt
{
    param(
        [string[]]
        $Assembly,

        [switch]
        $ForBuildServer,

        [string]
        $Directory
    )

    $outputDir = Join-Path -Path $TestDrive.FullName -ChildPath 'bin\Debug\netcoreapp2.0'
    if ($Directory)
    {
        $outputDir = Join-Path -Path $TestDrive.FullName -ChildPath $Directory
    }
    elseif ($ForBuildServer)
    {
        $outputDir = Join-Path -Path $TestDrive.FullName -ChildPath 'bin\Release\netcoreapp2.0'
    }

    It 'should build the project' {
        foreach ($name in $Assembly)
        {
            Join-Path -Path $outputDir -ChildPath $name | Should -Exist
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
        $minLines = 10
        $maxLines = 30
    }
    elseif ($Detailed)
    {
        $minLines = 2000
        $maxLines = 20000
    }
    elseif ($Diagnostic)
    {
        $minLines = 30000
        $maxLines = 10000000
    }

    $outputLines = $dotnetOutput | Measure-Object | Select-Object -ExpandProperty 'Count'

    It 'should run with correct verbosity' {
        $outputLines | Should -BeGreaterThan $minLines
        $outputLines | Should -BeLessThan $maxLines
    }
}

function WhenRunningDotNetBuild
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
    $taskParameter = @{ 'SDKVersion' = '2.*' }

    if ($outputDirectory)
    {
        $taskParameter['OutputDirectory'] = $outputDirectory
    }

    if ($argument)
    {
        $taskParameter['Argument'] = $argument
    }

    if ($path)
    {
        $taskParameter['Path'] = $Path
    }

    if ($verbosity)
    {
        $taskParameter['Verbosity'] = $verbosity
    }

    try
    {
        $Global:Error.Clear()
        $script:dotnetOutput = Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'DotNetBuild'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'DotNetBuild.when not given any Paths' {
    Context 'By Developer' {
        Init
        GivenDotnetCoreProject 'DotNetCore.csproj'
        WhenRunningDotNetBuild -ForDeveloper
        ThenProjectBuilt 'DotNetCore.dll'
        ThenBuiltCorrectVersion
        ThenVerbosityIs -Minimal
        ThenTaskSuccess
    }

    Context 'By BuildServer' {
        Init
        GivenDotnetCoreProject 'DotNetCore.csproj'
        WhenRunningDotNetBuild -ForBuildServer
        ThenProjectBuilt 'DotNetCore.dll' -ForBuildServer
        ThenBuiltCorrectVersion
        ThenVerbosityIs -Detailed
        ThenTaskSuccess
    }
}

Describe 'DotNetBuild.when not given any Paths and no csproj or solution exists' {
    Init
    WhenRunningDotNetBuild -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'failed\ with\ exit\ code'
}

Describe 'DotNetBuild.when given Path to a csproj file' {
    Init
    GivenDotnetCoreProject 'DotNetCore.csproj'
    GivenPath 'DotNetCore.csproj'
    WhenRunningDotNetBuild
    ThenProjectBuilt 'DotNetCore.dll'
    ThenBuiltCorrectVersion
    ThenTaskSuccess
}

Describe 'DotNetBuild.when given Path to nonexistent csproj file' {
    Init
    GivenPath 'nonexistent.csproj'
    WhenRunningDotNetBuild -ErrorAction SilentlyContinue
    ThenTaskFailedWithError '\bdoes\ not\ exist\b'
}

Describe 'DotNetBuild.when dotnet build fails' {
    Init
    GivenDotnetCoreProject 'DotNetCore.csproj'
    GivenFailingDotNetCoreProject 'FailingDotNetCore.csproj'
    GivenPath 'DotNetCore.csproj','FailingDotNetCore.csproj'
    WhenRunningDotNetBuild -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'failed\ with\ exit\ code'
}

Describe 'DotNetBuild.when given multiple Paths to csproj files' {
    Init
    GivenDotnetCoreProject 'DotNetCore.csproj', 'DotNetCore2.csproj'
    GivenPath 'DotNetCore.csproj', 'DotNetCore2.csproj'
    WhenRunningDotNetBuild
    ThenProjectBuilt 'DotNetCore.dll','DotNetCore2.dll'
    ThenBuiltCorrectVersion
    ThenTaskSuccess
}

Describe 'DotNetBuild.when given verbosity level' {
    Context 'By Developer' {
        Init
        GivenDotnetCoreProject 'DotNetCore.csproj'
        GivenVerbosity 'diagnostic'
        WhenRunningDotNetBuild
        ThenProjectBuilt 'DotNetCore.dll'
        ThenBuiltCorrectVersion
        ThenVerbosityIs -Diagnostic
        ThenTaskSuccess
    }

    Context 'By BuildServer' {
        Init
        GivenDotnetCoreProject 'DotNetCore.csproj'
        GivenVerbosity 'diagnostic'
        WhenRunningDotNetBuild
        ThenProjectBuilt 'DotNetCore.dll'
        ThenBuiltCorrectVersion
        ThenVerbosityIs -Diagnostic
        ThenTaskSuccess
    }
}

Describe 'DotNetBuild.when given output directory' {
    Init
    GivenDotnetCoreProject 'DotNetCore.csproj'
    GivenOutputDirectory 'Output Dir'
    WhenRunningDotNetBuild
    ThenProjectBuilt 'DotNetCore.dll' -Directory 'Output Dir'
    ThenBuiltCorrectVersion
    ThenTaskSuccess
}

Describe 'DotNetBuild.when given additional arguments --no-restore and -nologo' {
    Init
    GivenDotnetCoreProject 'DotNetCore.csproj'
    WhenRunningDotNetBuild

    GivenArgument '--no-restore','-nologo'
    WhenRunningDotNetBuild
    ThenProjectBuilt 'DotNetCore.dll'
    ThenBuiltCorrectVersion
    ThenOutput -DoesNotContain '\bRestore\ completed\b'
    ThenOutput -DoesNotContain '\bCopyright\ \(C\)\ Microsoft\ Corporation\b'
    ThenTaskSuccess
}
