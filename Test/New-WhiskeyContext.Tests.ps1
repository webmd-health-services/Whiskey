
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null

$configurationPath = $null
$context = $null
$path = "bad"
$runMode = $null
$warningMessage = $null

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

        $BuildNumber = '1',

        [String] $IsPRFromBranch
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

        if( $IsPRFromBranch )
        {
            $buildInfo.IsPullRequest = $true
            $buildInfo.ScmSourceBranch = $IsPRFromBranch
        }
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

function Init
{
    $script:runMode = $null
    $script:configurationPath = ''
    $script:context = $null
    $script:path = "bad"
    $script:warningMessage = $null

    $script:testRoot = New-WhiskeyTestRoot
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

Describe 'New-WhiskeyContext.when run by a developer for an application' {
    It 'should create context' {
        Init
        GivenConfiguration
        WhenCreatingContext -Environment 'fubar'
        ThenDeveloperContextCreated -Environment 'fubar'
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when version number uses build number' {
    Context 'by developer' {
        It 'should create context' {
            Init
            GivenConfiguration -BuildNumber '0'
            WhenCreatingContext -Environment 'fubar'
            ThenDeveloperContextCreated -Environment 'fubar'
        }
    }
    Context 'by build server' {
        It 'should create context' {
            Init
            GivenConfiguration -BuildNumber '45' -ForBuildServer
            WhenCreatingContext -Environment 'fubar'
            ThenBuildServerContextCreated -Environment 'fubar'
        }
    }
}

Describe 'New-WhiskeyContext.when run by developer for a library' {
    It 'should create context' {
        Init
        GivenConfiguration
        WhenCreatingContext
        ThenDeveloperContextCreated
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when run by developer and configuration file does not exist' {
    It 'should fail' {
        Init
        GivenConfigurationFileDoesNotExist
        WhenCreatingContext -ThenCreationFailsWithErrorMessage 'does not exist' -ErrorAction SilentlyContinue
    }
}

Describe 'New-WhiskeyContext.when run by the build server' {
    It 'should create the context' {
        Init
        GivenConfiguration -ForBuildServer
        WhenCreatingContext -Environment 'fubar'
        ThenBuildServerContextCreated -Environment 'fubar'
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when run by the build server and customizing download root' {
    It 'should create the context' {
        Init
        GivenConfiguration -ForBuildServer
        WhenCreatingContext -WithDownloadRoot $testRoot
        ThenBuildServerContextCreated -WithDownloadRoot $testRoot
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when application name in configuration file' {
    It 'should create the context' {
        Init
        GivenConfiguration
        WhenCreatingContext
        ThenDeveloperContextCreated
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when building on master branch' {
    It 'should create the context' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'master'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when building on feature branch' {
    It 'should create the context' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'feature/fubar'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when building on release branch' {
    It 'should create the context' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'release/5.1'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when building on long-lived release branch' {
    It 'should create the context' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'release'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when building on develop branch' {
    It 'should create the context' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'develop'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when building on hot fix branch' {
    It 'should create the context' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'hotfix/snafu'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when building on bug fix branch' {
    It 'should create the context' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'bugfix/fubarnsafu'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when publishing on custom branch' {
    It 'should create the context' {
        Init
        GivenConfiguration -OnBranch 'feature/3.0' -ForBuildServer -PublishingOn 'feature/3.0'
        WhenCreatingContext
        ThenBuildServerContextCreated
        ThenPublishes
    }
}

Describe 'New-WhiskeyContext.when publishing on multiple branches and building on one of them' {
    It 'should create the context' {
        Init
        GivenConfiguration -OnBranch 'fubarsnafu' -ForBuildServer -PublishingOn @( 'feature/3.0', 'fubar*' )
        WhenCreatingContext
        ThenPublishes
    }
}

Describe 'New-WhiskeyContext.when publishing on multiple branches and not building on one of them' {
    It 'should create the context' {
        Init
        GivenConfiguration -OnBranch 'some-issue-master' -ForBuildServer -PublishingOn @( 'feature/3.0', 'master' )
        WhenCreatingContext
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when building a PR that targets a publishing branch' {
    It 'should not publish' {
        Init
        GivenConfiguration -ForBuildServer -OnBranch 'main' -IsPRFromBranch 'feature/pr' -PublishingOn @('main')
        WhenCreatingContext
        ThenDoesNotPublish
    }
}

Describe 'New-WhiskeyContext.when configuration is just a property name' {
    It 'should create the context' {
        Init
        GivenWhiskeyYml 'Build'
        WhenCreatingContext
    }
}

Describe 'New-WhiskeyContext.when run mode is "Clean"' {
    It 'should create the context' {
        Init
        GivenRunMode 'Clean'
        GivenConfiguration
        WhenCreatingContext
        ThenShouldCleanIs $true
        ThenShouldInitializeIs $false
    }
}

Describe 'New-WhiskeyContext.when run mode is "Initialize"' {
    It 'should create the context' {
        Init
        GivenRunMode 'Initialize'
        GivenConfiguration
        WhenCreatingContext
        ThenShouldCleanIs $false
        ThenShouldInitializeIs $true
    }
}

Describe 'New-WhiskeyContext.when run mode is default' {
    It 'should create the context' {
        Init
        GivenConfiguration
        WhenCreatingContext
        ThenShouldCleanIs $false
        ThenShouldInitializeIs $false
    }
}

Describe 'New-WhiskeyContext.when both Build and BuildTasks pipelines exists' {
    It 'should fail' {
        Init
        GivenConfiguration @{
            Build = @()
            BuildTasks = @()
        }
        WhenCreatingContext -ThenCreationFailsWithErrorMessage 'contains\ both\ "Build"\ and\ the\ deprecated\ "BuildTasks"\ pipelines' -ErrorAction SilentlyContinue
    }
}

Describe 'New-WhiskeyContext.when both Publish and PublishTasks pipelines exists' {
    It 'should fail' {
        Init
        GivenConfiguration @{
            Publish = @();
            PublishTasks = @();
        }
        WhenCreatingContext -ThenCreationFailsWithErrorMessage 'contains\ both\ "Publish"\ and\ the\ deprecated\ "PublishTasks"\ pipelines' -ErrorAction SilentlyContinue
    }
}

Describe 'New-WhiskeyContext.when BuildTasks pipeline exists' {
    It 'should warn that BuildTasks is obsolete' {
        Init
        GivenConfiguration @{
            BuildTasks = @(
                @{ Version = '1.0.0' }
            )
        }
        WhenCreatingContext
        ThenWarning 'The\ default\ "BuildTasks"\ pipeline\ has\ been\ renamed\ to\ "Build"'
    }
}

Describe 'New-WhiskeyContext.when PublishTasks pipeline exists' {
    It 'should warn that PublishTasks is obsolete' {
        Init
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
