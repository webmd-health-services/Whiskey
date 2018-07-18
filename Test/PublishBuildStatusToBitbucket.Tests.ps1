
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false
[Whiskey.Context]$context = $null

function Init
{
    $script:failed = $false
    [Whiskey.Context]$script:context = $null
    Mock -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey'
}

function GivenBuild
{
    param(
        [switch]
        $ByDeveloper,

        [switch]
        $ByBuildServer
    )

    if ($ByDeveloper)
    {
        $developerOrBuildServerParam = @{ 'ForDeveloper' = $true }
    }
    elseif ($ByBuildServer)
    {
        $developerOrBuildServerParam = @{ 'ForBuildServer' = $true }
    }

    [Whiskey.Context]$script:context = New-WhiskeyTestContext @developerOrBuildServerParam
    $context.BuildMetadata.ScmCommitID = 'deadbee'
    $context.BuildMetadata.BuildUri = 'https://job.example.com/build'
    $context.BuildMetadata.JobName = 'snafu'
    $context.BuildMetadata.BuildServer = [Whiskey.BuildServer]::Jenkins
    $context.BuildMetadata.JobUri = 'https://job.example.com/'
}

function GivenBuildFailed
{
    $context.BuildStatus = [Whiskey.BuildStatus]::Failed
}

function GivenBuildStarted
{
    $context.BuildStatus = [Whiskey.BuildStatus]::Started
}

function GivenBuildSucceeded
{
    $context.BuildStatus = [Whiskey.BuildStatus]::Succeeded
}

function GivenCredential
{
    param(
        $ID,
        $UserName,
        $Password
    )

    $Password = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $credential = New-Object -TypeName PSCredential -ArgumentList $UserName, $Password
    Add-WhiskeyCredential -Context $script:context -ID $ID -Credential $credential
}

function ThenErrorMatches
{
    param(
        $Regex
    )

    It ('should write an error') {
        $Global:Error | Should -Match $Regex
    }
}

function ThenNoErrors
{
    It ('should not write any errors') {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenNotPublished
{
        It 'should not published the build status' {
            Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -Times 0
        }
}

function ThenPublishedBuildInfo
{
    $buildInfo = $context.BuildMetadata

    It ('should publish status on commit "{0}"' -f $buildInfo.ScmCommitID) {
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $CommitID -eq $buildInfo.ScmCommitID }
    }

    It ('should publish status with key "{0}"' -f $buildInfo.JobUri) {
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $Key -eq $buildInfo.JobUri }
    }

    It ('should publish status for build "{0}"' -f $buildInfo.BuildUri) {
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $BuildUri -eq $buildInfo.BuildUri }
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $buildInfo.JobName }
    }

}

function ThenPublishedStatus
{
    param(
        $ExpectedStatus
    )

    It ('should publish status "{0}" to Bitbucket Server' -f $ExpectedStatus) {
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $Status -eq $ExpectedStatus }
    }
}

function ThenPublishedTo
{
    param(
        $ExpectedUri
    )

    It ('should publish to Bitbucket Server at "{0}"' -f $ExpectedUri) {
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $Connection.Uri -eq $ExpectedUri }
    }
}
function ThenPublishedWithCredential
{
    param(
        $ExpectedUserName,
        $ExpectedPassword
    )

    It ('should publish to Bitbucket Server as "{0}"' -f $ExpectedUserName) {
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'Whiskey' -ParameterFilter {
            $Connection.Credential.UserName -eq $ExpectedUserName -and `
            $Connection.Credential.GetNetworkCredential().Password -eq $ExpectedPassword
        }
    }
}

function ThenTaskFailed
{
    It 'should fail' {
        $failed | Should -BeTrue
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        $WithProperties = @{}
    )

    $Global:Error.Clear()
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name 'PublishBuildStatusToBitbucket' -Parameter $WithProperties
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $script:failed = $true
    }
}

Describe 'PublishBuildStatusToBitbucket.when run by developer' {
    Init
    GivenBuild -ByDeveloper
    GivenCredential 'BitbucketCredential' -UserName 'user' -Password 'pass'
    GivenBuildStarted
    WhenRunningTask -WithProperties @{ 'Uri' = 'https://bitbucket.example.com'; 'CredentialID' = 'BitbucketCredential'}
    ThenNotPublished
    ThenNoErrors
}

Describe 'PublishBuildStatusToBitbucket.when not given Uri' {
    Init
    GivenBuild -ByBuildServer
    GivenCredential 'BitbucketCredential' -UserName 'user' -Password 'pass'
    GivenBuildStarted
    WhenRunningTask -WithProperties @{ 'CredentialID' = 'BitbucketCredential' } -ErrorAction SilentlyContinue
    ThenErrorMatches 'Property\ "Uri"\ does\ not\ exist\ or\ does\ not\ have\ a\ value'
    ThenTaskFailed
}

Describe 'PublishBuildStatusToBitbucket.when not given Credential' {
    Init
    GivenBuild -ByBuildServer
    GivenBuildStarted
    WhenRunningTask -WithProperties @{ 'Uri' = 'https://bitbucket.example.com' } -ErrorAction SilentlyContinue
    ThenErrorMatches 'Property\ "CredentialID"\ does\ not\ exist\ or\ does\ not\ have\ a\ value'
    ThenTaskFailed
}

Describe 'PublishBuildStatusToBitbucket.when publishing build status started' {
    Init
    GivenBuild -ByBuildServer
    GivenCredential 'BitbucketCredential' -UserName 'user' -Password 'pass'
    GivenBuildStarted
    WhenRunningTask -WithProperties @{ 'Uri' = 'https://bitbucket.example.com'; 'CredentialID' = 'BitbucketCredential'}
    ThenPublishedTo 'https://bitbucket.example.com'
    ThenPublishedStatus 'INPROGRESS'
    ThenPublishedWithCredential -ExpectedUserName 'user' -ExpectedPassword 'pass'
    ThenPublishedBuildInfo
    ThenNoErrors
}

Describe 'PublishBuildStatusToBitbucket.when publishing build status succeeded' {
    Init
    GivenBuild -ByBuildServer -Succeeded
    GivenCredential 'BitbucketCredential' -UserName 'user' -Password 'pass'
    GivenBuildSucceeded
    WhenRunningTask -WithProperties @{ 'Uri' = 'https://bitbucket.example.com'; 'CredentialID' = 'BitbucketCredential'}
    ThenPublishedTo 'https://bitbucket.example.com'
    ThenPublishedStatus 'Successful'
    ThenPublishedWithCredential -ExpectedUserName 'user' -ExpectedPassword 'pass'
    ThenPublishedBuildInfo
    ThenNoErrors
}

Describe 'PublishBuildStatusToBitbucket.when publishing build status failed' {
    Init
    GivenBuild -ByBuildServer -Succeeded
    GivenCredential 'BitbucketCredential' -UserName 'user' -Password 'pass'
    GivenBuildFailed
    WhenRunningTask -WithProperties @{ 'Uri' = 'https://bitbucket.example.com'; 'CredentialID' = 'BitbucketCredential'}
    ThenPublishedTo 'https://bitbucket.example.com'
    ThenPublishedStatus 'Failed'
    ThenPublishedWithCredential -ExpectedUserName 'user' -ExpectedPassword 'pass'
    ThenPublishedBuildInfo
    ThenNoErrors
}
