
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\BitbucketServerAutomation' -Resolve) -Force

$context = $null
$threwException = $false
$version = $null
$uri = $null
$credential = $null
$credentialID = $null
$repositoryKey = $null
$projectKey = $null
$commitID = $null
$gitUri = $null

function GivenACommit
{
    param(
        [Switch]
        $ThatIsInvalid
    )

    if( -not $ThatIsInvalid )
    {
        $script:commitID = 'ValidCommitHash'
    }
    else
    {
        $script:commitID = $null
    }
}

function GivenBBServerAt
{
    param(
        $Uri
    )

    $script:uri = $Uri
}

function GivenCredential
{
    param(
        $ID,
        $UserName,
        $Password
    )

    $script:credentialID = $ID
    $script:credential = New-Object 'Management.Automation.PsCredential' $UserName,(ConvertTo-SecureString -AsPlainText -Force -String $Password)
}

function GivenRepository
{
    param(
        $Named,
        $InProject
    )

    $script:projectKey = $InProject
    $script:repositoryKey = $Named
}

function GivenGitUrl
{
    param(
        $Uri
    )

    $script:projectKey = $null
    $script:repositoryKey = $null
    $script:gitUri = $Uri
}

function GivenNoBBServerUri
{
    $script:uri = $null
}

function GivenNoCredential
{
    $script:credentialID = $null
    $script:credential = $null
}

function GivenNoRepoInformation
{
    $script:projectKey = $null
    $script:repositoryKey = $null
}

function GivenVersion
{
    param(
        $Version
    )

    $script:version = $Version
}

function Init
{
    $script:gitUri = ''
}

function WhenTaggingACommit
{
    [CmdletBinding()]
    param(
        [Switch]
        $ThatWillFail
    )

    $script:context = New-WhiskeyTestContext -ForTaskName 'PublishBitbucketServerTag' -ForVersion $version -ForBuildServer
    $context.BuildMetadata.ScmUri = $gitUri
    mock -CommandName 'New-BBServerTag' -ModuleName 'Whiskey'

    $taskParameter = @{ }
    if( $uri )
    {
        $taskParameter['Uri'] = $uri
    }

    if( $credentialID )
    {
        $taskParameter['CredentialID'] = $credentialID
        if( $credential )
        {
            Add-WhiskeyCredential -Context $context -ID $credentialID -Credential $credential
        }
    }

    if( $projectKey -and $repositoryKey )
    {
        $taskParameter['ProjectKey'] = $projectKey
        $taskParameter['RepositoryKey'] = $repositoryKey
    }

    $context.BuildMetadata.ScmCommitID = $commitID

    $global:Error.Clear()
    $script:threwException = $false
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name 'PublishBitbucketServerTag' -Parameter $taskParameter
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }
    finally
    {
        # Remove so Pester can delete the test drive
        Remove-Module -Name 'BitbucketServerAutomation' -Force
        # Re-import so Pester can verify mocks.
        Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\BitbucketServerAutomation' -Resolve) -Force
    }
}

function ThenTaskFails
{
    param(
        $Pattern
    )

    it 'should throw an exception' {
        $threwException | Should be $true
    }

    It ('the exception should match /{0}/' -f $Pattern) {
        $Global:Error | Should -Match $Pattern
    }
}

function ThenTaskSucceeds
{
    it 'should not throw an exception' {
        $threwException | should be $false
    }
}

function ThenTheCommitShouldBeTagged
{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $Tag,

        [Parameter(Mandatory=$true)]
        $InProject,

        [Parameter(Mandatory=$true)]
        $InRepository,

        [Parameter(Mandatory=$true)]
        $AtUri,

        [Parameter(Mandatory=$true)]
        $AsUser,

        [Parameter(Mandatory=$true)]
        $WithPassword
    )

    it ('should tag the commit ''{0}''' -f $Tag) {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Name  expected  {0}' -f $Tag)
            Write-Debug -Message ('      actual    {0}' -f $Name)
            $Name -eq $Tag 
        }
    }

    it ('should connect to Bitbucket Server at ''{0}''' -f $AtUri) {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Connection.Uri -eq $AtUri }
    }

    it ('should connect to Bitbucket Server as user ''{0}''' -f $AsUser) {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Connection.Credential.UserName -eq $AsUser }
    }

    it ('should connect to Bitbucket Server with password ''{0}''' -f $WithPassword) {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Connection.Credential.GetNetworkCredential().Password -eq $WithPassword }
    }

    it ('should tag the commit in Bitbucket Server project ''{0}''' -f $InProject) {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $ProjectKey -eq $InProject }
    }

    it ('should tag the commit in Bitbucket Server repository ''{0}''' -f $InRepository) {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $RepositoryKey -eq $InRepository }
    }

    it ('should fail the build if creating tag fails') {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $ErrorActionPreference -eq [Management.Automation.ActionPreference]::Stop }
    }
}

