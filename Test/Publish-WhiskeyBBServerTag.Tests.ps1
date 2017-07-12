
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$threwException = $false
$version = $null
$uri = $null
$credential = $null
$credentialID = $null
$repositoryKey = $null
$projectKey = $null

function GivenACommit
{
    param(
        [Switch]
        $ThatIsInvalid
    )

    if( -not $ThatIsInvalid )
    {
        mock -CommandName 'Get-WhiskeyCommitID' -ModuleName 'Whiskey' -MockWith { return "ValidCommitHash" }
    }
    else
    {
        mock -CommandName 'Get-WhiskeyCommitID' -ModuleName 'Whiskey' -MockWith { return $null }
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
    $script:credential = New-Credential -UserName $UserName -Password $Password
}

function GivenRepository
{
    param(
        $Named,
        $InProject
    )

    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_URL' } -MockWith { return $false }
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
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_URL' } -MockWith { return $true }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_URL' } -MockWith { return [pscustomobject]@{ Value = $Uri } }.GetNewClosure()
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

function WhenTaggingACommit
{
    [CmdletBinding()]
    param(
        [Switch]
        $ThatWillFail
    )

    $script:context = [pscustomobject]@{
                                            Credentials = @{ };
                                            Version = [pscustomobject]@{
                                                                            SemVer2 = 'notused';
                                                                            SemVer2NoBuildMetadata = $version;
                                                                            SemVer1 = 'notused';
                                                                            Version = 'notused';
                                                                       };
                                            TaskIndex = 1;
                                            TaskName = 'PublishBitbucketServerTag';
                                            ConfigurationPath = (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
                                       }

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
            $context.Credentials[$credentialID] = $credential
        }
    }

    if( $projectKey -and $repositoryKey )
    {
        $taskParameter['ProjectKey'] = $projectKey
        $taskParameter['RepositoryKey'] = $repositoryKey
    }

    $global:Error.Clear()
    $script:threwException = $false
    try
    {
        Publish-WhiskeyBBServerTag -TaskContext $context -TaskParameter $taskParameter
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
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

Describe 'Publish-WhiskeyBBServerTag.when repository cloned using SSH' {
    GivenCredential 'bbservercredential' 'username' 'password'
    GivenBBServerAt 'https://bbserver.example.com'
    GivenGitUrl 'ssh://git@bbserver.example.com/project/repo.git'
    GivenACommit 
    GivenVersion '1.4.5'
    WhenTaggingACommit
    ThenTheCommitShouldBeTagged '1.4.5' -InProject 'project' -InRepository 'repo' -AtUri 'https://bbserver.example.com' -AsUser 'username' -WithPassword 'password'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyBBServerTag.when repository cloned using HTTPS' {
    GivenCredential 'bbservercredential' 'username' 'password'
    GivenBBServerAt 'https://bbserver.example.com'
    GivenGitUrl 'https://user@bbserver.example.com/scm/project/repo.git'
    GivenACommit 
    GivenVersion '34.432.3'
    WhenTaggingACommit
    ThenTheCommitShouldBeTagged '34.432.3' -InProject 'project' -InRepository 'repo' -AtUri 'https://bbserver.example.com' -AsUser 'username' -WithPassword 'password'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyBBServerTag.when user provides repository keys' {
    GivenCredential 'bbservercredential' 'username' 'password'
    GivenBBServerAt 'https://bbserver.example.com'
    GivenRepository 'fubar' -InProject 'snafu'
    GivenACommit 
    GivenVersion '34.432.3'
    WhenTaggingACommit
    ThenTheCommitShouldBeTagged '34.432.3' -InProject 'snafu' -InRepository 'fubar' -AtUri 'https://bbserver.example.com' -AsUser 'username' -WithPassword 'password'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyBBServerTag.when attempting to tag without a valid commit' {
    GivenGitUrl 'does not matter'
    GivenACommit -ThatIsInvalid
    WhenTaggingACommit -ErrorAction SilentlyContinue
    ThenTaskFails 'Unable to identify a valid commit to tag'
    ThenTheCommitShouldNotBeTagged
}

Describe 'Publsh-WhiskeyBBServerTag.when no credential ID' {
    GivenNoCredential
    WhenTaggingACommit -ErrorAction SilentlyContinue
    ThenTaskFails '\bCredentialID\b.*\bis\ mandatory\b'
}

Describe 'Publsh-WhiskeyBBServerTag.when no URI' {
    GivenCredential -ID 'id' -UserName 'fubar' -Password 'snafu'
    GivenNoBBServerUri
    WhenTaggingACommit -ErrorAction SilentlyContinue
    ThenTaskFails '\bUri\b.*\bis\ mandatory\b'
}

Describe 'Publsh-WhiskeyBBServerTag.when no repository information' {
    GivenNoRepoInformation
    GivenCredential -ID 'id' -UserName 'fubar' -Password 'snafu'
    GivenBBServerAt 'https://bitbucket.example.com'
    GivenACommit 'deadbeedeadbee'
    WhenTaggingACommit -ErrorAction SilentlyContinue
    ThenTaskFails '\bunable\ to\ determine\ the\ repository'
}