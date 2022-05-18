
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\nuget.exe' -Resolve
$packagesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'packages'

$latestNUnit2Version =
    Find-Package -Name 'NUnit.Runners' -AllVersions |
    Where-Object 'Version' -Like '2.*' |
    Where-Object 'Version' -NotLike '*-*' |
    Select-Object -First 1 |
    Select-Object -ExpandProperty 'Version'

& $nugetPath install 'NUnit.Runners' -Version $latestNUnit2Version -OutputDirectory $packagesRoot


function Assert-NUnitTestsRun
{
    param(
        [String] $ReportPath
    )

    $ReportPath | Should -Exist
    Join-Path -Path $ReportPath -ChildPath 'nunit2*.xml' | Should -Exist
}

function Assert-NUnitTestsNotRun
{
    param(
        [String] $ReportPath
    )

    Join-Path -Path $ReportPath -ChildPath 'nunit2*.xml' | Should -Not -Exist
}

function Invoke-NUnitTask
{

    [CmdletBinding()]
    param(
        [switch]$ThatFails,

        [switch]$WithNoPath,

        [switch]$WithInvalidPath,

        [switch]$WithFailingTests,

        [switch]$WithRunningTests,

        [String]$WithError
    )

    process
    {

        Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') `
                  -Destination $TestDrive.FullName
        Copy-Item -Path $packagesRoot -Destination $TestDrive.FullName -Recurse -ErrorAction Ignore

        if( $WithNoPath )
        {
            $taskParameter = @{ }
        }
        elseif( $WithInvalidPath )
        {
            $taskParameter = @{
                                Path = @(
                                            'I\do\not\exist'
                                        )
                              }
        }
        elseif( $WithFailingTests )
        {
            $taskParameter = @{
                                Path = @(
                                            'NUnit2FailingTest.dll'
                                        )
                              }
        }
        else
        {
            $taskParameter = @{
                                Path = @(
                                            ('NUnit2PassingTest.dll'),
                                            ('NUnit2FailingTest.dll')
                                        )
                              }
        }

        $script:context = New-WhiskeyTestContext -ForBuildRoot $TestDrive.FullName -ForBuildServer

        $threwException = $false
        try
        {
            $Global:Error.Clear()
            Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'NUnit2'
        }
        catch
        {
            $threwException = $true
        }

        if( $WithError )
        {
            $Global:Error | Where-Object { $_ -match $WithError } | Should -Not -BeNullOrEmpty
        }

        if( $ThatFails )
        {
            $threwException | Should -BeTrue
        }
        else
        {
            (Join-Path -Path $context.BuildRoot -ChildPath "packages\NUnit.Runners.$($latestNUnit2Version)") |
                Should -Exist
        }

        if( $WithFailingTests -or $WithRunningTests )
        {
            Assert-NUnitTestsRun -ReportPath $context.OutputDirectory
        }
        else
        {
            Assert-NUnitTestsNotRun -ReportPath $context.OutputDirectory
        }

        Remove-Item -Path $context.OutputDirectory -Recurse -Force
    }
}

function GivenNuGetPackageInstalled
{
    param(
        $Name,
        $AtVersion
    )

    & $nugetPath install $Name -Version $AtVersion -OutputDirectory (Join-Path -Path $TestDrive.FullName -ChildPath 'packages')
}

$solutionToBuild = $null
$assemblyToTest = $null
$output = $null
$context = $null
$threwException = $false
$thrownError = $null
$taskParameter = $null
$nunitVersion = $null
$exclude = $null
$include = $null

function GivenPassingTests
{
    $script:solutionToBuild = 'NUnit2PassingTest.sln'
    $script:assemblyToTest = 'NUnit2PassingTest.dll'
    $script:taskParameter = @{ 'Path' = $script:solutionToBuild }
}

function GivenInvalidPath
{
    $script:assemblyToTest = 'I/do/not/exist'
}

