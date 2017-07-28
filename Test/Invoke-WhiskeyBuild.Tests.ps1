#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$runByDeveloper = $false
$runByBuildServer = $false
$publish = $false
$publishingTasks = $null
$buildPipelineFails = $false
$publishPipelineFails = $false

function Assert-ContextPassedTo
{
    param(
        $FunctionName,
        $Times = 1
    )

    $expectedContext = $context
    Assert-MockCalled -CommandName $FunctionName -ModuleName 'Whiskey' -Times $Times -ParameterFilter { 
        if( $TaskContext )
        {
            $Context = $TaskContext
        }

        #$DebugPreference = 'Continue'
        Write-Debug ('-' * 80)
        Write-Debug 'TaskContext:'
        $TaskContext | Out-String | Write-Debug
        Write-Debug 'Context:'
        $Context | Out-String | Write-Debug
        Write-Debug 'Expected Context:'
        $expectedContext | Out-String | Write-Debug
        Write-Debug ('-' * 80)
        [Object]::ReferenceEquals($Context,$expectedContext) }
}

function GivenBuildPipelineFails
{
    $script:buildPipelineFails = $true
}

function GivenBuildPipelinePasses
{
    $script:buildPipelineFails = $false
}

function GivenPreviousBuildOutput
{
    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath '.output\file.txt') -ItemType 'File' -Force
}

function GivenNotPublishing
{
    $script:publish = $false
}

function GivenPublishing
{
    $script:publish = $true
}

function GivenPublishingPipelineFails
{
    $script:publishPipelineFails = $true
}

function GivenPublishingPipelineSucceeds
{
    $script:publishPipelineFails = $false
}

function GivenRunByBuildServer
{
    $script:runByDeveloper = $false
    $script:runByBuildServer = $true
}

function GivenRunByDeveloper
{
    $script:runByDeveloper = $true
    $script:runByBuildServer = $false
}

function GivenThereAreNoPublishingTasks
{
    $script:publishingTasks = $null
}

function GivenThereArePublishingTasks
{
    $script:publishing = $true
    $script:publishingTasks = @( @{ 'TaskOne' = @{ } } )
}

function ThenBuildOutputRemoved
{
    It ('should remove .output directory') {
        Join-Path -Path ($whiskeyYmlPath | Split-Path) -ChildPath '.output' | Should -Not -Exist
    }
}

function ThenBuildPipelineRan
{
    It ('should run the BuildTasks pipeline') {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyPipeline' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Name -eq 'BuildTasks' }
        Assert-ContextPassedTo 'Invoke-WhiskeyPIpeline' -Times 1
    }
}

function ThenBuildOutputNotRemoved
{
    It ('should not remove .output directory') {
        Join-Path -Path $TestDrive.FullName -ChildPath '.output\file.txt' | Should -Exist
    }
}

function ThenBuildOutputRemoved
{
    It ('should remove .output directory') {
        Join-Path -Path $TestDrive.FullName -ChildPath '.output' | Should -Not -Exist
    }
}

function ThenBuildRunInMode
{
    param(
        $ExpectedRunMode
    )

    It ('should run in ''{0}'' mode' -f $ExpectedRunMode) {
        $context.RunMode | Should -Be $ExpectedRunMode
    }
}

function ThenBuildStatusSetTo
{
    param(
        [string]
        $ExpectedStatus
    )

    It ('should set commmit build status to ''{0}''' -f $ExpectedStatus) {
        Assert-MockCalled -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Status -eq $ExpectedStatus }
        Assert-ContextPassedTo 'Set-WhiskeyBuildStatus'
    }
}

function ThenBuildStatusMarkedAsCompleted
{
    ThenBuildStatusSetTo 'Started'
    ThenBuildStatusSetTo 'Completed'
}

function ThenBuildStatusMarkedAsFailed
{
    ThenBuildStatusSetTo 'Started'
    ThenBuildStatusSetTo 'Failed'
}

function ThenContextPassedWhenSettingBuildStatus
{
    ThenMockCalled 'Set-WhiskeyBuildStatus' -Times 2
}

function ThenPublishPipelineRan
{
    It ('should run the PublishTasks pipeline') {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyPipeline' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Name -eq 'PublishTasks' }
        Assert-ContextPassedTo 'Invoke-WhiskeyPIpeline' -Times 2
    }
}

function ThenPublishPipelineNotRun
{
    It ('should run the PublishTasks pipeline') {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyPipeline' -ModuleName 'Whiskey' -Times 0 -ParameterFilter { $Name -eq 'PublishTasks' }
    }
}

