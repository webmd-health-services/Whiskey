
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Whiskey.Context]$context = $null
$property = $null
$failed = $false

function Init
{
    $script:context = $null
    $script:version = $null
    $script:failed = $false
}

function GivenFile
{
    param(
        $Name,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Name)
}

function GivenProperty
{
    param(
        $Property
    )

    $script:property = $Property
}

function ThenErrorIs
{
    param(
        $Regex
    )

    It ('should write an error') {
        $Global:Error | Should -Match $Regex
    }
}

function ThenSemVer2Is
{
    param(
        [SemVersion.SemanticVersion]
        $ExpectedVersion
    )

    It ('should set SemVer2') {
        $context.Version.SemVer2 | Should -Be $ExpectedVersion
    }

    It ('should set SemVer2NoBuildMetadata') {
        $context.Version.SemVer2NoBuildMetadata | Should -Be (New-Object 'SemVersion.SemanticVersion' ($ExpectedVersion.Major,$ExpectedVersion.Minor,$ExpectedVersion.Patch,$ExpectedVersion.Prerelease))
    }
}

function ThenSemVer1Is
{
    param(
        [SemVersion.SemanticVersion]
        $ExpectedVersion
    )

    It ('should set SemVer1') {
        $context.Version.SemVer1 | Should -Be $ExpectedVersion
    }
}

function ThenTaskFailed
{
    It ('should fail') {
        $failed | Should -Be $true
    }
}

function ThenVersionIs
{
    param(
        [version]
        $ExpectedVersion
    )

    It ('should set Version') {
        $context.Version.Version | Should -Be $ExpectedVersion
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
    )

    $script:context = New-WhiskeyTestContext -ForBuildServer
    $Global:Error.Clear()
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name 'Version' -Parameter $property
    }
    catch
    {
        $script:failed = $true
        Write-Error $_

    }
}

Describe 'Version.when using simplified syntax' {
    Init
    GivenProperty @{ '' = '4.4.5-rc.5+branch.deadbee' }
    WhenRunningTask
    ThenSemVer2Is '4.4.5-rc.5+branch.deadbee'
    ThenSemVer1Is '4.4.5-rc5'
    ThenVersionIs '4.4.5'
}

Describe 'Version.when using Version property' {
    Init
    GivenProperty @{ 'Version' = '4.4.5-rc.5+branch.deadbee' }
    WhenRunningTask
    ThenSemVer2Is '4.4.5-rc.5+branch.deadbee'
    ThenSemVer1Is '4.4.5-rc5'
    ThenVersionIs '4.4.5'
}

Describe 'Version.when Version is invalid' {
    Init
    GivenProperty @{ 'Version' = '4.5' }
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailed
    ThenErrorIs 'is\ not\ a\ semantic\ version'
}

Describe 'Version.when Version has no metadata' {
    Init
    GivenProperty @{ 'Version' = '4.5.6' }
    WhenRunningTask 
    ThenSemVer2Is '4.5.6'
    ThenSemVer1Is '4.5.6'
    ThenVersionIs '4.5.6'
}

Describe 'Version.when Version has no build metadata' {
    Init
    GivenProperty @{ 'Version' = '4.5.6-rc.5' }
    WhenRunningTask 
    ThenSemVer2Is '4.5.6-rc.5'
    ThenSemVer1Is '4.5.6-rc5'
    ThenVersionIs '4.5.6'
}

Describe 'Version.when Version has no prerelease version' {
    Init
    GivenProperty @{ 'Version' = '4.5.6+branch.commit' }
    WhenRunningTask 
    ThenSemVer2Is '4.5.6+branch.commit'
    ThenSemVer1Is '4.5.6'
    ThenVersionIs '4.5.6'
}

Describe 'Version.when using Prerelease property to set prerelease version' {
    Init
    GivenProperty @{ 'Version' = '4.5.6-rc.1' ; 'Prerelease' = 'rc.2' }
    WhenRunningTask 
    ThenSemVer2Is '4.5.6-rc.2'
    ThenSemVer1Is '4.5.6-rc2'
    ThenVersionIs '4.5.6'
}

Describe 'Version.when Prerelease property is not a valid prerelease version' {
    Init
    GivenProperty @{ 'Version' = '4.5.6-rc.1' ; 'Prerelease' = '~!@#$%^&*()_+' }
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailed
    ThenErrorIs 'not\ a\ valid\ prerelease\ version'
}

Describe 'Version.when using Build property to set build metadata' {
    Init
    GivenProperty @{ 'Version' = '4.5.6+branch.commit' ; 'Build' = 'branch2.commit2' }
    WhenRunningTask 
    ThenSemVer2Is '4.5.6+branch2.commit2'
    ThenSemVer1Is '4.5.6'
    ThenVersionIs '4.5.6'
}

Describe 'Version.when Prerelease property is not a valid build metadata' {
    Init
    GivenProperty @{ 'Version' = '4.5.6+branch.commit' ; 'Build' = '~!@#$%^&*()_+' }
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenTaskFailed
    ThenErrorIs 'not\ valid\ build\ metadata'
}

Describe 'Version.when pulling version from PowerShell module manifest' {
    Init
    GivenFile 'manifest.psd1' '@{ ModuleVersion = ''4.2.3'' }'
    GivenProperty @{ Path = 'manifest.psd1' }
    WhenRunningTask 
    ThenVersionIs '4.2.3'
    ThenSemVer1Is '4.2.3'
    ThenSemVer2Is '4.2.3'
}
