#!/usr/bin/env pwsh

<#
.SYNOPSIS
Builds the Whiskey repository.

.DESCRIPTION
The `build.ps1` script invokes a build of the Whiskey repository. It will first download the .NET Core SDK into a `.dotnet` directory in the repo root and use that SDK to build the Whiskey assembly. After the Whiskey assembly is built, it is copied into Whiskey's `bin` directory after which the Whiskey PowerShell module is imported. Finally, `Invoke-WhiskeyBuild` is called to run the build tasks specified in the `whiskey.yml` file in the root of the repository.

To download all the tools that are required for a build, use the `-Initialize` switch.

To cleanup downloaded build tools and artifacts created from previous builds, use the `-Clean` switch.

To build the Whiskey assembly with a custom `--configuration` passed to the `dotnet build` command, use the `-MSBuildConfiguration` parameter. By default, `Debug` when run by a developer and `Release` when run by a build server.

.EXAMPLE
./build.ps1

Starts a build of Whiskey.

.EXAMPLE
./build.ps1 -MSBuildConfiguration 'Release'

Starts a build and uses "Release" as the build configuration when building the Whiskey assembly.
#>
[CmdletBinding(DefaultParameterSetName='Build')]
param(
    [Parameter(Mandatory,ParameterSetName='Clean')]
    # Runs the build in clean mode, which removes any files, tools, packages created by previous builds.
    [switch] $Clean,

    [Parameter(Mandatory,ParameterSetName='Initialize')]
    # Initializes the repository.
    [switch] $Initialize,

    [String] $PipelineName,

    [String] $MSBuildConfiguration = 'Debug',

    [switch] $SkipBootstrap
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
#Requires -Version 5.1
Set-StrictMode -Version Latest

if( -not $SkipBootstrap )
{
    $whiskeyPsd1Path = Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Whiskey.psd1'
    # ErrorAction Ignore because the assemblies haven't been compiled yet and Test-ModuleManifest complains about that.
    $manifest = Test-ModuleManifest -Path $whiskeyPsd1Path -ErrorAction Ignore
    if( -not $manifest )
    {
        Write-Error -Message ('Unable to load Whiskey''s module manifest.')
        exit 1
    }

    $version = $manifest.Version

    $buildInfo = ''
    $prereleaseInfo = ''
    if( Test-Path -Path ('env:APPVEYOR') )
    {
        $commitID = $env:APPVEYOR_REPO_COMMIT
        $commitID = $commitID.Substring(0,7)

        $branch = $env:APPVEYOR_REPO_BRANCH
        $branch = $branch -replace '[^A-Za-z0-9-]','-'

        $buildInfo = '+{0}.{1}.{2}' -f $env:APPVEYOR_BUILD_NUMBER,$branch,$commitID

        if( $branch -eq 'prerelease' )
        {
            $prereleaseInfo = '-beta.{0}' -f $env:APPVEYOR_BUILD_NUMBER
            $buildInfo = '+{0}.{1}' -f $branch,$commitID
        }

        $MSBuildConfiguration = 'Release'

        $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = 'true'
    }

    if( -not (Get-Variable -Name 'IsWindows' -ErrorAction Ignore) )
    {
        # Because we only do this on platforms where they don't exist.
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '')]
        $IsLinux = $false

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '')]
        $IsMacOS = $false

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '')]
        $IsWindows = $true
    }

    $whiskeyBinPath = Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\bin'
    if( -not (Test-Path -Path $whiskeyBinPath) )
    {
        New-Item -Path $whiskeyBinPath -ItemType 'Directory' | Out-Null
    }

    [Uri[]] $binToolUrls = @(
        'https://dist.nuget.org/win-x86-commandline/v6.10.2/nuget.exe',
        'https://dot.net/v1/dotnet-install.sh',
        'https://dot.net/v1/dotnet-install.ps1'
    )

    foreach( $url in $binToolUrls )
    {
        $toolPath = Join-Path -Path $whiskeyBinPath -ChildPath $url.Segments[-1]
        $msg = "Installing ""$($toolPath)"" from $($url)."
        Write-Information $msg
        Invoke-WebRequest -Uri $url -OutFile $toolPath
    }

    if( $IsWindows )
    {
        $dotnetInstallPath = Join-Path -Path $whiskeyBinPath -ChildPath 'dotnet-install.ps1'
        # SDK
        & $dotnetInstallPath -Channel 'LTS'
        # Runtime for tests
        & $dotnetInstallPath -Channel '6.0' -Runtime dotnet
    }
    else
    {
        if( -not (Get-Command -Name 'curl' -ErrorAction SilentlyContinue) )
        {
            $msg = 'Curl is required to install .NET Core. Please install it with this platform''s (or your) ' +
                    'preferred package manager.'
            Write-Error -Message $msg
            exit 1
        }

        $dotnetInstallPath = Join-Path -Path $whiskeyBinPath -ChildPath 'dotnet-install.sh'
        $output = @()
        bash -c @"
. '$($dotnetInstallPath)' --channel 'LTS'
which dotnet
. '$($dotnetInstallPath)' --channel '6.0' --runtime 'dotnet'
"@ |
            Tee-Object -Variable 'output'

        $dotnetPath =
            $output | Where-Object { Test-Path -Path $_ -PathType Leaf } | Select-Object -First 1 | Split-Path -Parent
        if( -not $dotnetPath )
        {
            $msg = "Shell command to install .NET didn't return the path to the dotnet command."
            Write-Error -Message $msg -ErrorAction Stop
        }
        $env:PATH = "$($dotnetPath)$([IO.Path]::PathSeparator)$($env:PATH)"
    }

    if( -not (Get-Command -Name 'dotnet' -ErrorAction Ignore) )
    {
        Write-Error -Message '.NET failed to install or wasn''t added to PATH environment variable.'
        exit 1
    }

    $versionSuffix = '{0}{1}' -f $prereleaseInfo,$buildInfo
    $productVersion = '{0}{1}' -f $version,$versionSuffix
    Push-Location -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assembly')
    try
    {
        $outputDirectory = Join-Path -Path $PSScriptRoot -ChildPath '.output'
        if( -not (Test-Path -Path $outputDirectory -PathType Container) )
        {
            New-Item -Path $outputDirectory -ItemType 'Directory'
        }

        $params = & {
            "--configuration=$($MSBuildConfiguration)"
            '/p:Version={0}' -f $productVersion
            '/p:VersionPrefix={0}' -f $version
            if( $versionSuffix )
            {
                '/p:VersionSuffix={0}' -f $versionSuffix
            }
            if( $VerbosePreference -eq 'Continue' )
            {
                '--verbosity=n'
            }
            '/filelogger9'
            ('/flp9:LogFile={0};Verbosity=d' -f (Join-Path -Path $outputDirectory -ChildPath 'msbuild.whiskey.log'))
        }

        Write-Verbose "dotnet build --configuration=$($MSBuildConfiguration) $($params -join ' ')"
        dotnet build $params

        dotnet test $params --results-directory=$outputDirectory --logger=trx --no-build
        if( $LASTEXITCODE )
        {
            Write-Error -Message ('Unit tests failed.')
        }

        $whiskeyCsprojPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assembly\Whiskey\Whiskey.csproj' -Resolve
        foreach( $framework in @('netstandard2.0', 'net452') )
        {
            $outPath = Join-Path -Path $whiskeyBinPath -ChildPath $framework
            dotnet publish $params -f $framework --no-self-contained --no-build --no-restore -o $outPath $whiskeyCsprojPath
        }

    }
    finally
    {
        Pop-Location
    }
}

