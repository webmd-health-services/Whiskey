
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

# Load this module here so that it's assemblies get loaded into memory. Otherwise, the test will load
# the module from the test drive, and Pester will complain that it can't delete the test drive.
Import-WhiskeyTestModule -Name 'VSSetup' -Force
Remove-Module -Name 'VSSetup' -Force

$testRoot = $null
$output = $null
$path = $null
$threwException = $null
$assembly = $null
$version = $null
$nuGetVersion = $null
$use32Bit = $null

$assemblyRoot = Join-Path -Path $PSScriptRoot 'Assemblies'
foreach( $item in @( 'bin', 'obj', 'packages' ) )
{
    Get-ChildItem -Path $assemblyRoot -Filter $item -Recurse -Directory |
        Remove-Item -Recurse -Force
}

function Get-BuildRoot
{
    return (Join-Path -Path $testRoot -ChildPath 'BuildRoot')
}

function GivenCustomMSBuildScriptWithMultipleTargets
{
    New-MSBuildProject -FileName 'fubar.msbuild' -BuildRoot (Get-BuildRoot)
    $script:path = 'fubar.msbuild'
}

function GivenAProjectThatCompiles
{
    param(
        [String]$ProjectName = 'NUnit2PassingTest'
    )

    $source = Join-Path -Path $PSScriptRoot -ChildPath ('Assemblies\{0}' -f $ProjectName)
    $destination = Get-BuildRoot
    $destination = Join-Path -Path $destination -ChildPath $ProjectName
    Copy-Item -Path $source -Destination $destination -Recurse
    $script:path = '{0}\{0}.sln' -f $ProjectName
    $script:assembly = '{0}.dll' -f $ProjectName
}

function GivenProject
{
    param(
        $Project
    )

    $path = Join-Path -Path $testRoot -ChildPath 'BuildRoot\project.msbuild'
    New-Item -Path $path -ItemType 'File' -Force
    $Project | Set-Content -Path $path -Force
    $script:path = $path | Split-Path -Leaf
}

function GivenAProjectThatDoesNotCompile
{
    GivenAProjectThatCompiles
    Get-ChildItem -Path (Get-BuildRoot) -Filter 'AssemblyInfo.cs' -Recurse |
        ForEach-Object { Add-Content -Path $_.FullName -Value '>' }
}

function GivenAProjectThatDoesNotExist
{
    GivenAProjectThatCompiles
    $script:path = 'I\do\not\exist.csproj'
    $script:assembly = 'exist.dll'
}

function GivenNoPathToBuild
{
    GivenAProjectThatCompiles
    $script:path = $null
}

function GivenProjectsThatCompile
{
    GivenAProjectThatCompiles 'NUnit2PassingTest'
    GivenAProjectThatCompiles 'NUnit2FailingTest'
    $script:path = @( 'NUnit2PassingTest\NUnit2PassingTest.sln', 'NUnit2FailingTest\NUnit2FailingTest.sln' )
    $script:assembly = @( 'NUnit2PassingTest.dll', 'NUnit2FailingTest.dll' )
    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whiskey.yml') -Destination (Get-BuildRoot)
}

function GivenUse32BitIs
{
    param(
        $Value
    )

    $script:use32Bit = $value
}

function GivenVersion
{
    param(
        $Version
    )

    $script:version = $Version
}

function GivenNuGetVersion
{
    param(
        $NuGetVersion
    )

    $script:nuGetVersion = $NuGetVersion
}

function Init
{
    $script:version = $null
    $script:nuGetVersion = $null
    $script:use32Bit = $false

    $script:testRoot = New-WhiskeyTestRoot
}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [hashtable]$WithParameter = @{},

        [Parameter(Mandatory,ParameterSetName='AsDeveloper')]
        [switch]$AsDeveloper,

        [Parameter(Mandatory,ParameterSetName='AsBuildServer')]
        [switch]$AsBuildServer,

        [switch]$InCleanMode,

        [SemVersion.SemanticVersion]$AtVersion,

        [switch]$WithNoPath
    )

    $optionalParams = @{ }
    if( $AsDeveloper )
    {
        $optionalParams['ForDeveloper'] = $true
    }

    if( $AsBuildServer )
    {
        $optionalParams['ForBuildServer'] = $true
    }

    if( $AtVersion )
    {
        $optionalParams['ForVersion'] = $AtVersion
    }

    $context = New-WhiskeyTestContext @optionalParams -ForBuildRoot (Get-BuildRoot) -IncludePSModule 'VSSetup'

    if( -not $WithNoPath )
    {
        $WithParameter['Path'] = $path
    }

    $script:threwException = $false
    $script:output = $null
    if( $InCleanMode )
    {
        $context.RunMode = 'Clean'
    }

    if( $version )
    {
        $WithParameter['Version'] = $version
    }

    if( $nuGetVersion )
    {
        $WithParameter['NuGetVersion'] = $nuGetVersion
    }

    if( $use32Bit )
    {
        $WithParameter['Use32Bit'] = $use32Bit
    }

    $Global:Error.Clear()
    try
    {
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $WithParameter -Name 'MSBuild'
        $output | Write-WhiskeyDebug
    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }
}

