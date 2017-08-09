
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

InModuleScope 'Whiskey' {
    $buildInfo = $null

    function GivenEnvironmentVariable
    {
        param(
            $Name,
            $Value
        )

        $filter = [scriptblock]::Create(('$Path -eq ''env:{0}''' -f $Name))
        Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter $filter -MockWith { return $true }
        Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -ParameterFilter $filter -MockWith { return [pscustomobject]@{ Value = $Value } }.GetNewClosure()
    }

    function GivenDeveloperEnvironment
    {
        param(
        )

        Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path-eq 'env:JENKINS_URL' } -MockWith { return $false }

    }

    function GivenJenkinsEnvironment
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            $BuildNumber,
            [Parameter(Mandatory=$true)]
            $BuildID,
            [Parameter(Mandatory=$true)]
            $JobName,
            [Parameter(Mandatory=$true)]
            $BuildUri,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $GitUri,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $GitCommit,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $GitBranch
        )

        GivenEnvironmentVariable 'JENKINS_URL' 'https://jenkins.example.com'
        GivenEnvironmentVariable 'BUILD_NUMBER' $BuildNumber
        GivenEnvironmentVariable 'BUILD_TAG' $BuildID
        GivenEnvironmentVariable 'JOB_NAME' $JobName
        GivenEnvironmentVariable 'BUILD_URL' $BuildUri
        if( $PSCmdlet.ParameterSetName -eq 'WithGitScm' )
        {
            GivenEnvironmentVariable 'GIT_URL' $GitUri
            GivenEnvironmentVariable 'GIT_COMMIT' $GitCommit
            GivenEnvironmentVariable 'GIT_BRANCH' $GitBranch
        }
    }


    function Init
    {
        $script:buildInfo = $null
    }

    function ThenBuildMetadataIs
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            $BuildNumber,
            [Parameter(Mandatory=$true)]
            $BuildID,
            [Parameter(Mandatory=$true)]
            $JobName,
            [Parameter(Mandatory=$true)]
            $BuildUri,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $GitUri,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $GitCommit,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $GitBranch
        )

        $buildInfo = $script:buildInfo

        It ('should set build number') {
            $buildInfo.BuildNumber | Should Be $BuildNumber
        }

        It ('should set build ID') {
            $buildInfo.BuildID | Should Be $BuildID
        }

        It ('should set job name') {
            $buildInfo.JobName | Should Be $JobName
        }

        It ('should set build URI') {
            $buildInfo.BuildUri | Should Be $BuildUri
        }

        It ('should set SCM URI') {
            $buildInfo.ScmUri | Should Be $GitUri
        }

        It ('should set SCM commit ID') {
            $buildInfo.ScmCommitID | Should Be $GitCommit
        }

        It ('should set SCM branch') {
            $buildInfo.ScmBranch | Should Be $GitBranch
        }
    }

    function WhenGettingBuildMetadata
    {
        $script:buildInfo = Get-WhiskeyBuildMetadata
    }

    Describe 'Get-WhiskeyBuildMetadata.when running under Jenkins' {
        Init
        GivenJenkinsEnvironment -BuildNumber '27' -BuildID 'jenkins_Fubar_27' -JobName 'Fubar' -BuildUri 'https://build.example.com' -GitUri 'https://git.example.com' -GitCommit 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb' -GitBranch 'origin/master'
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber '27' -BuildID 'jenkins_Fubar_27' -JobName 'Fubar' -BuildUri 'https://build.example.com' -GitUri 'https://git.example.com' -GitCommit 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb' -GitBranch 'origin/master'
    }

    Describe 'Get-WhiskeyBuildMetadata.when run by a developer' {
        Init
        GivenDeveloperEnvironment
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber '' -BuildID '' -JobName '' -BuildUri '' -GitUri '' -GitCommit '' -GitBranch ''
    }
}