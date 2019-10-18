
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$failed = $false

function GivenCredential
{
    param(
        [string]
        $ID,

        [pscredential]
        $Credential
    )

    Add-WhiskeyCredential -Context $context -ID $ID -Credential $Credential
}

function GivenNoCredentials
{
}

function GivenNoReporters
{
}

function GivenRunByBuildServer
{
    $script:context = New-WhiskeyTestContext -ForBuildServer `
                                             -ForBuildRoot $testRoot `
                                             -IncludePSModule 'BitbucketServerAutomation'
}

function GivenRunByDeveloper
{
    $script:context = New-WhiskeyTestContext -ForDeveloper `
                                             -ForBuildRoot $testRoot `
                                             -IncludePSModule 'BitbucketServerAutomation'
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

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
    # So we can mock the calls.
    Import-WhiskeyTestModule -Name 'BitbucketServerAutomation' -Force
}

function Reset
{
    Reset-WhiskeyTestPSModule
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

    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $Status -eq $ExpectedStatus }

    $buildInfo = $context.BuildMetadata
    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' `
                      -ModuleName 'Whiskey' `
                      -ParameterFilter { $CommitID -eq $buildInfo.ScmCommitID }
    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' `
                      -ModuleName 'Whiskey' `
                      -ParameterFilter { $Key -eq $buildInfo.JobUri }
    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' `
                      -ModuleName 'Whiskey' `
                      -ParameterFilter { $BuildUri -eq $buildInfo.BuildUri }
    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' `
                      -ModuleName 'Whiskey' `
                      -ParameterFilter { $Name -eq $buildInfo.JobName }
    
    $expectedUri = $At
    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' `
                      -ModuleName 'Whiskey' `
                      -ParameterFilter { $Connection.Uri -eq $expectedUri }

    $expectedUsername = $AsUser
    $expectedPassword = $WithPassword
    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' `
                      -ModuleName 'Whiskey' `
                      -ParameterFilter { $Connection.Credential.UserName -eq $expectedUsername }
    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' `
                      -ModuleName 'Whiskey' `
                      -ParameterFilter { $Connection.Credential.GetNetworkCredential().Password -eq $expectedPassword }
}

function ThenNoBuildStatusReported
{
    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -Times 0
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
    $context.BuildMetadata.ScmCommitID = 'deadbee'
    $context.BuildMetadata.BuildUri = 'https://job.example.com/build'
    $context.BuildMetadata.JobName = 'snafu'
    $context.BuildMetadata.BuildServer = [Whiskey.BuildServer]::Jenkins
    $context.BuildMetadata.JobUri = 'https://job.example.com/'
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

    $failed | Should -BeTrue
    $Global:Error | Where-Object { $_ -match $Pattern } | Should -Not -BeNullOrEmpty
}

Describe 'Set-WhiskeyBuildStatus.when there are no reporters is present' {
    AfterEach { Reset }
    Context 'by build server' {
        It 'should do nothing' {
            Init
            GivenRunByBuildServer
            GivenNoReporters
            WhenReportingBuildStatus Started
            ThenNoBuildStatusReported
        }
    }

    Context 'by developer' {
        It 'should do nothing' {
            Init
            GivenRunByDeveloper
            GivenNoReporters
            WhenReportingBuildStatus Started
            ThenNoBuildStatusReported
        }
    }
}

Describe 'Set-WhiskeyBuildStatus.when reporting build started to Bitbucket Server' {
    AfterEach { Reset }
    Context 'by build server' {
        It 'should report build status' {
            Init
            GivenRunByBuildServer
            GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'CredentialID' = 'BBServer1' } }
            $credential = New-Object 'Management.Automation.PsCredential' bitbucketserver,(ConvertTo-SecureString -AsPlainText -Force -String 'fubar')
            GivenCredential 'BBServer1' $credential
            WhenReportingBuildStatus Started
            ThenBuildStatusReportedToBitbucketServer InProgress -At 'https://bitbucket.example.com' -AsUser 'bitbucketserver' -WithPassword 'fubar'
        }
    }

    Context 'by developer' {
        It 'should do nothing' {
            Init
            GivenRunByDeveloper
            GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'Credential' = 'BBServer' } }
            WhenReportingBuildStatus Started
            ThenNoBuildStatusReported
        }
    }
}

Describe 'Set-WhiskeyBuildStatus.when reporting build failed to Bitbucket Server' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenRunByBuildServer
        GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'CredentialID' = 'BBServer1' } }
        $credential = New-Object 'Management.Automation.PsCredential' bitbucketserver,(ConvertTo-SecureString -AsPlainText -Force -String 'fubar')
        GivenCredential 'BBServer1' $credential
        WhenReportingBuildStatus Failed
        ThenBuildStatusReportedToBitbucketServer Failed -At 'https://bitbucket.example.com' -AsUser 'bitbucketserver' -WithPassword 'fubar'
    }
}

Describe 'Set-WhiskeyBuildStatus.when reporting build completed to Bitbucket Server' {
    AfterEach { Reset }
    It 'should set status' {
        Init
        GivenRunByBuildServer
        GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'CredentialID' = 'BBServer1' } }
        $credential = New-Object 'Management.Automation.PsCredential' bitbucketserver,(ConvertTo-SecureString -AsPlainText -Force -String 'fubar')
        GivenCredential 'BBServer1' $credential
        WhenReportingBuildStatus Completed
        ThenBuildStatusReportedToBitbucketServer Successful -At 'https://bitbucket.example.com' -AsUser 'bitbucketserver' -WithPassword 'fubar'
    }
}

Describe 'Set-WhiskeyBuildStatus.when using an unknown reporter' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenRunByBuildServer
        GivenReporter  @{ 'Nonsense' = @{ } }
        WhenReportingBuildStatus Started -ErrorAction SilentlyContinue
        ThenReportingFailed 'unknown\ build\ status\ reporter'
    }
}

Describe 'Set-WhiskeyBuildStatus.when missing credential' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenRunByBuildServer
        GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; 'CredentialID' = 'BBServer1' } }
        GivenNoCredentials
        WhenReportingBuildStatus Started -ErrorAction SilentlyContinue
        ThenReportingFailed 'credential\ "BBServer1"\ does\ not\ exist'
    }
}

Describe 'Set-WhiskeyBuildStatus.when missing credential ID' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenRunByBuildServer
        GivenReporter @{ 'BitbucketServer' = @{ 'Uri' = 'https://bitbucket.example.com' ; } }
        WhenReportingBuildStatus Started -ErrorAction SilentlyContinue
        ThenReportingFailed 'Property\ ''CredentialID''\ does\ not\ exist'
    }
}

Describe 'Set-WhiskeyBuildStatus.when missing URI' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenRunByBuildServer
        GivenReporter @{ 'BitbucketServer' = @{ 'CredentialID' = 'fubar' ; } }
        WhenReportingBuildStatus Started -ErrorAction SilentlyContinue
        ThenReportingFailed 'Property\ ''Uri''\ does\ not\ exist'
    }
}
