
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dotNetOutput = $null
$failed = $false
$taskProperties = @{ }

function Init
{
    $script:dotNetOutput = $null
    $script:failed = $false
    $script:taskProperties = @{ }
}

function GivenProject
{
    [CmdletBinding(DefaultParameterSetName='Passing')]
    Param(
        [Parameter(Position=0)]
        [string]
        $Path,

        [Parameter(Mandatory=$true, ParameterSetName='Passing')]
        [switch]
        $WithPassingTests,

        [Parameter(Mandatory=$true, ParameterSetName='Failing')]
        [switch]
        $WithFailingTests
    )

    $projectRoot = Join-Path -Path $TestDrive.FullName -ChildPath ($Path | Split-Path -Parent)
    New-Item -Path $projectRoot -ItemTYpe 'Directory' -Force | Out-Null

    $test = 'Assert.Pass();'
    if ($WithFailingTests)
    {
        $test = 'Assert.That(1, Is.EqualTo(2));'
    }

@'
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <TargetFramework>netcoreapp2.0</TargetFramework>
    </PropertyGroup>

    <ItemGroup>
        <PackageReference Include="nunit" Version="3.10.1" />
        <PackageReference Include="NUnit3TestAdapter" Version="3.10.0" />
        <PackageReference Include="Microsoft.NET.Test.Sdk" Version="15.6.1" />
    </ItemGroup>
</Project>
'@ | Set-Content -Path (Join-Path -Path $projectRoot -ChildPath ($Path | Split-Path -Leaf))

@"
using NUnit.Framework;

namespace $([IO.Path]::GetFileNameWithoutExtension($Path))
{
	[TestFixture]
	public class Tests
    {
        [Test]
        public void Test1()
        {
            $($test)
        }
    }
}
"@ | Set-Content -Path (Join-Path -Path $ProjectRoot -ChildPath 'TestFixture.cs')
}

function GivenTaskProperties
{
    Param(
        [hashtable]
        $Properties
    )

    $script:taskProperties = $Properties
}

function ThenFileExists
{
    Param(
        $Path
    )

    It ('should create the file "{0}"' -f $Path) {
        Join-Path -Path $TestDrive.FullName -ChildPath $Path | Should -Exist
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
            $dotNetOutput -join [Environment]::NewLine | Should -Match $Contains
        }
    }
    else
    {
        It ('output should not contain ''{0}''' -f $DoesNotContain) {
            $dotNetOutput -join [Environment]::NewLine | Should -Not -Match $DoesNotContain
        }
    }
}

function ThenTaskFailedWithError
{
    param(
        $Message
    )

    It 'task should fail' {
        $failed | Should -Be $true
    }

    It ('should write an error matching /{0}/' -f $Message) {
        $Global:Error[0] | Should -Match $Message
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
        $minLines = 500
        $maxLines = 3000
    }
    elseif ($Diagnostic)
    {
        $minLines = 7000
        $maxLines = 10000000
    }

    $outputLines = $dotNetOutput | Measure-Object | Select-Object -ExpandProperty 'Count'

    It 'should run with correct verbosity' {
        $outputLines | Should -BeGreaterThan $minLines
        $outputLines | Should -BeLessThan $maxLines
    }
}

