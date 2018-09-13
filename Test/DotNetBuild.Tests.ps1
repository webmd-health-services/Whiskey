    
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Set-EnvironmentVariable -Name 'DOTNET_SKIP_FIRST_TIME_EXPERIENCE' -Value 'true' -ForProcess

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
        $Path
    )

    foreach ($project in $Path)
    {
        $projectRoot = Join-Path -Path $TestDrive.FullName -ChildPath ($project | Split-Path -Parent)
        New-Item -Path $projectRoot -ItemTYpe 'Directory' -Force | Out-Null

        $csprojPath = Join-Path -Path $projectRoot -ChildPath ($project | Split-Path -Leaf)

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

    $builtVersion = Get-Item -Path $AssemblyPath | Select-Object -ExpandProperty 'VersionInfo' | Select-Object -ExpandProperty 'ProductVersion'
    It 'should build assembly with correct version' {
        $builtVersion | Should -Be $taskContext.Version.SemVer1
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

    $outputLines = $dotNetOutput | Measure-Object | Select-Object -ExpandProperty 'Count'

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
    $taskParameter = @{ 'SdkVersion' = '2.*' }

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

    $dotnetSkipFirstTime = $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE
    try
    {
        $Global:Error.Clear()
        Set-Item -Path 'env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE' -Value 'true'
        $script:dotNetOutput = Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'DotNetBuild'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
    finally
    {
        if( $dotnetSkipFirstTime )
        {
            $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = $dotnetSkipFirstTime
        }
        else
        {
            Remove-Item -Path 'env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE'
        }
    }
}

Describe 'DotNetBuild.when not given any Paths' {
    Context 'By Developer' {
        try
        {
            Init
            GivenDotNetCoreProject 'DotNetCore.csproj'
            WhenRunningDotNetBuild -ForDeveloper
            ThenProjectBuilt 'bin\Debug\netcoreapp2.0\DotNetCore.dll'
            ThenVerbosityIs -Minimal
            ThenTaskSuccess
            ThenLogFile 'dotnet.build.log' -Exists
        }
        finally
        {
            Remove-DotNet
        }
    }

    Context 'By BuildServer' {
        try
        {
            Init
            GivenDotNetCoreProject 'DotNetCore.csproj'
            WhenRunningDotNetBuild -ForBuildServer
            ThenProjectBuilt 'bin\Release\netcoreapp2.0\DotNetCore.dll'
            ThenVerbosityIs -Minimal
            ThenTaskSuccess
            ThenLogFile 'dotnet.build.log' -Exists
        }
        finally
        {
            Remove-DotNet
        }
    }
}

Describe 'DotNetBuild.when not given any Paths and no csproj or solution exists' {
    Init
    WhenRunningDotNetBuild -ErrorAction SilentlyContinue
    ThenTaskFailedWithError 'failed\ with\ exit\ code'
}

Describe 'DotNetBuild.when given Path to a csproj file' {
    try
    {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj'
        GivenPath 'DotNetCore.csproj'
        WhenRunningDotNetBuild
        ThenProjectBuilt 'bin\Debug\netcoreapp2.0\DotNetCore.dll'
        ThenTaskSuccess
        ThenLogFile 'dotnet.build.DotNetCore.csproj.log' -Exists
    }
    finally
    {
        Remove-DotNet
    }
}

Describe 'DotNetBuild.when given Path to nonexistent csproj file' {
    try
    {
        Init
        GivenPath 'nonexistent.csproj'
        WhenRunningDotNetBuild -ErrorAction SilentlyContinue
        ThenTaskFailedWithError '\bdoes\ not\ exist\b'
        ThenLogFile 'dotnet.build*.log' -Not -Exists
    }
    finally
    {
        Remove-DotNet
    }
}

Describe 'DotNetBuild.when dotnet build fails' {
    try
    {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj'
        GivenFailingDotNetCoreProject 'FailingDotNetCore.csproj'
        GivenPath 'DotNetCore.csproj','FailingDotNetCore.csproj'
        WhenRunningDotNetBuild -ErrorAction SilentlyContinue
        ThenTaskFailedWithError 'failed\ with\ exit\ code'
        ThenLogFile 'dotnet.build.DotNetCore.csproj.log' -Exists
        ThenLogFile 'dotnet.build.FailingDotNetCore.csproj.log' -Exists
    }
    finally
    {
        Remove-DotNet
    }
}

Describe 'DotNetBuild.when given multiple Paths to csproj files' {
    try
    {
        Init
        GivenDotNetCoreProject 'app\DotNetCoreApp.csproj', 'test\DotNetCoreTest.csproj'
        GivenPath 'app\DotNetCoreApp.csproj', 'test\DotNetCoreTest.csproj'
        WhenRunningDotNetBuild
        ThenProjectBuilt 'app\bin\Debug\netcoreapp2.0\DotNetCoreApp.dll'
        ThenProjectBuilt 'test\bin\Debug\netcoreapp2.0\DotNetCoreTest.dll'
        ThenTaskSuccess
        ThenLogFile 'dotnet.build.DotNetCoreApp.csproj.log' -Exists
        ThenLogFile 'dotnet.build.DotNetCoreTest.csproj.log' -Exists
    }
    finally
    {
        Remove-DotNet
    }
}

Describe 'DotNetBuild.when given verbosity level' {
    Context 'By Developer' {
        try
        {
            Init
            GivenDotNetCoreProject 'DotNetCore.csproj'
            GivenVerbosity 'diagnostic'
            WhenRunningDotNetBuild -ForDeveloper
            ThenProjectBuilt 'bin\Debug\netcoreapp2.0\DotNetCore.dll'
            ThenVerbosityIs -Diagnostic
            ThenTaskSuccess
            ThenLogFile 'dotnet.build.log' -Exists
        }
        finally
        {
            Remove-DotNet
        }
    }

    Context 'By BuildServer' {
        try
        {
            Init
            GivenDotNetCoreProject 'DotNetCore.csproj'
            GivenVerbosity 'diagnostic'
            WhenRunningDotNetBuild -ForBuildServer
            ThenProjectBuilt 'bin\Release\netcoreapp2.0\DotNetCore.dll'
            ThenVerbosityIs -Diagnostic
            ThenTaskSuccess
            ThenLogFile 'dotnet.build.log' -Exists
        }
        finally
        {
            Remove-DotNet
        }
    }
}

Describe 'DotNetBuild.when given output directory' {
    try
    {
        Init
        GivenDotNetCoreProject 'src\app\DotNetCoreApp.csproj', 'src\engine\DotNetCoreEngine.csproj'
        GivenPath 'src\app\DotNetCoreApp.csproj', 'src\engine\DotNetCoreEngine.csproj'
        GivenOutputDirectory 'Output Dir'
        WhenRunningDotNetBuild
        ThenProjectBuilt 'src\app\Output Dir\DotNetCoreApp.dll'
        ThenProjectBuilt 'src\engine\Output Dir\DotNetCoreEngine.dll'
        ThenTaskSuccess
        ThenLogFile 'dotnet.build.DotNetCoreApp.csproj.log' -Exists
        ThenLogFile 'dotnet.build.DotNetCoreEngine.csproj.log' -Exists
    }
    finally
    {
        Remove-DotNet
    }
}

Describe 'DotNetBuild.when given additional arguments --no-restore and -nologo' {
    try
    {
        Init
        GivenDotNetCoreProject 'DotNetCore.csproj'
        WhenRunningDotNetBuild

        GivenArgument '--no-restore','-nologo'
        WhenRunningDotNetBuild
        ThenProjectBuilt 'bin\Debug\netcoreapp2.0\DotNetCore.dll'
        ThenOutput -DoesNotContain '\bRestore\ completed\b'
        ThenOutput -DoesNotContain '\bCopyright\ \(C\)\ Microsoft\ Corporation\b'
        ThenTaskSuccess
        ThenLogFile 'dotnet.build.log' -Exists
    }
    finally
    {
        Remove-DotNet
    }
}

Remove-EnvironmentVariable -Name 'DOTNET_SKIP_FIRST_TIME_EXPERIENCE' -ForProcess
