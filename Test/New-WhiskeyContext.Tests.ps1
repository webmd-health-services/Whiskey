
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null

    $script:configurationPath = $null
    $script:context = $null
    $script:path = "bad"
    $script:runMode = $null
    $script:warningMessage = $null

    function Assert-Context
    {
        param(
            [Whiskey.Context] $Context,

            $Environment,

            [switch] $ByBuildServer,

            [String]$DownloadRoot
        )

        $Context.Environment | Should -Be $Environment
        $Context.ConfigurationPath | Should -Be (Join-Path -Path $testRoot -ChildPath 'whiskey.yml')
        $Context.BuildRoot | Should -Be ($Context.ConfigurationPath | Split-Path)
        $Context.OutputDirectory | Should -Be (Join-Path -Path $Context.BuildRoot -ChildPath '.output')
        $Context.OutputDirectory | Should -Exist
        $Context.TaskName | Should -BeNullOrEmpty
        $Context.TaskIndex | Should -Be -1
        $Context.PipelineName | Should -Be ''
        $Context.TaskDefaults | Should -BeOfType ([Collections.IDictionary])

        $expectedVersion = '0.0.0'
        ThenVersionIs $expectedVersion
        ThenSemVer2NoBuildMetadataIs $expectedVersion
        ThenSemVer1Is $expectedVersion
        ThenSemVer2Is $expectedVersion
        $Context.Configuration | Should -BeOfType ([Collections.IDictionary])
        $Context.Configuration.ContainsKey('SomProperty') | Should -BeTrue
        $Context.Configuration['SomProperty'] | Should -Be 'SomeValue'

        if( -not $DownloadRoot )
        {
            $DownloadRoot = $Context.BuildRoot.FullName
        }

        $Context.DownloadRoot.FullName | Should -Be $DownloadRoot
        $Context.ByBuildServer | Should -Be $ByBuildServer
        $Context.ByDeveloper | Should -Be (-not $ByBuildServer)
        $Context | Get-Member -Name 'ApiKeys' | Should -Not -BeNullOrEmpty
        $Context.ApiKeys | Should -BeOfType ([Collections.IDictionary])
        $Context | Get-Member -Name 'ShouldClean' | Should -BeTrue
        $Context.ShouldClean | Should -BeFalse
        $Context | Get-Member -Name 'ShouldInitialize' | Should -BeTrue
        $Context.ShouldInitialize | Should -BeFalse
        $Context | Get-Member -Name 'BuildMetadata' | Should -Not -BeNullOrEmpty
        $Context.BuildMetadata | Should -Not -BeNullOrEmpty
        $Context | Get-Member -Name 'Variables' | Should -Not -BeNullOrEmpty
        $Context.Variables | Should -BeOfType ([Collections.IDictionary])
    }

    function GivenConfiguration
    {
        param(
            [switch]$ForBuildServer,

            [String]$OnBranch = 'develop',

            [String[]]$PublishingOn,

            [Parameter(Position=0)]
            [Collections.IDictionary]$Configuration,

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

        $buildInfo = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyBuildMetadataObject'
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

        $script:configurationPath = Join-Path -Path $testRoot -ChildPath 'whiskey.yml'
        $Yaml | Set-Content -Path $script:configurationPath
    }

    function ThenSemVer1Is
    {
        param(
            [SemVersion.SemanticVersion]$SemanticVersion
        )

        $script:context.Version.SemVer1.ToString() | Should -Be $SemanticVersion.ToString()
        $script:context.Version.SemVer1 | Should -BeOfType ([SemVersion.SemanticVersion])
    }

    function ThenSemVer2Is
    {
        param(
            [SemVersion.SemanticVersion]$SemanticVersion
        )
        $script:context.Version.SemVer2.ToString() | Should -Be $SemanticVersion.ToString()
        $script:context.Version.SemVer2 | Should -BeOfType ([SemVersion.SemanticVersion])
    }

    function ThenSemVer2NoBuildMetadataIs
    {
        param(
            [SemVersion.SemanticVersion]$SemanticVersion
        )

        $script:Context.Version.SemVer2NoBuildMetadata.ToString() | Should -Be $SemanticVersion.ToString()
        $script:Context.Version.SemVer2NoBuildMetadata | Should -BeOfType ([SemVersion.SemanticVersion])
    }

    function ThenVersionIs
    {
        param(
            [Version]$ExpectedVersion
        )

        $script:Context.Version.Version.ToString() | Should -Be $expectedVersion.ToString()
        $script:Context.Version.Version | Should -BeOfType ([Version])
    }

    function WhenCreatingContext
    {
        [CmdletBinding()]
        param(
            [String] $Environment = 'developer',

            [String] $ThenCreationFailsWithErrorMessage,

            [String]$WithDownloadRoot,

            [Whiskey.RunBy] $RunBy
        )

        process
        {
            $parameters = @{
                'Environment' = $Environment;
                'ConfigurationPath' = $script:ConfigurationPath;
            }

            if( $WithDownloadRoot )
            {
                $parameters['DownloadRoot'] = $WithDownloadRoot
            }

            $Global:Error.Clear()
            $threwException = $false
            try
            {
                $script:context = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyContext' `
                                                            -Parameter $parameters `
                                                            -WarningVariable 'newWhiskeyContextWarning'
                $script:warningMessage = $newWhiskeyContextWarning
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
                $threwException | Should -BeTrue
                $Global:Error | Should -Match $ThenCreationFailsWithErrorMessage
            }
            else
            {
                $threwException | Should -BeFalse
                $Global:Error | Should -BeNullOrEmpty
            }
        }
    }

    function ThenBuildServerContextCreated
    {
        [CmdletBinding()]
        param(
            [String]$Environment = 'developer',

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
            $iWasCalled | Should -BeTrue
        }
    }

    function ThenDeveloperContextCreated
    {
        [CmdletBinding()]
        param(
            [String]$Environment = 'developer'
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
            $iWasCalled | Should -BeTrue
        }
    }

    function ThenPublishes
    {
        $script:Context.Publish | Should -BeTrue
    }

    function ThenDoesNotPublish
    {
        $script:Context.Publish | Should -BeFalse
    }

    function ThenShouldCleanIs
    {
        param(
            $ExpectedValue
        )

        $script:context.ShouldClean | Should -Be $ExpectedValue
    }

    function ThenShouldInitializeIs
    {
        param(
            $ExpectedValue
        )

        $script:context.ShouldInitialize | Should -Be $ExpectedValue
    }

    function ThenVersionMatches
    {
        param(
            [String]$Version
        )

        $script:context.Version.SemVer2 | Should -Match $Version
        $script:context.Version.SemVer2NoBuildMetadata | Should -Match $Version
        $script:context.Version.SemVer1 | Should -Match $Version
        $script:context.Version.Version | Should -Match $Version
    }

    function ThenWarning
    {
        param(
            $Message
        )

        $script:warningMessage | Should -Match $Message
    }
}

Describe 'New-WhiskeyContext' {
    BeforeEach {
        $script:runMode = $null
        $script:configurationPath = ''
        $script:context = $null
        $script:path = "bad"
        $script:warningMessage = $null

        $script:testRoot = New-WhiskeyTestRoot
    }

    Context 'run by a developer for an application' {
        It 'creates context' {
            GivenConfiguration
            WhenCreatingContext -Environment 'fubar'
            ThenDeveloperContextCreated -Environment 'fubar'
            ThenDoesNotPublish
        }
    }

    Context 'version number uses build number' {
        Context 'by developer' {
            It 'creates context' {
                GivenConfiguration -BuildNumber '0'
                WhenCreatingContext -Environment 'fubar'
                ThenDeveloperContextCreated -Environment 'fubar'
            }
        }
        Context 'by build server' {
            It 'creates context' {
                GivenConfiguration -BuildNumber '45' -ForBuildServer
                WhenCreatingContext -Environment 'fubar'
                ThenBuildServerContextCreated -Environment 'fubar'
            }
        }
    }

    Context 'run by developer for a library' {
        It 'creates context' {
            GivenConfiguration
            WhenCreatingContext
            ThenDeveloperContextCreated
            ThenDoesNotPublish
        }
    }

    Context 'run by developer and configuration file does not exist' {
        It 'fails' {
            GivenConfigurationFileDoesNotExist
            WhenCreatingContext -ThenCreationFailsWithErrorMessage 'does not exist' -ErrorAction SilentlyContinue
        }
    }

    Context 'run by the build server' {
        It 'creates context' {
            GivenConfiguration -ForBuildServer
            WhenCreatingContext -Environment 'fubar'
            ThenBuildServerContextCreated -Environment 'fubar'
            ThenDoesNotPublish
        }
    }

    Context 'run by the build server and customizing download root' {
        It 'creates context' {
            GivenConfiguration -ForBuildServer
            WhenCreatingContext -WithDownloadRoot $testRoot
            ThenBuildServerContextCreated -WithDownloadRoot $testRoot
            ThenDoesNotPublish
        }
    }

    Context 'application name in configuration file' {
        It 'creates context' {
            GivenConfiguration
            WhenCreatingContext
            ThenDeveloperContextCreated
            ThenDoesNotPublish
        }
    }

    Context 'building on master branch' {
        It 'creates context' {
            GivenConfiguration -ForBuildServer -OnBranch 'master'
            WhenCreatingContext
            ThenBuildServerContextCreated
            ThenDoesNotPublish
        }
    }

    Context 'building on feature branch' {
        It 'creates context' {
            GivenConfiguration -ForBuildServer -OnBranch 'feature/fubar'
            WhenCreatingContext
            ThenBuildServerContextCreated
            ThenDoesNotPublish
        }
    }

    Context 'building on release branch' {
        It 'creates context' {
            GivenConfiguration -ForBuildServer -OnBranch 'release/5.1'
            WhenCreatingContext
            ThenBuildServerContextCreated
            ThenDoesNotPublish
        }
    }

    Context 'building on long-lived release branch' {
        It 'creates context' {
            GivenConfiguration -ForBuildServer -OnBranch 'release'
            WhenCreatingContext
            ThenBuildServerContextCreated
            ThenDoesNotPublish
        }
    }

    Context 'building on develop branch' {
        It 'creates context' {
            GivenConfiguration -ForBuildServer -OnBranch 'develop'
            WhenCreatingContext
            ThenBuildServerContextCreated
            ThenDoesNotPublish
        }
    }

    Context 'building on hot fix branch' {
        It 'creates context' {
            GivenConfiguration -ForBuildServer -OnBranch 'hotfix/snafu'
            WhenCreatingContext
            ThenBuildServerContextCreated
            ThenDoesNotPublish
        }
    }

    Context 'building on bug fix branch' {
        It 'creates context' {
            GivenConfiguration -ForBuildServer -OnBranch 'bugfix/fubarnsafu'
            WhenCreatingContext
            ThenBuildServerContextCreated
            ThenDoesNotPublish
        }
    }

    Context 'publishing on custom branch' {
        It 'creates context' {
            GivenConfiguration -OnBranch 'feature/3.0' -ForBuildServer -PublishingOn 'feature/3.0'
            WhenCreatingContext
            ThenBuildServerContextCreated
            ThenPublishes
        }
    }

    Context 'publishing on multiple branches and building on one of them' {
        It 'creates context' {
            GivenConfiguration -OnBranch 'fubarsnafu' -ForBuildServer -PublishingOn @( 'feature/3.0', 'fubar*' )
            WhenCreatingContext
            ThenPublishes
        }
    }

    Context 'publishing on multiple branches and not building on one of them' {
        It 'creates context' {
            GivenConfiguration -OnBranch 'some-issue-master' -ForBuildServer -PublishingOn @( 'feature/3.0', 'master' )
            WhenCreatingContext
            ThenDoesNotPublish
        }
    }

    Context 'configuration is just a property name' {
        It 'creates context' {
            GivenWhiskeyYml 'Build'
            WhenCreatingContext
        }
    }

    Context 'run mode is "Clean"' {
        It 'creates context' {
            GivenRunMode 'Clean'
            GivenConfiguration
            WhenCreatingContext
            ThenShouldCleanIs $true
            ThenShouldInitializeIs $false
        }
    }

    Context 'run mode is "Initialize"' {
        It 'creates context' {
            GivenRunMode 'Initialize'
            GivenConfiguration
            WhenCreatingContext
            ThenShouldCleanIs $false
            ThenShouldInitializeIs $true
        }
    }

    Context 'run mode is default' {
        It 'creates context' {
            GivenConfiguration
            WhenCreatingContext
            ThenShouldCleanIs $false
            ThenShouldInitializeIs $false
        }
    }

    Context 'both Build and BuildTasks pipelines exists' {
        It 'fails' {
            GivenConfiguration @{
                Build = @()
                BuildTasks = @()
            }
            WhenCreatingContext -ThenCreationFailsWithErrorMessage 'contains\ both\ "Build"\ and\ the\ deprecated\ "BuildTasks"\ pipelines' -ErrorAction SilentlyContinue
        }
    }

    Context 'both Publish and PublishTasks pipelines exists' {
        It 'fails' {
            GivenConfiguration @{
                Publish = @();
                PublishTasks = @();
            }
            WhenCreatingContext -ThenCreationFailsWithErrorMessage 'contains\ both\ "Publish"\ and\ the\ deprecated\ "PublishTasks"\ pipelines' -ErrorAction SilentlyContinue
        }
    }

    Context 'BuildTasks pipeline exists' {
        It 'should warn that BuildTasks is obsolete' {
            GivenConfiguration @{
                BuildTasks = @(
                    @{ Version = '1.0.0' }
                )
            }
            WhenCreatingContext
            ThenWarning 'The\ default\ "BuildTasks"\ pipeline\ has\ been\ renamed\ to\ "Build"'
        }
    }

    Context 'PublishTasks pipeline exists' {
        It 'should warn that PublishTasks is obsolete' {
            GivenConfiguration @{
                Build = @(
                    @{ Version = '1.0.0' }
                );
                PublishTasks = @(
                    'NuGetPush'
                );
            }
            WhenCreatingContext
            ThenWarning 'The\ default\ "PublishTasks"\ pipeline\ has\ been\ renamed\ to\ "Publish"'
        }
    }
}