function WhenRunningDotNetTest
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

    $taskContext = New-WhiskeyTestContext @developerOrBuildServer -ForBuildRoot $TestDrive.FullName
    $taskProperties['SdkVersion'] = '2.1.4'

    # Need to build the test project first since the DotNetTest task is configured to not build anything.
    $dotNetBuildTaskProperties = @{ 'SdkVersion' = '2.1.4' }
    if ($taskProperties['Path'])
    {
        $dotNetBuildTaskProperties['Path'] = $taskProperties['Path']
    }
    Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $dotNetBuildTaskProperties -Name 'DotNetBuild' -ErrorAction Ignore

    try
    {
        $Global:Error.Clear()
        $script:dotNetOutput = Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskProperties -Name 'DotNetTest'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

InModuleScope Whiskey {
    Describe 'DotNetTest.[Whiskey.RequiresTool] attribute' {
        $dotNetTestTaskAttributes = (Get-Command -Name 'Invoke-WhiskeyDotNetTest').ScriptBlock.Attributes
        $requiresToolAttribute = $dotNetTestTaskAttributes | Where-Object { $_.TypeId.Name -eq 'RequiresToolAttribute' }

        It 'should have a [Whiskey.RequiresTool] attribute' {
            $requiresToolAttribute | Should -Not -BeNullOrEmpty
        }

        It 'should install the "DotNet" tool' {
            $requiresToolAttribute | Get-Member -Name 'Name' | Should -Not -BeNullOrEmpty
            $requiresToolAttribute.Name | Should -Be 'DotNet'
        }

        It 'should accept an "SdkVersion" property in the whiskey.yml' {
            $requiresToolAttribute | Get-Member -Name 'VersionParameterName' | Should -Not -BeNullOrEmpty
            $requiresToolAttribute.VersionParameterName -eq 'SdkVersion'
        }
    }
}

Describe 'DotNetTest.when not given any Paths' {
    Context 'By Developer' {
        Init
        GivenProject 'DotNetCoreTestProject.csproj' -WithPassingTests
        WhenRunningDotNetTest -ForDeveloper
        ThenOutput -Contains 'Test\ Run\ Successful.'
        ThenVerbosityIs -Minimal
        ThenTaskSuccess
    }

    Context 'By BuildServer' {
        Init
        GivenProject 'DotNetCoreTestProject.csproj' -WithPassingTests
        WhenRunningDotNetTest -ForBuildServer
        ThenOutput -Contains 'Test\ Run\ Successful.'
        ThenVerbosityIs -Detailed
        ThenTaskSuccess
    }
}

Describe 'DotNetTest.when not given any Paths and no csproj or solution exists' {
    Init
    WhenRunningDotNetTest -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'dotnet\.exe\ failed\ with\ exit\ code\ \d+'
}

Describe 'DotNetTest.when given Path to nonexistent csproj file' {
    Init
    GivenTaskProperties @{ 'Path' = 'nonexistent.csproj' }
    WhenRunningDotNetTest -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'nonexistent\.csproj"\ does\ not\ exist'
}

Describe 'DotNetTest.when project was not built first' {
    Init
    Mock -CommandName 'Invoke-WhiskeyTask' -ParameterFilter { $Name -eq 'DotNetBuild' }
    WhenRunningDotNetTest -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'dotnet\.exe\ failed\ with\ exit\ code\ \d+'
}

Describe 'DotNetTest.when given multiple Paths to a csproj file' {
    Init
    GivenProject 'Tests\Unit\UnitTestProject.csproj' -WithPassingTests
    GivenProject 'Tests\Integration\IntegrationTestProject.csproj' -WithPassingTests
    GivenTaskProperties @{ 'Path' = 'Tests\Unit\UnitTestProject.csproj','Tests\Integration\IntegrationTestProject.csproj' }
    WhenRunningDotNetTest
    ThenOutput -Contains 'Running\ all\ tests\ in\ .*\\UnitTestProject\.dll'
    ThenOutput -Contains 'Running\ all\ tests\ in\ .*\\IntegrationTestProject\.dll'
    ThenOutput -Contains 'Test\ Run\ Successful.'
    ThenTaskSuccess
}

Describe 'DotNetTest.when given multiple Paths to a csproj file and one of them has failing tests' {
    Init
    GivenProject 'Tests\Unit\UnitTestProject.csproj' -WithPassingTests
    GivenProject 'Tests\Integration\IntegrationTestProject.csproj' -WithFailingTests
    GivenTaskProperties @{ 'Path' = 'Tests\Unit\UnitTestProject.csproj','Tests\Integration\IntegrationTestProject.csproj' }
    WhenRunningDotNetTest -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'dotnet\.exe\ failed\ with\ exit\ code\ \d+'
}

Describe 'DotNetTest.when given verbosity level' {
    Context 'By Developer' {
        Init
        GivenProject 'DotNetCoreTestProject.csproj' -WithPassingTests
        GivenTaskProperties @{ 'Verbosity' = 'diagnostic' }
        WhenRunningDotNetTest -ForDeveloper
        ThenVerbosityIs -Diagnostic
        ThenTaskSuccess
    }

    Context 'By BuildServer' {
        Init
        GivenProject 'DotNetCoreTestProject.csproj' -WithPassingTests
        GivenTaskProperties @{ 'Verbosity' = 'diagnostic' }
        WhenRunningDotNetTest -ForBuildServer
        ThenVerbosityIs -Diagnostic
        ThenTaskSuccess
    }
}

Describe 'DotNetTest.when given additional arguments' {
    Init
    GivenProject 'DotNetCoreTestProject.csproj' -WithPassingTests
    GivenTaskProperties @{ 'Argument' = '--list-tests' }
    WhenRunningDotNetTest
    ThenOutput -Contains 'The\ following\ tests\ are\ available:'
    ThenTaskSuccess
}

Describe 'DotNetTest.when given Filter expression' {
    Init
    GivenProject 'DotNetCoreTestProject.csproj' -WithPassingTests
    GivenTaskProperties @{ 'Filter' = 'NonExistentTest' }
    WhenRunningDotNetTest
    ThenOutput -Contains 'No\ test\ is\ available\ in\ .*\\DotNetCoreTestProject.dll'
    ThenTaskSuccess
}

Describe 'DotNetTest.when given Logger' {
    Init
    GivenProject 'DotNetCoreTestProject.csproj' -WithPassingTests
    GivenTaskProperties @{ 'Logger' = 'trx;LogFileName=testresultsfile.trx' }
    WhenRunningDotNetTest
    ThenOutput -Contains 'Test\ Run\ Successful.'
    ThenFileExists '.output\testresultsfile.trx'
    ThenTaskSuccess
}
