
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:buildInfo = $null
    $script:envVars = @{}

    function GivenEnv
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [hashtable] $Variables
        )

        foreach ($envVarName in $Variables.Keys)
        {
            GivenEnvironmentVariable -Name $envVarName -Value $Variables[$envVarName]
        }
    }

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

        $buildPropertiesPath = Join-Path -Path $TestDrive -ChildPath 'teamcity.build890238409.properties'
        $configPropertiesPath = Join-Path -Path $TestDrive -ChildPath 'teamcity.config890238409.properties'

        # teamcity.configuration.properties.fileJoin-Path -Path $TestDrive.FullName -ChildPath 'teamcity.build.properties.file'
        GivenEnvironmentVariable 'TEAMCITY_BUILD_PROPERTIES_FILE' $buildPropertiesPath
        GivenProperty $buildPropertiesPath 'teamcity.build.id' $BuildID
        GivenProperty $buildPropertiesPath 'teamcity.configuration.properties.file' $configPropertiesPath
        GivenProperty $buildPropertiesPath 'teamcity.buildType.id' $BuildTypeID

        GivenProperty $configPropertiesPath 'teamcity.build.branch' $VcsBranch
        GivenProperty $configPropertiesPath 'vcsroot.url' $VcsUri
        GivenProperty $configPropertiesPath 'teamcity.serverUrl' $ServerUri
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
            $ScmBranch
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
        $envVars = $script:envVars
        Mock -CommandName 'Get-Item' `
             -ModuleName 'Whiskey' `
             -ParameterFilter { $Path -like 'env:*' } `
             -MockWith {
                $envVarName = $Path.Substring(4)
                if (-not $envVars.ContainsKey($envVarName))
                {
                    Write-Error -Message "Cannot find path ""${Path}"" because it does not exist." `
                                -ErrorAction $PesterBoundParameters['ErrorAction']
                    return
                }

                return [pscustomobject]@{ Value = $envVars[$envVarName] }
             }

        Mock -CommandName 'Test-Path' `
             -ModuleName 'Whiskey' `
             -ParameterFilter { $Path -like 'env:*' } `
             -MockWith {
                $envVarName = $Path.Substring(4)
                return $envVars.ContainsKey($envVarName)
            }

        $script:buildInfo = Invoke-WhiskeyPrivateCommand -Name 'Get-WhiskeyBuildMetadata'
    }
}


Describe 'Get-WhiskeyBuildMetadata' {
    BeforeEach {
        $script:buildInfo = $null
        $script:envVars = @{}
        $Global:Error.Clear()
    }

    Context 'running under Jenkins' {
        BeforeEach {
            GivenEnvironmentVariable 'JENKINS_URL' 'https://jenkins.example.com'
        }

        It 'sets build metadata' {
            GivenEnv @{
                'BUILD_NUMBER' = '27'
                'BUILD_TAG' = 'jenkins_Fubar_27'
                'JOB_NAME' = 'Fubar'
                'JOB_URL' = 'https://job.example.com'
                'BUILD_URL' = 'https://build.example.com'
                'GIT_URL' = 'https://git.example.com'
                'GIT_COMMIT' = 'commitid'
                'GIT_BRANCH' = 'origin/master'
            }
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

        It 'sets pull request build metadata' {
            GivenEnv @{
                'BUILD_NUMBER' = '28'
                'BUILD_TAG' = 'jenkins_Fubar_28'
                'JOB_NAME' = 'Fubar'
                'JOB_URL' = 'https://job.example.com'
                'BUILD_URL' = 'https://build.example.com'
                'GIT_URL' = 'https://git.example.com'
                'GIT_COMMIT' = 'new_commit_id'
                'GIT_BRANCH' = 'PR-47'
                'CHANGE_BRANCH' = 'origin/feature/pr'
            }
            WhenGettingBuildMetadata
            ThenBuildMetadataIs -BuildNumber '28' `
                                -BuildID 'jenkins_Fubar_28' `
                                -JobName 'Fubar' `
                                -BuildUri 'https://build.example.com' `
                                -ScmUri 'https://git.example.com' `
                                -ScmCommit 'new_commit_id' `
                                -ScmBranch 'feature/pr' `
                                -JobUri 'https://job.example.com'
        }
    }

    Context 'developer' {
        It 'does not set most build metadata' {
            GivenDeveloperEnvironment
            WhenGettingBuildMetadata
            ThenBuildMetadataIs -BuildNumber 0 `
                                -BuildID '' `
                                -JobName '' `
                                -BuildUri $null `
                                -ScmUri $null `
                                -ScmCommit '' `
                                -ScmBranch '' `
                                -JobUri $null
            ThenRunByDeveloper
        }
    }

    Context 'AppVeyor' {
        BeforeEach {
            GivenEnvironmentVariable 'APPVEYOR' 'True'
        }

        It 'sets build metadata' {
            GivenEnv @{
                'APPVEYOR_BUILD_NUMBER' = '112'
                'APPVEYOR_BUILD_ID' = '10187821'
                'APPVEYOR_PROJECT_NAME' = 'WhiskeyName'
                'APPVEYOR_PROJECT_SLUG' = 'whiskeyslug'
                'APPVEYOR_REPO_PROVIDER' = 'gitHub'
                'APPVEYOR_REPO_NAME' = 'webmd-health-services/Whiskey'
                'APPVEYOR_REPO_BRANCH' = 'master'
                'APPVEYOR_REPO_COMMIT' = 'commit_id'
                'APPVEYOR_ACCOUNT_NAME' = 'whs'
                'APPVEYOR_BUILD_VERSION' = '1.1.1+112'
            }
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

        It 'sets pull request build metadata' {
            GivenEnv @{
                'APPVEYOR_BUILD_NUMBER' = '113'
                'APPVEYOR_BUILD_ID' = '10187822'
                'APPVEYOR_PROJECT_NAME' = 'WhiskeyName'
                'APPVEYOR_PROJECT_SLUG' = 'whiskeyslug'
                'APPVEYOR_REPO_PROVIDER' = 'gitHub'
                'APPVEYOR_REPO_NAME' = 'webmd-health-services/Whiskey'
                'APPVEYOR_REPO_BRANCH' = 'master'
                'APPVEYOR_REPO_COMMIT' = 'new_commit_id'
                'APPVEYOR_ACCOUNT_NAME' = 'whs'
                'APPVEYOR_BUILD_VERSION' = '1.1.1+112'
                'APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH' = 'feature/branch'
                'APPVEYOR_PULL_REQUEST_HEAD_COMMIT' = 'branch_commit_id'
            }
            WhenGettingBuildMetadata
            ThenBuildMetadataIs -BuildNumber '113' `
                                -BuildID '10187822' `
                                -JobName 'WhiskeyName' `
                                -BuildUri 'https://ci.appveyor.com/project/whs/whiskeyslug/build/1.1.1+112' `
                                -ScmUri 'https://github.com/webmd-health-services/Whiskey.git' `
                                -ScmCommit 'branch_commit_id' `
                                -ScmBranch 'feature/branch' `
                                -JobUri 'https://ci.appveyor.com/project/whs/whiskeyslug'
            ThenBuildServerIs ([Whiskey.BuildServer]::AppVeyor)
        }

        It 'ignores environment variables that exist with no value' {
            GivenEnv @{
                'APPVEYOR_BUILD_NUMBER' = '113'
                'APPVEYOR_BUILD_ID' = '10187822'
                'APPVEYOR_PROJECT_NAME' = 'WhiskeyName'
                'APPVEYOR_PROJECT_SLUG' = 'whiskeyslug'
                'APPVEYOR_REPO_PROVIDER' = 'gitHub'
                'APPVEYOR_REPO_NAME' = 'webmd-health-services/Whiskey'
                'APPVEYOR_REPO_BRANCH' = 'master'
                'APPVEYOR_REPO_COMMIT' = 'new_commit_id'
                'APPVEYOR_ACCOUNT_NAME' = 'whs'
                'APPVEYOR_BUILD_VERSION' = '1.1.1+112'
                'APPVEYOR_PULL_REQUEST_HEAD_REPO_BRANCH' = ''
                'APPVEYOR_PULL_REQUEST_HEAD_COMMIT' = ''
            }
            WhenGettingBuildMetadata
            ThenBuildMetadataIs -BuildNumber '113' `
                                -BuildID '10187822' `
                                -JobName 'WhiskeyName' `
                                -BuildUri 'https://ci.appveyor.com/project/whs/whiskeyslug/build/1.1.1+112' `
                                -ScmUri 'https://github.com/webmd-health-services/Whiskey.git' `
                                -ScmCommit 'new_commit_id' `
                                -ScmBranch 'master' `
                                -JobUri 'https://ci.appveyor.com/project/whs/whiskeyslug'
            ThenBuildServerIs ([Whiskey.BuildServer]::AppVeyor)
        }
    }

    Context 'TeamCity' {
        It 'sets build metadata' {
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
}