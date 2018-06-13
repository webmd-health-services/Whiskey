
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dotNetOutput = $null
$failed = $false
$taskContext = $null
$taskProperties = @{ }

function Init
{
    $script:dotNetOutput = $null
    $script:failed = $false
    $script:taskContext = $null
    $script:taskProperties = @{ }
}

function GivenDotNetCoreProject
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $Path,

        [Parameter(Mandatory=$true)]
        [string]
        $WithPackageReference
    )

    $projectRoot = Join-Path -Path $TestDrive.FullName -ChildPath ($Path | Split-Path -Parent)
    New-Item -Path $projectRoot -ItemTYpe 'Directory' -Force | Out-Null

    $csprojPath = Join-Path -Path $projectRoot -ChildPath ($Path | Split-Path -Leaf)

    $PackageReferenceEntry = '<PackageReference Include="{0}" />' -f $WithPackageReference

@"
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <TargetFramework>netcoreapp2.0</TargetFramework>
        <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    </PropertyGroup>
    <ItemGroup>
        $($PackageReferenceEntry)
    </ItemGroup>
</Project>
"@ | Set-Content -Path $csprojPath
}

function GivenFailingDotNetCoreProject
{
    param(
        $Path
    )

        $csprojPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
@'
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
    </PropertyGroup>
</Project>
'@ | Set-Content -Path $csprojPath
}

function GivenTaskProperties
{
    Param(
        [hashtable]
        $Properties
    )

    $script:taskProperties = $Properties
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

function ThenPublished
{
    [CmdletBinding(DefaultParameterSetName='Default')]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Project')]
        [string]
        $ProjectAssembly,

        [Parameter(Mandatory=$true,ParameterSetName='ThirdParty')]
        [string]
        $ThirdPartyAssembly
    )

    if ($ProjectAssembly)
    {
        $assemblyPath = Join-Path -Path $TestDrive.FullName -ChildPath $ProjectAssembly

        It ('should build and publish project assembly to "{0}"' -f $ProjectAssembly) {
            $assemblyPath | Should -Exist
        }

        $builtVersion = Get-Item -Path $assemblyPath | Select-Object -ExpandProperty 'VersionInfo' | Select-Object -ExpandProperty 'ProductVersion'
        It 'should build assembly with correct version' {
            $builtVersion | Should -Be $taskContext.Version.SemVer1
        }
    }
    else
    {
        $assemblyPath = Join-Path -Path $TestDrive.FullName -ChildPath $ThirdPartyAssembly

        It ('should publish third-party assembly to "{0}"' -f $ThirdPartyAssembly) {
            $assemblyPath | Should -Exist
        }
    }
}

function ThenTaskFailedWithError
{
    param(
        $ExpectedError
    )

    It 'task should fail' {
        $failed | Should -BeTrue
    }

    It 'should write an error' {
        $Global:Error[0] | Should -Match $ExpectedError
    }
}

function ThenTaskSuccess
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'task should succeed' {
        $failed | Should -BeFalse
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
        $minLines = 5
        $maxLines = 30
    }
    elseif ($Detailed)
    {
        $minLines = 2000
        $maxLines = 20000
    }
    elseif ($Diagnostic)
    {
        $minLines = 100000
        $maxLines = 10000000
    }

    $outputLines = $dotNetOutput | Measure-Object | Select-Object -ExpandProperty 'Count'

    It 'should run with correct verbosity' {
        $outputLines | Should -BeGreaterThan $minLines
        $outputLines | Should -BeLessThan $maxLines
    }
}

