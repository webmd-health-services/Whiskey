
function New-WhsCIContext
{
    <#
    .SYNOPSIS
    Creates a context object to use when running builds.

    .DESCRIPTION
    The `New-WhsCIContext` function creates a context object used when running builds. It gets passed to each build task. The YAML file at `ConfigurationPath` is parsed. If it has a `Version` property, it is converted to a semantic version, a classic version, and a NuGet verson (a semantic version without any build metadata). An object is then returned with the following properties:

    * `ConfigurationPath`: the absolute path to the YAML file passed via the `ConfigurationPath` parameter
    * `BuildRoot`: the absolute path to the directory the YAML configuration file is in.
    * `BuildConfiguration`: the build configuration to use when compiling code. Set from the parameter by the same name.
    * `OutputDirectory`: the path to a directory where build output, reports, etc. should be saved. This directory is created for you.
    * `Version`: a `SemVersion.SemanticVersion` object representing the semantic version to use when building the application. This object has two extended properties: `Version`, a `Version` object that represents the semantic version with all pre-release and build metadata stripped off; and `NuGetVersion` a `SemVersion.SemanticVersion` object with all build metadata stripped off.
    * `NuGetVersion`: the semantic version with all build metadata stripped away.
    * `Configuration`: the parsed YAML as a hashtable.
    * `DownloadRoot`: the path to a directory where tools can be downloaded when needed. 
    * `ByBuildServer`: a flag indicating if the build is being run by a build server.
    * `ByDeveloper`: a flag indicating if the build is being run by a developer.
    * `ApplicatoinName`: the name of the application being built.

    In addition, if you're creating a context while running under a build server, you must supply BuildMaster, ProGet, and Bitbucket Server connection information. That connection information is returned in the following properties:

    * `BuildMasterSession`
    * `ProGetSession`
    * `BBServerConnection`

    .EXAMPLE
    New-WhsCIContext -Path '.\whsbuild.yml' -BuildConfiguration 'debug'

    Demonstrates how to create a context for a developer build.

    .EXAMPLE
    New-WhsCIContext -Path '.\whsbuild.yml' -BuildConfiguration 'debug' -BBServerCredential $bbCred -BBServerUri $bbUri -BuildMasterUri $bmUri -BuildMasterApiKey $bmApiKey -ProGetCredential $progetCred -ProGetUri $progetUri

    Demonstrates how to create a context for a build run by a build server.
    #>
    [CmdletBinding(DefaultParameterSetName='ByDeveloper')]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the `whsbuild.yml` file that defines build settings and tasks.
        $ConfigurationPath,

        [Parameter(Mandatory=$true)]
        [string]
        # The configuration to use when compiling code, e.g. `Debug`, `Release`.
        $BuildConfiguration,

        [Parameter(Mandatory=$true,ParameterSetName='ByBuildServer')]
        [pscredential]
        # The credential to use when authenticating to Bitbucket Server. Required if running under a build server.
        $BBServerCredential,

        [Parameter(Mandatory=$true,ParameterSetName='ByBuildServer')]
        [uri]
        # The URI to Bitbucket Server. Required if running under a build server.
        $BBServerUri,

        [Parameter(Mandatory=$true,ParameterSetName='ByBuildServer')]
        [uri]
        # The URI to BuildMaster. Required if running under a build server.
        $BuildMasterUri,

        [Parameter(Mandatory=$true,ParameterSetName='ByBuildServer')]
        [string]
        # The API key to use when using BuildMaster's Release and Package Deployment API. Required if running under a build server.
        $BuildMasterApiKey,

        [Parameter(Mandatory=$true,ParameterSetName='ByBuildServer')]
        [pscredential]
        # The credential to use when authenticating to ProGet. Required if running under a build server.
        $ProGetCredential,

        [Parameter(Mandatory=$true)]
        [uri]
        # The URI to ProGet. Used to get NuGet packages, NPM packages, etc.
        $ProGetUri,

        [Parameter(ParameterSetName='ByBuildServer')]
        [string]
        # The name/path to the feed in ProGet where universal application packages should be uploaded. The default is `upack/App`. Combined with the `ProGetUri` parameter to create the URI to the feed.
        $ProGetAppFeed = 'upack/Apps',

        [Parameter(ParameterSetName='ByBuildServer')]
        [string]
        # The name/path to the feed in ProGet where NPM packages should be uploaded to and downloaded from. The default is `npm/npm`. Combined with the `ProGetUri` parameter to create the URI to the feed.
        $ProGetNpmFeed = 'npm/npm',

        [string]
        # The place where downloaded tools should be cached. The default is `$env:LOCALAPPDATA\WebMD Health Services\WhsCI`.
        $DownloadRoot
    )

    Set-StrictMode -Version 'Latest'

    $ConfigurationPath = Resolve-Path -LiteralPath $ConfigurationPath -ErrorAction Ignore
    if( -not $ConfigurationPath )
    {
        throw ('Configuration file path ''{0}'' does not exist.' -f $PSBoundParameters['ConfigurationPath'])
    }

    $config = Get-Content -Path $ConfigurationPath -Raw | ConvertFrom-Yaml
    if( -not $config )
    {
        $config = @{} 
    }

    [SemVersion.SemanticVersion]$semVersion = $config['Version'] | ConvertTo-WhsCISemanticVersion -ErrorAction Ignore
    if( -not $semVersion )
    {
        throw ('{0}: Version: ''{1}'' is not a valid semantic version. Please see http://semver.org for semantic versioning documentation.' -f $ConfigurationPath,$config['Version'])
    }

    $version = New-Object -TypeName 'version' -ArgumentList $semVersion.Major,$semVersion.Minor,$semVersion.Patch
    $semVersion | Add-Member -MemberType NoteProperty -Name 'Version' -Value $version
    $nugetVersion = New-Object -TypeName 'SemVersion.SemanticVersion' -ArgumentList $semVersion.Major,$semVersion.Minor,$semVersion.Patch
    if( $semVersion.Prerelease )
    {
        $nugetVersion = New-Object -TypeName 'SemVersion.SemanticVersion' -ArgumentList $semVersion.Major,$semVersion.Minor,$semVersion.Patch,$semVersion.Prerelease
    }
    $semVersion | Add-Member -MemberType NoteProperty -Name 'NuGetVersion' -Value $nugetVersion

    if( -not $DownloadRoot )
    {
        $DownloadRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI'
    }

    $appName = $null
    if( $config.ContainsKey('ApplicationName') )
    {
        $appName = $config['ApplicationName']
    }

    $releaseName = $null
    if( $config.ContainsKey('ReleaseName') )
    {
        $releaseName = $config['ReleaseName']
    }

    $bitbucketConnection = $null
    $buildmasterSession = $null
    $progetSession = $null
    
    $progetSession = [pscustomobject]@{
                                            Uri = $ProGetUri;
                                            Credential = $null;
                                            AppFeedUri = (New-Object -TypeName 'Uri' -ArgumentList $ProGetUri,$ProGetAppFeed)
                                            NpmFeedUri = (New-Object -TypeName 'Uri' -ArgumentList $ProGetUri,$ProGetNpmFeed)
                                            AppFeed = $ProGetAppFeed;
                                            NpmFeed = $ProGetNpmFeed;
                                        }
    $publish = $false
    $byBuildServer = Test-WhsCIRunByBuildServer
    if( $byBuildServer )
    {
        if( $PSCmdlet.ParameterSetName -ne 'ByBuildServer' )
        {
            throw (@"
New-WhsCIContext is being run by a build server, but called using the developer parameter set. When running under a build server, you must supply the following parameters:

* BBServerCredential
* BBServerUri
* BuildMasterUri
* BuildMasterApiKey
* ProGetCredential
* ProGetUri

Use the `Test-WhsCIRunByBuildServer` function to determine if you're running under a build server or not.
"@)
        }
        
        $branch = (Get-Item -Path 'env:GIT_BRANCH').Value -replace '^origin/',''
        $branch = $branch -replace '/.*$',''
        $publishOn = @( 'develop', 'release', 'master' )
        if( $config.ContainsKey( 'PublishOn' ) )
        {
            $publishOn = $config['PublishOn']
        }

        $publish = ($branch -match ('^({0})$' -f ($publishOn -join '|')))
        if( -not $releaseName -and $publish )
        {        
            $releaseName = $branch
        }

        $bitbucketConnection = New-BBServerConnection -Credential $BBServerCredential -Uri $BBServerUri
        $buildmasterSession = New-BMSession -Uri $BuildMasterUri -ApiKey $BuildMasterApiKey
        $progetSession.Credential = $ProGetCredential
    }

    $buildRoot = $ConfigurationPath | Split-Path
    $context = [pscustomobject]@{
                                    ApplicationName = $appName;
                                    ReleaseName = $releaseName;
                                    BuildRoot = $buildRoot;
                                    ConfigurationPath = $ConfigurationPath;
                                    BBServerConnection = $bitbucketConnection;
                                    BuildMasterSession = $buildmasterSession;
                                    ProGetSession = $progetSession;
                                    BuildConfiguration = $BuildConfiguration;
                                    OutputDirectory = (Get-WhsCIOutputDirectory -WorkingDirectory $buildRoot);
                                    TaskName = $null;
                                    TaskIndex = -1;
                                    PackageVariables = @{};
                                    Version = $semVersion;
                                    Configuration = $config;
                                    DownloadRoot = $DownloadRoot;
                                    ByBuildServer = $byBuildServer;
                                    ByDeveloper = (-not $byBuildServer);
                                    Publish = $publish;
                                }
    return $context
}