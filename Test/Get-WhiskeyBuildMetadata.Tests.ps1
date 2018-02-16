
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
        Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path-eq 'env:TEAMCITY_BUILD_PROPERTIES_FILE' } -MockWith { return $false }
        GivenNotRunningUnderAppVeyor

    }

    function GivenAppVeyorEnvironment
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            $BuildNumber,
            [Parameter(Mandatory=$true)]
            $BuildID,
            [Parameter(Mandatory=$true)]
            $ProjectName,
            [Parameter(Mandatory=$true)]
            $ProjectSlug,
            [Parameter(Mandatory=$true)]
            $ScmProvider,
            [Parameter(Mandatory=$true)]
            $ScmRepoName,
            [Parameter(Mandatory=$true)]
            $ScmBranch,
            [Parameter(Mandatory=$true)]
            $ScmCommit,
            [Parameter(Mandatory=$true)]
            $AccountName,
            [Parameter(Mandatory=$true)]
            $BuildVersion
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
            $JobUri,
            [Parameter(Mandatory=$true)]
            $BuildUri,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $GitUri,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $GitCommit,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $GitBranch
        )

        GivenNotRunningUnderAppVeyor
        GivenEnvironmentVariable 'JENKINS_URL' 'https://jenkins.example.com'
        GivenEnvironmentVariable 'BUILD_NUMBER' $BuildNumber
        GivenEnvironmentVariable 'BUILD_TAG' $BuildID
        GivenEnvironmentVariable 'JOB_NAME' $JobName
        GivenEnvironmentVariable 'JOB_URL' $JobUri
        GivenEnvironmentVariable 'BUILD_URL' $BuildUri
        if( $PSCmdlet.ParameterSetName -eq 'WithGitScm' )
        {
            GivenEnvironmentVariable 'GIT_URL' $GitUri
            GivenEnvironmentVariable 'GIT_COMMIT' $GitCommit
            GivenEnvironmentVariable 'GIT_BRANCH' $GitBranch
        }
    }

    function GivenNotRunningUnderAppVeyor
    {
        Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path-eq 'env:APPVEYOR' } -MockWith { return $false }
    }

    function GivenTeamCityEnvironment
    {
        param(
            [Parameter(Mandatory=$true)]
            $BuildNumber,
            [Parameter(Mandatory=$true)]
            $VcsNumber,
            [Parameter(Mandatory=$true)]
            $ProjectName,
            [Parameter(Mandatory=$true)]
            $VcsBranch,
            [Parameter(Mandatory=$true)]
            $VcsUri,
            [Parameter(Mandatory=$true)]
            $ServerUri,
            [Parameter(Mandatory=$true)]
            $BuildTypeID,
            [Parameter(Mandatory=$true)]
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
            $JobUri,
            [Parameter(Mandatory=$true)]
            $BuildUri,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $ScmUri,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $ScmCommit,
            [Parameter(Mandatory=$true,ParameterSetName='WithGitScm')]
            $ScmBranch
        )

        $buildInfo = $script:buildInfo

        It ('should set build number') {
            $buildInfo.BuildNumber | Should -BeOfType $BuildNumber.GetType()
            $buildInfo.BuildNumber | Should -Be $BuildNumber
        }

        It ('should set build ID') {
            $buildInfo.BuildID | Should Be $BuildID
        }

        It ('should set job name') {
            $buildInfo.JobName | Should Be $JobName
        }

        It ('should set job URI') {
            $buildInfo.JobUri | Should Be $JobUri
        }

        It ('should set build URI') {
            $buildInfo.BuildUri | Should Be $BuildUri
        }

        It ('should set SCM URI') {
            $buildInfo.ScmUri | Should Be $ScmUri
        }

        It ('should set SCM commit ID') {
            $buildInfo.ScmCommitID | Should Be $ScmCommit
        }

        It ('should set SCM branch') {
            $buildInfo.ScmBranch | Should Be $ScmBranch
        }
    }

    function ThenBuildServerIs
    {
        param(
            $Name
        )

        $buildInfo = $script:buildInfo
        $scriptPropertyName = 'Is{0}' -f $Name

        It ('should be running by {0}' -f $Name) {
            $buildInfo.BuildServer | Should Be $Name
            $buildInfo.$scriptPropertyName | Should Be $true
            $buildInfo.IsDeveloper | Should Be $false
            $buildInfo.IsBuildServer | Should Be $true
        }
    }

    function ThenRunByDeveloper
    {
        $buildInfo = $script:buildInfo
        It ('should be running as developer') {
            $buildInfo.BuildServer | Should BeNullOrEmpty
            $buildInfo.IsDeveloper | Should Be $true
            $buildInfo.IsBuildServer | Should Be $false
        }
    }

    function WhenGettingBuildMetadata
    {
        $script:buildInfo = Get-WhiskeyBuildMetadata
    }

    Describe 'Get-WhiskeyBuildMetadata.when running under Jenkins' {
        Init
        GivenJenkinsEnvironment -BuildNumber '27' `
                                -BuildID 'jenkins_Fubar_27' `
                                -JobName 'Fubar' `
                                -BuildUri 'https://build.example.com' `
                                -GitUri 'https://git.example.com' `
                                -GitCommit 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb' `
                                -GitBranch 'origin/master' `
                                -JobUri 'https://job.example.com'
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber '27' `
                            -BuildID 'jenkins_Fubar_27' `
                            -JobName 'Fubar' `
                            -BuildUri 'https://build.example.com' `
                            -ScmUri 'https://git.example.com' `
                            -ScmCommit 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb' `
                            -ScmBranch 'master' `
                            -JobUri 'https://job.example.com' 
        ThenBuildServerIs 'Jenkins'
    }

    Describe 'Get-WhiskeyBuildMetadata.when run by a developer' {
        Init
        GivenDeveloperEnvironment
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber 0 -BuildID '' -JobName '' -BuildUri '' -ScmUri '' -ScmCommit '' -ScmBranch '' -JobUri ''
        ThenRunByDeveloper
    }

    Describe 'Get-WhiskeyBuildMetadata.when running under AppVeyor' {
        Init
        GivenAppVeyorEnvironment -BuildNumber '112' `
                                 -BuildID '10187821' `
                                 -ProjectName 'WhiskeyName' `
                                 -ProjectSlug 'whiskeyslug' `
                                 -ScmProvider 'gitHub' `
                                 -ScmRepoName 'webmd-health-services/Whiskey' `
                                 -ScmBranch 'master' `
                                 -ScmCommit 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb' `
                                 -AccountName 'whs' `
                                 -BuildVersion '1.1.1+112' 
        WhenGettingBuildMetadata
        ThenBuildMetadataIs -BuildNumber '112' `
                            -BuildID '10187821' `
                            -JobName 'WhiskeyName' `
                            -BuildUri 'https://ci.appveyor.com/project/whs/whiskeyslug/build/1.1.1+112' `
                            -ScmUri 'https://github.com/webmd-health-services/Whiskey.git' `
                            -ScmCommit 'deadbeedeadbeedeadbeedeadbeedeadbeedeadb' `
                            -ScmBranch 'master' `
                            -JobUri 'https://ci.appveyor.com/project/whs/whiskeyslug' 
        ThenBuildServerIs 'AppVeyor'
    }

    Describe 'Get-WhiskeyBuildMetadata.when running under TeamCity' {
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
        ThenBuildServerIs 'TeamCity'
    }

}