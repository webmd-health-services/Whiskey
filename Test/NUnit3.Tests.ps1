Set-StrictMode -Version 'Latest'

BeforeAll {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    # Build the assemblies that use NUnit3. Only do this once.
    $latestNUnit3Version =
        Find-Package -Name 'NUnit.Runners' -AllVersions |
        Where-Object 'Version' -Like '3.*' |
        Where-Object 'Version' -NotLike '*-*' |
        Select-Object -First 1 |
        Select-Object -ExpandProperty 'Version'

    $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\nuget.exe' -Resolve
    $script:packagesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'packages'
    Remove-Item -Path $script:packagesRoot -Recurse -Force -ErrorAction Ignore
    & $nugetPath install 'NUnit.Runners' -Version $latestNUnit3Version -OutputDirectory $script:packagesRoot
    & $nugetPath install 'NUnit.Console' -Version $latestNUnit3Version -OutputDirectory $script:packagesRoot

    $whiskeyYmlPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whiskey.nunit3.yml'
    $script:taskContext = New-WhiskeyContext -Environment 'Developer' -ConfigurationPath $whiskeyYmlPath
    try
    {
        Invoke-WhiskeyBuild -Context $script:taskContext
    }
    finally
    {
    }

    $script:testNum = 0
    $script:argument = $null
    $script:failed = $false
    $script:framework = $null
    $script:targetResultFormat = $null
    $script:initialize = $null
    $script:output = $null
    $script:assembliesToTest = $null
    $script:testFilter = $null

    $script:outputDirectory = $null
    $script:nunitReport = $null

    function Get-GeneratedNUnitReport
    {
        param(
            $ResultFormat = 'nunit3'
        )

        return Get-ChildItem -Path $script:outputDirectory -Filter "$($ResultFormat)*.xml"
    }

    function Get-NunitXmlElement
    {
        param(
            $ReportFile,
            $Element
        )

        Get-Content $reportFile.FullName -Raw |
            ForEach-Object {
                $testResult = [xml]$_
                $testResult.SelectNodes(('//{0}' -f $Element))
            }
    }

    function Get-PassingTestPath
    {
        return Join-Path -Path 'NUnit3Tests' -ChildPath 'NUnit3PassingTest.dll'
    }

    function Get-FailingTestPath
    {
        return Join-Path -Path 'NUnit3Tests' -ChildPath 'NUnit3FailingTest.dll'
    }

    function GivenArgument
    {
        param(
            $script:Argument
        )
        $script:argument = $script:Argument
    }

    function GivenInitialize
    {
        $script:initialize = $true
    }

    function GivenPath
    {
        param(
            $Path
        )

        $script:assembliesToTest = $Path
    }

    function GivenPassingPath
    {
        GivenPath (Get-PassingTestPath)
    }

    function GivenFailingPath
    {
        GivenPath (Get-FailingTestPath)
    }

    function GivenFramework
    {
        param(
            $Version
        )

        $script:framework = $Version
    }

    function GivenResultFormat
    {
        param(
            $ResultFormat
        )

        $script:targetResultFormat = $ResultFormat
    }

    function GivenTestFilter
    {
        param(
            $Filter
        )

        $script:testFilter = $Filter
    }

    function GivenVersion
    {
        param(
            $Version
        )

        $script:nunitVersion = $Version
    }

    function WhenRunningTask
    {
        [CmdletBinding()]
        param(
        )

        $script:taskContext = New-WhiskeyTestContext -ForDeveloper `
                                                     -ForBuildRoot $script:buildRoot `
                                                     -ForOutputDirectory $script:outputDirectory

        $taskParameter = @{}

        if ($script:assembliesToTest)
        {
            $taskParameter['Path'] = $script:assembliesToTest
        }

        if ($script:framework)
        {
            $taskParameter['Framework'] = $script:framework
        }

        if ($script:targetResultFormat)
        {
            $taskParameter['ResultFormat'] = $script:targetResultFormat
        }

        if ($script:argument)
        {
            $taskParameter['Argument'] = $script:argument
        }

        if ($script:testFilter)
        {
            $taskParameter['TestFilter'] = $script:testFilter
        }

        if( $nunitVersion )
        {
            $taskParameter['Version'] = $nunitVersion
        }

        Copy-Item -Path $script:packagesRoot -Destination $script:buildRoot -Recurse -ErrorAction Ignore

        try
        {
            $script:output = Invoke-WhiskeyTask -TaskContext $script:taskContext -Parameter $taskParameter -Name 'NUnit3'
        }
        catch
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_
        }
    }

    function ThenPackageInstalled
    {
        param(
            $PackageName,
            $Version = '*'
        )

        Join-Path -Path $script:buildRoot -ChildPath "packages\$($PackageName).$($Version)" | Should -Exist
    }

    function ThenPackageNotInstalled
    {
        param(
            $PackageName
        )

        Join-Path -Path $script:buildRoot -ChildPath "packages\$($PackageName).*" | Should -Not -Exist
    }

    function ThenRanNUnitWithNoHeaderArgument
    {
        $script:output[0] | Should -Not -Match 'NUnit Console Runner'
    }

    function ThenRanWithSpecifiedFramework
    {
        param(
            [String] $ExpectedFramework
        )

        $script:nunitReport = Get-GeneratedNUnitReport

        $resultFramework = Get-NunitXmlElement -ReportFile $script:nunitReport -Element 'setting'
        $resultFramework =
            $resultFramework |
            Where-Object { $_.name -eq 'TargetRuntimeFramework' } |
            Select-Object -ExpandProperty 'value'

        $resultFramework | Should -Be $ExpectedFramework
    }

    function ThenTaskFailedWithMessage
    {
        param(
            $Message
        )

        $script:failed | Should -BeTrue
        $Global:Error[0] | Should -Match $Message
    }

    function ThenTaskSucceeded
    {
        $Global:Error | Should -BeNullOrEmpty
        $script:failed | Should -BeFalse
    }

    function ThenRanOnlySpecificTest
    {
        param(
            $TestName
        )

        $script:nunitReport = Get-GeneratedNUnitReport

        $testResults = Get-NunitXmlElement -ReportFile $script:nunitReport -Element 'test-case'
        $testResultsCount = $testResults.name | Measure-Object | Select-Object -ExpandProperty Count

        $testNameCount = $TestName | Measure-Object | Select-Object -ExpandProperty Count

        $testResultsCount | Should -Be $testNameCount

        $testResults.name | ForEach-Object {
            $_ | Should -BeIn $TestName
        }
    }

    function ThenNUnitReportGenerated
    {
        param(
            $ResultFormat = 'nunit3'
        )

        $script:nunitReport = Get-GeneratedNUnitReport -ResultFormat $ResultFormat

        $script:nunitReport | Should -Not -BeNullOrEmpty -Because 'test results should be saved'
        $script:nunitReport | Select-Object -ExpandProperty 'Name' | Should -Match "^$($ResultFormat)\+.{8}\..{3}\.xml"
        if ($ResultFormat -eq 'nunit3')
        {
            Get-NunitXmlElement -ReportFile $script:nunitReport -Element 'test-run' | Should -Not -BeNullOrEmpty
        }
        else
        {
            Get-NunitXmlElement -ReportFile $script:nunitReport -Element 'test-results' | Should -Not -BeNullOrEmpty
        }
        Get-NunitXmlElement -ReportFile $script:nunitReport -Element 'test-case' | Should -Not -BeNullOrEmpty
    }

    function ThenNUnitShouldNotRun
    {
        $script:nunitReport = Get-GeneratedNUnitReport
        $script:nunitReport | Should -BeNullOrEmpty -Because 'test results should not be saved if NUnit does not run'
    }

    function ThenOutput
    {
        param(
            $Contains,
            $DoesNotContain
        )

        if ($Contains)
        {
            $script:output -join [Environment]::NewLine | Should -Match $Contains
        }
        else {
            $script:output -join [Environment]::NewLine | Should -Not -Match $DoesNotContain
        }
    }
}