$ErrorActionPreference = 'Continue'

prism install | Format-Table -AutoSize

& (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Import-Whiskey.ps1' -Resolve)

$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'whiskey.yml' -Resolve

Write-Verbose -Message '# POWERSHELLVERSIONTABLE'
$PSVersionTable | Format-List | Out-String | Write-Verbose

Write-Verbose -Message '# VARIABLES'
Get-Variable | Format-Table | Out-String | Write-Verbose

Write-Verbose -Message '# ENVIRONMENT PROPERTIES'
[Environment] |
    Get-Member -Static -MemberType Property |
    Where-Object { $_.Name -ne 'StackTrace' } |
    Select-Object -ExpandProperty 'Name' |
    ForEach-Object { [pscustomobject]@{ Name = $_ ; Value = [Environment]::$_ } } |
    Format-Table |
    Out-String |
    Write-Verbose

$optionalArgs = @{ }
if( $Clean )
{
    $optionalArgs['Clean'] = $true
}

if( $Initialize )
{
    $optionalArgs['Initialize'] = $true
}

if( $PipelineName )
{
    $optionalArgs['PipelineName'] = $PipelineName
}

$context = New-WhiskeyContext -Environment 'Dev' -ConfigurationPath $configPath
$apiKeys = @{
                'PowerShellGallery' = 'WHS_POWERSHELL_GALLERY_API_KEY';
                'github.com' = 'WHS_GITHUB_ACCESS_TOKEN';
                'AppVeyor' = 'WHS_APPVEYOR_BEARER_TOKEN';
            }

Write-Verbose -Message '# ENVIRONMENT VARIABLES'
Get-ChildItem 'env:' |
    Where-Object { $_.Name -notin $apiKeys.Values } |
    Format-Table |
    Out-String |
    Write-Verbose

$apiKeys.Keys |
    Where-Object { Test-Path -Path ('env:{0}' -f $apiKeys[$_]) } |
    ForEach-Object {
        $apiKeyID = $_
        $envVarName = $apiKeys[$apiKeyID]
        Write-Verbose ('Adding API key "{0}" with value from environment variable "{1}".' -f $apiKeyID,$envVarName)
        Add-WhiskeyApiKey -Context $context -ID $apiKeyID -Value (Get-Item -Path ('env:{0}' -f $envVarName)).Value
    }
Invoke-WhiskeyBuild -Context $context @optionalArgs
