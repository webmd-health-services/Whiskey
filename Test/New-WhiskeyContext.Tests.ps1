
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$buildServerContext = @{
                            BBServerCredential = (New-Credential -UserName 'bitbucket' -Password 'snafu');
                            BBServerUri = 'http://bitbucket.example.com/';
                            BuildMasterUri = 'http://buildmaster.example.com/';
                            BuildMasterApiKey = 'deadbeef';
                            ProGetCredential = (New-Credential -UserName 'proget' -Password 'snafu');
                        }
$progetUri = [uri]'https://proget.example.com/'
$progetUris = @( $progetUri, [uri]'https://proget.another.example.com/' )
$configurationPath = $null
$context = $null

function Assert-Context
{
    param(
        $Context,

        $Environment,

        $SemanticVersion,

        [Switch]
        $ByBuildServer,

        $DownloadRoot,

        $ApplicationName,

        $ReleaseName,

        $WithProGetAppFeed = 'Apps', 

        $WithProGetNpmFeed = 'npm/npm',

        $WithProGetNuGetFeed = 'nuget/NuGet',

        $WithProGetPowerShellFeed = 'posh/PoSh'
    )

    $script:context = $Context

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

    It 'should have PackageVariables property' {
        $Context.PackageVariables | Should BeOfType ([hashtable])
        $Context.PackageVariables.Count | Should Be 0
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
        $Context.Configuration | Should BeOfType ([hashtable])
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

    It 'should set build configuration' {
        $Context.BuildConfiguration | Should Be 'fubar'
    }

    It 'should set build server flag' {
        $Context.ByBuildServer | Should Be $ByBuildServer
        $Context.ByDeveloper | Should Be (-not $ByBuildServer)
    }


    It 'should set ProGet URIs' {
        $Context.ProGetSession | Should Not BeNullOrEmpty
        $Context.ProGetSession.AppFeedUri | Should Be $progetUris
        $Context.ProGetSession.AppFeedName | Should Be $WithProGetAppFeed
        $Context.ProGetSession.NpmFeedUri | Should Be (New-Object -TypeName 'Uri' -ArgumentList $progetUri,$WithProGetNpmFeed)
        $Context.ProGetSession.NuGetFeedUri | Should Be (New-Object -TypeName 'Uri' -ArgumentList $progetUri,$WithProGetNuGetFeed)
        $Context.ProGetSession.PowerShellFeedUri | Should Be (New-Object -TypeName 'Uri' -ArgumentList $progetUri,$WithProGetPowerShellFeed)
    }
}

function GivenBuildID
{
    param(
        $BuildID
    )

    function Get-WhiskeyBuildID
    {
    }
    Mock -CommandName 'Get-WhiskeyBuildID' -ModuleName 'Whiskey' -MockWith { $BuildID }.GetNewClosure()
}

function GivenConfiguration
{
    param(
        [string]
        $WithVersion,

        [Switch]
        $ForBuildServer,

        [String]
        $OnBranch = 'develop',

        $ForApplicationName,

        $ForReleaseName,

        [string[]]
        $PublishingOn,

        [Parameter(Position=0)]
        [hashtable]
        $Configuration
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

    if( $ForApplicationName )
    {
        $Configuration['ApplicationName'] = $ForApplicationName
    }

    if( $ForReleaseName )
    {
        $Configuration['ReleaseName'] = $ForReleaseName
    }

    if( $PublishingOn )
    {
        $Configuration['PublishOn'] = $PublishingOn
    }
    
    if( $ForBuildServer )
    {
        $gitBranch = $OnBranch
        $filter = { $Path -eq 'env:GIT_BRANCH' }
        $mock = { [pscustomobject]@{ Value = $gitBranch } }.GetNewClosure()
        Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -ParameterFilter $filter -MockWith $mock
        Mock -CommandName 'Get-Item' -ParameterFilter $filter -MockWith $mock

        Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_BRANCH' } -MockWith { return $true }
        Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_BRANCH' } -MockWith { return [pscustomobject]@{ Value = $OnBranch } }.GetNewClosure() 

        if( $WithVersion )
        {
            Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return [SemVersion.SemanticVersion]$Configuration['Version'] }.GetNewClosure()
        }
        else
        {
            Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:BUILD_ID' } -MockWith { return $true }
            Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:BUILD_ID' } -MockWith { return [pscustomobject]@{ Value = '1' } }
            Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_COMMIT' } -MockWith { return $true }
            Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_COMMIT' } -MockWith { return [pscustomobject]@{ Value = 'deadbee' } }
        }
    }
    else
    {
        if( $WithVersion )
        {
            Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { 
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

function GivenWhiskeyYml
{
    param(
        $Yaml
    )

    $script:configurationPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml'
    $Yaml | Set-Content -Path $configurationPath
}

function ThenSemVer1Is
{
    param(
        [SemVersion.SemanticVersion]
        $SemanticVersion
    )

    It ('should set semantic version v1 to {0}' -f $SemanticVersion) {
        $context.Version.SemVer1 | Should Be $SemanticVersion
        $context.Version.SemVer1 | Should BeOfType ([SemVersion.SemanticVersion])
    }
}

function ThenSemVer2Is
{
    param(
        [SemVersion.SemanticVersion]
        $SemanticVersion
    )

    It ('should set semantic version v2 to {0}' -f $SemanticVersion) {
        $context.Version.SemVer2 | Should Be $SemanticVersion
        $context.Version.SemVer2 | Should BeOfType ([SemVersion.SemanticVersion])
    }
}

function ThenSemVer2NoBuildMetadataIs
{
    param(
        [SemVersion.SemanticVersion]
        $SemanticVersion
    )

    It ('should set semantic version v2 with no build metadata to {0}' -f $SemanticVersion) {
        $Context.Version.SemVer2NoBuildMetadata | Should Be $SemanticVersion
        $Context.Version.SemVer2NoBuildMetadata | Should BeOfType ([SemVersion.SemanticVersion])
    }

}

function ThenVersionIs
{
    param(
        [Version]
        $ExpectedVersion
    )

    It ('should set version to {0}' -f $ExpectedVersion) {
        $Context.Version.Version | Should Be $expectedVersion
        $Context.Version.Version | Should BeOfType ([version])
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

        $WithProGetAppFeed = 'Apps', 

        $WithProGetNpmFeed = 'npm/npm',

        $WithProGetNuGetFeed = 'nuget/NuGet',

        $WithPowerShellNuGetFeed = 'posh/PoSh',

        $WithDownloadRoot,

        [Switch]
        $WithNoToolInfo
    )

    process
    {
        if( $ByDeveloper )
        {
            Mock -CommandName 'Test-WhiskeyRunByBuildServer' -ModuleName 'Whiskey' -MockWith { return $false }
        }

        $optionalArgs = @{ }
        if( $ByBuildServer )
        {
            Mock -CommandName 'Test-WhiskeyRunByBuildServer' -ModuleName 'Whiskey' -MockWith { return $true }
        }

        if( -not $WithNoToolInfo )
        {
            $optionalArgs = $buildServerContext.Clone()
            if( $WithProGetAppFeed )
            {
                $optionalArgs['ProGetAppFeedName'] = $WithProGetAppFeed
            }
            if( $WithProGetNpmFeed )
            {
                $optionalArgs['NpmFeedUri'] = New-Object 'uri' $progetUri, $WithProGetNpmFeed
            }
            if( $WithProGetNuGetFeed )
            {
                $optionalArgs['NuGetFeedUri'] = New-Object 'uri' $progetUri, $WithProGetNuGetFeed
            }
            if( $WithPowerShellNuGetFeed )
            {
                $optionalArgs['PowerShellFeedUri'] = New-Object 'uri' $progetUri, $WithPowerShellNuGetFeed
            }
        }

        if( $WithDownloadRoot )
        {
            $optionalArgs['DownloadRoot'] = $WithDownloadRoot
        }

        $Global:Error.Clear()
        $threwException = $false
        try
        {
            $script:context = New-WhiskeyContext -Environment $Environment -ConfigurationPath $ConfigurationPath -BuildConfiguration 'fubar' -ProGetAppFeedUri $progetUris @optionalArgs
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

        [String]
        $WithReleaseName = $null,

        $WithProGetAppFeed, 

        $WithProGetNpmFeed,

        $WithProGetNuGetFeed,

        $WithPowerShellNuGetFeed,

        $WithDownloadRoot
    )

    begin
    {
        $iWasCalled = $false
    }

    process
    {
        $optionalArgs = @{}
        if( $WithProGetAppFeed )
        {
            $optionalArgs['WithProGetAppFeed'] = $WithProGetAppFeed
        }
        if( $WithProGetNpmFeed )
        {
            $optionalArgs['WithProGetNpmFeed'] = $WithProGetNpmFeed
        }
        if( $WithProGetNuGetFeed )
        {
            $optionalArgs['WithProGetNuGetFeed'] = $WithProGetNuGetFeed
        }
        if( $WithPowerShellNuGetFeed )
        {
            $optionalArgs['WithProGetPowerShellFeed'] = $WithPowerShellNuGetFeed
        }

        $iWasCalled = $true
        Assert-Context -Environment $Environment -Context $Context -SemanticVersion $WithSemanticVersion -ByBuildServer -DownloadRoot $WithDownloadRoot @optionalArgs

        It 'should set Bitbucket Server connection' {
            $Context.BBServerConnection | Should Not BeNullOrEmpty
            $Context.BBServerConnection.Uri | Should Be $buildServerContext['BBServerUri']
            [object]::ReferenceEquals($Context.BBServerConnection.Credential,$buildServerContext['BBServerCredential']) | Should Be $true
        }

        It 'should set BuildMaster session' {
            $Context.BuildMasterSession | Should Not BeNullOrEmpty
            $Context.BuildMasterSession.Uri | Should Be $buildServerContext['BuildMasterUri']
            $Context.BuildMasterSession.ApiKey | Should Be $buildServerContext['BuildMasterApiKey']
        }

        It 'should set ProGet session' {
            $Context.ProGetSession | Should Not BeNullOrEmpty
            [object]::ReferenceEquals($Context.ProGetSession.Credential,$buildServerContext['ProGetCredential']) | Should Be $true
        }
        if( $WithReleaseName )
        {
            It 'should set publish' {
                $Context.Publish | Should Be $True
            }

            It 'should set release name' {
                $Context.ReleaseName | Should Be $WithReleaseName
            }
        }
        else
        {
            It 'should not set publish' {
                $Context.Publish | Should Be $False
            }

            It 'should not set release name' {
                $Context.ReleaseName | Should BeNullOrEmpty
            }
        }
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
        $WithSemanticVersion,

        $WithApplicationName = $null,

        $WithReleaseName = $null
    )

    begin
    {
        $iWasCalled = $false
    }

    process
    {
        $iWasCalled = $true

        Assert-Context -Environment $Environment -Context $Context -SemanticVersion $WithSemanticVersion

        It 'should not set Bitbucket Server connection' {
            $Context.BBServerConnection | Should BeNullOrEmpty
        }

        It 'should not set BuildMaster session' {
            $Context.BuildMasterSession| Should BeNullOrEmpty
        }

        It 'should set application name' {
            $Context.ApplicationName | Should Be $WithApplicationName
        }

        It 'should set release name' {
            $Context.ReleaseName | Should Be $WithReleaseName
        }
        
        It 'should not set publish' {
            $Context.Publish | Should Be $false
        }
    }

    end
    {
        It 'should return a context' {
            $iWasCalled | Should Be $true
        }
    }
}

function ThenVersionMatches
{
    param(
        [string]
        $Version
    )

    It ('should set version to {0}' -f $Version) {
        $context.Version.SemVer2 | Should -Match $Version
        $context.Version.SemVer2NoBuildMetadata | Should -Match $Version
        $context.Version.SemVer1 | Should -Match $Version
        $context.Version.Version | Should -Match $Version
    }
}

Describe 'New-WhiskeyContext.when run by a developer for an application' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu'
    WhenCreatingContext -ByDeveloper -Environment 'fubar'
    ThenDeveloperContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -Environment 'fubar'
}

Describe 'New-WhiskeyContext.when run by developer for a library' {
    GivenConfiguration -WithVersion '1.2.3'
    WhenCreatingContext -ByDeveloper 
    ThenDeveloperContextCreated -WithSemanticVersion ('1.2.3+{0}.{1}' -f $env:USERNAME,$env:COMPUTERNAME)
}

Describe 'New-WhiskeyContext.when run by developer and configuration file does not exist' {
    GivenConfigurationFileDoesNotExist
    WhenCreatingContext -ByDeveloper -ThenCreationFailsWithErrorMessage 'does not exist' -ErrorAction SilentlyContinue
}

Describe 'New-WhiskeyContext.when run by developer and version is not a semantic version' {
    GivenConfiguration -WithVersion 'fubar'
    WhenCreatingContext -ByDeveloper  -ThenCreationFailsWithErrorMessage 'not a valid semantic version' -ErrorAction SilentlyContinue
}

Describe 'New-WhiskeyContext.when run by the build server' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer
    WhenCreatingContext -ByBuildServer -Environment 'fubar'
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'develop' -Environment 'fubar'
}

Describe 'New-WhiskeyContext.when run by the build server and customizing ProGet feed names' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer
    WhenCreatingContext -ByBuildServer -WithProgetAppFeed 'fubar' -WithProGetNpmFeed 'snafu' -WithProGetNuGetFeed 'fubarsnafu' -WithPowerShellNuGetFeed 'snafubar'
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithProGetAppFeed 'fubar' -WithProGetNpmFeed 'snafu' -WithReleaseName 'develop' -WithProGetNuGetFeed 'fubarsnafu' -WithPowerShellNuGetFeed 'snafubar'
}

Describe 'New-WhiskeyContext.when run by the build server and customizing download root' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer
    WhenCreatingContext -ByBuildServer -WithDownloadRoot $TestDrive.FullName
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithDownloadRoot $TestDrive.FullName -WithReleaseName 'develop'
}

Describe 'New-WhiskeyContext.when run by build server called with developer parameter set' {
    GivenConfiguration -WithVersion '1.2.3' -ForBuildServer
    WhenCreatingContext -ByBuildServer -WithNoToolInfo -ThenCreationFailsWithErrorMessage 'developer parameter set' -ErrorAction SilentlyContinue
}

Describe 'New-WhiskeyContext.when application name in configuration file' {
    GivenConfiguration -WithVersion '1.2.3' -ForApplicationName 'fubar'
    WhenCreatingContext -ByDeveloper
    ThenDeveloperContextCreated -WithApplicationName 'fubar' -WithSemanticVersion '1.2.3'
}

Describe 'New-WhiskeyContext.when release name in configuration file' {
    GivenConfiguration -WithVersion '1.2.3' -ForReleaseName 'fubar'
    WhenCreatingContext -ByDeveloper
    ThenDeveloperContextCreated -WithReleaseName 'fubar' -WithSemanticVersion '1.2.3'
}


Describe 'New-WhiskeyContext.when building on master branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'master'
    WhenCreatingContext -ByBuildServer
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'master'
}

Describe 'New-WhiskeyContext.when building on feature branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'feature/fubar'
    WhenCreatingContext -ByBuildServer
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' #-WithReleaseName 'origin/feature/fubar'
}