Describe 'NUnit3' {
    BeforeEach {
        $Global:Error.Clear()
        $script:argument = $null
        $script:failed = $false
        $script:framework = $null
        $script:targetResultFormat = $null
        $script:initialize = $null
        $script:output = $null
        $script:assembliesToTest = $null
        $script:testFilter = $null
        $script:nunitVersion = $null
        $script:supportNUnit2 = $false

        $script:buildRoot = Join-Path -Path $TestDrive -ChildPath $script:testNum
        New-Item -Path $script:buildRoot -ItemType 'Directory'

        $script:outputDirectory = Join-Path -Path $script:buildRoot -ChildPath '.output'

        # Test assemblies in separate folders to avoid cross-reference of NUnit Framework assembly versions
        @(3, 2) | ForEach-Object  {
            New-Item (Join-Path $script:buildRoot "NUnit$($_)Tests") -Type Directory
            Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath "Assemblies\NUnit$($_)*Test\bin\*\*") `
                -Destination (Join-Path $script:buildRoot "NUnit$($_)Tests")
        }
    }

    AfterEach {
        $script:testNum += 1
        $Global:Error | Format-List * -Force | Out-String | Write-Verbose # -Verbose
    }

    It 'should validate path parameter provided' {
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'Property "Path" is mandatory'
    }

    It 'should validate path exists' {
        GivenPath 'NUnit3PassingTest\bin\Debug\NUnit3FailingTest.dll', 'nonexistentfile'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'does not exist.'
    }

    It 'should validate NUnit executable exists' {
        Mock -CommandName 'Get-ChildItem' `
                -ModuleName 'Whiskey' `
                -ParameterFilter { $Filter -eq 'nunit3-console.exe' }
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'Unable to find .nunit3-console\.exe.'
    }

    It 'should run NUnit' {
        GivenPassingPath
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenTaskSucceeded
    }

    It 'should run multiple test assemblies' {
        GivenPath (Get-PassingTestPath), (Get-PassingTestPath)
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenTaskSucceeded
    }

    It 'should fail the build' {
        GivenPath (Get-FailingTestPath), (Get-PassingTestPath)
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenNUnitReportGenerated
        ThenTaskFailedWithMessage 'NUnit tests failed'
    }

    It 'should run tests with specific dotNET framework' {
        GivenPassingPath
        GivenFramework 'net-4.5'
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenRanWithSpecifiedFramework 'net-4.5'
        ThenTaskSucceeded
    }

    It 'should generate nunit3 output' {
        GivenPath (Get-PassingTestPath)
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenTaskSucceeded
    }

    It 'should generate nunit2 output' {
        GivenPath (Get-PassingTestPath)
        GivenResultFormat 'nunit2'
        WhenRunningTask
        ThenNUnitReportGenerated -ResultFormat 'nunit2'
        ThenTaskSucceeded
    }

    It 'should pass extra arguments' {
        GivenPassingPath
        GivenArgument '--noheader','--dispose-runners'
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenRanNUnitWithNoHeaderArgument
        ThenTaskSucceeded
    }

    It 'should pass bad args to NUnit' {
        GivenPassingPath
        GivenArgument '-badarg'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenNUnitShouldNotRun
        ThenTaskFailedWithMessage 'NUnit didn''t run successfully'
    }

    It 'should pass test filter' {
        GivenPassingPath
        GivenTestFilter "cat == 'Category with Spaces 1'"
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenRanOnlySpecificTest 'HasCategory1'
        ThenTaskSucceeded
    }

    It 'should pass multiple test filters' {
        GivenPassingPath
        GivenTestFilter "cat == 'Category with Spaces 1'", "cat == 'Category with Spaces 2'"
        WhenRunningTask
        ThenNUnitReportGenerated
        ThenRanOnlySpecificTest 'HasCategory1','HasCategory2'
        ThenTaskSucceeded
    }

    It 'should customize version of NUnit' {
        GivenPassingPath
        GivenVersion '3.2.1'
        WhenRunningTask
        ThenPackageInstalled 'NUnit.ConsoleRunner' '3.2.1'
    }
}