function ThenAssembliesAreVersioned
{
    param(
        [String]$ProductVersion,

        [String]$FileVersion
    )

    Get-ChildItem -Path (Get-BuildRoot) -Filter $assembly -File -Recurse |
        Select-Object -ExpandProperty 'VersionInfo' |
        ForEach-Object {
            $_.ProductVersion | Should -Be $ProductVersion
            $_.FileVersion | Should -Be $FileVersion
        }
}

function ThenAssembliesAreNotVersioned
{
    Get-ChildItem -Path (Get-BuildRoot) -Include $assembly -File -Recurse |
        Select-Object -ExpandProperty 'VersionInfo' |
        ForEach-Object {
            $_.ProductVersion | Should -Be '0.0.0.0'
            $_.FileVersion | Should -Be '0.0.0.0'
        }
}

function ThenOutputLogged
{
    $buildRoot = Get-BuildRoot
    Join-Path -Path $buildRoot -ChildPath ('.output\msbuild.NUnit2PassingTest.sln.log') | Should -Exist
}

function ThenBinsAreEmpty
{
    Get-ChildItem -Path (Get-BuildRoot) -Filter $assembly -File -Recurse | Should -BeNullOrEmpty
    foreach ($project in $path) {
        $projectPath = Join-Path -Path (Get-BuildRoot) -ChildPath ($project | Split-Path)
        Get-ChildItem -Path $projectPath -Include 'packages' -Directory | Should -BeNullOrEmpty
    }
}

function ThenBothTargetsRun
{
    Join-Path -Path (Get-BuildRoot) -ChildPath '*.clean' | Should -Exist
    Join-Path -Path (Get-BuildRoot) -ChildPath '*.build' | Should -Exist
}

function ThenNuGetPackagesRestored
{
    foreach( $item in $path )
    {
        $item = $item | Split-Path
        $packagesRoot = Join-Path -Path (Get-BuildRoot) -ChildPath $item
        $packagesRoot = Join-Path -Path $packagesRoot -ChildPath 'packages'
        $packagesRoot | Should -Exist
    }
}

function ThenNuGetPackagesNotRestored
{
    Get-ChildItem -Path (Get-BuildRoot) -Filter 'packages' -Recurse |
        ForEach-Object { Get-ChildItem -Path $_.FullName -Exclude 'NuGet.CommandLine.*' } | Should -BeNullOrEmpty
}

function ThenOutputNotLogged
{
    $buildRoot = Get-BuildRoot
    Join-Path -Path $buildRoot -ChildPath ('.output\*.log') | should -Not -Exist
}

function ThenProjectsCompiled
{
    param(
        [String]$To
    )

    if( $To )
    {
        $outputRoot = Join-Path -Path (Get-BuildRoot) -ChildPath $To
        foreach( $item in $assembly )
        {
            (Join-Path -Path $outputRoot -ChildPath $item) | Should -Exist
        }
        Get-ChildItem -Path (Get-BuildRoot) -Include 'bin' -Directory -Recurse |
            Get-ChildItem -Include $assembly -File -Recurse |
            Should -BeNullOrEmpty
    }
    else
    {
        foreach( $item in $path )
        {
            $item = $item | Split-Path
            $solutionRoot = Join-Path -Path (Get-BuildRoot) -ChildPath $item
            Get-ChildItem -Path $solutionRoot -Directory -Include 'bin','obj' -Recurse | Should -Not -BeNullOrEmpty
            Get-ChildItem -Path $solutionRoot -Include $assembly -File -Recurse | Should -Not -BeNullOrEmpty
        }
    }
}

