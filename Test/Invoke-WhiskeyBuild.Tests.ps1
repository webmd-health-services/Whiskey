#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$runByDeveloper = $false
$runByBuildServer = $false

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
    Mock -CommandName 'Invoke-WhiskeyPipeline' -ModuleName 'Whiskey' -MockWith { throw 'BuildTasks pipeline failed!' }
}

function GivenBuildPipelinePasses
{
    Mock -CommandName 'Invoke-WhiskeyPipeline' -ModuleName 'Whiskey'
}

function GivenPreviousBuildOutput
{
    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath '.output\file.txt') -ItemType 'File' -Force
}

function GivenPublishingToBuildMasterFails
{
    Mock -CommandName 'New-WhiskeyBuildMasterPackage' -ModuleName 'Whiskey' -MockWith { throw 'Build Master Pipeline failed' }
}

function GivenPublishingToBuildMasterSucceeds
{
    Mock -CommandName 'New-WhiskeyBuildMasterPackage' -ModuleName 'Whiskey'
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

function ThenBuildOutputRemoved
{
    It ('should remove .output directory') {
        Join-Path -Path ($whiskeyYmlPath | Split-Path) -ChildPath '.output' | Should -Not -Exist
    }
}

function ThenBuildPipelineRun
{
    It ('should run the BuildTasks pipeline') {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyPipeline' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Name -eq 'BuildTasks' }
        Assert-ContextPassedTo 'Invoke-WhiskeyPIpeline' -Times 1
    }
}

function ThenBuildMasterPackageNotPublished
{
    It ('should not publish BuildMaster package') {
        Assert-MockCalled -CommandName 'New-WhiskeyBuildMasterPackage' -ModuleName 'Whiskey' -Times 0
    }
}

function ThenBuildMasterPackagePublished
{
    It ('should publish BuildMaster package') {
        Assert-MockCalled -CommandName 'New-WhiskeyBuildMasterPackage' -ModuleName 'Whiskey' -Times 1
        Assert-ContextPassedTo 'New-WhiskeyBuildMasterPackage'
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

function ThenCommitNotTagged
{
    It 'should not tag the commit ' {
        Assert-MockCalled -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey' -Times 0
    }
}

function ThenCommitTagged
{
    It ('should tag the commit') {
        Assert-ContextPassedTo 'Publish-WhiskeyTag'
    }
}

function ThenContextPassedWhenSettingBuildStatus
{
    ThenMockCalled 'Set-WhiskeyBuildStatus' -Times 2
}

function ThenThrewException
{
    param(
        $Pattern
    )

    It ('should throw a terminating exception that matches /{0}/' -f $Pattern) {
        $threwException | Should -Be $true
        $Global:Error | Should -Match $Pattern
    }
}

function WhenRunningBuild
{
    [CmdletBinding()]
    param(
        [Switch]
        $WithCleanSwitch
    )

    Mock -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey'
    Mock -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey'

    $script:context = [pscustomobject]@{
                                    BuildRoot = $TestDrive.FullName;
                                    Version = [pscustomobject]@{
                                                                    'SemVer2' = '';
                                                                    'SemVer2NoBuildMetadata' = '';
                                                                    'Version' = '';
                                                                    'SemVer1' = '';
                                                               }
                                    OutputDirectory = (Join-Path -Path $TestDrive.FullName -ChildPath '.output');
                                    ByDeveloper = $runByDeveloper;
                                    ByBuildServer = $runByBuildServer;
                                }

    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        $cleanParam = @{}
        if( $WithCleanSwitch )
        {
            $cleanParam['Clean'] = $true
        }
        Invoke-WhiskeyBuild -Context $context @cleanParam
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
        GivenPublishingToBuildMasterSucceeds
        WhenRunningBuild
        ThenBuildPipelineRun
        ThenBuildStatusMarkedAsCompleted
        ThenCommitNotTagged
    }
    Context 'By Build Server' {
        GivenRunByBuildServer
        GivenBuildPipelinePasses
        GivenPublishingToBuildMasterSucceeds
        WhenRunningBuild
        ThenBuildPipelineRun
        ThenBuildStatusMarkedAsCompleted
        ThenCommitTagged
    }
}

Describe 'Invoke-WhiskeyBuild.when build pipeline fails' {
    Context 'By Developer' {
        GivenRunByDeveloper
        GivenBuildPipelineFails
        GivenPublishingToBuildMasterSucceeds
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRun
        ThenBuildMasterPackageNotPublished
        ThenBuildStatusMarkedAsFailed
        ThenCommitNotTagged
    }
    Context 'By Build Server' {
        GivenRunByBuildServer
        GivenBuildPipelineFails 
        GivenPublishingToBuildMasterSucceeds
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRun
        ThenBuildMasterPackageNotPublished
        ThenBuildStatusMarkedAsFailed
        ThenCommitNotTagged
    }
}

Describe 'Invoke-WhiskeyBuild.when publishing BuildMaster package fails' {
    Context 'By Developer' {
        GivenRunByDeveloper
        GivenBuildPipelinePasses
        GivenPublishingToBuildMasterFails
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRun
        ThenBuildMasterPackagePublished
        ThenBuildStatusMarkedAsFailed
        ThenCommitNotTagged
    }
    Context 'By Build Server' {
        GivenRunByBuildServer
        GivenBuildPipelinePasses 
        GivenPublishingToBuildMasterFails
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRun
        ThenBuildMasterPackagePublished
        ThenBuildStatusMarkedAsFailed
        ThenCommitNotTagged
    }
}

Describe 'Invoke-WhiskeyBuild.when cleaning' {
    GivenRunByDeveloper
    GivenBuildPipelinePasses
    GivenPublishingToBuildMasterSucceeds
    GivenPreviousBuildOutput
    WhenRunningBuild -WithCleanSwitch
    ThenBuildOutputRemoved
}


Describe 'Invoke-WhiskeyBuild.when not cleaning' {
    GivenRunByDeveloper
    GivenBuildPipelinePasses
    GivenPublishingToBuildMasterSucceeds
    GivenPreviousBuildOutput
    WhenRunningBuild
    ThenBuildOutputNotRemoved
}