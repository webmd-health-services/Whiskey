
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$buildInfo = $null
$script:envVars = @{}

function GivenEnvironmentVariable
{
    param(
        $Name,
        $Value
    )

    $script:envVars[$Name] = $Value
}

function GivenDeveloperEnvironment
{
    param(
    )

    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path-eq 'env:JENKINS_URL' } -MockWith { return $false }
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path-eq 'env:TEAMCITY_BUILD_PROPERTIES_FILE' } -MockWith { return $false }
    GivenNotRunningUnderAppVeyor

}

function GivenAppVeyorEnvironment
{
    [CmdletBinding(DefaultParameterSetName='NotAPR')]
    param(
        [Parameter(Mandatory)]
        [int] $BuildNumber,

        [Parameter(Mandatory)]
        $BuildID,

        [Parameter(Mandatory)]
        $ProjectName,

        [Parameter(Mandatory)]
        $ProjectSlug,

        [Parameter(Mandatory)]
        $ScmProvider,

        [Parameter(Mandatory)]
        $ScmRepoName,
        [Parameter(Mandatory)]
        $ScmBranch,

        [Parameter(Mandatory)]
        $ScmCommit,

        [Parameter(Mandatory)]
        $AccountName,

        [Parameter(Mandatory)]
        $BuildVersion,

        [Parameter(Mandatory, ParameterSetName='ForPR')]
        [String] $ScmSourceBranch,

        [Parameter(Mandatory, ParameterSetName='ForPR')]
        [String] $ScmSourceCommitID
    )

    GivenEnvironmentVariable 'APPVEYOR' 'True'
    GivenEnvironmentVariable 'APPVEYOR_BUILD_NUMBER' $BuildNumber
    GivenEnvironmentVariable 'APPVEYOR_BUILD_ID' $BuildID
    GivenEnvironmentVariable 'APPVEYOR_PROJECT_NAME' $ProjectName
    GivenEnvironmentVariable 'APPVEYOR_PROJECT_SLUG' $ProjectSlug
    GivenEnvironmentVariable 'APPVEYOR_REPO_PROVIDER' $ScmProvider
    GivenEnvironmentVariable 'APPVEYOR_REPO_NAME' $ScmRepoName
    GivenEnvironmentVariable 'APPVEYOR_REPO_BRANCH' $ScmBranch
    GivenEnvironmentVariable 'APPVEYOR_REPO_COMMIT' $ScmCommit
    GivenEnvironmentVariable 'APPVEYOR_ACCOUNT_NAME' $AccountName
    GivenEnvironmentVariable 'APPVEYOR_BUILD_VERSION' $BuildVersion

    if( $PSCmdlet.ParameterSetName -eq 'ForPR' )
    {
        GivenEnvironmentVariable 'APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH' $ScmSourceBranch
        GivenEnvironmentVariable 'APPVEYOR_PULL_REQUEST_HEAD_COMMIT' $ScmSourceCommitID
    }
}

function GivenJenkinsEnvironment
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $BuildNumber,

        [Parameter(Mandatory)]
        $BuildID,

        [Parameter(Mandatory)]
        $JobName,

        [Parameter(Mandatory)]
        $JobUri,

        [Parameter(Mandatory)]
        $BuildUri,

        [Parameter(Mandatory, ParameterSetName='WithGitScmForPR')]
        [Parameter(Mandatory, ParameterSetName='WithGitScm')]
        $GitUri,

        [Parameter(Mandatory, ParameterSetName='WithGitScmForPR')]
        [Parameter(Mandatory, ParameterSetName='WithGitScm')]
        $GitCommit,

        [Parameter(Mandatory, ParameterSetName='WithGitScmForPR')]
        [Parameter(Mandatory, ParameterSetName='WithGitScm')]
        $GitBranch,

        [Parameter(Mandatory, ParameterSetName='WithGitScmForPR')]
        $GitSourceBranch
    )

    GivenNotRunningUnderAppVeyor
    GivenEnvironmentVariable 'JENKINS_URL' 'https://jenkins.example.com'
    GivenEnvironmentVariable 'BUILD_NUMBER' $BuildNumber
    GivenEnvironmentVariable 'BUILD_TAG' $BuildID
    GivenEnvironmentVariable 'JOB_NAME' $JobName
    GivenEnvironmentVariable 'JOB_URL' $JobUri
    GivenEnvironmentVariable 'BUILD_URL' $BuildUri
    if( $PSCmdlet.ParameterSetName -like 'WithGitScm*' )
    {
        GivenEnvironmentVariable 'GIT_URL' $GitUri
        GivenEnvironmentVariable 'GIT_COMMIT' $GitCommit
        GivenEnvironmentVariable 'GIT_BRANCH' $GitBranch

        if( $PSCmdlet.ParameterSetName -eq 'WithGitScmForPR' )
        {
            GivenEnvironmentVariable 'CHANGE_BRANCH' $GitSourceBranch
        }
    }
}

