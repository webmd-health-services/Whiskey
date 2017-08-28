
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$pipelines = $null
$threwException = $false

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
    $script:pipelines = New-Object 'Collections.Generic.List[string]'
    $script:threwException = $false
}

function ThenPipelineFailed
{
    param(
        $Pattern
    )

    It ('should write a terminating error') {
        $threwException | Should -Be $true
    }


    It ('should fail with message that matches /{0}/' -f $Pattern) {
        $Global:Error | Should -Match $Pattern
    }
}

function ThenPipelineRun
{
    param(
        $Name,
        [string]
        $BecauseFileExists
    )

    It ('should run pipeline ''{0}''' -f $Name) {
        Join-Path -Path $TestDrive.FullName -ChildPath $BecauseFileExists | Should -Exist
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
    )

    $whiskeyYmlPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml'
    foreach( $pipeline in $pipelines )
    {
        $pipeline | Add-Content -Path $whiskeyYmlPath 
    }

    $context = New-WhiskeyTestContext -ForDeveloper -ConfigurationPath $whiskeyYmlPath
    $Global:Error.Clear()
    try
    {
        Invoke-WhiskeyBuild -Context $context
    }
    catch
    {
        Write-Error $_
        $script:threwException = $true
    }
}

Describe 'WhiskeyPipeline Task.when running another pipeline' {
    Init
    GivenPipeline 'Fubar' @'
- CopyFile:
    Path: whiskey.yml
    DestinationDirectory: $(WHISKEY_PIPELINE_NAME)
'@
    GivenPipeline 'BuildTasks' @'
- Pipeline:
    Name: Fubar
- CopyFile:
    Path: whiskey.yml
    DestinationDirectory: $(WHISKEY_PIPELINE_NAME)
'@
    WhenRunningTask
    ThenPipelineRun 'Fubar' -BecauseFileExists 'Fubar\whiskey.yml'
    ThenPipelineRun 'BuildTasks' -BecauseFileExists 'BuildTasks\whiskey.yml'
}

Describe 'WhiskeyPipeline Task.when running multiple pipelines' {
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

    GivenPipeline 'BuildTasks' @'
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
    ThenPipelineRun 'BuildTasks' -BecauseFileExists 'BuildTasks\whiskey.yml'
}

Describe 'WhiskeyPipeline Task.when Name property is missing' {
    Init
    GivenPipeline 'BuildTasks' @'
- Pipeline
'@
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenPipelineFailed 'mandatory'
}

Describe 'WhiskeyPipeline Task.when Name property doesn''t have a value' {
    Init
    GivenPipeline 'BuildTasks' @'
- Pipeline:
    Name: 
'@
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenPipelineFailed 'is missing or doesn''t have a value'
}