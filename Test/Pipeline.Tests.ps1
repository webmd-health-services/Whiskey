
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:whiskeyYmlPath = $null
    $script:context = $null
    $script:warnings = $null

    # So we can mock Whiskey's internal version.
    function Invoke-WhiskeyPowerShell
    {
    }

    function GivenFile
    {
        param(
            [Parameter(Mandatory)]
            [String]$Name,

            [Parameter(Mandatory)]
            [String]$Content
        )

        $path = Join-Path -Path $script:testRoot -ChildPath $Name
        $Content | Set-Content -Path $path
    }

    function GivenWhiskeyYmlBuildFile
    {
        param(
            [Parameter(Position=0)]
            [String]$Yaml
        )

        $config = $null
        $root = $script:testRoot
        $script:whiskeyYmlPath = Join-Path -Path $root -ChildPath 'whiskey.yml'
        $Yaml | Set-Content -Path $script:whiskeyYmlPath
        return $script:whiskeyYmlPath
    }

    function ThenFile
    {
        param(
            [Parameter(Mandatory)]
            [String]$Named,

            [switch]$Not,

            [Parameter(Mandatory)]
            [switch]$Exists,

            [Parameter(Mandatory)]
            [String]$Because
        )

        Join-Path -Path $script:testRoot -ChildPath $Named | Should -Not:$Not -Exist
    }
    function ThenPipelineFailed
    {
        $threwException | Should -Be $true
    }

    function ThenBuildOutputRemoved
    {
        Join-Path -Path ($script:whiskeyYmlPath | Split-Path) -ChildPath '.output' | Should -Not -Exist
    }

    function ThenPipelineSucceeded
    {
        $Global:Error | Should -BeNullOrEmpty
        $threwException | Should -BeFalse
    }

    function ThenDotNetProjectsCompilationFailed
    {
        param(
            [String]$ConfigurationPath,

            [String[]]$ProjectName
        )

        $root = Split-Path -Path $ConfigurationPath -Parent
        foreach( $name in $ProjectName )
        {
            (Join-Path -Path $root -ChildPath ('{0}.clean' -f $ProjectName)) | Should -Not -Exist
            (Join-Path -Path $root -ChildPath ('{0}.build' -f $ProjectName)) | Should -Not -Exist
        }
    }

    function ThenNUnitTestsNotRun
    {
        param(
        )

        Get-ChildItem -Path $script:context.OutputDirectory -Filter 'nunit2*.xml' | Should -BeNullOrEmpty
    }

    function ThenShouldWarn
    {
        param(
            $Pattern
        )

        $script:warnings | Should -Match $Pattern
    }

    function ThenThrewException
    {
        param(
            $Pattern
        )

        $threwException | Should -Be $true
        $Global:Error | Should -Match $Pattern
    }

    function WhenRunningPipeline
    {
        [CmdletBinding()]
        param(
            [String]$Name
        )

        $environment = $PSCmdlet.ParameterSetName
        $configuration = 'FubarSnafu'
        $optionalParams = @{ }

        [SemVersion.SemanticVersion]$version = '5.4.1-prerelease+build'

        $script:context = New-WhiskeyTestContext -ConfigurationPath $script:whiskeyYmlPath `
                                                -ForBuildServer `
                                                -ForVersion $version `
                                                -ForBuildRoot $script:testRoot
        $Global:Error.Clear()
        $script:threwException = $false
        try
        {
            Invoke-WhiskeyPipeline -Context $script:context -Name $Name -WarningVariable 'warnings'
            $script:warnings = $warnings
        }
        catch
        {
            $script:threwException = $true
            Write-Error $_
        }
    }
}

Describe 'Pipeline' {
    BeforeEach {
        $script:testRoot = New-WhiskeyTestRoot
    }

    It 'fails running an unknown task' {
        GivenWhiskeyYmlBuildFile -Yaml @'
Build:
    - FubarSnafu:
        Path: whiskey.yml
'@
        WhenRunningPipeline 'Build' -ErrorAction SilentlyContinue
        ThenPipelineFailed
        ThenThrewException 'not\ exist'
    }

    It 'fails build when task fails' {
        GivenFile 'ishouldnotrun.ps1' @'
New-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'iran.txt')
'@
        GivenWhiskeyYmlBuildFile -Yaml @'
Build:
- PowerShell:
    Path: idonotexist.ps1
- PowerShell:
    Path: ishouldnotrun.ps1
'@
        WhenRunningPipeline 'Build' -ErrorAction SilentlyContinue
        ThenPipelineFailed
        ThenFile 'iran.txt' -Not -Exists -Because 'should not execute additional tasks'
    }

    It 'handles no task properties' {
        GivenWhiskeyYmlBuildFile @"
Build:
- PublishNodeModule
- PublishNodeModule:
"@
        Mock -CommandName 'Publish-WhiskeyNodeModule' -Verifiable -ModuleName 'Whiskey'
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Publish-WhiskeyNodeModule' -ModuleName 'Whiskey' -Times 2
    }

    It 'passes default properties to task' {
        GivenWhiskeyYmlBuildFile @"
Build:
- Exec: This is a default property
"@
        Mock -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'This is a default property' }
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'This is a default property' }
    }

    It 'parses default properties correctly' {
        GivenWhiskeyYmlBuildFile @"
Build:
- Exec: someexec somearg
"@
        Mock -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec somearg' }
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec somearg' }
    }

    It 'parses default properties with quoted strings' {
        GivenWhiskeyYmlBuildFile @"
Build:
- Exec: 'someexec "some arg"'
"@
        Mock -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec "some arg"' }
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec "some arg"' }
    }

    It 'validates pipeline exists' {
        GivenWhiskeyYmlBuildFile @"
"@
        WhenRunningPipeline 'Build' -ErrorAction SilentlyContinue
        ThenPipelineFailed
        ThenThrewException 'Pipeline\ "Build"\ does\ not\ exist'
    }

    It 'handles no pipeline properties' {
        GivenWhiskeyYmlBuildFile @"
Build
"@
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        ThenShouldWarn 'pipeline\ "Build"\ doesn''t\ have\ any\ tasks'
    }

    It 'handles empty pipeline properties ' {
        GivenWhiskeyYmlBuildFile @"
Build:
"@
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        ThenShouldWarn 'pipeline\ "Build"\ doesn''t\ have\ any\ tasks'
    }
}
