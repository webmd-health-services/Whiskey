
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

InModuleScope -ModuleName 'Whiskey' -ScriptBlock {

    $progetUri = [uri]'https://proget.example.com/'
    $configurationPath = $null
    $context = $null
    $path = "bad"
    $runMode = $null

    function Assert-Context
    {
        param(
            [Whiskey.Context]
            $Context,

            $Environment,

            [Switch]
            $ByBuildServer,

            $DownloadRoot
        )

        It 'should set environment' {
            $Context.Environment | Should -Be $Environment
        }

        It 'should set configuration path' {
            $Context.ConfigurationPath | Should Be (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
        }

        It 'should set build root' {
            $Context.BuildRoot | Should Be ($Context.ConfigurationPath | Split-Path)
        }

        It 'should set output directory' {
            $Context.OutputDirectory | Should Be (Join-Path -Path $Context.BuildRoot -ChildPath '.output')
        }

        It 'should create output directory' {
            $Context.OutputDirectory | Should Exist
        }

        It 'should have TaskName property' {
            $Context.TaskName | Should BeNullOrEmpty
        }

        It 'should have TaskIndex property' {
            $Context.TaskIndex | Should Be -1
        }

        It 'should have PipelineName property' {
            $Context.PipelineName | Should -Be ''
        }

        It 'should have TaskDefaults property' {
            $Context.TaskDefaults | Should -BeOfType ([Collections.IDictionary])
        }

        $expectedVersion = '{0:yyyy.Mdd}.{1}' -f (Get-Date),$Context.BuildMetadata.BuildNumber
        ThenVersionIs $expectedVersion
        ThenSemVer2NoBuildMetadataIs $expectedVersion
        ThenSemVer1Is $expectedVersion
        if( $ByBuildServer )
        {
            $expectedVersion = '{0}+{1}.{2}.{3}' -f $expectedVersion,$Context.BuildMetadata.BuildNumber,($Context.BuildMetadata.ScmBranch -replace '[^A-Za-z0-9-]','-'),$Context.BuildMetadata.ScmCommitID.Substring(0,7)
        }
        ThenSemVer2Is $expectedVersion
        It 'should set raw configuration hashtable' {
            $Context.Configuration | Should -BeOfType ([Collections.IDictionary])
            $Context.Configuration.ContainsKey('SomProperty') | Should Be $true
            $Context.Configuration['SomProperty'] | Should Be 'SomeValue'
        }

        if( -not $DownloadRoot )
        {
            $DownloadRoot = $Context.BuildRoot
        }

        It 'should set download root' {
            $Context.DownloadRoot.FullName | Should -Be $DownloadRoot.FullName
        }

        It 'should set build server flag' {
            $Context.ByBuildServer | Should Be $ByBuildServer
            $Context.ByDeveloper | Should Be (-not $ByBuildServer)
        }

        It 'ApiKeys property should exit' {
            $Context | Get-Member -Name 'ApiKeys' | Should -Not -BeNullOrEmpty
        }

        It 'ApiKeys property should be a hashtable' {
            $Context.ApiKeys | Should -BeOfType ([Collections.IDictionary])
        }

        It ('should have ShouldClean method') {
            $Context | Get-Member -Name 'ShouldClean' | Should -BE $true
            $Context.ShouldClean | Should -Be $false
        }

        It ('should have ShouldInitialize method') {
            $Context | Get-Member -Name 'ShouldInitialize' | Should -BE $true
            $Context.ShouldInitialize | Should -Be $false
        }

        It ('should have BuildMetadata property') {
            $Context | Get-Member -Name 'BuildMetadata' | Should -Not -BeNullOrEmpty
            $Context.BuildMetadata | Should -Not -BeNullOrEmpty
        }

        It ('should have Variables property') {
            $Context | Get-Member -Name 'Variables' | Should -Not -BeNullOrEmpty
            $Context.Variables | Should -BeOfType ([Collections.IDictionary])
        }
    }

    function GivenConfiguration
    {
        param(
            [Switch]
            $ForBuildServer,

            [String]
            $OnBranch = 'develop',

            [string[]]
            $PublishingOn,

            [Parameter(Position=0)]
            [Collections.IDictionary]
            $Configuration,

            $BuildNumber = '1'
        )

        if( -not $Configuration )
        {
            $Configuration = @{ }
        }

        $Configuration['SomProperty'] = 'SomeValue'

        if( $PublishingOn )
        {
            $Configuration['PublishOn'] = $PublishingOn
        }
    
        $buildInfo = New-WhiskeyBuildMetadataObject
        $buildInfo.BuildNumber = $BuildNumber

        Mock -CommandName 'Get-WhiskeyBuildMetadata' -ModuleName 'Whiskey' -MockWith { return $buildInfo }.GetNewClosure()
        if( $ForBuildServer )
        {
            $buildInfo.ScmBranch = $OnBranch
            $buildInfo.ScmCommitID = 'deadbeedeadbee'
            $buildInfo.BuildServer = [Whiskey.BuildServer]::Jenkins
        }

        $yaml = $Configuration | ConvertTo-Yaml
        GivenWhiskeyYml $yaml
    }

    function GivenConfigurationFileDoesNotExist
    {
        $script:configurationPath = 'I\do\not\exist'
    }

    function GivenRunMode
    {
        param(
            $RunMode
        )

        $script:runMode = $RunMode
    }

    function GivenWhiskeyYml
    {
        param(
            $Yaml
        )

        $script:configurationPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml'
        $Yaml | Set-Content -Path $script:configurationPath
    }

    function Init
    {
        $script:runMode = $null
        $script:configurationPath = ''
        $script:context = $null
        $script:path = "bad"
    }

    function ThenSemVer1Is
    {
        param(
            [SemVersion.SemanticVersion]
            $SemanticVersion
        )

        It ('should set semantic version v1 to {0}' -f $SemanticVersion) {
            $script:context.Version.SemVer1.ToString() | Should Be $SemanticVersion.ToString()
            $script:context.Version.SemVer1 | Should BeOfType ([SemVersion.SemanticVersion])
        }
    }

    function ThenSemVer2Is
    {
        param(
            [SemVersion.SemanticVersion]
            $SemanticVersion
        )
        It ('should set semantic version v2 to {0}' -f $SemanticVersion) {
            $script:context.Version.SemVer2.ToString() | Should Be $SemanticVersion.ToString()
            $script:context.Version.SemVer2 | Should BeOfType ([SemVersion.SemanticVersion])
        }
    }

    function ThenSemVer2NoBuildMetadataIs
    {
        param(
            [SemVersion.SemanticVersion]
            $SemanticVersion
        )

        It ('should set semantic version v2 with no build metadata to {0}' -f $SemanticVersion) {
            $script:Context.Version.SemVer2NoBuildMetadata.ToString() | Should Be $SemanticVersion.ToString()
            $script:Context.Version.SemVer2NoBuildMetadata | Should BeOfType ([SemVersion.SemanticVersion])
        }

    }

    function ThenVersionIs
    {
        param(
            [Version]
            $ExpectedVersion
        )

        It ('should set version to {0}' -f $ExpectedVersion) {
            $script:Context.Version.Version.ToString() | Should Be $expectedVersion.ToString()
            $script:Context.Version.Version | Should BeOfType ([version])
        }
    }

    function WhenCreatingContext
    {
        [CmdletBinding()]
        param(
            [string]
            $Environment = 'developer',

            [string]
            $ThenCreationFailsWithErrorMessage,

            $WithDownloadRoot,

            [Whiskey.RunBy]
            $RunBy
        )

        process
        {
            $optionalArgs = @{ }
            if( $WithDownloadRoot )
            {
                $optionalArgs['DownloadRoot'] = $WithDownloadRoot
            }

            $Global:Error.Clear()
            $threwException = $false
            try
            {
                $script:context = New-WhiskeyContext -Environment $Environment -ConfigurationPath $script:ConfigurationPath @optionalArgs
                if( $RunBy )
                {
                    $script:context.RunBy = $RunBy
                }

                if( $script:runMode )
                {
                    $script:context.RunMode = $script:runMode
                }
                if(Test-Path $Script:path)
                {
                    remove-item $Script:path
                }
            }
            catch
            {
                $threwException = $true
                $_ | Write-Error 
            }

            if( $ThenCreationFailsWithErrorMessage )
            {
                It 'should throw an exception' {
                    $threwException | Should Be $true
                }

                It 'should write an error' {
                    $Global:Error | Should Match $ThenCreationFailsWithErrorMessage
                }
            }
            else
            {
                It 'should not throw an exception' {
                    $threwException | Should Be $false
                }

                It 'should not write an error' {
                    $Global:Error | Should BeNullOrEmpty
                }
            }
        }
    }

    function ThenBuildServerContextCreated
    {
        [CmdletBinding()]
        param(
            [string]
            $Environment = 'developer',

            $WithDownloadRoot
        )

        begin
        {
            $iWasCalled = $false
        }

        process
        {
            $optionalArgs = @{}

            $iWasCalled = $true
            $context = $script:Context
            Assert-Context -Environment $Environment -Context $context -ByBuildServer -DownloadRoot $WithDownloadRoot @optionalArgs
        }

        end
        {
            It 'should return a context' {
                $iWasCalled | Should Be $true
            }
        }
    }

    function ThenDeveloperContextCreated
    {
        [CmdletBinding()]
        param(
            [string]
            $Environment = 'developer'
        )

        begin
        {
            $iWasCalled = $false
        }

        process
        {
            $iWasCalled = $true

            Assert-Context -Environment $Environment -Context $script:Context
        }

        end
        {
            It 'should return a context' {
                $iWasCalled | Should Be $true
            }
        }
    }

    function ThenPublishes
    {
        It 'should publish' {
            $script:Context.Publish | Should Be $True
        }
    }

    function ThenDoesNotPublish
    {
        It 'should not publish' {
            $script:Context.Publish | Should Be $False
        }
    }

    function ThenShouldCleanIs
    {
        param(
            $ExpectedValue
        )

        It ('ShouldClean should be ''{0}''' -f $ExpectedValue) {
            $script:context.ShouldClean | Should -Be $ExpectedValue
        }
    }

    function ThenShouldInitializeIs
    {
        param(
            $ExpectedValue
        )

        It ('ShouldInitialize should be ''{0}''' -f $ExpectedValue) {
            $script:context.ShouldInitialize | Should -Be $ExpectedValue
        }
    }

    function ThenVersionMatches
    {
        param(
            [string]
            $Version
        )

        It ('should set version to {0}' -f $Version) {
            $script:context.Version.SemVer2 | Should -Match $Version
            $script:context.Version.SemVer2NoBuildMetadata | Should -Match $Version
            $script:context.Version.SemVer1 | Should -Match $Version
            $script:context.Version.Version | Should -Match $Version
        }
    }

    Describe 'New-WhiskeyContext.when run by a developer for an application' {
        Init
        GivenConfiguration
        WhenCreatingContext -Environment 'fubar'
        ThenDeveloperContextCreated -Environment 'fubar'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when version number uses build number' {
        Context 'by developer' {
            Init
            GivenConfiguration -BuildNumber '0'
            WhenCreatingContext -Environment 'fubar'
            ThenDeveloperContextCreated -Environment 'fubar'
        }
        Context 'by build server' {
            Init
            GivenConfiguration -BuildNumber '45' -ForBuildServer
            WhenCreatingContext -Environment 'fubar'
            ThenBuildServerContextCreated -Environment 'fubar'
        }
    }

    Describe 'New-WhiskeyContext.when run by developer for a library' {
        Init
        GivenConfiguration
        WhenCreatingContext 
        ThenDeveloperContextCreated 
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when run by developer and configuration file does not exist' {
        Init
        GivenConfigurationFileDoesNotExist
        WhenCreatingContext -ThenCreationFailsWithErrorMessage 'does not exist' -ErrorAction SilentlyContinue
    }

    Describe 'New-WhiskeyContext.when run by the build server' {
        Init
        GivenConfiguration -ForBuildServer
        WhenCreatingContext -Environment 'fubar'
        ThenBuildServerContextCreated -Environment 'fubar'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when run by the build server and customizing download root' {
        Init
        GivenConfiguration -ForBuildServer
        WhenCreatingContext -WithDownloadRoot $TestDrive
        ThenBuildServerContextCreated -WithDownloadRoot $TestDrive
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when application name in configuration file' {
        Init
        GivenConfiguration
        WhenCreatingContext
        ThenDeveloperContextCreated
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on master branch' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'master'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on feature branch' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'feature/fubar'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on release branch' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'release/5.1'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on long-lived release branch' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'release'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on develop branch' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'develop'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on hot fix branch' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'hotfix/snafu'
        WhenCreatingContext 
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on bug fix branch' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'bugfix/fubarnsafu'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when publishing on custom branch' {
        Init
        GivenConfiguration -OnBranch 'feature/3.0' -ForBuildServer -PublishingOn 'feature/3.0'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenPublishes
    }

    Describe 'New-WhiskeyContext.when publishing on multiple branches and building on one of them' {
        Init
        GivenConfiguration -OnBranch 'fubarsnafu' -ForBuildServer -PublishingOn @( 'feature/3.0', 'fubar*' ) 
        WhenCreatingContext
        ThenPublishes
    }

    Describe 'New-WhiskeyContext.when publishing on multiple branches and not building on one of them' {
        Init
        GivenConfiguration -OnBranch 'some-issue-master' -ForBuildServer -PublishingOn @( 'feature/3.0', 'master' ) 
        WhenCreatingContext
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when configuration is just a property name' {
        Init
        GivenWhiskeyYml 'BuildTasks'
        WhenCreatingContext
    }

    Describe 'New-WhiskeyContext.when run mode is ''Clean''' {
        Init
        GivenRunMode 'Clean'
        GivenConfiguration
        WhenCreatingContext
        ThenShouldCleanIs $true
        ThenShouldInitializeIs $false
    }

    Describe 'New-WhiskeyContext.when run mode is ''Initialize''' {
        Init
        GivenRunMode 'Initialize'
        GivenConfiguration
        WhenCreatingContext
        ThenShouldCleanIs $false
        ThenShouldInitializeIs $true
    }

    Describe 'New-WhiskeyContext.when run mode is default' {
        Init
        GivenConfiguration
        WhenCreatingContext
        ThenShouldCleanIs $false
        ThenShouldInitializeIs $false
    }
    
    Describe 'New-WhiskeyContext.when Version property is used' {
        Init
        GivenConfiguration @{ 'BuildTasks' = @(@{ 'Exec' = 'cmd /C echo' }) ; 'Version' = '1.2.3-rc.1+fubar.snafu' }
        WhenCreatingContext -RunBy 'BuildServer'
        # Run a build to ensure the Version task is in the build tasks.
        Invoke-WhiskeyBuild -Context $script:context
        ThenSemVer1Is '1.2.3-rc1'
        ThenSemVer2Is '1.2.3-rc.1+.'
        ThenSemVer2NoBuildMetadataIs '1.2.3-rc.1'
    }

    Describe 'New-WhiskeyContext.when VersionFrom property is used' {
        Init
        '@{ ModuleVersion = "1.2.3" }' | Set-Content -Path (Join-Path -Path $TestDrive.Fullname -ChildPath 'module.psd1')
        GivenConfiguration @{ 'VersionFrom' = 'module.psd1' }
        WhenCreatingContext -RunBy 'BuildServer'
        # Run a build to ensure the Version task is in the build tasks.
        Invoke-WhiskeyBuild -Context $script:context
        ThenSemVer1Is '1.2.3'
        ThenSemVer2Is '1.2.3+.'
        ThenSemVer2NoBuildMetadataIs '1.2.3'
    }

    Describe 'New-WhiskeyContext.when Version task already exists' {
        Init
        GivenConfiguration @{
                                Version = '4.5.6';
                                BuildTasks = @(
                                                @{
                                                    Version = @{
                                                                    Version = '1.2.3'
                                                            }
                                                }
                                            )
                            }
        WhenCreatingContext
        # Run a build to ensure the Version task is in the build tasks.
        Invoke-WhiskeyBuild -Context $script:context
        ThenSemVer1Is '1.2.3'
        ThenSemVer2Is '1.2.3'
        ThenSemVer2NoBuildMetadataIs '1.2.3'
    }

    Describe 'New-WhiskeyContext.when PrereleaseMap property exists' {
        Init
        GivenConfiguration @{
                            PrereleaseMap = @(
                                                @{ 'develop' = 'beta' },
                                                @{ 'feature/*' = 'alpha' }
                                            ); 
                        }
        WhenCreatingContext -RunBy 'BuildServer'
        $script:context.BuildMetadata.ScmBranch = 'feature/snafu'
        $script:context.BuildMetadata.BuildNumber = $buildNumber = '50'
        # Run a build to ensure the Version task is in the build tasks.
        Invoke-WhiskeyBuild -Context $script:context
        $expectedVersion = '{0:yyyy.Mdd}.{1}' -f $script:context.StartedAt,$buildNumber
        ThenSemVer1Is ('{0}-alpha{1}' -f $expectedVersion,$buildNumber)
        ThenSemVer2Is ('{0}-alpha.{1}+feature-snafu.' -f $expectedVersion,$buildNumber)
        ThenSemVer2NoBuildMetadataIs ('{0}-alpha.{1}' -f $expectedVersion,$buildNumber)
    }

    Describe 'New-WhiskeyContext.when there are no Version, VersionFrom or PrereleaseMap properties' {
        Init
        GivenConfiguration -BuildNumber 50 `
                           -Configuration @{ 'BuildTasks' = @( @{ 'Exec' = 'cmd /C echo' } ) } `
                           -ForBuildServer
        WhenCreatingContext
        # Run a build to ensure the Version task is in the build tasks.
        Invoke-WhiskeyBuild -Context $script:context
        $expectedVersion = '{0:yyyy.Mdd}.50' -f $script:context.StartedAt
        ThenVersionIs $expectedVersion
        ThenSemVer1Is $expectedVersion
        ThenSemVer2Is ('{0}+50.develop.deadbee' -f $expectedVersion)
        ThenSemVer2NoBuildMetadataIs $expectedVersion
    }

    Describe 'New-WhiskeyContext.when there are no Version, VersionFrom or PrereleaseMap properties and being run by a developer' {
        Init
        GivenConfiguration -BuildNumber 50 `
                           -Configuration @{ 'BuildTasks' = @( @{ 'Exec' = 'cmd /C echo' } ) }
        WhenCreatingContext
        # Run a build to ensure the Version task is in the build tasks.
        Invoke-WhiskeyBuild -Context $script:context
        $expectedVersion = '{0:yyyy.Mdd}.50' -f $script:context.StartedAt
        ThenVersionIs $expectedVersion
        ThenSemVer1Is $expectedVersion
        ThenSemVer2Is $expectedVersion
        ThenSemVer2NoBuildMetadataIs $expectedVersion
    }
}