function ThenProjectsNotCompiled
{
    Get-ChildItem -Path (Get-BuildRoot) -Include $assembly -File -Recurse | Should -BeNullOrEmpty
}

function ThenOutput
{
    param(
        [String[]]$Contains,

        [String[]]$DoesNotContain,

        [String]$Is
    )

    # remove the NuGet output
    $fullOutput = ($output | Where-Object { $_ -notmatch ('^(Installing|Successfully installed)\b') }) -join [Environment]::NewLine
    $needle = " to packages.config projects"
    $indexOfNeedle = $fullOutput.IndexOf($needle, [StringComparison]::InvariantCultureIgnoreCase)
    if( $indexOfNeedle -ge 0 )
    {
        $startIndex = $indexOfNeedle + $needle.Length + [Environment]::NewLine.Length
        if( $startIndex -gt $fullOutput.Length )
        {
            $fullOutput = ''
        }
        else
        {
            $fullOutput = $fullOutput.Substring($startIndex)
        }
    }

    if( $Contains )
    {
        foreach( $item in $Contains )
        {
            $fullOutput | Should -Match $item
        }
    }

    if( $Is -or $PSBoundParameters.ContainsKey('Is') )
    {
        $desc = $Is
        if( -not $desc )
        {
            $desc = '[empty]'
        }
        $fullOutput | Should -Match ('^{0}$' -f $Is)
    }

    if( $DoesNotContain )
    {
        foreach( $item in $DoesNotContain )
        {
            $output | Should -Not -Match $item
        }
    }
}

function ThenOutputIsEmpty
{
    ThenOutput -Is ''
}

function ThenOutputIsMinimal
{
    ThenOutput -Is '.*\ ->\ .*'
}

function ThenOutputIsDebug
{
    ThenOutput -Contains 'Target\ "[^"]+"\ in\ file\ '
}

function ThenSpecificNuGetVersionInstalled
{
    $nuGetPackageVersion = 'NuGet.CommandLine.{0}' -f $nuGetVersion

    Join-Path -Path (Get-BuildRoot) -ChildPath ('packages\{0}' -f $nugetPackageVersion) | Should -Exist
}

function ThenTaskFailed
{
    param(
    )

    $threwException | Should -BeTrue
}

function ThenWritesError
{
    param(
        $Pattern
    )

    $Global:Error | Where-Object { $_ -match $Pattern } | Should -Not -BeNullOrEmpty
}

if( -not $IsWindows )
{
    Describe 'MSBuild.when run on non-Windows platform' {
        AfterEach { Reset }
        It 'should fail' {
            Init
            GivenAProjectThatCompiles
            WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
            ThenTaskFailed
            ThenWritesError 'Windows\ platform'
        }
    }

    return
}

Describe 'MSBuild.when building real projects as a developer' {
    AfterEach { Reset }
    It 'should compile the projects' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper
        ThenNuGetPackagesRestored
        ThenProjectsCompiled
        ThenAssembliesAreNotVersioned
        ThenOutputLogged
    }
}

Describe 'MSBuild.when building multiple real projects as a developer' {
    AfterEach { Reset }
    It 'should build all the projects' {
        Init
        GivenProjectsThatCompile
        WhenRunningTask -AsDeveloper
        ThenNuGetPackagesRestored
        ThenProjectsCompiled
        ThenAssembliesAreNotVersioned
    }
}

Describe 'MSBuild.when building real projects as build server' {
    AfterEach { Reset }
    It 'should version with build metadata' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsBuildServer -AtVersion '1.5.9-rc.45+1034.master.deadbee'
        ThenNuGetPackagesRestored
        ThenProjectsCompiled
        ThenAssembliesAreVersioned -ProductVersion '1.5.9-rc.45+1034.master.deadbee' -FileVersion '1.5.9'
    }
}

Describe 'MSBuild.when compilation fails' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenAProjectThatDoesNotCompile
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenNuGetPackagesRestored
        ThenProjectsNotCompiled
        ThenTaskFailed
        ThenWritesError 'MSBuild\ exited\ with\ code\ 1'
    }
}

Describe 'MSBuild.when path parameter is empty' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenNoPathToBuild
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenProjectsNotCompiled
        ThenNuGetPackagesNotRestored
        ThenTaskFailed
        ThenWritesError ([regex]::Escape('Path is mandatory'))
    }
}

