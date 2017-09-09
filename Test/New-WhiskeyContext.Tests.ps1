
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
            $Context,

            $Environment,

            $SemanticVersion,

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
            $Context.TaskDefaults | Should -BeOfType ([hashtable])
        }

        ThenSemVer2Is $SemanticVersion

        $expectedVersion = ('{0}.{1}.{2}' -f $SemanticVersion.Major,$SemanticVersion.Minor,$SemanticVersion.Patch)
        ThenVersionIs $expectedVersion

        $expectedReleaseVersion = $expectedVersion
        if( $SemanticVersion.Prerelease )
        {
            $expectedReleaseVersion = '{0}-{1}' -f $expectedVersion,$SemanticVersion.Prerelease
        }

        ThenSemVer2NoBuildMetadataIs $expectedReleaseVersion

        It 'should set raw configuration hashtable' {
            $Context.Configuration | Should -BeOfType ([Collections.Generic.Dictionary[object,object]])
            $Context.Configuration.ContainsKey('SomProperty') | Should Be $true
            $Context.Configuration['SomProperty'] | Should Be 'SomeValue'
        }

        if( -not $DownloadRoot )
        {
            $DownloadRoot = $Context.BuildRoot
        }

        It 'should set download root' {
            $Context.DownloadRoot | Should Be $DownloadRoot
        }

        It 'should set build server flag' {
            $Context.ByBuildServer | Should Be $ByBuildServer
            $Context.ByDeveloper | Should Be (-not $ByBuildServer)
        }

        It 'ApiKeys property should exit' {
            $Context | Get-Member -Name 'ApiKeys' | Should -Not -BeNullOrEmpty
        }

        It 'ApiKeys property should be a hashtable' {
            $Context.ApiKeys | Should -BeOfType ([hashtable])
        }

        It ('should have ShouldClean method') {
            $Context | Get-Member -Name 'ShouldClean' | Should -BE $true
            $Context.ShouldClean() | Should -Be $false
        }

        It ('should have ShouldInitialize method') {
            $Context | Get-Member -Name 'ShouldInitialize' | Should -BE $true
            $Context.ShouldClean() | Should -Be $false
        }

        It ('should have BuildMetadata property') {
            $Context | Get-Member -Name 'BuildMetadata' | Should -Not -BeNullOrEmpty
            $Context.BuildMetadata | Should -Not -BeNullOrEmpty
        }
    }

    function GivenConfiguration
    {
        param(
            [string]
            $WithVersion,

            [Switch]
            $ForBuildServer,

            [string]
            $withPath,

            [String]
            $OnBranch = 'develop',

            [string[]]
            $PublishingOn,

            [Parameter(Position=0)]
            [hashtable]
            $Configuration,

            $BuildNumber = '1'
        )

        if( -not $Configuration )
        {
            $Configuration = @{ }
        }

        $Configuration['SomProperty'] = 'SomeValue'
        if( $WithVersion )
        {
            $Configuration['Version'] = $WithVersion
        }

        if( $PublishingOn )
        {
            $Configuration['PublishOn'] = $PublishingOn
        }
        if( $withPath )
        {
            $Configuration['VersionFrom'] = $withPath
            $Script:path = $withPath
        }
    
        $buildInfo = New-WhiskeyBuildMetadataObject

        Mock -CommandName 'Get-WhiskeyBuildMetadata' -ModuleName 'Whiskey' -MockWith { return $buildInfo }.GetNewClosure()
        if( $ForBuildServer )
        {
            $buildInfo.ScmBranch = $OnBranch
            $buildInfo.BuildNumber = $BuildNumber
            $buildInfo.ScmCommitID = 'deadbee'
            $buildInfo.BuildServerName = 'Jenkins'

            if( $WithVersion )
            {
                Mock -CommandName 'New-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return [SemVersion.SemanticVersion]$Configuration['Version'] }.GetNewClosure()
            }
        }
        else
        {
            if( $WithVersion )
            {
                Mock -CommandName 'New-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { 
                    [SemVersion.SemanticVersion]$semVersion = $null
                    if( -not [SemVersion.SemanticVersion]::TryParse($Configuration['Version'],[ref]$semVersion) )
                    {
                        return
                    }
                    return $semVersion
                }.GetNewClosure()
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
            $script:context.Version.SemVer1 | Should Be $SemanticVersion
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
            $script:context.Version.SemVer2 | Should Be $SemanticVersion
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
            $script:Context.Version.SemVer2NoBuildMetadata | Should Be $SemanticVersion
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
            $script:Context.Version.Version | Should Be $expectedVersion
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

            [Switch]
            $ByDeveloper,

            [Switch]
            $ByBuildServer,

            $WithDownloadRoot
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

            [SemVersion.SemanticVersion]
            $WithSemanticVersion,

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
            Assert-Context -Environment $Environment -Context $context -SemanticVersion $WithSemanticVersion -ByBuildServer -DownloadRoot $WithDownloadRoot @optionalArgs
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
            $Environment = 'developer',

            [SemVersion.SemanticVersion]
            $WithSemanticVersion
        )

        begin
        {
            $iWasCalled = $false
        }

        process
        {
            $iWasCalled = $true

            Assert-Context -Environment $Environment -Context $script:Context -SemanticVersion $WithSemanticVersion
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

        It ('ShouldClean() should be ''{0}''' -f $ExpectedValue) {
            $script:context.ShouldClean() | Should -Be $ExpectedValue
        }
    }

    function ThenShouldInitializeIs
    {
        param(
            $ExpectedValue
        )

        It ('ShouldInitialize() should be ''{0}''' -f $ExpectedValue) {
            $script:context.ShouldInitialize() | Should -Be $ExpectedValue
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
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu'
        WhenCreatingContext -ByDeveloper -Environment 'fubar'
        ThenDeveloperContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -Environment 'fubar'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when run by developer for a library' {
        Init
        GivenConfiguration -WithVersion '1.2.3'
        WhenCreatingContext -ByDeveloper 
        ThenDeveloperContextCreated -WithSemanticVersion ('1.2.3+{0}.{1}' -f $env:USERNAME,$env:COMPUTERNAME)
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when run by developer and configuration file does not exist' {
        Init
        GivenConfigurationFileDoesNotExist
        WhenCreatingContext -ByDeveloper -ThenCreationFailsWithErrorMessage 'does not exist' -ErrorAction SilentlyContinue
    }

    Describe 'New-WhiskeyContext.when run by developer and version is not a semantic version' {
        Init
        GivenConfiguration -WithVersion 'fubar'
        WhenCreatingContext -ByDeveloper  -ThenCreationFailsWithErrorMessage 'unable\ to\ create\ the\ semantic\ version' -ErrorAction SilentlyContinue
    }

    Describe 'New-WhiskeyContext.when run by the build server' {
        Init
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer
        WhenCreatingContext -ByBuildServer -Environment 'fubar'
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -Environment 'fubar'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when run by the build server and customizing download root' {
        Init
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer
        WhenCreatingContext -ByBuildServer -WithDownloadRoot $TestDrive.FullName
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithDownloadRoot $TestDrive.FullName
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when application name in configuration file' {
        Init
        GivenConfiguration -WithVersion '1.2.3'
        WhenCreatingContext -ByDeveloper
        ThenDeveloperContextCreated -WithSemanticVersion '1.2.3'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on master branch' {
        Init
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'master'
        WhenCreatingContext -ByBuildServer
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on feature branch' {
        Init
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'feature/fubar'
        WhenCreatingContext -ByBuildServer
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on release branch' {
        Init
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'release/5.1'
        WhenCreatingContext -ByBuildServer
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on long-lived release branch' {
        Init
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'release'
        WhenCreatingContext -ByBuildServer
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on develop branch' {
        Init
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'develop'
        WhenCreatingContext -ByBuildServer
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on hot fix branch' {
        Init
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'hotfix/snafu'
        WhenCreatingContext -ByBuildServer 
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when building on bug fix branch' {
        Init
        GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'bugfix/fubarnsafu'
        WhenCreatingContext -ByBuildServer
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when publishing on custom branch' {
        Init
        GivenConfiguration -WithVersion '1.2.3' -OnBranch 'feature/3.0' -ForBuildServer -PublishingOn 'feature/3.0'
        WhenCreatingContext -ByBuildServer
        ThenBuildServerContextCreated -WithSemanticVersion '1.2.3'
        ThenPublishes
    }

    Describe 'New-WhiskeyContext.when publishing on multiple branches and building on one of them' {
        Init
        GivenConfiguration -WithVersion '1.2.3' -OnBranch 'fubarsnafu' -ForBuildServer -PublishingOn @( 'feature/3.0', 'fubar*' ) 
        WhenCreatingContext -ByBuildServer
        ThenPublishes
    }

    Describe 'New-WhiskeyContext.when publishing on multiple branches and not building on one of them' {
        Init
        GivenConfiguration -WithVersion '1.2.3' -OnBranch 'some-issue-master' -ForBuildServer -PublishingOn @( 'feature/3.0', 'master' ) 
        WhenCreatingContext -ByBuildServer
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when run by developer on a prerelease branch' {
        Init
        GivenConfiguration -WithVersion '1.2.3' -OnBranch 'master' -PublishingOn 'master'
        WhenCreatingContext -ByDeveloper
        ThenSemVer2Is '1.2.3'
        ThenDoesNotPublish
    }

    Describe 'New-WhiskeyContext.when publishing on a prerelease branch' {
        Init
        GivenConfiguration  @{ 'Version' = '1.2.3' ; 'PublishOn' = @( 'alpha/*' ); 'PrereleaseMap' = @( @{ 'beta/*' = 'beta' } ; @{ 'alpha/*' = 'alpha' } ); } -OnBranch 'alpha/2.0' -ForBuildServer -BuildNumber '93'
        WhenCreatingContext -ByBuildServer
        ThenSemVer2Is '1.2.3-alpha.93+93.alpha-2.0.deadbee'
        ThenVersionIs '1.2.3'
        ThenSemVer1Is '1.2.3-alpha93'
    }

    Describe 'New-WhiskeyContext.when a PrereleaseMap has multiple keys' {
        Init
        GivenConfiguration  @{ 'Version' = '1.2.3' ; 'PublishOn' = @( 'alpha/*' ); 'PrereleaseMap' = @( @{ 'alpha/*' = 'alpha' ; 'beta/*' = 'beta' } ); } -OnBranch 'alpha/2.0' -ForBuildServer
        WhenCreatingContext -ByBuildServer -ThenCreationFailsWithErrorMessage 'must be a list of objects' -ErrorAction SilentlyContinue
    }

    Describe 'New-WhiskeyContext.when there prerelease branches but not building on one of them' {
        Init
        GivenConfiguration  @{ 'Version' = '1.2.3' ; 'PublishOn' = @( 'alphabet' ); 'PrereleaseMap' = @( @{ 'alpha' = 'alpha' } ); } -OnBranch 'alphabet' -ForBuildServer -BuildNumber '94'
        WhenCreatingContext -ByBuildServer
        ThenSemVer2Is '1.2.3+94.master.deadbee'
        ThenVersionIs '1.2.3'
        ThenSemVer1Is '1.2.3'
    }

    function GivenNodeVersionFrom
    {
        param(
            [string]
            $AtVersion,
            [string]
            $withPath
        )
        New-Item -Force $withPath -type file -value ('{{"version":"{0}"}}' -f $AtVersion)
    }
    function GivenModuleVersionFrom
    {
        param(
            [string]
            $withPath,
            [string]
            $AtVersion
        )
        
        New-Item -Force $withPath -type file -Value ("@{{""ModuleVersion""= ""{0}""}}" -f $AtVersion)

    }
    Describe 'New-WhiskeyContext.when building a Node module by a developer' {
        Init
        GivenConfiguration -withPath 'package.json'
        GivenNodeVersionFrom -AtVersion '9.4.6' -withPath 'package.json'
        WhenCreatingContext -ByDeveloper
        ThenSemVer2Is '9.4.6'
        ThenVersionIs '9.4.6'
        ThenSemVer2NoBuildMetadataIs '9.4.6'
        ThenSemVer1Is '9.4.6'
    }

    Describe 'New-WhiskeyContext.when building a Node module by a developer' {
        Init
        GivenConfiguration -withPath 'package.json'
        GivenNodeVersionFrom -AtVersion '9.4.6' -withPath 'package.json'
        WhenCreatingContext -ByDeveloper
        ThenSemVer2Is '9.4.6'
        ThenVersionIs '9.4.6'
        ThenSemVer2NoBuildMetadataIs '9.4.6'
        ThenSemVer1Is '9.4.6'
    }

    Describe 'New-WhiskeyContext.when building a Node module by a build server' {
        Init
        GivenConfiguration -ForBuildServer -withPath 'package.json'
        GivenNodeVersionFrom -AtVersion '9.4.6' -withPath 'package.json'
        WhenCreatingContext -ByBuildServer 
        ThenSemVer2Is '9.4.6'
        ThenVersionIs '9.4.6'
        ThenSemVer2NoBuildMetadataIs '9.4.6'
        ThenSemVer1Is '9.4.6'
    }

    Describe 'New-WhiskeyContext.when building a Powershell module by a build server' {
        Init
        GivenConfiguration -ForBuildServer -withPath 'package.psd1'
        GivenModuleVersionFrom -AtVersion '9.4.6' -withPath 'package.psd1'
        WhenCreatingContext -ByBuildServer 
        ThenSemVer2Is '9.4.6'
        ThenVersionIs '9.4.6'
        ThenSemVer2NoBuildMetadataIs '9.4.6'
        ThenSemVer1Is '9.4.6'
    }

    Describe 'New-WhiskeyContext.when building a Node.js application and ignoring package.json version number' {
        Init
        GivenConfiguration -Configuration @{ }
        GivenNodeVersionFrom -AtVersion '9.4.6' -withPath 'package.json' 
        WhenCreatingContext 
        ThenVersionMatches ('^{0}\.' -f (Get-Date).ToString('yyyy\\.Mdd'))
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
}