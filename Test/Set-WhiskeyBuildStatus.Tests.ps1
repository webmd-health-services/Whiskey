
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$byDeveloper = $false
$byBuildServer = $false
$failed = $false

function GivenCredential
{
    param(
        [string]
        $ID,

        [pscredential]
        $Credential
    )

    $context.Credentials.Add( $ID, $Credential )
}

function GivenNoCredentials
{
}

function GivenNoReporters
{
}

function GivenRunByBuildServer
{
    $script:context = New-WhiskeyTestContext -ForBuildServer
}

function GivenRunByDeveloper
{
    $script:context = New-WhiskeyTestContext -ForDeveloper
}

function GivenReporter
{
    param(
        [Parameter(Position=0)]
        [object]
        $Reporter
    )

    $context.Configuration['PublishBuildStatusTo'] = @( $Reporter )
}

function ThenBuildStatusReportedToBitbucketServer
{
    param(
        [Parameter(Position=0)]
        $ExpectedStatus,
        $At,
        $AsUser,
        $WithPassword
    )

    It ('should report {0} to Bitbucket Server' -f $ExpectedStatus) {
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $Status -eq $ExpectedStatus }
    }

    It ('should report to Bitbucket Server at {0}' -f $At) {
        $expectedUri = $At
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $Connection.Uri -eq $expectedUri }
    }

    It ('should report to Bitbucket Server as {0}' -f $AsUser) {
        $expectedUsername = $AsUser
        $expectedPassword = $WithPassword
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $Connection.Credential.UserName -eq $expectedUsername }
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $Connection.Credential.GetNetworkCredential().Password -eq $expectedPassword }
    }
}

function ThenNoBuildStatusReported
{
    It 'should not report build status' {
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -Times 0
    }
}

function WhenReportingBuildStatus
{
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [ValidateSet('Started','Completed','Failed')]
        $Status
    )

    Mock -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey'
    $Global:Error.Clear()
    try
    {
        Set-WhiskeyBuildStatus -Context $context -Status $Status
        $script:failed = $false
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenReportingFailed
{
    param(
        $Pattern
    )

    It 'should throw an exception' {
        $failed | Should -Be $true
        $Global:Error | Should -Match $Pattern
    }

}

Describe 'Set-WhiskeyBuildStatus.when there are no reporters is present' {
    Context 'by build server' {
        GivenRunByBuildServer
        GivenNoReporters
        WhenReportingBuildStatus Started
        ThenNoBuildStatusReported
    }

    Context 'by developer' {
        GivenRunByDeveloper
        GivenNoReporters
        WhenReportingBuildStatus Started
        ThenNoBuildStatusReported
    }
}

Describe 'Set-WhiskeyBuildStatus.when reporting build started to Bitbucket Server' {
    Context 'by build server' {
        GivenRunByBuildServer
        GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'CredentialID' = 'BBServer1' } }
        GivenCredential 'BBServer1' (New-Credential -UserName 'bitbucketserver' -Password 'fubar')
        WhenReportingBuildStatus Started
        ThenBuildStatusReportedToBitbucketServer InProgress -At 'https://bitbucket.example.com' -AsUser 'bitbucketserver' -WithPassword 'fubar'
    }

    Context 'by developer' {
        GivenRunByDeveloper
        GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'Credential' = 'BBServer' } }
        WhenReportingBuildStatus Started
        ThenNoBuildStatusReported
    }
}

Describe 'Set-WhiskeyBuildStatus.when reporting build failed to Bitbucket Server' {
    GivenRunByBuildServer
    GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'CredentialID' = 'BBServer1' } }
    GivenCredential 'BBServer1' (New-Credential -UserName 'bitbucketserver' -Password 'fubar')
    WhenReportingBuildStatus Failed
    ThenBuildStatusReportedToBitbucketServer Failed -At 'https://bitbucket.example.com' -AsUser 'bitbucketserver' -WithPassword 'fubar'
}

Describe 'Set-WhiskeyBuildStatus.when reporting build completed to Bitbucket Server' {
    GivenRunByBuildServer
    GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'CredentialID' = 'BBServer1' } }
    GivenCredential 'BBServer1' (New-Credential -UserName 'bitbucketserver' -Password 'fubar')
    WhenReportingBuildStatus Completed
    ThenBuildStatusReportedToBitbucketServer Successful -At 'https://bitbucket.example.com' -AsUser 'bitbucketserver' -WithPassword 'fubar'
}

Describe 'Set-WhiskeyBuildStatus.when using an unknown reporter' {
    GivenRunByBuildServer
    GivenReporter  @{ 'Nonsense' = @{ } }
    WhenReportingBuildStatus Started -ErrorAction SilentlyContinue
    ThenReportingFailed 'unknown\ build\ status\ reporter'
}

Describe 'Set-WhiskeyBuildStatus.when missing credential' {
    GivenRunByBuildServer
    GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'CredentialID' = 'BBServer1' } }
    GivenNoCredentials
    WhenReportingBuildStatus Started -ErrorAction SilentlyContinue
    ThenReportingFailed 'credential\ ''BBServer1''\ does\ not\ exist'
}

Describe 'Set-WhiskeyBuildStatus.when missing credential ID' {
    GivenRunByBuildServer
    GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; } }
    WhenReportingBuildStatus Started -ErrorAction SilentlyContinue
    ThenReportingFailed 'Property\ ''CredentialID''\ does\ not\ exist'
}

Describe 'Set-WhiskeyBuildStatus.when missing URI' {
    GivenRunByBuildServer
    GivenReporter @{ 'BitbucketServer' = @{ 'CredentialID' = 'fubar' ; } }
    WhenReportingBuildStatus Started -ErrorAction SilentlyContinue
    ThenReportingFailed 'Property\ ''Uri''\ does\ not\ exist'
}