function ThenTheCommitShouldNotBeTagged
{
    param(
        [String]
        $WithError
    )

    it 'should not tag the commit' {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 0
    }
}

Describe 'PublishBitbucketServerTag.when repository cloned using SSH' {
    Init
    GivenCredential 'bbservercredential' 'username' 'password'
    GivenBBServerAt 'https://bbserver.example.com'
    GivenGitUrl 'ssh://git@bbserver.example.com/project/repo.git'
    GivenACommit 
    GivenVersion '1.4.5'
    WhenTaggingACommit
    ThenTheCommitShouldBeTagged '1.4.5' -InProject 'project' -InRepository 'repo' -AtUri 'https://bbserver.example.com' -AsUser 'username' -WithPassword 'password'
    ThenTaskSucceeds
}

Describe 'PublishBitbucketServerTag.when repository cloned using HTTPS' {
    Init
    GivenCredential 'bbservercredential' 'username' 'password'
    GivenBBServerAt 'https://bbserver.example.com'
    GivenGitUrl 'https://user@bbserver.example.com/scm/project/repo.git'
    GivenACommit 
    GivenVersion '34.432.3'
    WhenTaggingACommit
    ThenTheCommitShouldBeTagged '34.432.3' -InProject 'project' -InRepository 'repo' -AtUri 'https://bbserver.example.com' -AsUser 'username' -WithPassword 'password'
    ThenTaskSucceeds
}

Describe 'PublishBitbucketServerTag.when user provides repository keys' {
    Init
    GivenCredential 'bbservercredential' 'username' 'password'
    GivenBBServerAt 'https://bbserver.example.com'
    GivenRepository 'fubar' -InProject 'snafu'
    GivenACommit 
    GivenVersion '34.432.3'
    WhenTaggingACommit
    ThenTheCommitShouldBeTagged '34.432.3' -InProject 'snafu' -InRepository 'fubar' -AtUri 'https://bbserver.example.com' -AsUser 'username' -WithPassword 'password'
    ThenTaskSucceeds
}

Describe 'PublishBitbucketServerTag.when attempting to tag without a valid commit' {
    Init
    GivenGitUrl 'does not matter'
    GivenACommit -ThatIsInvalid
    WhenTaggingACommit -ErrorAction SilentlyContinue
    ThenTaskFails 'Unable to identify a valid commit to tag'
    ThenTheCommitShouldNotBeTagged
}

Describe 'Publsh-WhiskeyBBServerTag.when no credential ID' {
    Init
    GivenNoCredential
    WhenTaggingACommit -ErrorAction SilentlyContinue
    ThenTaskFails '\bCredentialID\b.*\bis\ mandatory\b'
}

Describe 'Publsh-WhiskeyBBServerTag.when no URI' {
    Init
    GivenCredential -ID 'id' -UserName 'fubar' -Password 'snafu'
    GivenNoBBServerUri
    WhenTaggingACommit -ErrorAction SilentlyContinue
    ThenTaskFails '\bUri\b.*\bis\ mandatory\b'
}

Describe 'Publsh-WhiskeyBBServerTag.when no repository information' {
    Init
    GivenNoRepoInformation
    GivenCredential -ID 'id' -UserName 'fubar' -Password 'snafu'
    GivenBBServerAt 'https://bitbucket.example.com'
    GivenACommit 'deadbeedeadbee'
    WhenTaggingACommit -ErrorAction SilentlyContinue
    ThenTaskFails '\bunable\ to\ determine\ the\ repository'
}