Describe 'New-WhiskeyContext.when building on release branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'release/5.1'
    WhenCreatingContext -ByBuildServer
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'release/5.1'
}

Describe 'New-WhiskeyContext.when building on long-lived release branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'release'
    WhenCreatingContext -ByBuildServer
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'release'
}

Describe 'New-WhiskeyContext.when building on develop branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'develop'
    WhenCreatingContext -ByBuildServer
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' -WithReleaseName 'develop'
}

Describe 'New-WhiskeyContext.when building on hot fix branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'hotfix/snafu'
    WhenCreatingContext -ByBuildServer 
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' #-WithReleaseName 'origin/hotfix/snafu'
}

Describe 'New-WhiskeyContext.when building on bug fix branch' {
    GivenConfiguration -WithVersion '1.2.3-fubar+snafu' -ForBuildServer -OnBranch 'bugfix/fubarnsafu'
    WhenCreatingContext -ByBuildServer
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3-fubar+snafu' #-WithReleaseName 'origin/bugfix/fubarnsafu'
}

Describe 'New-WhiskeyContext.when publishing on custom branch' {
    GivenConfiguration -WithVersion '1.2.3' -OnBranch 'feature/3.0' -ForBuildServer -PublishingOn 'feature/3\.0'
    WhenCreatingContext -ByBuildServer
    ThenBuildServerContextCreated -WithSemanticVersion '1.2.3' -WithReleaseName 'feature/3.0'
}

