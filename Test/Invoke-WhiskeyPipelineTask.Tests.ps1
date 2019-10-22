
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$clean = $false
$initialize = $false
$pipelines = $null
$threwException = $false

function GivenCleanMode
{
    $script:clean = $true
    Mock -CommandName 'Uninstall-WhiskeyPowerShellModule' -ModuleName 'Whiskey'
}

function GivenInitializeMode
{
    $script:initialize = $true
}

function GivenPipeline
{
    param(
        $Name,
        $Yaml
    )

     $pipelines.Add(@"
$($Name):
$($Yaml)
"@)
}

function Init
{
    $script:clean = $false
    $script:initialize = $false
    $script:pipelines = New-Object 'Collections.Generic.List[string]'
    $script:threwException = $false

    $script:testRoot = New-WhiskeyTestRoot
}

function ThenPowershellModule
{
    param(
        [Parameter(Position=0)]
        [string]
        $Name,

        [Parameter(ParameterSetName='Cleaned')]
        [switch]
        $Cleaned,

        [Parameter(ParameterSetName='Installed')]
        [switch]
        $Installed
    )

    $expectedName = $Name
    if ($Cleaned)
    {
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyPowerShellModule' `
                          -ModuleName 'Whiskey' `
                          -ParameterFilter { $Name -eq $expectedName }
    }
    elseif ($Installed)
    {
        Assert-MockCalled -CommandName 'Resolve-WhiskeyPowerShellModule' `
                          -ModuleName 'Whiskey' `
                          -ParameterFilter { $Name -eq $expectedName }
        Assert-MockCalled -CommandName 'Install-WhiskeyPowerShellModule' `
                          -ModuleName 'Whiskey' `
                          -ParameterFilter { $Name -eq $expectedName }
    }
}

function ThenPipelineFailed
{
    param(
        $Pattern
    )

    $threwException | Should -BeTrue
    $Global:Error | Should -Match $Pattern
}

function ThenPipelineRun
{
    param(
        $Name,
        [string]
        $BecauseFileExists
    )

    Join-Path -Path $testRoot -ChildPath $BecauseFileExists | Should -Exist
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
    )

    $whiskeyYmlPath = Join-Path -Path $testRoot -ChildPath 'whiskey.yml'
    foreach( $pipeline in $pipelines )
    {
        $pipeline | Add-Content -Path $whiskeyYmlPath 
    }

    $context = New-WhiskeyTestContext -ForDeveloper -ConfigurationPath $whiskeyYmlPath -ForBuildRoot $testRoot
    $Global:Error.Clear()
    try
    {
        if ($clean)
        {
            Invoke-WhiskeyBuild -Context $context -Clean
        }
        elseif ($initialize)
        {
            Mock -CommandName 'Resolve-WhiskeyPowerShellModule' `
                 -ModuleName 'Whiskey' `
                 -MockWith { [pscustomobject]@{ 'Name' = $Name; 'Version' = $Version } }
            Mock -CommandName 'Install-WhiskeyPowerShellModule' -ModuleName 'Whiskey'
            Invoke-WhiskeyBuild -Context $context -Initialize
        }
        else
        {
            Invoke-WhiskeyBuild -Context $context
        }
    }
    catch
    {
        Write-Error $_
        $script:threwException = $true
    }
}

Describe 'Pipeline.when running another pipeline' {
    It 'it should run' {
        Init
        GivenPipeline 'Fubar' @'
- CopyFile:
    Path: whiskey.yml
    DestinationDirectory: $(WHISKEY_PIPELINE_NAME)
'@
        GivenPipeline 'Build' @'
- Pipeline:
    Name: Fubar
- CopyFile:
    Path: whiskey.yml
    DestinationDirectory: $(WHISKEY_PIPELINE_NAME)
'@
        WhenRunningTask
        ThenPipelineRun 'Fubar' -BecauseFileExists 'Fubar\whiskey.yml'
        ThenPipelineRun 'Build' -BecauseFileExists 'Build\whiskey.yml'
    }
}

Describe 'Pipeline.when running multiple pipelines' {
    It 'should run each pipeline' {
        Init
        GivenPipeline 'Fubar' @'
- CopyFile:
    Path: whiskey.yml
    DestinationDirectory: $(WHISKEY_PIPELINE_NAME)
'@
        GivenPipeline 'Snafu' @'
- CopyFile:
    Path: whiskey.yml
    DestinationDirectory: $(WHISKEY_PIPELINE_NAME)
'@

        GivenPipeline 'Build' @'
- Pipeline:
    Name: 
    - Fubar
    - Snafu
- CopyFile:
    Path: whiskey.yml
    DestinationDirectory: $(WHISKEY_PIPELINE_NAME)
'@
        WhenRunningTask
        ThenPipelineRun 'Fubar' -BecauseFileExists 'Fubar\whiskey.yml'
        ThenPipelineRun 'Snafu' -BecauseFileExists 'Snafu\whiskey.yml'
        ThenPipelineRun 'Build' -BecauseFileExists 'Build\whiskey.yml'
    }
}

Describe 'Pipeline.when Name property is missing' {
    It 'should fail' {
        Init
        GivenPipeline 'Build' @'
- Pipeline
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenPipelineFailed 'mandatory'
    }
}

Describe 'Pipeline.when Name property doesn''t have a value' {
    It 'should fail' {
        Init
        GivenPipeline 'Build' @'
- Pipeline:
    Name: 
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenPipelineFailed 'is missing or doesn''t have a value'
    }
}

Describe 'Pipeline.when running in Clean mode' {
    It 'should still run tasks in pipeline' {
        Init
        GivenCleanMode
        GivenPipeline 'Fubar' @'
- GetPowerShellModule:
    Name: Rivet
    Version: 0.8.1
'@
        GivenPipeline 'Build' @'
- Pipeline:
    Name: Fubar
'@
        WhenRunningTask
        ThenPowershellModule 'Rivet' -Cleaned
    }
}

Describe 'Pipeline.when running in Initialize mode' {
    It 'should still run tasks in pipeline' {
        Init
        GivenInitializeMode
        GivenPipeline 'Fubar' @'
- GetPowerShellModule:
    Name: Rivet
    Version: 0.8.1
'@
        GivenPipeline 'Build' @'
- Pipeline:
    Name: Fubar
'@
        WhenRunningTask
        ThenPowershellModule 'Rivet' -Installed
    }
}