Describe 'MSBuild.when path parameter is not provided' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithNoPath -ErrorAction SilentlyContinue
        ThenProjectsNotCompiled
        ThenNuGetPackagesNotRestored
        ThenTaskFailed
        ThenWritesError ([regex]::Escape('Path is mandatory'))
    }
}

Describe 'MSBuild.when Path Parameter does not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenAProjectThatDoesNotExist
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenProjectsNotCompiled
        ThenNuGetPackagesnoTRestored
        ThenTaskFailed
        ThenWritesError ([regex]::Escape('does not exist.'))
    }
}

Describe 'MSBuild.when cleaning build output' {
    AfterEach { Reset }
    It 'should build using the clean target' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper
        ThenProjectsCompiled
        WhenRunningTask -InCleanMode -AsDeveloper
        ThenBinsAreEmpty
    }
}

Describe 'MSBuild.when customizing output level' {
    AfterEach { Reset }
    It 'should output at that level' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Verbosity' = 'q'; }
        ThenOutputIsEmpty
    }
}

Describe 'MSBuild.when run by developer using default verbosity output level' {
    AfterEach { Reset }
    It 'should use minimal output level' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper
        ThenOutputIsMinimal
    }
}

Describe 'MSBuild.when run by build server using default verbosity output level' {
    AfterEach { Reset }
    It 'should output at minimal level' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsBuildServer
        ThenOutputIsMinimal
    }
}

Describe 'MSBuild.when passing extra build properties' {
    AfterEach { Reset }
    It 'should pass the parameters' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Property' = @( 'Fubar=Snafu' ) ; 'Verbosity' = 'diag' }
        ThenOutput -Contains 'Fubar=Snafu'
    }
}

Describe 'MSBuild.when passing custom arguments' {
    AfterEach { Reset }
    It 'should pass the parameters' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Argument' = @( '/nologo', '/version' ) }
        ThenOutput -Contains '\d+\.\d+\.\d+\.\d+'
    }
}

Describe 'MSBuild.when passing a single custom argument' {
    AfterEach { Reset }
    It 'should pass the argument' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Argument' = @( '/version' ) }
        ThenOutput -Contains '\d+\.\d+\.\d+\.\d+'
    }
}

Describe 'MSBuild.when run with no CPU parameter' {
    AfterEach { Reset }
    It 'should default to multi-CPU build' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Verbosity' = 'n' }
        ThenOutput -Contains '\n\ {5}\d>'
    }
}

Describe 'MSBuild.when run with CPU parameter' {
    AfterEach { Reset }
    It 'should use that CPU count' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'CpuCount' = 1; 'Verbosity' = 'n' }
        ThenOutput -DoesNotContain '^\ {5}\d>'
    }
}

Describe 'MSBuild.when using custom output directory' {
    AfterEach { Reset }
    It 'should use that output directory' {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'OutputDirectory' = '.myoutput' }
        ThenProjectsCompiled -To '.myoutput'
    }
}

Describe 'MSBuild.when using custom targets' {
    AfterEach { Reset }
    It 'should build that target' {
        Init
        GivenCustomMSBuildScriptWithMultipleTargets
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Target' = 'clean','build' ; 'Verbosity' = 'diag' }
        ThenBothTargetsRun
    }
}

Describe 'MSBuild.when using invalid version of MSBuild' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenAProjectThatCompiles
        GivenVersion 'some.bad.version'
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenWritesError -Pattern 'some\.bad\.version\b.*is\ not\ installed'
    }
}

