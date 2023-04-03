
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Environment]::SetEnvironmentVariable( 'DOTNET_SKIP_FIRST_TIME_EXPERIENCE', 'true', [EnvironmentVariableTarget]::Process )

$testRoot = $null
$argument = $null
$dotNetOutput = $null
$failed = $false
$outputDirectory = $null
$path = $null
$taskContext = $null
$verbosity = $null

function GivenDotNetCoreProject
{
    param(
        [String[]]$Path,

        $Targeting
    )

    foreach ($project in $Path)
    {
        $projectRoot = Join-Path -Path $testRoot -ChildPath ($project | Split-Path -Parent)
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

function Init
{
    $script:argument = $null
    $script:dotNetOutput = $null
    $script:failed = $false
    $script:outputDirectory = $null
    $script:path = $null
    $script:taskContext = $null
    $script:verbosity = $null

    $script:testRoot = New-WhiskeyTestRoot
}

function Reset
{
    Remove-DotNet -BuildRoot $testRoot
}

function ThenLogFile
{
    param(
        $Name,
        [switch]$Not,
        [switch]$Exists
    )

    $fullPath = Join-Path -Path $testRoot -ChildPath '.output'
    $fullPath = Join-Path -Path $fullPath -ChildPath $Name
    if( $Not )
    {
        if ('should not create build log file')
        {
            $fullPath | Should -Not -Exist
        }
    }
    else
    {
        if ('should create build log file')
        {
            $fullPath | Should -Exist
        }
    }
}

function ThenProjectBuilt
{
    param(
        [String]$AssemblyPath
    )

    $AssemblyPath = Join-Path -Path $testRoot -ChildPath $AssemblyPath

    $AssemblyPath | Should -Exist
}

function ThenTaskFailedWithError
{
    param(
        $ExpectedError
    )

    $failed | Should -BeTrue
    $Global:Error |
        Where-Object { $_ | Get-Member 'ScriptStackTrace' } |
        Where-Object 'ScriptStackTrace' -NotMatch '\bdotnet-install\.(ps1|sh)\b' |
        Should -Match $ExpectedError
}

function ThenTaskSuccess
{
    $Global:Error |
        Where-Object { $_ | Get-Member 'ScriptStackTrace' } |
        Where-Object 'ScriptStackTrace' -NotMatch '\bdotnet-install\.(ps1|sh)\b' |
        Should -BeNullOrEmpty
    $failed | Should -BeFalse
}

function WhenRunningDotNet
{
    [CmdletBinding()]
    param(
        $Command,

        $WithPath,

        $WithArgument,

        $InWorkingDirectory,

        [switch] $NotLogging,

        [String] $UsingSdk
    )

    $script:taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $testRoot
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

    if( $InWorkingDirectory )
    {
        $taskParameter['WorkingDirectory'] = $InWorkingDirectory
    }

    if( $NotLogging )
    {
        $taskParameter['NoLog'] = $true
    }

    if( $UsingSdk )
    {
        $taskParameter['SdkVersion'] = $UsingSdk
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

Describe 'DotNet.when command succeeds' {
    AfterEach { Reset }
    It 'should pass build' {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        WhenRunningDotNet 'build' -WithArgument @( '-c=$(WHISKEY_MSBUILD_CONFIGURATION)', '--output=bin\' )
        ThenProjectBuilt 'bin\DotNetCore.dll'
        ThenLogFile 'dotnet.build.log' -Exists
        ThenTaskSuccess
    }
}

Describe 'DotNet.when not logging' {
    AfterEach { Reset }
    It 'should pass build' {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        WhenRunningDotNet 'build' `
                          -WithArgument @( '-c=$(WHISKEY_MSBUILD_CONFIGURATION)', '--output=bin\' ) `
                          -NotLogging
        ThenProjectBuilt 'bin\DotNetCore.dll'
        ThenLogFile 'dotnet*.log' -Not -Exists
        ThenTaskSuccess
    }
}

Describe 'DotNet.when customizing SDK' {
    AfterEach { Reset }
    It 'should install that version of the SDK' {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        Mock -CommandName 'Get-Command' `
             -ModuleName 'Whiskey' `
             -ParameterFilter { $Name -eq 'dotnet' -and $All -and $ErrorActionPreference -eq 'Ignore' }
        WhenRunningDotNet 'build' `
                          -WithArgument @( '-c=$(WHISKEY_MSBUILD_CONFIGURATION)', '--output=bin\' ) `
                          -NotLogging `
                          -UsingSdk '5.*'
        ThenProjectBuilt 'bin\DotNetCore.dll'
        ThenTaskSuccess
        $sdkInstallPath = Join-Path -Path $testRoot -ChildPath '.dotnet'
        $sdkInstallPath = Join-Path -Path $sdkInstallPath -ChildPath 'sdk'
        $sdkInstallPath | Should -Exist

        (& (Join-Path -Path $testRoot -ChildPath '.dotnet\dotnet') '--list-sdks') |
            Where-Object { $_ -match "5\.\d+\.\d+ \[$([regex]::Escape($sdkInstallPath))\]" } |
            Should -Not -BeNullOrEmpty
    }
}

Describe 'DotNet.when command fails' {
    AfterEach { Reset }
    It 'should fail build' {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj' -Targeting 'netcoreappX.x'
        WhenRunningDotNet 'build' -WithArgument @( '-c=$(WHISKEY_MSBUILD_CONFIGURATION)', '--output=bin\' ) -ErrorAction SilentlyContinue
        ThenTaskFailedWithError 'dotnet(\.exe)?"\ failed\ with\ exit\ code'
    }
}

Describe 'DotNet.when passing paths to the command' {
    AfterEach { Reset }
    It 'should resolve paths' {
        Init
        GivenDotNetCoreProject 'DotNetCore\DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        GivenDotNetCoreProject 'DotNetCore2\DotNetCore2.csproj' -Targeting 'netcoreapp2.0'
        WhenRunningDotNet 'build' -WithPath 'DotNetCore*\*.csproj'
        ThenProjectBuilt 'DotNetCore\bin\Debug\netcoreapp2.0\DotNetCore.dll'
        ThenProjectBuilt 'DotNetCore2\bin\Debug\netcoreapp2.0\DotNetCore2.dll'
        ThenLogFile 'dotnet.build.DotNetCore.csproj.log' -Exists
        ThenLogFile 'dotnet.build.DotNetCore2.csproj.log' -Exists
        ThenTaskSuccess
    }
}


Describe 'DotNet.when command is missing' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenDotNetCoreProject 'DotNetCore\DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        WhenRunningDotNet -ErrorAction SilentlyContinue
        ThenTaskFailedWithError 'is\ required'
    }
}

Describe 'DotNet.when passing paths to the command and working directory isn''t the build root' {
    AfterEach { Reset }
    It 'should resolve paths' {
        Init
        GivenDotNetCoreProject 'DotNetCore\DotNetCore.csproj' -Targeting 'netcoreapp2.0'
        GivenDotNetCoreProject 'DotNetCore\DotNetCore2.csproj' -Targeting 'netcoreapp2.0'
        WhenRunningDotNet 'build' -WithPath 'DotNetCore\*.csproj' -InWorkingDirectory 'DotNetCore' -WarningVariable 'warnings'
        ThenProjectBuilt 'DotNetCore\bin\Debug\netcoreapp2.0\DotNetCore.dll'
        ThenProjectBuilt 'DotNetCore\bin\Debug\netcoreapp2.0\DotNetCore2.dll'
        ThenLogFile 'dotnet.build.DotNetCore.csproj.log' -Exists
        ThenLogFile 'dotnet.build.DotNetCore2.csproj.log' -Exists
        ThenTaskSuccess
        $warnings | Should -Match 'are now resolved relative'
    }
}