function GivenExclude
{
    param(
        [String[]]$Value
    )
    $script:exclude = $value
}

function GivenInclude
{
    param(
        [String[]]$Value
    )
    $script:include = $value
}

function GivenVersion
{
    param(
        $Version
    )

    $script:nunitVersion = $Version
}

function Init
{
    $Global:Error.Clear()
    $script:nunitVersion = $null
    $script:include = $null
    $script:exclude = $null

    if( (Test-Path -Path $packagesRoot -PathType Container) )
    {
        Copy-Item -Path $packagesRoot -Destination (Join-Path -Path $TestDrive.FullName -ChildPath 'packages') -Recurse
    }
    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') -Destination $TestDrive.FullName

    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') -Destination $TestDrive.FullName
    Copy-Item -Path $packagesRoot -Destination $TestDrive.FullName -Recurse -ErrorAction Ignore
}

function WhenRunningTask
{
    param(
        [hashtable]$WithParameters = @{ },

        [switch]$WhenRunningInitialize
    )

    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $TestDrive.FullName

    if( $WhenRunningInitialize )
    {
        $context.RunMode = 'initialize'
    }

    try
    {
        $WithParameters['Path'] = $assemblyToTest

        if( $exclude )
        {
            $WithParameters['exclude'] = $exclude
        }
        if( $include )
        {
            $WithParameters['include'] = $include
        }
        if( $nunitVersion )
        {
            $WithParameters['Version'] = $nunitVersion
        }

        $Global:Error.Clear()
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Parameter $WithParameters -Name 'NUnit2' 
        $output | Write-WhiskeyVerbose -Context $context
        $script:threwException = $false
        $script:thrownError = $null
    }
    catch
    {
        $script:threwException = $true
        $script:thrownError = $_
    }
}

function Get-TestCaseResult
{
    [OutputType([System.Xml.XmlElement])]
    param(
        [String]$TestName
    )

    Get-ChildItem -Path $context.OutputDirectory -Filter 'nunit2*.xml' |
        Get-Content -Raw |
            ForEach-Object {
                $testResult = [xml]$_
                $testResult.SelectNodes(('//test-case[contains(@name,".{0}")]' -f $TestName))
            }
}

function ThenOutput
{
    param(
        [String[]]$Contains,

        [String[]]$DoesNotContain
    )

    foreach( $regex in $Contains )
    {
        $output -join [Environment]::NewLine | Should -Match $regex
    }

    foreach( $regex in $DoesNotContain )
    {
        $output | Should -Not -Match $regex
    }
}

function ThenTestsNotRun
{
    param(
        [String[]]$TestName
    )

    foreach( $name in $TestName )
    {
        Get-TestCaseResult -TestName $name | Should -BeNullOrEmpty
    }
}

function ThenTestsPassed
{
    param(
        [String[]]$TestName
    )

    foreach( $name in $TestName )
    {
        $result = Get-TestCaseResult -TestName $name
        $result | Should -Not -BeNullOrEmpty
        $result.GetAttribute('result') | ForEach-Object { $_ | Should -Be 'Success' }
    }
}

function ThenItShouldNotRunTests
{
    $context.OutputDirectory | Get-ChildItem -Filter 'nunit2*.xml' | Should -Not -Exist
}

function ThenItInstalled {
    param (
        [String]$Name,

        [Version]$Version
    )

    Join-Path -Path $script:context.BuildRoot -ChildPath "packages\$($Name).$($Version)" | Should -Exist
}

function ThenErrorIs {
    param(
        $Regex
    )
    Write-host $Global:error
    $Global:Error | Should -Match $Regex
}

function ThenErrorShouldNotBeThrown {
    param(
        $ErrorMessage
    )
    $Global:Error | Where-Object { $_ -match $ErrorMessage } | Should -BeNullOrEmpty
}

function ThenNoErrorShouldBeThrown
{
    $Global:Error | Should -BeNullOrEmpty
}

