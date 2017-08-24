
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$output = $null
$path = $null
$threwException = $null
$assembly = $null
$previousBuildRunAt = $null
$version = $null

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
    robocopy $source $destination '/MIR' '/NP' '/R:0'
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

function GivenVersion
{
    param(
        $Version
    )

    $script:version = $Version
}

function Init
{
    $script:version = $null
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

    $context = New-WhiskeyTestContext @optionalParams -ForBuildRoot (Join-Path -Path $TestDrive.FullName -ChildPath 'BuildRoot')

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
    
    $Global:Error.Clear()
    try
    {
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $WithParameter -Name 'MSBuild' | ForEach-Object { Write-Debug $_ ; $_ }
    }
    catch
    {
        Write-Error $_
        $script:threwException = $true
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

function ThenDebugOutputLogged
{
    $buildRoot = Get-BuildRoot
    It 'should write a debug log' {
        Join-Path -Path $buildRoot -ChildPath ('.output\msbuild.NUnit2PassingTest.sln.debug.log') | should -Exist
    }
}

function ThenBinsAreEmpty
{
    It 'should remove assemblies directories' {
        Get-ChildItem -Path (Get-BuildRoot) -Filter $assembly -File -Recurse | Should -BeNullOrEmpty
    }
    It 'should remove packages directory' {
        Get-ChildItem -Path (Get-BuildRoot) -Directory -Include 'packages' -Recurse | Should -BeNullOrEmpty
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
        Get-ChildItem -Path (Get-BuildRoot) -Filter 'packages' -Recurse | Should -BeNullOrEmpty
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

Describe 'MSBuild Task.when building real projects as a developer' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper
    ThenNuGetPackagesRestored
    ThenProjectsCompiled
    ThenAssembliesAreNotVersioned
    ThenDebugOutputLogged
}

Describe 'MSBuild Task.when building multiple real projects as a developer' {
    Init
    GivenProjectsThatCompile
    WhenRunningTask -AsDeveloper
    ThenNuGetPackagesRestored
    ThenProjectsCompiled
    ThenAssembliesAreNotVersioned
}

Describe 'MSBuild Task.when building real projects as build server' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsBuildServer -AtVersion '1.5.9-rc.45+1034.master.deadbee'
    ThenNuGetPackagesRestored
    ThenProjectsCompiled
    ThenAssembliesAreVersioned -ProductVersion '1.5.9-rc.45+1034.master.deadbee' -FileVersion '1.5.9'
    ThenDebugOutputLogged

}

Describe 'MSBuild Task.when compilation fails' {
    Init
    GivenAProjectThatDoesNotCompile
    WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
    ThenNuGetPackagesRestored
    ThenProjectsNotCompiled
    ThenTaskFailed
    ThenWritesError 'MSBuild\ exited\ with\ code\ 1'
}

Describe 'MSBuild Task.when Path parameter is empty' {
    Init
    GivenNoPathToBuild
    WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
    ThenProjectsNotCompiled
    ThenNuGetPackagesNotRestored
    ThenTaskFailed
    ThenWritesError ([regex]::Escape('Element ''Path'' is mandatory'))
}

Describe 'MSBuild Task.when Path parameter is not provided' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper -WithNoPath -ErrorAction SilentlyContinue
    ThenProjectsNotCompiled
    ThenNuGetPackagesNotRestored
    ThenTaskFailed
    ThenWritesError ([regex]::Escape('Element ''Path'' is mandatory'))
}

Describe 'MSBuild Task.when Path Parameter does not exist' {
    Init
    GivenAProjectThatDoesNotExist
    WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
    ThenProjectsNotCompiled
    ThenNuGetPackagesnoTRestored
    ThenTaskFailed
    ThenWritesError ([regex]::Escape('does not exist.'))
}

Describe 'MSBuild Task.when cleaning build output' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper
    ThenProjectsCompiled
    WhenRunningTask -InCleanMode -AsDeveloper
    ThenBinsAreEmpty
}

Describe 'MSBuild Task.when customizing output level' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper -WithParameter @{ 'Verbosity' = 'q'; }
    ThenOutputIsEmpty
}

Describe 'MSBuild Task.when run by developer using default verbosity output level' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper
    ThenOutputIsMinimal
}

Describe 'MSBuild Task.when run by build server using default verbosity output level' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsBuildServer
    ThenOutputIsMinimal
}

Describe 'MSBuild Task.when passing extra build properties' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper -WithParameter @{ 'Property' = @( 'Fubar=Snafu' ) ; 'Verbosity' = 'diag' }
    ThenOutput -Contains 'Fubar=Snafu'
}

Describe 'MSBuild Task.when passing custom arguments' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper -WithParameter @{ 'Argument' = @( '/nologo', '/version' ) }
    ThenOutput -Contains '\d+\.\d+\.\d+\.\d+'
}

Describe 'MSBuild Task.when passing a single custom argument' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper -WithParameter @{ 'Argument' = @( '/version' ) }
    ThenOutput -Contains '\d+\.\d+\.\d+\.\d+'
}

Describe 'MSBuild Task.when run with no CPU parameter' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper -WithParameter @{ 'Verbosity' = 'n' }
    ThenOutput -Contains '\n\ {5}\d>'
}

Describe 'MSBuild Task.when run with CPU parameter' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper -WithParameter @{ 'CpuCount' = 1; 'Verbosity' = 'n' }
    ThenOutput -DoesNotContain '^\ {5}\d>'
}

Describe 'MSBuild Task.when using custom output directory' {
    Init
    GivenAProjectThatCompiles
    WhenRunningTask -AsDeveloper -WithParameter @{ 'OutputDirectory' = '.myoutput' }
    ThenProjectsCompiled -To '.myoutput'
}

Describe 'MSBuild Task.when using custom targets' {
    Init
    GivenCustomMSBuildScriptWithMultipleTargets
    WhenRunningTask -AsDeveloper -WithParameter @{ 'Target' = 'clean','build' ; 'Verbosity' = 'diag' }
    ThenBothTargetsRun
}

Describe 'MSBuild Task.when using invalid version of MSBuild' {
    Init
    GivenAProjectThatCompiles 
    GivenVersion 'some.bad.version'
    WhenRunningTask -AsDeveloper -ErrorAction SilentlyContinue
    ThenTaskFailed
    ThenWritesError -Pattern 'some\.bad\.version\b.*is\ not\ installed'
}

Describe 'MSBuild Task.when customizing version of MSBuild' {
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

Describe 'MSBuild Task.when disabling multi-CPU builds' {
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

Describe 'MSBuild Task.when disabling file logger' {
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