function WhenRunningBuild
{
    [CmdletBinding()]
    param(
        [Switch]
        $WithCleanSwitch,

        [Switch]
        $WithInitializeSwitch
    )

    Mock -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey'

    Mock -CommandName 'Invoke-WhiskeyPipeline' -ModuleName 'Whiskey' -MockWith ([scriptblock]::Create(@"
        #`$DebugPreference = 'Continue'

        `$buildPipelineFails = `$$($buildPipelineFails)
        `$publishPipelineFails = `$$($publishPipelineFails)
        
        Write-Debug ('Name  {0}' -f `$Name)
        Write-Debug `$buildPipelineFails
        Write-Debug `$publishPipelineFails

        if( `$Name -eq 'BuildTasks' -and `$buildPipelineFails )
        {
            throw ('BuildTasks pipeline fails!')
        }

        if( `$Name -eq 'PublishTasks' -and `$publishPipelineFails )
        {
            throw ('PublishTasks pipeline fails!')
        }
"@))

    $config = @{ }

    if( $publishingTasks )
    {
        $config['PublishTasks'] = $publishingTasks
    }

    $script:context = New-WhiskeyContextObject 
    $context.BuildRoot = $TestDrive.FullName;
    $context.Configuration = $config;
    $context.OutputDirectory = (Join-Path -Path $TestDrive.FullName -ChildPath '.output');
    $context.ByDeveloper = $runByDeveloper;
    $context.ByBuildServer = $runByBuildServer;
    $context.Publish = $publish;
    $context.RunMode = 'Build';

    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        $modeParam = @{}
        if( $WithCleanSwitch )
        {
            $modeParam['Clean'] = $true
        }
        elseif( $WithInitializeSwitch )
        {
            $modeparam['Initialize'] = $true
        }
        Invoke-WhiskeyBuild -Context $context @modeParam
    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }    
}

Describe 'Invoke-WhiskeyBuild.when build passes' {
    Context 'By Developer' {
        GivenRunByDeveloper
        GivenBuildPipelinePasses
        GivenThereArePublishingTasks
        GivenPublishing
        GivenPublishingPipelineSucceeds
        WhenRunningBuild
        ThenBuildPipelineRan
        ThenPublishPipelineRan
        ThenBuildStatusMarkedAsCompleted
    }
    Context 'By Build Server' {
        GivenRunByBuildServer
        GivenBuildPipelinePasses
        GivenPublishing
        GivenThereArePublishingTasks
        WhenRunningBuild
        ThenBuildPipelineRan
        ThenPublishPipelineRan
        ThenBuildStatusMarkedAsCompleted
    }
}

Describe 'Invoke-WhiskeyBuild.when build pipeline fails' {
    Context 'By Developer' {
        GivenRunByDeveloper
        GivenBuildPipelineFails
        GivenPublishingPipelineSucceeds
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRan
        ThenPublishPipelineNotRun
        ThenBuildStatusMarkedAsFailed
    }
    Context 'By Build Server' {
        GivenRunByBuildServer
        GivenBuildPipelineFails 
        GivenPublishingPipelineSucceeds
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRan
        ThenPublishPipelineNotRun
        ThenBuildStatusMarkedAsFailed
    }
}

Describe 'Invoke-WhiskeyBuild.when publishing pipeline fails' {
    Context 'By Developer' {
        GivenRunByDeveloper
        GivenBuildPipelinePasses
        GivenThereArePublishingTasks
        GivenPublishingPipelineFails
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRan
        ThenPublishPipelineRan
        ThenBuildStatusMarkedAsFailed
    }
    Context 'By Build Server' {
        GivenRunByBuildServer
        GivenBuildPipelinePasses 
        GivenPublishingPipelineFails
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRan
        ThenPublishPipelineRan
        ThenBuildStatusMarkedAsFailed
    }
}

Describe 'Invoke-WhiskeyBuild.when cleaning' {
    GivenRunByDeveloper
    GivenBuildPipelinePasses
    GivenNotPublishing
    GivenPreviousBuildOutput
    WhenRunningBuild -WithCleanSwitch
    ThenBuildOutputRemoved
    ThenBuildRunInMode 'Clean'
}

Describe 'Invoke-WhiskeyBuild.when initializaing' {
    GivenRunByDeveloper
    GivenBuildPipelinePasses
    GivenNotPublishing
    GivenPreviousBuildOutput
    WhenRunningBuild -WithInitializeSwitch
    ThenBuildRunInMode 'Initialize'
}

Describe 'Invoke-WhiskeyBuild.when in default run mode' {
    GivenRunByDeveloper
    GivenBuildPipelinePasses
    GivenNotPublishing
    GivenPreviousBuildOutput
    WhenRunningBuild
    ThenBuildOutputNotRemoved
    ThenBuildRunInMode 'Build'
}

Describe 'Invoke-WhiskeyBuild.when not publishing' {
    GivenRunByBuildServer
    GivenNotPublishing
    GivenThereArePublishingTasks
    GivenPublishingPipelineSucceeds
    WhenRunningBuild
    ThenPublishPipelineNotRun
}


Describe 'Invoke-WhiskeyBuild.when publishing but no tasks' {
    GivenRunByBuildServer
    GivenPublishing
    GivenThereAreNoPublishingTasks
    GivenPublishingPipelineSucceeds
    WhenRunningBuild
    ThenPublishPipelineNotRun
}