if( -not $IsWindows )
{
    Describe 'NUnit2.when run on non-Windows platform' {
        It 'should fail to run' {
            Init
            GivenPassingTests
            WhenRunningTask
            ThenErrorIs 'Windows\ platform'
        }
    }
    return
}

$taskContext = New-WhiskeyContext -Environment 'Developer' -ConfigurationPath (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whiskey.nunit2.yml')
Invoke-WhiskeyBuild -Context $taskContext

Describe 'NUnit2.when running NUnit tests' {
    It 'should run NUnit2 directly' {
        Invoke-NUnitTask -WithRunningTests
    }
}

Describe 'NUnit2.when running failing NUnit2 tests' {
    $withError = [regex]::Escape('NUnit2 tests failed')
    It 'should run NUnit directly' {
        Invoke-NUnitTask -WithFailingTests -ThatFails -WithError $withError
    }
}

Describe 'NUnit2.when Path Parameter is not included' {
    It 'should fail the build' {
        $withError = [regex]::Escape('Property "Path" is mandatory')
        Invoke-NUnitTask -ThatFails -WithNoPath -WithError $withError
    }
}

Describe 'NUnit2.when Path Parameter is invalid' {
    It 'should fail the build' {
        $withError = [regex]::Escape('do not exist.')
        Invoke-NUnitTask -ThatFails -WithInvalidPath -WithError $withError
    }
}

Describe 'NUnit2.when NUnit console not in package' {
    It 'should fail the build' {
        Mock -CommandName 'Test-Path' `
             -ModuleName 'Whiskey' `
             -MockWith { return $false } `
             -ParameterFilter { $Path -like '*nunit-console.exe' }
        $withError = [regex]::Escape('doesn''t exist at')
        Invoke-NUnitTask -ThatFails -WithError $withError -ErrorAction SilentlyContinue
    }
}

Describe 'NUnit2.when including tests by category' {
    It 'should pass categories to NUnit' {
        Init
        GivenPassingTests
        WhenRunningTask -WithParameters @{ 'Include' = '"Category with Spaces 1,Category with Spaces 2"' }
        ThenTestsPassed 'HasCategory1','HasCategory2'
        ThenTestsNotRun 'ShouldPass'
    }
}

Describe 'NUnit2.when using category filters with spaces' {
    It 'should pass categories to NUnit' {
        Init
        GivenPassingTests
        GivenInclude -Value 'Category with Spaces 1,Category With Spaces 1'
        GivenExclude -Value 'Category with Spaces,Another with spaces'
        WhenRunningTask
        ThenNoErrorShouldBeThrown
    }
}

Describe 'NUnit2.when excluding tests by category' {
    It 'should not run excluded tests' {
        Init
        GivenPassingTests
        GivenExclude '"Category with Spaces 1,Category with Spaces 2"'
        WhenRunningTask
        ThenTestsNotRun 'HasCategory1','HasCategory2'
        ThenTestsPassed 'ShouldPass'
    }
}

Describe 'NUnit2.when running with custom arguments' {
    It 'should pass arguments' {
        Init
        GivenPassingTests
        WhenRunningTask -WithParameters @{ 'Argument' = @( '/nologo', '/nodots' ) }
        ThenOutput -DoesNotContain 'NUnit-Console\ version\ ','^\.{2,}'
    }
}

Describe 'NUnit2.when running under a custom dotNET framework' {
    It 'should use custom framework' {
        Init
        GivenPassingTests
        WhenRunningTask @{ 'Framework' = 'net-4.5' }
        ThenOutput -Contains 'Execution\ Runtime:\ net-4\.5'
    }
}

Describe 'NUnit2.when using custom tool versions' {
    It 'should use those tool versions' {
        Init
        GivenPassingTests
        GivenVersion '2.6.1'
        WhenRunningTask
        ThenItInstalled 'Nunit.Runners' '2.6.1'
    }
}
