
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\nuget.exe' -Resolve
    $script:packagesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'packages'
    $script:testNum = 0

    $script:latestNUnit2Version =
        Find-Package -Name 'NUnit.Runners' -AllVersions |
        Where-Object 'Version' -Like '2.*' |
        Where-Object 'Version' -NotLike '*-*' |
        Select-Object -First 1 |
        Select-Object -ExpandProperty 'Version'

    & $script:nugetPath install `
                        'NUnit.Runners' `
                        -Version $script:latestNUnit2Version `
                        -OutputDirectory $script:packagesRoot

    $nunit2WhiskeyYmlPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whiskey.nunit2.yml'
    $script:taskContext = New-WhiskeyContext -Environment 'Developer' -ConfigurationPath $nunit2WhiskeyYmlPath
    Invoke-WhiskeyBuild -Context $script:taskContext

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
                      -Destination $script:testDir
            Copy-Item -Path $script:packagesRoot -Destination $script:testDir -Recurse -ErrorAction Ignore

            if( $WithNoPath )
            {
                $script:taskParameter = @{ }
            }
            elseif( $WithInvalidPath )
            {
                $script:taskParameter = @{
                                    Path = @(
                                                'I\do\not\exist'
                                            )
                                }
            }
            elseif( $WithFailingTests )
            {
                $script:taskParameter = @{
                                    Path = @(
                                                'NUnit2FailingTest.dll'
                                            )
                                }
            }
            else
            {
                $script:taskParameter = @{
                                    Path = @(
                                                ('NUnit2PassingTest.dll'),
                                                ('NUnit2FailingTest.dll')
                                            )
                                }
            }

            $script:context = New-WhiskeyTestContext -ForBuildRoot $script:testDir -ForBuildServer

            $script:threwException = $false
            try
            {
                $Global:Error.Clear()
                Invoke-WhiskeyTask -TaskContext $script:context -Parameter $script:taskParameter -Name 'NUnit2'
            }
            catch
            {
                $script:threwException = $true
            }

            if( $WithError )
            {
                $Global:Error | Where-Object { $_ -match $WithError } | Should -Not -BeNullOrEmpty
            }

            if( $ThatFails )
            {
                $script:threwException | Should -BeTrue
            }
            else
            {
                (Join-Path -Path $script:context.BuildRoot -ChildPath "packages\NUnit.Runners.$($script:latestNUnit2Version)") |
                    Should -Exist
            }

            if( $WithFailingTests -or $WithRunningTests )
            {
                Assert-NUnitTestsRun -ReportPath $script:context.OutputDirectory
            }
            else
            {
                Assert-NUnitTestsNotRun -ReportPath $script:context.OutputDirectory
            }

            Remove-Item -Path $script:context.OutputDirectory -Recurse -Force
        }
    }

    function GivenNuGetPackageInstalled
    {
        param(
            $Name,
            $AtVersion
        )

        $outputDirPath = Join-Path -Path $script:testDir -ChildPath 'packages'
        & $script:nugetPath install $Name -Version $AtVersion -OutputDirectory $outputDirPath
    }

    $script:solutionToBuild = $null
    $script:assemblyToTest = $null
    $script:output = $null
    $script:context = $null
    $script:threwException = $false
    $script:thrownError = $null
    $script:taskParameter = $null
    $script:nunitVersion = $null
    $script:exclude = $null
    $script:include = $null

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

        $script:testDir = Join-Path -Path $TestDrive -ChildPath $testNum
        New-Item -Path $script:testDir -ItemType 'Directory'

        if( (Test-Path -Path $script:packagesRoot -PathType Container) )
        {
            Copy-Item -Path $script:packagesRoot -Destination (Join-Path -Path $script:testDir -ChildPath 'packages') -Recurse
        }
        Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') -Destination $script:testDir

        Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2*\bin\*\*') -Destination $script:testDir
        Copy-Item -Path $script:packagesRoot -Destination $script:testDir -Recurse -ErrorAction Ignore
    }

    function WhenRunningTask
    {
        param(
            [hashtable]$WithParameters = @{ },

            [switch]$WhenRunningInitialize
        )

        $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $script:testDir

        if( $WhenRunningInitialize )
        {
            $script:context.RunMode = 'initialize'
        }

        try
        {
            $WithParameters['Path'] = $script:assemblyToTest

            if( $script:exclude )
            {
                $WithParameters['exclude'] = $script:exclude
            }
            if( $script:include )
            {
                $WithParameters['include'] = $script:include
            }
            if( $script:nunitVersion )
            {
                $WithParameters['Version'] = $script:nunitVersion
            }

            $Global:Error.Clear()
            $script:output = Invoke-WhiskeyTask -TaskContext $script:context -Parameter $WithParameters -Name 'NUnit2'
            $script:output | Write-WhiskeyVerbose -Context $script:context
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

        Get-ChildItem -Path $script:context.OutputDirectory -Filter 'nunit2*.xml' |
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
            $script:output -join [Environment]::NewLine | Should -Match $regex
        }

        foreach( $regex in $DoesNotContain )
        {
            $script:output | Should -Not -Match $regex
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
        $script:context.OutputDirectory | Get-ChildItem -Filter 'nunit2*.xml' | Should -Not -Exist
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
}

Describe 'NUnit2' {
    BeforeEach {
        Init
    }

    AfterEach {
        $script:testNum += 1

        $Global:Error | Format-List * -Force | Out-String | Write-Verbose #-Verbose
    }

    It 'should run NUnit2' {
        Invoke-NUnitTask -WithRunningTests
    }

    It 'should fail build' {
        $withError = [regex]::Escape('NUnit2 tests failed')
        Invoke-NUnitTask -WithFailingTests -ThatFails -WithError $withError
    }

    It 'should require Path parameter' {
        $withError = [regex]::Escape('Property "Path" is mandatory')
        Invoke-NUnitTask -ThatFails -WithNoPath -WithError $withError
    }

    It 'should validate Path exists' {
        $withError = [regex]::Escape('do not exist.')
        Invoke-NUnitTask -ThatFails -WithInvalidPath -WithError $withError
    }

    It 'should validate NUnit package' {
        Mock -CommandName 'Test-Path' `
            -ModuleName 'Whiskey' `
            -MockWith { return $false } `
            -ParameterFilter { $Path -like '*nunit-console.exe' }
        $withError = [regex]::Escape('doesn''t exist at')
        Invoke-NUnitTask -ThatFails -WithError $withError -ErrorAction SilentlyContinue
    }

    It 'should pass categories' {
        GivenPassingTests
        WhenRunningTask -WithParameters @{ 'Include' = '"Category with Spaces 1,Category with Spaces 2"' }
        ThenTestsPassed 'HasCategory1','HasCategory2'
        ThenTestsNotRun 'ShouldPass'
    }

    It 'should pass categories with spaces' {
        GivenPassingTests
        GivenInclude -Value 'Category with Spaces 1,Category With Spaces 1'
        GivenExclude -Value 'Category with Spaces,Another with spaces'
        WhenRunningTask
        ThenNoErrorShouldBeThrown
    }

    It 'should exclude tests' {
        GivenPassingTests
        GivenExclude '"Category with Spaces 1,Category with Spaces 2"'
        WhenRunningTask
        ThenTestsNotRun 'HasCategory1','HasCategory2'
        ThenTestsPassed 'ShouldPass'
    }

    It 'should pass custom arguments' {
        GivenPassingTests
        WhenRunningTask -WithParameters @{ 'Argument' = @( '/nologo', '/nodots' ) }
        ThenOutput -DoesNotContain 'NUnit-Console\ version\ ','^\.{2,}'
    }

    It 'should use custom dotNet framework' {
        GivenPassingTests
        WhenRunningTask @{ 'Framework' = 'net-4.5' }
        ThenOutput -Contains 'Execution\ Runtime:\ net-4\.5'
    }

    It 'should use custom tool versions' {
        GivenPassingTests
        GivenVersion '2.6.1'
        WhenRunningTask
        ThenItInstalled 'Nunit.Runners' '2.6.1'
    }
}
