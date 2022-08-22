
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Write-Debug 'PUBLISHBITBUCKETSERVERTAG  PSMODULEPATH'
    $env:PSModulePath -split ([IO.Path]::PathSeparator) | Write-Debug

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
    Import-WhiskeyTestModule -Name 'BitbucketServerAutomation' -Force

    $script:context = $null
    $script:threwException = $false
    $script:version = $null
    $script:uri = $null
    $script:credential = $null
    $script:credentialID = $null
    $script:repositoryKey = $null
    $script:projectKey = $null
    $script:commitID = $null
    $script:gitUri = $null

    function GivenACommit
    {
        param(
            [switch]$ThatIsInvalid
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
        [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
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

    function WhenTaggingACommit
    {
        [CmdletBinding()]
        param(
            [switch]$ThatWillFail
        )

        $script:context = New-WhiskeyTestContext -ForTaskName 'PublishBitbucketServerTag' `
                                                 -ForVersion $script:version `
                                                 -ForBuildServer `
                                                 -ForBuildRoot $script:testRoot `
                                                 -IncludePSModule 'BitbucketServerAutomation'

        $script:context.BuildMetadata.ScmUri = $script:gitUri
        mock -CommandName 'New-BBServerTag' -ModuleName 'Whiskey'

        $taskParameter = @{ }
        if( $script:uri )
        {
            $taskParameter['Uri'] = $script:uri
        }

        if( $script:credentialID )
        {
            $taskParameter['CredentialID'] = $script:credentialID
            if( $script:credential )
            {
                Add-WhiskeyCredential -Context $script:context -ID $script:credentialID -Credential $script:credential
            }
        }

        if( $script:projectKey -and $script:repositoryKey )
        {
            $taskParameter['ProjectKey'] = $script:projectKey
            $taskParameter['RepositoryKey'] = $script:repositoryKey
        }

        $script:context.BuildMetadata.ScmCommitID = $script:commitID

        $global:Error.Clear()
        $script:threwException = $false
        try
        {
            Invoke-WhiskeyTask -TaskContext $script:context -Name 'PublishBitbucketServerTag' -Parameter $taskParameter
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
            Import-WhiskeyTestModule -Name 'BitbucketServerAutomation' -Force
        }
    }

    function ThenTaskFails
    {
        param(
            $Pattern
        )

        $script:threwException | Should -BeTrue
        $Global:Error | Should -Match $Pattern
    }

    function ThenTaskSucceeds
    {
        $script:threwException | Should -BeFalse
    }

    function ThenTheCommitShouldBeTagged
    {
        [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
        param(
            [Parameter(Mandatory,Position=0)]
            $Tag,

            [Parameter(Mandatory)]
            $InProject,

            [Parameter(Mandatory)]
            $InRepository,

            [Parameter(Mandatory)]
            $AtUri,

            [Parameter(Mandatory)]
            $AsUser,

            [Parameter(Mandatory)]
            $WithPassword
        )

        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-WhiskeyDebug -Message ('Name  expected  {0}' -f $Tag)
            Write-WhiskeyDebug -Message ('      actual    {0}' -f $Name)
            $Name -eq $Tag
        }

        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            $Connection.Uri -eq $AtUri }
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Connection.Credential.UserName -eq $AsUser }
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Connection.Credential.GetNetworkCredential().Password -eq $WithPassword }
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            $ProjectKey -eq $InProject }
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $RepositoryKey -eq $InRepository }
    }

    function ThenTheCommitShouldNotBeTagged
    {
        param(
            [String]$WithError
        )

        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'Whiskey' -Times 0
    }
}

Describe 'PublishBitbucketServerTag' {
    BeforeEach {
        Write-Debug 'PUBLISHBITBUCKETSERVERTAG  INIT  PSMODULEPATH'
        $env:PSModulePath -split ([IO.Path]::PathSeparator) | Write-Debug

        $script:gitUri = ''
        $script:testRoot = New-WhiskeyTestRoot
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }

    It 'should create the tag when repository cloned using SSH' {
        GivenCredential 'bbservercredential' 'username' 'password'
        GivenBBServerAt 'https://bbserver.example.com'
        GivenGitUrl 'ssh://git@bbserver.example.com/project/repo.git'
        GivenACommit
        GivenVersion '1.4.5'
        WhenTaggingACommit
        ThenTheCommitShouldBeTagged '1.4.5' -InProject 'project' -InRepository 'repo' -AtUri 'https://bbserver.example.com' -AsUser 'username' -WithPassword 'password'
        ThenTaskSucceeds
    }

    It 'should create the tag when repository cloned using HTTPS' {
        GivenCredential 'bbservercredential' 'username' 'password'
        GivenBBServerAt 'https://bbserver.example.com'
        GivenGitUrl 'https://user@bbserver.example.com/scm/project/repo.git'
        GivenACommit
        GivenVersion '34.432.3'
        WhenTaggingACommit
        ThenTheCommitShouldBeTagged '34.432.3' -InProject 'project' -InRepository 'repo' -AtUri 'https://bbserver.example.com' -AsUser 'username' -WithPassword 'password'
        ThenTaskSucceeds
    }

    It 'should create the tag when user provides repository key' {
        GivenCredential 'bbservercredential' 'username' 'password'
        GivenBBServerAt 'https://bbserver.example.com'
        GivenRepository 'fubar' -InProject 'snafu'
        GivenACommit
        GivenVersion '34.432.3'
        WhenTaggingACommit
        ThenTheCommitShouldBeTagged '34.432.3' -InProject 'snafu' -InRepository 'fubar' -AtUri 'https://bbserver.example.com' -AsUser 'username' -WithPassword 'password'
        ThenTaskSucceeds
    }

    It 'should fail when attempting to tag without a valid commit' {
        GivenGitUrl 'does not matter'
        GivenACommit -ThatIsInvalid
        WhenTaggingACommit -ErrorAction SilentlyContinue
        ThenTaskFails 'Unable to identify a valid commit to tag'
        ThenTheCommitShouldNotBeTagged
    }

    It 'shoudl fail when no credential ID' {
        GivenNoCredential
        WhenTaggingACommit -ErrorAction SilentlyContinue
        ThenTaskFails '\bCredentialID\b.*\bis\ mandatory\b'
    }

    It 'should fail when no URI' {
        GivenCredential -ID 'id' -UserName 'fubar' -Password 'snafu'
        GivenNoBBServerUri
        WhenTaggingACommit -ErrorAction SilentlyContinue
        ThenTaskFails '\bUri\b.*\bis\ mandatory\b'
    }

    It 'should fail when no repository information' {
        GivenNoRepoInformation
        GivenCredential -ID 'id' -UserName 'fubar' -Password 'snafu'
        GivenBBServerAt 'https://bitbucket.example.com'
        GivenACommit 'deadbeedeadbee'
        WhenTaggingACommit -ErrorAction SilentlyContinue
        ThenTaskFails '\bunable\ to\ determine\ the\ repository'
    }
}
