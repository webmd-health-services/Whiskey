
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:taskContext = $null
    $script:taskDefaults = @{}
    $script:threwException = $false

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
            Invoke-WhiskeyTask -TaskContext $script:taskContext -Name 'TaskDefaults' -Parameter $script:taskDefaults
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

        $script:threwException | Should -BeTrue
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

        $script:taskContext.TaskDefaults.ContainsKey($Task) | Should -BeTrue
        $script:taskContext.TaskDefaults[$Task].ContainsKey($Property) | Should -BeTrue
        $script:taskContext.TaskDefaults[$Task][$Property] | Should -Be $Value
    }
}

Describe 'TaskDefault' {
    BeforeEach {
        $script:testRoot = New-WhiskeyTestRoot
        $script:taskContext = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $script:testRoot
        $script:taskDefaults = @{}
        $script:threwException = $false
    }

    It 'should use the defaults' {
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

    It 'should change default' {
        GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenNoErrors

        GivenTaskDefaults @{ 'Version' = 13.0 } -ForTask 'MSBuild'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 13.0
        ThenNoErrors
    }

    It 'should fail' {
        GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'NotARealTask'
        WhenSettingTaskDefaults -ErrorAction SilentlyContinue
        ThenFailedWithError 'Task ''NotARealTask'' does not exist.'
    }

    It 'should set defaults' {
        GivenRunMode 'Clean'
        GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenNoErrors
    }

    It 'should set defaults' {
        GivenRunMode 'Initialize'
        GivenTaskDefaults @{ 'Version' = 12.0 } -ForTask 'MSBuild'
        WhenSettingTaskDefaults
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenNoErrors
    }
}
