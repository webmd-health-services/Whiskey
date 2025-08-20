
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:errors = $null
    $script:warnings = $null
    $script:infos = $null
    $script:output = $null
    $script:failed = $false
    $script:durationRegex = '(\[ \dm\d\ds\]\ \ ){2}'

    function ThenFailed
    {
        param(
            [Parameter(Mandatory)]
            [String]$ExpectedErrorMessage
        )

        $script:failed | Should -BeTrue
        $Global:Error | Should -Match $ExpectedErrorMessage
    }

    function ThenWroteDebug
    {
        param(
            [Parameter(Mandatory)]
            [String]$Message
        )

        $script:output | Select-Object -Last 1 | Should -Match $Message
    }

    function ThenWroteError
    {
        param(
            [Parameter(Mandatory)]
            [String]$Message
        )

        $script:errors | Should -Match $Message
    }

    function ThenWroteInfo
    {
        param(
            [Parameter(Mandatory)]
            [String]$Message
        )

        $script:infos | Select-Object -First 1 | Should -Match "$($script:durationRegex)Log"
        $script:infos |
            Select-Object -Skip 1 |
            Select-Object -SkipLast 1 |
            Should -Match "$($script:durationRegex)\ \ $($Message)"
        $script:infos | Select-Object -Last 1 | Should -Match "^\[ \dm\d\ds\]  \[ \dm\d\ds\]$"
    }

    function ThenWroteVerbose
    {
        param(
            [Parameter(Mandatory)]
            [String]$Message
        )

        $script:output | Where-Object { $_ -match [regex]::Escape($Message) } | Should -Not -BeNullOrEmpty
    }

    function ThenWroteWarning
    {
        param(
            [Parameter(Mandatory)]
            [String]$Message
        )

        $script:warnings | Should -Match $Message
    }

    function WhenLogging
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String[]]$Message,

            [String]$AtLevel,

            [hashtable]$WithParameter = @{ },

            [switch]$InCleanMode,

            [switch]$InInitializeMode
        )

        $WithParameter['Message'] = $Message

        if( $AtLevel )
        {
            $WithParameter['Level'] = $AtLevel
        }

        $script:failed = $false
        $context = New-WhiskeyTestContext -ForDeveloper `
                                          -ForBuildRoot $TestDrive `
                                          -InCleanMode:$InCleanMOde `
                                          -InInitMode:$InInitializeMode
        try
        {
            $script:output = Invoke-WhiskeyTask -Name 'Log' `
                                                -TaskContext $context `
                                                -Parameter $WithParameter `
                                                -ErrorVariable 'errors' `
                                                -WarningVariable 'warnings' `
                                                -InformationVariable 'infos' `
                                                4>&1 `
                                                5>&1
            $script:errors = $errors
            $script:warnings = $warnings
            $script:infos = $infos
        }
        catch
        {
            $script:failed = $true
            Write-CaughtError $_
        }
    }
}

Describe 'Log' {
    BeforeEach {
        $script:errors = $null
        $script:warnings = $null
        $script:infos = $null
        $script:output = $null
        $Global:Error.Clear()
    }

    It 'writes errors' {
        WhenLogging 'My error!' -AtLevel 'Error' -ErrorAction SilentlyContinue
        ThenWroteError 'My error!'
    }

    It 'writes warnings' {
        WhenLogging 'My warning!' -AtLevel 'Warning' -WarningAction SilentlyContinue
        ThenWroteWarning 'My warning!'
    }

    It 'writes information' {
        WhenLogging 'My info!' -AtLevel 'Info'
        ThenWroteInfo 'My info!'
    }

    It 'writes at information level by default' {
        WhenLogging 'My info!'
        ThenWroteInfo 'My info!'
    }

    It 'writes verbose messages' {
        WhenLogging 'My verbose!' -AtLevel 'Verbose' -Verbose
        ThenWroteVerbose 'My verbose!'
    }

    It 'writes debug messages' {
        $DebugPreference = 'Continue'
        WhenLogging 'My debug!' -AtLevel 'Debug'
        ThenWroteDebug 'My debug!'
    }

    It 'validates log level' {
        WhenLogging 'does not matter' -AtLevel 'HumDiggity' -ErrorAction SilentlyContinue
        ThenFailed 'Property "Level" has an invalid value'
    }

    It 'supports ErrorAction stop' {
        WhenLogging 'STOP!' -AtLevel 'Error' -WithParameter @{ '.ErrorAction' = 'Stop' } -ErrorAction SilentlyContinue
        ThenFailed -ExpectedErrorMessage 'STOP!'
    }

    It 'groups multiple messages' {
        WhenLogging 'line 1', 'line 2', 'line 3'
        ThenWroteInfo 'line (1|2|3)'
    }

    It 'supports clean mode' {
        WhenLogging 'message' -InCleanMode
        ThenWroteInfo 'message'
    }

    It 'supports initialize mode' {
        WhenLogging 'message' -InInitializeMode
        ThenWroteInfo 'message'
    }
}