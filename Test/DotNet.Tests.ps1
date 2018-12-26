    
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Environment]::SetEnvironmentVariable( 'DOTNET_SKIP_FIRST_TIME_EXPERIENCE', 'true', [EnvironmentVariableTarget]::Process ) 

$argument = $null
$dotNetOutput = $null
$failed = $false
$outputDirectory = $null
$path = $null
$taskContext = $null
$verbosity = $null

function Init
{
    $script:argument = $null
    $script:dotNetOutput = $null
    $script:failed = $false
    $script:outputDirectory = $null
    $script:path = $null
    $script:taskContext = $null
    $script:verbosity = $null
}

function GivenDotNetCoreProject
{
    param(
        [string[]]
        $Path,

        $Targeting
    )

    foreach ($project in $Path)
    {
        $projectRoot = Join-Path -Path $TestDrive.FullName -ChildPath ($project | Split-Path -Parent)
        New-Item -Path $projectRoot -ItemTYpe 'Directory' -Force | Out-Null

        $csprojPath = Join-Path -Path $projectRoot -ChildPath ($project | Split-Path -Leaf)

(@'
<Project Sdk="Microsoft.NET.Sdk">
    <PropertyGroup>
        <TargetFramework>{0}</TargetFramework>
    </PropertyGroup>
</Project>
'@ -f $Targeting) | Set-Content -Path $csprojPath
    }
}

function ThenLogFile
{
    param(
        $Name,
        [Switch]
        $Not,
        [Switch]
        $Exists
    )

    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath '.output'
    $fullPath = Join-Path -Path $fullPath -ChildPath $Name
    if( $Not )
    {
        If ('should not create build log file') {
            $fullPath | Should -Not -Exist
        }
    }
    else
    {
        If ('should create build log file') {
            $fullPath | Should -Exist
        }
    }
}

function ThenProjectBuilt
{
    param(
        [string]
        $AssemblyPath
    )

    $AssemblyPath = Join-Path -Path $TestDrive.FullName -ChildPath $AssemblyPath

    It 'should build the project assembly' {
        $AssemblyPath | Should -Exist
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

function WhenRunningDotNet
{
    [CmdletBinding()]
    param(
        $Command,

        $WithPath,

        $WithArgument,

        $WithSdkVersion
    )

    $script:taskContext = New-WhiskeyTestContext -ForBuildServer
    $taskParameter = @{ }

    if( $Command )
    {
        $taskParameter['Command'] = $Command
    }

    if( $WithPath )
    {
        $taskParameter['Path'] = $WithPath
    }

    if ($WithArgument)
    {
        $taskParameter['Argument'] = $WithArgument
    }

    if( $WithSdkVersion )
    {
        $taskParameter['SdkVersion'] = $WithSdkVersion
    }

    try
    {
        $Global:Error.Clear()
        $script:dotNetOutput = Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'DotNet'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'DotNetBuild.when command succeeds' {
    try
    {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        WhenRunningDotNet 'build' -WithArgument @( '-c=$(WHISKEY_MSBUILD_CONFIGURATION)', '--output=bin\' ) -WithSdkVersion '2.*'
        ThenProjectBuilt 'bin\DotNetCore.dll'
        ThenLogFile 'dotnet.build.log' -Exists
        ThenTaskSuccess
    }
    finally
    {
        Remove-DotNet
    }
}

Describe 'DotNetBuild.when command fails' {
    try
    {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        WhenRunningDotNet 'build' -WithArgument @( '-c=$(WHISKEY_MSBUILD_CONFIGURATION)', '--output=bin\' ) -WithSdkVersion '1.1.*' -ErrorAction SilentlyContinue
        ThenTaskFailedWithError 'dotnet\.exe\ failed\ with\ exit\ code'
    }
    finally
    {
        Remove-DotNet
    }
}

Describe 'DotNetBuild.when passing paths to the command' {
    try
    {
        Init
        GivenDotNetCoreProject 'DotNetCore\DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        GivenDotNetCoreProject 'DotNetCore2\DotNetCore2.csproj' -Targeting 'netcoreapp2.0'
        WhenRunningDotNet 'build' -WithPath 'DotNetCore*\*.csproj' -WithSdkVersion '2.*'
        ThenProjectBuilt 'DotNetCore\bin\Debug\netcoreapp2.0\DotNetCore.dll'
        ThenProjectBuilt 'DotNetCore2\bin\Debug\netcoreapp2.0\DotNetCore2.dll'
        ThenLogFile 'dotnet.build.DotNetCore.csproj.log' -Exists
        ThenLogFile 'dotnet.build.DotNetCore2.csproj.log' -Exists
        ThenTaskSuccess
    }
    finally
    {
        Remove-DotNet
    }
}


Describe 'DotNetBuild.when command is missing' {
    try
    {
        Init
        GivenDotNetCoreProject 'DotNetCore\DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        WhenRunningDotNet -ErrorAction SilentlyContinue
        ThenTaskFailedWithError 'is\ required'
    }
    finally
    {
        Remove-DotNet
    }
}