Describe 'New-WhiskeyContext.when run by developer on a prerelease branch' {
    GivenConfiguration -WithVersion '1.2.3' -OnBranch 'alpha/2.0' -PublishingOn '^alpha\b'
    WhenCreatingContext -ByDeveloper
    ThenSemVer2Is '1.2.3'
}

Describe 'New-WhiskeyContext.when publishing on a prerelease branch' {
    GivenConfiguration  @{ 'Version' = '1.2.3' ; 'PublishOn' = @( '^alpha\b' ); 'PrereleaseMap' = @( @{ '\balpha\b' = 'alpha' } ); } -OnBranch 'alpha/2.0' -ForBuildServer
    GivenBuildID '93'
    WhenCreatingContext -ByBuildServer
    ThenSemVer2Is '1.2.3-alpha.93'
    ThenVersionIs '1.2.3'
    ThenSemVer1Is '1.2.3-alpha93'
}

Describe 'New-WhiskeyContext.when a PrereleaseMap has multiple keys' {
    GivenConfiguration  @{ 'Version' = '1.2.3' ; 'PublishOn' = @( '^alpha\b' ); 'PrereleaseMap' = @( @{ '\balpha\b' = 'alpha' ; '\bbeta\b' = 'beta' } ); } -OnBranch 'alpha/2.0' -ForBuildServer
    WhenCreatingContext -ByBuildServer -ThenCreationFailsWithErrorMessage 'must be a list of objects' -ErrorAction SilentlyContinue
}

