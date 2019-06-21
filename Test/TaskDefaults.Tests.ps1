
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$taskContext = $null
$taskDefaults = @{}
$threwException = $false

function Init
{
    $script:taskContext = New-WhiskeyTestContext -ForDeveloper
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
        [hashtable]
        $Defaults,
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

    It 'should throw a terminating exception' {
        $threwException | Should -Be $true
    }

    It ('should write error message matching /{0}/' -f $ErrorMessage) {
        $Global:Error[0] | Should -Match $ErrorMessage
    }
}

function ThenNoErrors
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenTaskDefaultsContains
{
    param(
        $Task,
        $Property,
        $Value
    )

    It ('should set ''{0}'' property ''{1}'' to ''{2}''' -f $Task,$Property,($Value -join ', ')) {
        $taskContext.TaskDefaults.ContainsKey($Task) | Should -Be $true
        $taskContext.TaskDefaults[$Task].ContainsKey($Property) | Should -Be $true
        $taskContext.TaskDefaults[$Task][$Property] | Should -Be $Value
    }
}

Describe 'TaskDefaults.when setting defaults' {
    Init
    GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
    GivenTaskDefaults @{ 'Symbols' = 'false' } -ForTask 'NuGetPack'
    WhenSettingTaskDefaults
    ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
    ThenTaskDefaultsContains -Task 'NuGetPack' -Property 'Symbols' -Value 'false'
    ThenNoErrors

    Context 'Additional defaults should not modify existing defaults' {
        $script:taskDefaults = @{}
        GivenTaskDefaults @{ 'Version' = '3.9.0' } -ForTask 'NUnit3'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenTaskDefaultsContains -Task 'NuGetPack' -Property 'Symbols' -Value 'false'
        ThenTaskDefaultsContains -Task 'NUnit3' -Property 'Version' -Value '3.9.0'
        ThenNoErrors
    }
}

Describe 'TaskDefaults.when setting an existing default to a new value' {
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

Describe 'TaskDefaults.when given invalid task name' {
    Init
    GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'NotARealTask'
    WhenSettingTaskDefaults -ErrorAction SilentlyContinue
    ThenFailedWithError 'Task ''NotARealTask'' does not exist.'
}

Describe 'TaskDefaults.when setting defaults during Clean mode' {
    Init
    GivenRunMode 'Clean'
    GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
    WhenSettingTaskDefaults
    ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
    ThenNoErrors
}

Describe 'TaskDefaults.when setting defaults during Initialize mode' {
    Init
    GivenRunMode 'Initialize'
    GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
    WhenSettingTaskDefaults
    ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
    ThenNoErrors
}