Describe 'MSBuild.when customizing version of MSBuild' {
    AfterEach { Reset }
    It 'should use that version of MSBuild' {
        Init
        GivenProject @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <Target Name="Build">
        <Message Importance="High" Text="`$(MSBuildBinPath)" />
    </Target>
</Project>
"@
        $toolsVersionsRegPath = 'hklm:\software\Microsoft\MSBuild\ToolsVersions'
        $version = Get-ChildItem -Path $toolsVersionsRegPath | Select-Object -ExpandProperty 'Name' | Split-Path -Leaf | Sort-Object -Property { [Version]$_ } -Descending | Select -Last 1
        $expectedPath = Get-ItemProperty -Path (Join-Path -Path $toolsVersionsRegPath -ChildPath $version) -Name 'MSBuildToolsPath' | Select-Object -ExpandProperty 'MSBuildToolsPath'
        GivenVersion $version
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoMaxCpuCountArgument' = $true ; 'NoFileLogger' = $true; }
        ThenOutput -Contains ([regex]::Escape($expectedPath.TrimEnd('\')))
    }
}

Describe 'MSBuild.when customizing version of MSBuild and multiple installs for a version exist' {
    AfterEach { Reset }
    It 'should pick one' {
        Init
        GivenProject @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <Target Name="Build">
        <Message Importance="High" Text="`$(MSBuildBinPath)" />
    </Target>
</Project>
"@
        $toolsVersionsRegPath = 'hklm:\software\Microsoft\MSBuild\ToolsVersions'
        $version = Get-ChildItem -Path $toolsVersionsRegPath | Select-Object -ExpandProperty 'Name' | Split-Path -Leaf | Sort-Object -Property { [Version]$_ } -Descending | Select -Last 1
        $msbuildRoot = Get-ItemProperty -Path (Join-Path -Path $toolsVersionsRegPath -ChildPath $version) -Name 'MSBuildToolsPath' | Select-Object -ExpandProperty 'MSBuildToolsPath'
        $msbuildPath = Join-Path -Path $msbuildRoot -ChildPath 'MSBuild.exe' -Resolve
        Mock -CommandName 'Get-MSBuild' -ModuleName 'Whiskey' -MockWith {
            1..2 | ForEach-Object {
                [pscustomobject]@{
                                    Name =  $version;
                                    Version = [Version]$version;
                                    Path = $msbuildPath;
                                    Path32 = $msbuildPath;
                                }
            }
        }.GetNewClosure()
        GivenVersion $version
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoMaxCpuCountArgument' = $true ; 'NoFileLogger' = $true; }
        ThenOutput -Contains ([regex]::Escape($msbuildRoot.TrimEnd('\')))
    }
}

Describe 'MSBuild.when disabling multi-CPU builds' {
    AfterEach { Reset }
    It 'should run using default MSBuild CPU count' {
        Init
        GivenProject @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <Target Name="Build">
    </Target>
</Project>
"@
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoMaxCpuCountArgument' = $true; Verbosity = 'diag' }
        ThenOutput -Contains ('MSBuildNodeCount = 1')
    }
}

Describe 'MSBuild.when disabling file logger' {
    AfterEach { Reset }
    It 'should not log to a file' {
        Init
        GivenProject @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <Target Name="Build">
    </Target>
</Project>
"@
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoFileLogger' = $true }
        ThenOutputNotLogged
    }
}

Describe 'MSBuild.when run by developer using a specific version of NuGet' {
    AfterEach { Reset }
    It 'should use that version of NuGet' {
        Init
        GivenProjectsThatCompile
        GivenNuGetVersion '5.9.3'
        WhenRunningTask -AsDeveloper
        ThenSpecificNuGetVersionInstalled
        ThenNuGetPackagesRestored
    }
}

$procArchProject = @"
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
    <Target Name="Build">
        <Message Text="PROCESSOR_ARCHITECTURE = `$(PROCESSOR_ARCHITECTURE)" Importance="High" />
    </Target>
</Project>
"@

Describe 'MSBuild.when using 32-bit MSBuild is undefined' {
    AfterEach { Reset }
    It 'should use 64-bit MSBuild' {
        Init
        GivenProject $procArchProject
        WhenRunningTask -AsDeveloper
        ThenOutput -Contains 'PROCESSOR_ARCHITECTURE = AMD64'
    }
}

Describe 'MSBuild.when using 32-bit MSBuild' {
    AfterEach { Reset }
    It 'should use 32-bit MSBuild' {
        Init
        GivenProject $procArchProject
        GivenUse32BitIs 'true'
        WhenRunningTask -AsDeveloper
        ThenOutput -Contains 'PROCESSOR_ARCHITECTURE = x86'
    }
}

Describe 'MSBuild.when explicitly not using 32-bit MSBuild' {
    AfterEach { Reset }
    It 'should use 64-bit' {
        Init
        GivenProject $procArchProject
        GivenUse32BitIs 'false'
        WhenRunningTask -AsDeveloper
        ThenOutput -Contains 'PROCESSOR_ARCHITECTURE = AMD64'
    }
}