function GivenPackageJson
{
    param(
        [string]
        $AtVersion
    )

    @"
{
  "name": "middle-tier-client",
  "version": "$($AtVersion)",
  "description": "Perform web requests to the middle tier",
  "main": "index.js",
  "engines":{
    "node": "4.4.7"
  }
}
"@  | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'package.json')
}

Describe 'New-WhiskeyContext.when building a Node module by a developer' {
    GivenConfiguration
    GivenPackageJson -AtVersion '9.4.6'
    WhenCreatingContext -ByDeveloper
    ThenSemVer2Is '9.4.6'
    ThenVersionIs '9.4.6'
    ThenSemVer2NoBuildMetadataIs '9.4.6'
    ThenSemVer1Is '9.4.6'
}

Describe 'New-WhiskeyContext.when building a Node module by a build server' {
    GivenConfiguration -ForBuildServer
    GivenPackageJson -AtVersion '9.4.6'
    WhenCreatingContext -ByBuildServer
    ThenSemVer2Is '9.4.6'
    ThenVersionIs '9.4.6'
    ThenSemVer2NoBuildMetadataIs '9.4.6'
    ThenSemVer1Is '9.4.6'
}

Describe 'New-WhiskeyContext.when building a Node.js application and should use an auto-generated version number' {
    GivenConfiguration
    GivenPackageJson -AtVersion '0.0.0'
    WhenCreatingContext 
    ThenVersionMatches ('^{0}\.' -f (Get-DAte).ToString('yyyy\\.Mdd'))
}

Describe 'New-WhiskeyContext.when building a Node.js application and ignoring package.json version number' {
    GivenConfiguration -Configuration @{ 'IgnorePackageJsonVersion' = $true }
    GivenPackageJson -AtVersion '1.0.0' 
    WhenCreatingContext 
    ThenVersionMatches ('^{0}\.' -f (Get-DAte).ToString('yyyy\\.Mdd'))
}

Describe 'New-WhiskeyContext.when configuration is just a property name' {
    GivenWhiskeyYml 'BuildTasks'
    WhenCreatingContext
}

