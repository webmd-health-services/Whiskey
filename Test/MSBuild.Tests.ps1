
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

# Load this module here so that it's assemblies get loaded into memory. Otherwise, the test will load
# the module from the test drive, and Pester will complain that it can't delete the test drive.
Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\VSSetup' -Resolve) -Force
Remove-Module -Name 'VSSetup' -Force

$output = $null
$path = $null
$threwException = $null
$assembly = $null
$previousBuildRunAt = $null
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
    return (Join-Path -Path $TestDrive.FullName -ChildPath 'BuildRoot')
}

function GivenCustomMSBuildScriptWithMultipleTargets
{
    New-MSBuildProject -FileName 'fubar.msbuild' -BuildRoot (Get-BuildRoot)
    $script:path = 'fubar.msbuild'
}

function GivenAProjectThatCompiles
{
    param(
        [string]
        $ProjectName = 'NUnit2PassingTest'
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

    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'BuildRoot\project.msbuild'
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
}

function Reset
{
    if( (Get-Module -Name 'VSSetup') )
    {
        Remove-Module -Force 'VSSetup'
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [hashtable]
        $WithParameter = @{},

        [Parameter(Mandatory=$true,ParameterSetName='AsDeveloper')]
        [Switch]
        $AsDeveloper,

        [Parameter(Mandatory=$true,ParameterSetName='AsBuildServer')]
        [Switch]
        $AsBuildServer,

        [Switch]
        $InCleanMode,

        [SemVersion.SemanticVersion]
        $AtVersion,

        [Switch]
        $WithNoPath
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

    $context = New-WhiskeyTestContext @optionalParams -ForBuildRoot (Get-BuildRoot)

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
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $WithParameter -Name 'MSBuild' | ForEach-Object { Write-Debug $_ ; $_ }
    }
    catch
    {
        Write-Error $_
        $script:threwException = $true
        $Error | Format-List -Force * | Out-String | Write-Verbose -Verbose
    }
}

function ThenAssembliesAreVersioned
{
    param(
        [string]
        $ProductVersion,

        [string]
        $FileVersion
    )

    It 'should version the assemblies' {
        Get-ChildItem -Path (Get-BuildRoot) -Filter $assembly -File -Recurse |
            Select-Object -ExpandProperty 'VersionInfo' |
            ForEach-Object {
                $_.ProductVersion | Should -Be $ProductVersion
                $_.FileVersion | Should -Be $FileVersion
            }
    }
}

function ThenAssembliesAreNotVersioned
{
    It 'should not version the assemblies' {
        Get-ChildItem -Path (Get-BuildRoot) -Include $assembly -File -Recurse |
            Select-Object -ExpandProperty 'VersionInfo' |
            ForEach-Object {
                $_.ProductVersion | Should -Be '0.0.0.0'
                $_.FileVersion | Should -Be '0.0.0.0'
            }
    }
}

function ThenOutputLogged
{
    $buildRoot = Get-BuildRoot
    It 'should write a debug log' {
        Join-Path -Path $buildRoot -ChildPath ('.output\msbuild.NUnit2PassingTest.sln.log') | should -Exist
    }
}

function ThenBinsAreEmpty
{
    It 'should remove assemblies directories' {
        Get-ChildItem -Path (Get-BuildRoot) -Filter $assembly -File -Recurse | Should -BeNullOrEmpty
    }
    It 'should remove packages directory' {
        foreach ($project in $path) {
            $projectPath = Join-Path -Path (Get-BuildRoot) -ChildPath ($project | Split-Path)
            Get-ChildItem -Path $projectPath -Include 'packages' -Directory | Should -BeNullOrEmpty
        }
    }
}

function ThenBothTargetsRun
{
    It 'should run multiple targets' {
        Join-Path -Path (Get-BuildRoot) -ChildPath '*.clean' | Should -Exist
        Join-Path -Path (Get-BuildRoot) -ChildPath '*.build' | Should -Exist
    }
}

function ThenNuGetPackagesRestored
{
    It 'should restore NuGet packages' {
        foreach( $item in $path )
        {
            $item = $item | Split-Path
            $packagesRoot = Join-Path -Path (Get-BuildRoot) -ChildPath $item
            $packagesRoot = Join-Path -Path $packagesRoot -ChildPath 'packages'
            $packagesRoot | Should -Exist
        }
    }
}

function ThenNuGetPackagesNotRestored
{
    It 'should not restore NuGet packages' {
        Get-ChildItem -Path (Get-BuildRoot) -Filter 'packages' -Recurse |
            ForEach-Object { Get-ChildItem -Path $_.FullName -Exclude 'NuGet.CommandLine.*' } | Should -BeNullOrEmpty
    }
}

function ThenOutputNotLogged
{
    $buildRoot = Get-BuildRoot
    It 'should write a debug log' {
        Join-Path -Path $buildRoot -ChildPath ('.output\*.log') | should -Not -Exist
    }
}

function ThenProjectsCompiled
{
    param(
        [string]
        $To
    )

    if( $To )
    {
        $outputRoot = Join-Path -Path (Get-BuildRoot) -ChildPath $To
        It 'should compile code to custom directory' {
            foreach( $item in $assembly )
            {
                (Join-Path -Path $outputRoot -ChildPath $item) | Should -Exist
            }
            Get-ChildItem -Path (Get-BuildRoot) -Include 'bin' -Directory -Recurse |
                Get-ChildItem -Include $assembly -File -Recurse |
                Should -BeNullOrEmpty
        }
    }
    else
    {
        It 'should compile code' {
            foreach( $item in $path )
            {
                $item = $item | Split-Path
                $solutionRoot = Join-Path -Path (Get-BuildRoot) -ChildPath $item
                Get-ChildItem -Path $solutionRoot -Directory -Include 'bin','obj' -Recurse | Should -Not -BeNullOrEmpty
                Get-ChildItem -Path $solutionRoot -Include $assembly -File -Recurse | Should -Not -BeNullOrEmpty
            }
        }
    }
}

function ThenProjectsNotCompiled
{
    It 'bin directories should be empty' {
        Get-ChildItem -Path (Get-BuildRoot) -Include $assembly -File -Recurse | Should -BeNullOrEmpty
    }
}

function ThenOutput
{
    param(
        [string[]]
        $Contains,

        [string[]]
        $DoesNotContain,

        [string]
        $Is
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
            It ('the output should contain' -f $item) {
                $fullOutput | Should Match $item
            }
        }
    }

    if( $Is -or $PSBoundParameters.ContainsKey('Is') )
    {
        $desc = $Is
        if( -not $desc )
        {
            $desc = '[empty]'
        }
        It ('the output should be {0}' -f $desc) {
            $fullOutput | Should Match ('^{0}$' -f $Is)
        }
    }

    if( $DoesNotContain )
    {
        foreach( $item in $DoesNotContain )
        {
            It ('should not contain {0}' -f $item) {
                $output | Should Not Match $item
            }
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

    It ('should install ''{0}''' -f $nugetPackageVersion) {
        Join-Path -Path (Get-BuildRoot) -ChildPath ('packages\{0}' -f $nugetPackageVersion) | Should -Exist
    }
}

function ThenTaskFailed
{
    param(
    )

    It 'the task should fail' {
        $threwException | Should Be $true
    }
}

function ThenWritesError
{
    param(
        $Pattern
    )

    It 'should write an error' {
        $Global:Error | Where-Object { $_ -match $Pattern } | Should -Not -BeNullOrEmpty
    }
}

Describe 'MSBuild.when building real projects as a developer' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper
        ThenNuGetPackagesRestored
        ThenProjectsCompiled
        ThenAssembliesAreNotVersioned
        ThenOutputLogged
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when building multiple real projects as a developer' {
    try
    {
        Init
        GivenProjectsThatCompile
        WhenRunningTask -AsDeveloper
        ThenNuGetPackagesRestored
        ThenProjectsCompiled
        ThenAssembliesAreNotVersioned
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when building real projects as build server' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsBuildServer -AtVersion '1.5.9-rc.45+1034.master.deadbee'
        ThenNuGetPackagesRestored
        ThenProjectsCompiled
        ThenAssembliesAreVersioned -ProductVersion '1.5.9-rc.45+1034.master.deadbee' -FileVersion '1.5.9'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when compilation fails' {
    try
    {
        Init
        GivenAProjectThatDoesNotCompile
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenNuGetPackagesRestored
        ThenProjectsNotCompiled
        ThenTaskFailed
        ThenWritesError 'MSBuild\ exited\ with\ code\ 1'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when Path parameter is empty' {
    try
    {
        Init
        GivenNoPathToBuild
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenProjectsNotCompiled
        ThenNuGetPackagesNotRestored
        ThenTaskFailed
        ThenWritesError ([regex]::Escape('Element ''Path'' is mandatory'))
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when Path parameter is not provided' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithNoPath -ErrorAction SilentlyContinue
        ThenProjectsNotCompiled
        ThenNuGetPackagesNotRestored
        ThenTaskFailed
        ThenWritesError ([regex]::Escape('Element ''Path'' is mandatory'))
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when Path Parameter does not exist' {
    try
    {
        Init
        GivenAProjectThatDoesNotExist
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenProjectsNotCompiled
        ThenNuGetPackagesnoTRestored
        ThenTaskFailed
        ThenWritesError ([regex]::Escape('does not exist.'))
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when cleaning build output' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper
        ThenProjectsCompiled
        WhenRunningTask -InCleanMode -AsDeveloper
        ThenBinsAreEmpty
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when customizing output level' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Verbosity' = 'q'; }
        ThenOutputIsEmpty
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when run by developer using default verbosity output level' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper
        ThenOutputIsMinimal
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when run by build server using default verbosity output level' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsBuildServer
        ThenOutputIsMinimal
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when passing extra build properties' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Property' = @( 'Fubar=Snafu' ) ; 'Verbosity' = 'diag' }
        ThenOutput -Contains 'Fubar=Snafu'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when passing custom arguments' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Argument' = @( '/nologo', '/version' ) }
        ThenOutput -Contains '\d+\.\d+\.\d+\.\d+'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when passing a single custom argument' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Argument' = @( '/version' ) }
        ThenOutput -Contains '\d+\.\d+\.\d+\.\d+'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when run with no CPU parameter' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Verbosity' = 'n' }
        ThenOutput -Contains '\n\ {5}\d>'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when run with CPU parameter' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'CpuCount' = 1; 'Verbosity' = 'n' }
        ThenOutput -DoesNotContain '^\ {5}\d>'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when using custom output directory' {
    try
    {
        Init
        GivenAProjectThatCompiles
        WhenRunningTask -AsDeveloper -WithParameter @{ 'OutputDirectory' = '.myoutput' }
        ThenProjectsCompiled -To '.myoutput'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when using custom targets' {
    try
    {
        Init
        GivenCustomMSBuildScriptWithMultipleTargets
        WhenRunningTask -AsDeveloper -WithParameter @{ 'Target' = 'clean','build' ; 'Verbosity' = 'diag' }
        ThenBothTargetsRun
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when using invalid version of MSBuild' {
    try
    {
        Init
        GivenAProjectThatCompiles
        GivenVersion 'some.bad.version'
        WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenWritesError -Pattern 'some\.bad\.version\b.*is\ not\ installed'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when customizing version of MSBuild' {
    try
    {
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
        $version = Get-ChildItem -Path $toolsVersionsRegPath | Select-Object -ExpandProperty 'Name' | Split-Path -Leaf | Sort-Object -Property { [version]$_ } -Descending | Select -Last 1
        $expectedPath = Get-ItemProperty -Path (Join-Path -Path $toolsVersionsRegPath -ChildPath $version) -Name 'MSBuildToolsPath' | Select-Object -ExpandProperty 'MSBuildToolsPath'
        GivenVersion $version
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoMaxCpuCountArgument' = $true ; 'NoFileLogger' = $true; }
        ThenOutput -Contains ([regex]::Escape($expectedPath.TrimEnd('\')))
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when customizing version of MSBuild and multiple installs for a version exist' {
    try
    {
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
        $version = Get-ChildItem -Path $toolsVersionsRegPath | Select-Object -ExpandProperty 'Name' | Split-Path -Leaf | Sort-Object -Property { [version]$_ } -Descending | Select -Last 1
        $msbuildRoot = Get-ItemProperty -Path (Join-Path -Path $toolsVersionsRegPath -ChildPath $version) -Name 'MSBuildToolsPath' | Select-Object -ExpandProperty 'MSBuildToolsPath'
        $msbuildPath = Join-Path -Path $msbuildRoot -ChildPath 'MSBuild.exe' -Resolve
        Mock -CommandName 'Get-MSBuild' -ModuleName 'Whiskey' -MockWith {
            1..2 | ForEach-Object {
                [pscustomobject]@{
                                    Name =  $version;
                                    Version = [version]$version;
                                    Path = $msbuildPath;
                                    Path32 = $msbuildPath;
                                }
            }
        }.GetNewClosure()
        GivenVersion $version
        WhenRunningTask -AsDeveloper -WithParameter @{ 'NoMaxCpuCountArgument' = $true ; 'NoFileLogger' = $true; }
        ThenOutput -Contains ([regex]::Escape($msbuildRoot.TrimEnd('\')))
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when disabling multi-CPU builds' {
    try
    {
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
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when disabling file logger' {
    try
    {
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
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when run by developer using a specific version of NuGet' {
    try
    {
        Init
        GivenProjectsThatCompile
        GivenNuGetVersion '3.5.0'
        WhenRunningTask -AsDeveloper
        ThenSpecificNuGetVersionInstalled
        ThenNuGetPackagesRestored
    }
    finally
    {
        Reset
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
    try
    {
        Init
        GivenProject $procArchProject
        WhenRunningTask -AsDeveloper
        ThenOutput -Contains 'PROCESSOR_ARCHITECTURE = AMD64'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when using 32-bit MSBuild' {
    try
    {
        Init
        GivenProject $procArchProject
        GivenUse32BitIs 'true'
        WhenRunningTask -AsDeveloper
        ThenOutput -Contains 'PROCESSOR_ARCHITECTURE = x86'
    }
    finally
    {
        Reset
    }
}

Describe 'MSBuild.when explicitly not using 32-bit MSBuild' {
    try
    {
        Init
        GivenProject $procArchProject
        GivenUse32BitIs 'false'
        WhenRunningTask -AsDeveloper
        ThenOutput -Contains 'PROCESSOR_ARCHITECTURE = AMD64'
    }
    finally
    {
        Reset
    }
}
