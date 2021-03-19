 
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$errors = $null
$warnings = $null
$infos = $null
$output = $null
$failed = $false
$durationRegex = '(\[ \dm\d\ds\]\ \ ){2}'

function Init
{
    $script:errors = $null
    $script:warnings = $null
    $script:infos = $null
    $script:output = $null
    $Global:Error.Clear()
}

function ThenFailed
{
    param(
        [Parameter(Mandatory)]
        [String]$ExpectedErrorMessage
    )
    
    $failed | Should -BeTrue
    $Global:Error | Should -Match $ExpectedErrorMessage
}

function ThenWroteDebug
{
    param(
        [Parameter(Mandatory)]
        [String]$Message
    )

    $output | Should -Match $Message
}

function ThenWroteError
{
    param(
        [Parameter(Mandatory)]
        [String]$Message
    )

    $errors | Should -Match $Message
}

function ThenWroteInfo
{
    param(
        [Parameter(Mandatory)]
        [String]$Message
    )

    $infos | Select-Object -First 1 | Should -Match "$($durationRegex)Log"
    $infos | Select-Object -Skip 1 | Select-Object -SkipLast 1 | Should -Match "$($durationRegex)\ \ $($Message)"
    $infos | Select-Object -Last 1 | Should -Match "^\[ \dm\d\ds\]  \[ \dm\d\ds\]$"
}

function ThenWroteVerbose
{
    param(
        [Parameter(Mandatory)]
        [String]$Message
    )

    $output | Where-Object { $_ -match [regex]::Escape($Message) } | Should -Not -BeNullOrEmpty
}

function ThenWroteWarning
{
    param(
        [Parameter(Mandatory)]
        [String]$Message
    )

    $warnings | Should -Match $Message
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
                                      -ForBuildRoot $TestDrive.FullName `
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

Describe 'Log.when logging error' {
    It 'should write an error' {
        Init
        WhenLogging 'My error!' -AtLevel 'Error' -ErrorAction SilentlyContinue
        ThenWroteError 'My error!'
    }
}

Describe 'Log.when logging warning' {
    It 'should write warning' {
        Init
        WhenLogging 'My warning!' -AtLevel 'Warning' -WarningAction SilentlyContinue
        ThenWroteWarning 'My warning!'
    }
}

Describe 'Log.when logging information' {
    It 'should write information' {
        Init
        WhenLogging 'My info!' -AtLevel 'Info'
        ThenWroteInfo 'My info!'
    }
}

Describe 'Log.when logging at default level' {
    It 'should write information' {
        Init
        WhenLogging 'My info!'
        ThenWroteInfo 'My info!'
    }
}

Describe 'Log.when logging verbose' {
    It 'should write verbose message' {
        Init
        WhenLogging 'My verbose!' -AtLevel 'Verbose' -Verbose
        ThenWroteVerbose 'My verbose!'
    }
}

Describe 'Log.when logging debug' {
    It 'should write debug message' {
        Init
        $DebugPreference = 'Continue'
        WhenLogging 'My debug!' -AtLevel 'Debug'
        ThenWroteDebug 'My debug!'
    }
}

Describe 'Log.when using invalid level' {
    It 'should fail' {
        Init
        WhenLogging 'does not matter' -AtLevel 'HumDiggity' -ErrorAction SilentlyContinue
        ThenFailed 'Property "Level" has an invalid value'
    }
}

Describe 'Log.when user specifies ErrorAction = Stop' {
    It 'should fail' {
        Init
        WhenLogging 'STOP!' -AtLevel 'Error' -WithParameter @{ 'ErrorAction' = 'Stop' } -ErrorAction SilentlyContinue
        ThenFailed -ExpectedErrorMessage 'STOP!'
    }
}

Describe 'Log.when user specifies Verbose property' {
    It 'should write verbose' {
        Init
        $VerbosePreference = 'Ignore'
        WhenLogging 'VERBOSE!' -AtLevel 'Verbose' -WithParameter @{ 'Verbose' = $true }
        ThenWroteVerbose 'VERBOSE!'
    }
}

Describe 'Log.when user specifies Debug property' {
    It 'should write debug' {
        Init
        $DebugPreference = 'Ignore'
        WhenLogging 'DEBUG!' -AtLevel 'Debug' -WithParameter @{ 'Debug' = $true }
        ThenWroteDebug 'DEBUG!'
    }
}

Describe 'Log.when logging multiple messages' {
    It 'should group all the messages' {
        Init
        WhenLogging 'line 1', 'line 2', 'line 3' 
        ThenWroteInfo 'line (1|2|3)'
    }
}

Describe 'Log.when run in Clean mode' {
    It 'should write messages' {
        Init
        WhenLogging 'message' -InCleanMode
        ThenWroteInfo 'message'
    }
}

Describe 'Log.when run in Initialize mode' {
    It 'should write messages' {
        Init
        WhenLogging 'message' -InInitializeMode
        ThenWroteInfo 'message'
    }
}