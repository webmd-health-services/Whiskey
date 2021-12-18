
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$failed = $false

function Init
{
    $script:context = $null
    $script:failed = $false
}

function GivenDataFile
{
    param(
        $Name,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Name)
}

function GivenWhiskeyYml
{
    param(
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
}

function ThenError
{
    param(
        $Regex
    )

    It ('should write an error') {
        $Global:Error | Should -Match $Regex
    }
}

function ThenTaskFailed
{
    It ('should fail') {
        $failed | Should -Be $true
    }
}

function ThenVariable
{
    param(
        $Name,
        $Is
    )

    It ('should create variable') {
        $context.Variables.ContainsKey($Name) | Should -Be $true
        $context.Variables[$Name] -join ',' | Should -Be ($Is -join ',')
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
    )

    $Global:Error.Clear()

    $script:failed = $false
    try
    {
        [Whiskey.Context]$context = New-WhiskeyTestContext -ForDeveloper -ConfigurationPath (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
        $parameter = $context.Configuration['Build'] | Where-Object { $_.ContainsKey('SetVariableFromPowerShellDataFile') } | ForEach-Object { $_['SetVariableFromPowerShellDataFile'] }
        Invoke-WhiskeyTask -TaskContext $context -Name 'SetVariableFromPowerShellDataFile' -Parameter $parameter
        $script:context = $context
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $script:failed = $true
    }
}

Describe 'SetVariableFromPowerShellDataFile.when data file is a module manifest' {
    $whiskeyPsd1Path = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Whiskey.psd1'
    Init
    GivenDataFile 'whiskey.psd1' (Get-Content -Path $whiskeyPsd1Path -Raw)
    GivenWhiskeyYml @'
Build:
- SetVariableFromPowerShellDataFile:
    Path: whiskey.psd1
    Variables:
        ModuleVersion: MODULE_VERSION
        PrivateData:
            PSData:
                ReleaseNotes: RELEASE_NOTES
                Tags: TAGS
'@
    WhenRunningTask
    $manifest = Test-ModuleManifest -Path $whiskeyPsd1Path -ErrorAction Ignore -WarningAction Ignore
    ThenVariable 'MODULE_VERSION' -Is $manifest.Version
    ThenVariable 'RELEASE_NOTES' -Is $manifest.PrivateData['PSData']['ReleaseNotes']
    ThenVariable 'TAGS' -Is $manifest.PrivateData['PSData']['Tags']
}

Describe 'SetVariableFromPowerShellDataFile.when path doesn''t exist' {
    Init
    GivenWhiskeyYml @'
Build:
- SetVariableFromPowerShellDataFile:
    Path: fubar.psd1
'@
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailed
    ThenError 'does\ not\ exist'
}

Describe 'SetVariableFromPowerShellDataFile.when data file is invalid' {
    Init
    GivenDataFile 'fubar.psd1' '@{ Fubar =  }'
    GivenWhiskeyYml @'
Build:
- SetVariableFromPowerShellDataFile:
    Path: fubar.psd1
    Variables:
        Fubar: FUBAR
'@
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailed
    ThenError 'PowerShell\ Data\ File'
}

Describe 'SetVariableFromPowerShellDataFile.when data file doesn''t contain a property' {
    Init
    GivenDataFile 'fubar.psd1' '@{ Fubar = "Snafu" }'
    GivenWhiskeyYml @'
Build:
- SetVariableFromPowerShellDataFile:
    Path: fubar.psd1
    Variables:
        Snafu: SNAFU
'@
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailed
    ThenError 'does not\ contain\ "Snafu"\ property'
}

Describe 'SetVariableFromPowerShellDataFile.when data file doesn''t contain a nested property' {
    Init
    GivenDataFile 'fubar.psd1' '@{ GrandParent = @{ Parent = @{ Fubar = "Fubar" } } }'
    GivenWhiskeyYml @'
Build:
- SetVariableFromPowerShellDataFile:
    Path: fubar.psd1
    Variables:
        GrandParent:
            Parent:
                Snafu: Snafu
'@
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailed
    ThenError 'does not\ contain\ "GrandParent\.Parent\.Snafu"\ property'
}
