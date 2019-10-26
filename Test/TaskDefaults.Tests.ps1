
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$taskContext = $null
$taskDefaults = @{}
$threwException = $false

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
    $script:taskContext = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot
    $script:taskDefaults = @{}
    $script:threwException = $false
}

function GivenRunMode
{
    param(
        $RunMode
    )

    $script:taskContext.RunMode = $RunMode
}

function GivenTaskDefaults
{
    param(
        [hashtable]$Defaults,
        $ForTask
    )

    $script:taskDefaults[$ForTask] = $Defaults
}

function WhenSettingTaskDefaults
{
    [CmdletBinding()]
    param()

    $Global:Error.Clear()

    try
    {
        Invoke-WhiskeyTask -TaskContext $taskContext -Name 'TaskDefaults' -Parameter $taskDefaults
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenFailedWithError
{
    param(
        $ErrorMessage
    )

    $threwException | Should -BeTrue
    $Global:Error[0] | Should -Match $ErrorMessage
}

function ThenNoErrors
{
    $Global:Error | Should -BeNullOrEmpty
}

function ThenTaskDefaultsContains
{
    param(
        $Task,
        $Property,
        $Value
    )

    $taskContext.TaskDefaults.ContainsKey($Task) | Should -BeTrue
    $taskContext.TaskDefaults[$Task].ContainsKey($Property) | Should -BeTrue
    $taskContext.TaskDefaults[$Task][$Property] | Should -Be $Value
}

Describe 'TaskDefaults.when setting defaults' {
    It 'should use the defaults' {
        Init
        GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
        GivenTaskDefaults @{ 'Symbols' = 'false' } -ForTask 'NuGetPack'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenTaskDefaultsContains -Task 'NuGetPack' -Property 'Symbols' -Value 'false'
        ThenNoErrors

        # Make sure existing defaults don't get overwritten
        $script:taskDefaults = @{ }
        GivenTaskDefaults @{ 'Version' = '3.9.0' } -ForTask 'NUnit3'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenTaskDefaultsContains -Task 'NuGetPack' -Property 'Symbols' -Value 'false'
        ThenTaskDefaultsContains -Task 'NUnit3' -Property 'Version' -Value '3.9.0'
        ThenNoErrors
    }
}

Describe 'TaskDefaults.when setting an existing default to a new value' {
    It 'should change default' {
        Init
        GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenNoErrors

        GivenTaskDefaults @{ 'Version' = 13.0 } -ForTask 'MSBuild'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 13.0
        ThenNoErrors
    }
}

Describe 'TaskDefaults.when given invalid task name' {
    It 'should fail' {
        Init
        GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'NotARealTask'
        WhenSettingTaskDefaults -ErrorAction SilentlyContinue
        ThenFailedWithError 'Task ''NotARealTask'' does not exist.'
    }
}

Describe 'TaskDefaults.when setting defaults during Clean mode' {
    It 'should set defaults' {
        Init
        GivenRunMode 'Clean'
        GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenNoErrors
    }
}

Describe 'TaskDefaults.when setting defaults during Initialize mode' {
    It 'should set defaults' {
        Init
        GivenRunMode 'Initialize'
        GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenNoErrors
    }
}
