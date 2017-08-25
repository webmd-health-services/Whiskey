
function New-WhiskeyContext
{
    <#
    .SYNOPSIS
    Creates a context object to use when running builds.

    .DESCRIPTION
    The `New-WhiskeyContext` function creates a context object used when running builds. It gets passed to each build task. The YAML file at `ConfigurationPath` is parsed. If it has a `Version` property, it is converted to a semantic version, a classic version, and a NuGet verson (a semantic version without any build metadata). An object is then returned with the following properties:

    * `ConfigurationPath`: the absolute path to the YAML file passed via the `ConfigurationPath` parameter
    * `BuildRoot`: the absolute path to the directory the YAML configuration file is in.
    * `OutputDirectory`: the path to a directory where build output, reports, etc. should be saved. This directory is created for you.
    * `Version`: a `SemVersion.SemanticVersion` object representing the semantic version to use when building the application. This object has two extended properties: `Version`, a `Version` object that represents the semantic version with all pre-release and build metadata stripped off; and `ReleaseVersion` a `SemVersion.SemanticVersion` object with all build metadata stripped off.
    * `ReleaseVersion`: the semantic version with all build metadata stripped away, i.e. the version and pre-release only.
    * `Configuration`: the parsed YAML as a hashtable.
    * `DownloadRoot`: the path to a directory where tools can be downloaded when needed. 
    * `ByBuildServer`: a flag indicating if the build is being run by a build server.
    * `ByDeveloper`: a flag indicating if the build is being run by a developer.
    * `ApplicatoinName`: the name of the application being built.

    .EXAMPLE
    New-WhiskeyContext -Path '.\whiskey.yml' 

    Demonstrates how to create a context for a developer build.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The environment you're building in.
        $Environment,

        [Parameter(Mandatory=$true)]
        [string]
        # The path to the `whiskey.yml` file that defines build settings and tasks.
        $ConfigurationPath,

        [string]
        # The place where downloaded tools should be cached. The default is the build root.
        $DownloadRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $ConfigurationPath = Resolve-Path -LiteralPath $ConfigurationPath -ErrorAction Ignore
    if( -not $ConfigurationPath )
    {
        throw ('Configuration file path ''{0}'' does not exist.' -f $PSBoundParameters['ConfigurationPath'])
    }

    $config = Import-WhiskeyYaml -Path $ConfigurationPath

    $buildRoot = $ConfigurationPath | Split-Path
    if( -not $DownloadRoot )
    {
        $DownloadRoot = $buildRoot
    }

    $bitbucketConnection = $null

    $buildMetadata = Get-WhiskeyBuildMetadata
    $publish = $false
    $byBuildServer = $buildMetadata.IsBuildServer
    $prereleaseInfo = ''
    if( $byBuildServer )
    {
        $branch = $buildMetadata.ScmBranch

        if( $config.ContainsKey( 'PublishOn' ) )
        {
            Write-Verbose -Message ('PublishOn')
            foreach( $publishWildcard in $config['PublishOn'] )
            {
                $publish = $branch -like $publishWildcard
                if( $publish )
                {
                    Write-Verbose -Message ('           {0}    -like  {1}' -f $branch,$publishWildcard)
                    break
                }
                else
                {
                    Write-Verbose -Message ('           {0} -notlike  {1}' -f $branch,$publishWildcard)
                }
            }
        }

        if( $config['PrereleaseMap'] )
        {
            $idx = 0
            Write-Verbose -Message ('PrereleaseMap')
            foreach( $item in $config['PrereleaseMap'] )
            {
                if( -not ($item | Get-Member -Name 'Count') -or -not ($item | Get-Member 'Keys') -or $item.Count -ne 1 )
                {
                    throw ('{0}: Prerelease[{1}]: The `PrereleaseMap` property must be a list of objects. Each object must have one property. That property should be a wildcard. The property''s value should be the prerelease identifier to add to the version number on branches that match the wildcard. For example,
    
    PrereleaseMap:
    - "alpha/*": "alpha"
    - "release/*": "rc"
    ' -f $ConfigurationPath,$idx)
                }

                $wildcard = $item.Keys | Select-Object -First 1
                if( $branch -like $wildcard )
                {
                    Write-Verbose -Message ('               {0}     -like  {1}' -f $branch,$wildcard)
                    $prereleaseInfo = '{0}.{1}' -f $item[$wildcard],$buildMetadata.BuildNumber
                }
                else
                {
                    Write-Verbose -Message ('               {0}  -notlike  {1}' -f $branch,$wildcard)
                }
                $idx++
            }
        }
    }

    $packageJsonPath = Join-Path -Path $buildRoot -ChildPath 'package.json'
    $ignorePackageJsonVersion = $config.ContainsKey('IgnorePackageJsonVersion') -and $config['IgnorePackageJsonVersion']
    $versionParam = @{}
    if( $config.ContainsKey( 'VersionPath') )
    {
        $versionParam['Path'] = $config['VersionPath']
    }
    else
    {
        $versionParam['Version'] = $config['Version']
    }
    $semVersion = New-WhiskeySemanticVersion @versionParam -Prerelease $prereleaseInfo -BuildMetadata $buildMetadata -ErrorAction Stop
    if( -not $semVersion )
    {
        Write-Error ('Unable to create the semantic version for the current build. Is ''{0}'' a valid semantic version? If not, please update the Version property in ''{1}'' to be a valid semantic version.' -f $config['Version'], $ConfigurationPath) -ErrorAction Stop
    }

    $version = New-Object -TypeName 'version' -ArgumentList $semVersion.Major,$semVersion.Minor,$semVersion.Patch
    $semVersionNoBuild = New-Object -TypeName 'SemVersion.SemanticVersion' -ArgumentList $semVersion.Major,$semVersion.Minor,$semVersion.Patch
    $semVersionV1 = New-Object -TypeName 'SemVersion.SemanticVersion' -ArgumentList $semVersion.Major,$semVersion.Minor,$semVersion.Patch
    if( $semVersion.Prerelease )
    {
        $semVersionNoBuild = New-Object -TypeName 'SemVersion.SemanticVersion' -ArgumentList $semVersion.Major,$semVersion.Minor,$semVersion.Patch,$semVersion.Prerelease
        $semVersionV1Prerelease = $semVersion.Prerelease -replace '[^A-Za-z0-90]',''
        $semVersionV1 = New-Object -TypeName 'SemVersion.SemanticVersion' -ArgumentList $semVersion.Major,$semVersion.Minor,$semVersion.Patch,$semVersionV1Prerelease
    }
    
    $context = New-WhiskeyContextObject

    $context.Environment = $Environment;
    $context.BuildRoot = $buildRoot;
    $context.ConfigurationPath = $ConfigurationPath;

    $context.OutputDirectory = Join-Path -Path $buildRoot -ChildPath '.output'
    if( -not (Test-Path -Path $context.OutputDirectory -PathType Container) )
    {
        New-Item -Path $context.OutputDirectory -ItemType 'Directory' -Force | Out-Null
    }    
    $context.Version = [pscustomobject]@{
        SemVer2 = $semVersion;
        SemVer2NoBuildMetadata = $semVersionNoBuild;
        SemVer1 = $semVersionV1;
        Version = $version;
    }
    $context.Configuration = $config;
    $context.DownloadRoot = $DownloadRoot;
    $context.ByBuildServer = $byBuildServer;
    $context.ByDeveloper = (-not $byBuildServer);
    $context.Publish = $publish;
    $context.RunMode = 'Build';
    $context.BuildMetadata = $buildMetadata

    return $context
}