function GivenNotRunningUnderAppVeyor
{
    Mock -CommandName 'Test-Path' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $Path-eq 'env:APPVEYOR' } `
         -MockWith { return $false }
}

function GivenTeamCityEnvironment
{
    param(
        [Parameter(Mandatory)]
        [int]$BuildNumber,
        [Parameter(Mandatory)]
        $VcsNumber,
        [Parameter(Mandatory)]
        $ProjectName,
        [Parameter(Mandatory)]
        $VcsBranch,
        [Parameter(Mandatory)]
        $VcsUri,
        [Parameter(Mandatory)]
        $ServerUri,
        [Parameter(Mandatory)]
        $BuildTypeID,
        [Parameter(Mandatory)]
        $BuildID
    )

    GivenNotRunningUnderAppVeyor
    GivenEnvironmentVariable 'BUILD_NUMBER' $BuildNumber
    GivenEnvironmentVariable 'BUILD_VCS_NUMBER' $VcsNumber
    GivenEnvironmentVariable 'TEAMCITY_PROJECT_NAME' $ProjectName

    function GivenProperty
    {
        param(
            $Path,
            $Name,
            $Value
        )

        $Value = $Value -replace '([:\\])','\$1'
        ('{0}={1}' -f $Name,$Value) | Add-Content -Path $Path
    }

    $buildPropertiesPath = Join-Path -Path $TestDrive.FullName -ChildPath 'teamcity.build890238409.properties'
    $configPropertiesPath = Join-Path -Path $TestDrive.FullName -ChildPath 'teamcity.config890238409.properties'

    # teamcity.configuration.properties.fileJoin-Path -Path $TestDrive.FullName -ChildPath 'teamcity.build.properties.file'
    GivenEnvironmentVariable 'TEAMCITY_BUILD_PROPERTIES_FILE' $buildPropertiesPath
    GivenProperty $buildPropertiesPath 'teamcity.build.id' $BuildID
    GivenProperty $buildPropertiesPath 'teamcity.configuration.properties.file' $configPropertiesPath
    GivenProperty $buildPropertiesPath 'teamcity.buildType.id' $BuildTypeID

    GivenProperty $configPropertiesPath 'teamcity.build.branch' $VcsBranch
    GivenProperty $configPropertiesPath 'vcsroot.url' $VcsUri
    GivenProperty $configPropertiesPath 'teamcity.serverUrl' $ServerUri
}

function Init
{
    $script:buildInfo = $null
    $script:envVars = @{}
    $Global:Error.Clear()
}

function ThenBuildMetadataIs
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $BuildNumber,

        [Parameter(Mandatory)]
        $BuildID,

        [Parameter(Mandatory)]
        $JobName,

        [Parameter(Mandatory)]
        [AllowNull()]
        [Uri] $JobUri,

        [Parameter(Mandatory)]
        [AllowNull()]
        [Uri] $BuildUri,

        [Parameter(Mandatory, ParameterSetName='WithGitScm')]
        [AllowNull()]
        [Uri]$ScmUri,

        [Parameter(Mandatory, ParameterSetName='WithGitScm')]
        $ScmCommit,

        [Parameter(Mandatory, ParameterSetName='WithGitScm')]
        $ScmBranch,

        [switch] $IsPullRequest,

        [String] $ScmSourceBranch,

        [String] $ScmSourceCommitID
    )

    $buildInfo = $script:buildInfo

    $buildInfo.BuildNumber | Should -BeOfType $BuildNumber.GetType()
    $buildInfo.BuildNumber | Should -Be $BuildNumber
    $buildInfo.BuildID | Should -Be $BuildID
    $buildInfo.JobName | Should -Be $JobName
    $buildInfo.JobUri | Should -Be $JobUri
    $buildInfo.BuildUri | Should -Be $BuildUri
    $buildInfo.ScmUri | Should -Be $ScmUri
    $buildInfo.ScmCommitID | Should -Be $ScmCommit
    $buildInfo.ScmBranch | Should -Be $ScmBranch
    $buildInfo.IsPullRequest | Should -Be $IsPullRequest.IsPresent
    $buildInfo.ScmSourceBranch | Should -Be $ScmSourceBranch
    $buildInfo.ScmSourceCommitID | Should -Be $ScmSourceCommitID
}

function ThenBuildServerIs
{
    param(
        $Name
    )

    $buildInfo = $script:buildInfo
    $scriptPropertyName = 'Is{0}' -f $Name

    $buildInfo.BuildServer | Should -Be $Name
    $buildInfo.$scriptPropertyName | Should -Be $true
    $buildInfo.IsDeveloper | Should -Be $false
    $buildInfo.IsBuildServer | Should -Be $true
}

function ThenRunByDeveloper
{
    $buildInfo = $script:buildInfo
    $buildInfo.BuildServer | Should -Be ([Whiskey.BuildServer]::None)
    $buildInfo.IsDeveloper | Should -Be $true
    $buildInfo.IsBuildServer | Should -Be $false
}

function WhenGettingBuildMetadata
{
    # Make sure Get-Item fails when an environment variable fails so we make sure we handle it.
    Mock -CommandName 'Get-Item' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $Path -like 'env:*' } `
         -MockWith { Write-Error -Message "Cannot find path '$($Path)' because it does not exist." `
         -ErrorAction $ErrorActionPreference }

    foreach( $envVarName in $script:envVars.Keys )
    {
        $value = $script:envVars[$envVarName]
        $filter = [scriptblock]::Create(("`$Path -eq 'env:$($envVarName)'"))
        Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter $filter -MockWith { return $true }
        Mock -CommandName 'Get-Item' `
                -ModuleName 'Whiskey' `
                -ParameterFilter $filter `
                -MockWith { return [pscustomobject]@{ Value = $value }}.GetNewClosure()
    }


    $script:buildInfo = Invoke-WhiskeyPrivateCommand -Name 'Get-WhiskeyBuildMetadata'
}

Describe 'Get-WhiskeyBuildMetadata.when running under Jenkins' {
    It 'should set build metadata' {
        Init
        GivenJenkinsEnvironment -BuildNumber '27' `
                                -BuildID 'jenkins_Fubar_27' `
                                -JobName 'Fubar' `
                                -BuildUri 'https://build.example.com' `
                                -GitUri 'https://git.example.com' `
                                -GitCommit 'commitid' `
                                -GitBranch 'origin/master' `
                                -JobUri 'https://job.example.com'
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber '27' `
                            -BuildID 'jenkins_Fubar_27' `
                            -JobName 'Fubar' `
                            -BuildUri 'https://build.example.com' `
                            -ScmUri 'https://git.example.com' `
                            -ScmCommit 'commitid' `
                            -ScmBranch 'master' `
                            -JobUri 'https://job.example.com' 
        ThenBuildServerIs ([Whiskey.BuildServer]::Jenkins)
    }
}

Describe 'Get-WhiskeyBuildMetadata.when running under Jenkins pull request' {
    It 'should not write an error' {
        Init
        GivenJenkinsEnvironment -BuildNumber '28' `
                                -BuildID 'jenkins_Fubar_28' `
                                -JobName 'Fubar' `
                                -BuildUri 'https://build.example.com' `
                                -GitUri 'https://git.example.com' `
                                -GitCommit 'new_commit_id' `
                                -GitBranch 'origin/master' `
                                -JobUri 'https://job.example.com' `
                                -GitSourceBranch 'origin/feature/pr'
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber '28' `
                            -BuildID 'jenkins_Fubar_28' `
                            -JobName 'Fubar' `
                            -BuildUri 'https://build.example.com' `
                            -ScmUri 'https://git.example.com' `
                            -ScmCommit 'new_commit_id' `
                            -ScmBranch 'master' `
                            -JobUri 'https://job.example.com' `
                            -IsPullRequest `
                            -ScmSourceBranch 'feature/pr' `
                            -ScmSourceCommit 'new_commit_id'
    }
}

Describe 'Get-WhiskeyBuildMetadata.when run by a developer' {
    It 'should not set most build metadata' {
        Init
        GivenDeveloperEnvironment
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber 0 -BuildID '' -JobName '' -BuildUri $null -ScmUri $null -ScmCommit '' -ScmBranch '' -JobUri $null
        ThenRunByDeveloper
    }
}

Describe 'Get-WhiskeyBuildMetadata.when running under AppVeyor' {
    It 'should set build metadata' {
        Init
        GivenAppVeyorEnvironment -BuildNumber '112' `
                                 -BuildID '10187821' `
                                 -ProjectName 'WhiskeyName' `
                                 -ProjectSlug 'whiskeyslug' `
                                 -ScmProvider 'gitHub' `
                                 -ScmRepoName 'webmd-health-services/Whiskey' `
                                 -ScmBranch 'master' `
                                 -ScmCommit 'commit_id' `
                                 -AccountName 'whs' `
                                 -BuildVersion '1.1.1+112' 
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber '112' `
                            -BuildID '10187821' `
                            -JobName 'WhiskeyName' `
                            -BuildUri 'https://ci.appveyor.com/project/whs/whiskeyslug/build/1.1.1+112' `
                            -ScmUri 'https://github.com/webmd-health-services/Whiskey.git' `
                            -ScmCommit 'commit_id' `
                            -ScmBranch 'master' `
                            -JobUri 'https://ci.appveyor.com/project/whs/whiskeyslug' 
        ThenBuildServerIs ([Whiskey.BuildServer]::AppVeyor)
    }
}

Describe 'Get-WhiskeyBuildMetadata.when running under AppVeyor pull request' {
    It 'should set build metadata' {
        Init
        GivenAppVeyorEnvironment -BuildNumber '113' `
                                 -BuildID '10187822' `
                                 -ProjectName 'WhiskeyName' `
                                 -ProjectSlug 'whiskeyslug' `
                                 -ScmProvider 'gitHub' `
                                 -ScmRepoName 'webmd-health-services/Whiskey' `
                                 -ScmBranch 'master' `
                                 -ScmCommit 'new_commit_id' `
                                 -AccountName 'whs' `
                                 -BuildVersion '1.1.1+112' `
                                 -ScmSourceBranch 'feature/pr' `
                                 -ScmSourceCommitID 'source_branch_commit_id'
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber '113' `
                            -BuildID '10187822' `
                            -JobName 'WhiskeyName' `
                            -BuildUri 'https://ci.appveyor.com/project/whs/whiskeyslug/build/1.1.1+112' `
                            -ScmUri 'https://github.com/webmd-health-services/Whiskey.git' `
                            -ScmCommit 'new_commit_id' `
                            -ScmBranch 'master' `
                            -JobUri 'https://ci.appveyor.com/project/whs/whiskeyslug' `
                            -ScmSourceBranch 'feature/pr' `
                            -ScmSourceCommitID 'source_branch_commit_id' `
                            -IsPullRequest
        ThenBuildServerIs ([Whiskey.BuildServer]::AppVeyor)
    }
}

Describe 'Get-WhiskeyBuildMetadata.when running under TeamCity' {
    It 'should set build metadata' {
        Init
        GivenTeamCityEnvironment -BuildNumber '13' `
                                 -VcsNumber 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb' `
                                 -ProjectName 'TeamCityWhiskeyAdapter' `
                                 -VcsBranch 'refs/heads/master' `
                                 -VcsUri 'https://git.example.com' `
                                 -ServerUri 'https://teamcity.example.com' `
                                 -BuildTypeID 'TeamCityWhiskeyAdapter_Build' `
                                 -BuildID '30' 
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber '13' `
                            -BuildID '30' `
                            -JobName 'TeamCityWhiskeyAdapter_Build' `
                            -JobUri 'https://teamcity.example.com/viewType.html?buildTypeId=TeamCityWhiskeyAdapter_Build' `
                            -BuildUri 'https://teamcity.example.com/viewLog.html?buildId=30&buildTypeId=TeamCityWhiskeyAdapter_Build' `
                            -ScmUri 'https://git.example.com' `
                            -ScmCommit 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb' `
                            -ScmBranch 'master' 
        ThenBuildServerIs ([Whiskey.BuildServer]::TeamCity)
    }
}