function WhenRunningDotNetPublish
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
    $taskProperties['SdkVersion'] = '2.1.4'

    try
    {
        $Global:Error.Clear()
        $script:dotNetOutput = Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskProperties -Name 'DotNetPublish'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

InModuleScope Whiskey {
    Describe 'DotNetPublish.[Whiskey.RequiresTool] attribute' {
        $dotNetPublishTaskAttributes = (Get-Command -Name 'Invoke-WhiskeyDotNetPublish').ScriptBlock.Attributes
        $requiresToolAttribute = $dotNetPublishTaskAttributes | Where-Object { $_.TypeId.Name -eq 'RequiresToolAttribute' }

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

Describe 'DotNetPublish.when not given any Paths' {
    Context 'By Developer' {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
        WhenRunningDotNetPublish -ForDeveloper
        ThenPublished -ProjectAssembly 'bin\Debug\publish\DotNetCore.dll'
        ThenPublished -ThirdPartyAssembly 'bin\Debug\publish\Microsoft.AspNetCore.Http.dll'
        ThenVerbosityIs -Minimal
        ThenTaskSuccess
    }

    Context 'By BuildServer' {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
        WhenRunningDotNetPublish -ForBuildServer
        ThenPublished -ProjectAssembly 'bin\Release\publish\DotNetCore.dll'
        ThenPublished -ThirdPartyAssembly 'bin\Release\publish\Microsoft.AspNetCore.Http.dll'
        ThenVerbosityIs -Detailed
        ThenTaskSuccess
    }
}

Describe 'DotNetPublish.when not given any Paths and no csproj or solution exists' {
    Init
    WhenRunningDotNetPublish -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'dotnet\.exe\ failed\ with\ exit\ code\ \d+'
}

Describe 'DotNetPublish.when given Path to nonexistent csproj file' {
    Init
    GivenTaskProperties @{ 'Path' = 'NonExistent.csproj' }
    WhenRunningDotNetPublish -ErrorAction SilentlyContinue
    ThenTaskFailedWithError '\bdoes\ not\ exist\b'
}

Describe 'DotNetPublish.when given Path to a csproj file' {
    Init
    GivenDotNetCoreProject 'src\DotNetCore.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
    GivenTaskProperties @{ 'Path' = 'src\DotNetCore.csproj' }
    WhenRunningDotNetPublish
    ThenPublished -ProjectAssembly 'src\bin\Debug\publish\DotNetCore.dll'
    ThenPublished -ThirdPartyAssembly 'src\bin\Debug\publish\Microsoft.AspNetCore.Http.dll'
    ThenTaskSuccess
}

Describe 'DotNetPublish.when given multiple Paths to csproj files' {
    Init
    GivenDotNetCoreProject 'src\frontend\DotNetCoreFrontend.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
    GivenDotNetCoreProject 'src\backend\DotNetCoreBackend.csproj' -WithPackageReference 'Microsoft.AspNetCore.WebSockets.Server'
    GivenTaskProperties @{ 'Path' = 'src\frontend\DotNetCoreFrontend.csproj','src\backend\DotNetCoreBackend.csproj' }
    WhenRunningDotNetPublish
    ThenPublished -ProjectAssembly 'src\frontend\bin\Debug\publish\DotNetCoreFrontend.dll'
    ThenPublished -ProjectAssembly 'src\backend\bin\Debug\publish\DotNetCoreBackend.dll'
    ThenPublished -ThirdPartyAssembly 'src\frontend\bin\Debug\publish\Microsoft.AspnetCore.Http.dll'
    ThenPublished -ThirdPartyAssembly 'src\backend\bin\Debug\publish\Microsoft.AspnetCore.WebSockets.Server.dll'
    ThenTaskSuccess
}

Describe 'DotNetPublish.when given multiple projects and one fails to build' {
    Init
    GivenDotNetCoreProject 'DotNetCore.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
    GivenFailingDotNetCoreProject 'FailingDotNetCore.csproj'
    GivenTaskProperties @{ 'Path' = 'DotNetCore.csproj','FailingDotNetCore.csproj' }
    WhenRunningDotNetPublish -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'dotnet\.exe\ failed\ with\ exit\ code\ \d+'
}

Describe 'DotNetPublish.when given verbosity level' {
    Context 'By Developer' {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
        GivenTaskProperties @{ 'Verbosity' = 'diagnostic' }
        WhenRunningDotNetPublish -ForDeveloper
        ThenPublished -ProjectAssembly 'bin\Debug\publish\DotNetCore.dll'
        ThenPublished -ThirdPartyAssembly 'bin\Debug\publish\Microsoft.AspNetCore.Http.dll'
        ThenVerbosityIs -Diagnostic
        ThenTaskSuccess
    }

    Context 'By BuildServer' {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
        GivenTaskProperties @{ 'Verbosity' = 'diagnostic' }
        WhenRunningDotNetPublish -ForBuildServer
        ThenPublished -ProjectAssembly 'bin\Release\publish\DotNetCore.dll'
        ThenPublished -ThirdPartyAssembly 'bin\Release\publish\Microsoft.AspNetCore.Http.dll'
        ThenVerbosityIs -Diagnostic
        ThenTaskSuccess
    }
}

Describe 'DotNetPublish.when given output directory' {
    Init
    GivenDotNetCoreProject 'src\DotNetCore.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
    GivenDotNetCoreProject 'app\DotNetCoreApp.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
    GivenTaskProperties @{ 'Path'= 'src\DotNetCore.csproj','app\DotNetCoreApp.csproj'; 'OutputDirectory' = 'CustomBinDirectory' }
    WhenRunningDotNetPublish
    ThenPublished -ProjectAssembly 'src\CustomBinDirectory\DotNetCore.dll'
    ThenPublished -ProjectAssembly 'app\CustomBinDirectory\DotNetCoreApp.dll'
    ThenPublished -ThirdPartyAssembly 'src\CustomBinDirectory\Microsoft.AspNetCore.Http.dll'
    ThenPublished -ThirdPartyAssembly 'app\CustomBinDirectory\Microsoft.AspNetCore.Http.dll'
    ThenTaskSuccess
}

Describe 'DotNetPublish.when given additional argument -nologo' {
    Init
    GivenDotNetCoreProject 'DotNetCore.csproj' -WithPackageReference 'Microsoft.AspNetCore.Http'
    GivenTaskProperties @{ 'Argument' = '-nologo'; 'OutputDirectory' = 'bin' }
    WhenRunningDotNetPublish
    ThenOutput -DoesNotContain '\bCopyright\ \(C\)\ Microsoft\ Corporation\b'
    ThenPublished -ProjectAssembly 'bin\DotNetCore.dll'
    ThenPublished -ThirdPartyAssembly 'bin\Microsoft.AspNetCore.Http.dll'
    ThenTaskSuccess
}
