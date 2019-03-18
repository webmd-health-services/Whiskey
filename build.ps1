[CmdletBinding(DefaultParameterSetName='Build')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Clean')]
    [Switch]
    # Runs the build in clean mode, which removes any files, tools, packages created by previous builds.
    $Clean,

    [Parameter(Mandatory=$true,ParameterSetName='Initialize')]
    [Switch]
    # Initializes the repository.
    $Initialize,

    [string]
    $PipelineName,

    [string]
    $MSBuildConfiguration = 'Debug'
)

$ErrorActionPreference = 'Stop'
#Requires -Version 4
Set-StrictMode -Version Latest

# We can't use Whiskey to build Whiskey's assembly because we need Whiskey's assembly to use Whiskey.
$manifest = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Whiskey.psd1') -Raw
if( $manifest -notmatch '\bModuleVersion\b\s*=\s*(''|")([^''"]+)' )
{
    Write-Error -Message 'Unable to find the module version in the Whiskey manifest.'
}
$version = $Matches[2]

$buildInfo = ''
if( Test-Path -Path ('env:APPVEYOR') )
{
    $commitID = $env:APPVEYOR_REPO_COMMIT
    $commitID = $commitID.Substring(0,7)

    $branch = $env:APPVEYOR_REPO_BRANCH
    $branch = $branch -replace '[^A-Za-z0-9-]','-'

    $buildInfo = '+{0}.{1}.{2}' -f $env:APPVEYOR_BUILD_NUMBER,$branch,$commitID
    $MSBuildConfiguration = 'Release'

    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = 'true'
}

$minDotNetVersion = [version]'2.1.503'
$dotnetVersion = $null
$dotnetInstallDir = Join-Path -Path $PSScriptRoot -ChildPath '.dotnet'
$dotnetExeName = 'dotnet.exe'
if( -not (Get-Variable 'IsLinux' -ErrorAction SilentlyContinue) ) 
{
    $IsLinux = $false
    $IsMacOS = $false
    $IsWindows = $true
}
if( -not $IsWindows )
{
    $dotnetExeName = 'dotnet'
}
$dotnetPath = Join-Path -Path $dotnetInstallDir -ChildPath $dotnetExeName

if( (Test-Path -Path $dotnetPath -PathType Leaf) )
{
    $dotnetVersion = & $dotnetPath --version | ForEach-Object { [version]$_ }
    Write-Verbose ('dotnet {0} installed in {1}.' -f $dotnetVersion,$dotnetInstallDir)
}

if( -not $dotnetVersion -or $dotnetVersion -lt $minDotNetVersion )
{
    $dotnetInstallPath = Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\bin\dotnet-install.sh'
    if( $IsWindows )
    {
        $dotnetInstallPath = Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\bin\dotnet-install.ps1'
    }

    Write-Verbose -Message ('{0} -Version {1} -InstallDir "{2}" -NoPath' -f $dotnetInstallPath,$minDotNetVersion,$dotnetInstallDir)
    if( $IsWindows )
    {
        & $dotnetInstallPath -Version $minDotNetVersion -InstallDir $dotnetInstallDir -NoPath
    }
    else 
    {
        if( -not (Get-Command -Name 'curl' -ErrorAction SilentlyContinue) )
        {
            Write-Error -Message ('Curl is required to install .NET Core. Please install it with this platform''s (or your) preferred package manager.')
            exit 1
        }
        bash $dotnetInstallPath -Version $minDotNetVersion -InstallDir $dotnetInstallDir -NoPath
    }

    if( -not (Test-Path -Path $dotnetPath -PathType Leaf) )
    {
        Write-Error -Message ('.NET Core {0} didn''t get installed to "{1}".' -f $minDotNetVersion,$dotnetPath)
        exit 1
    }
}

Push-Location -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assembly')
try
{
    $outputDirectory = Join-Path -Path $PSScriptRoot -ChildPath '.output'
    if( -not (Test-Path -Path $outputDirectory -PathType Container) )
    {
        New-Item -Path $outputDirectory -ItemType 'Directory'
    }

    $params = & {
                            '/p:Version={0}{1}' -f $version,$buildInfo
                            '/p:VersionPrefix={0}' -f $version
                            if( $buildInfo )
                            {
                                '/p:VersionSuffix={0}' -f $buildInfo
                            }
                            if( $VerbosePreference -eq 'Continue' )
                            {
                                '--verbosity=n'
                            }
                            '/filelogger9'
                            ('/flp9:LogFile={0};Verbosity=d' -f (Join-Path -Path $outputDirectory -ChildPath 'msbuild.whiskey.log'))
                    }
    Write-Verbose ('{0} build --configuration={1} {2}' -f $dotnetPath,$MSBuildConfiguration,($params -join ' '))
    & $dotnetPath build --configuration=$MSBuildConfiguration $params

    & $dotnetPath test --configuration=$MSBuildConfiguration --results-directory=$outputDirectory --logger=trx
    if( $LASTEXITCODE )
    {
        Write-Error -Message ('Unit tests failed.')
    }
}
finally
{
    Pop-Location
}

$whiskeyBinPath = Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\bin'
$whiskeyOutBinPath = Join-Path -Path $PSScriptRoot -ChildPath ('Assembly\Whiskey\bin\{0}\netstandard2.0' -f $MSBuildConfiguration)
foreach( $assembly in (Get-ChildItem -Path $whiskeyOutBinPath -Filter '*.dll') )
{
    $destinationPath = Join-Path -Path $whiskeyBinPath -ChildPath $assembly.Name
    if( (Test-Path -Path $destinationPath -PathType Leaf) )
    {
        $sourceHash = Get-FileHash -Path $assembly.FullName
        $destinationHash = Get-FileHash -Path $destinationPath
        if( $sourceHash.Hash -eq $destinationHash.Hash )
        {
            continue
        }
    }

    Copy-Item -Path $assembly.FullName -Destination $whiskeyBinPath
}

# TODO: Once https://github.com/PowerShell/PowerShellGet/issues/399 is 
# fixed, change version numbers to wildcards on the patch version.
$nestedModules = @{
                        'PackageManagement' = '1.3.1';
                        'PowerShellGet' = '2.1.2';
                 }
$whiskeyRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey'
foreach( $nestedModuleName in $nestedModules.Keys )
{
    $moduleRoot = Join-Path -Path $whiskeyRoot -ChildPath $nestedModuleName
    if( -not (Test-Path -Path $moduleRoot -PathType Container) )
    {
        $nestedModuleVersion = $nestedModules[$nestedModuleName]
        # Run in a background job otherwise the default global 
        # PackageManagement module assembly remains loaded.
        Start-Job -ScriptBlock {
            Save-Module -Name $using:nestedModuleName `
                        -RequiredVersion $using:nestedModuleVersion `
                        -Path $using:whiskeyRoot
        } | Wait-Job | Receive-Job | Remove-Job
    }
}

$ErrorActionPreference = 'Continue'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Whiskey\Import-Whiskey.ps1' -Resolve)

$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'whiskey.yml' -Resolve

Write-Verbose -Message '# VARIABLES'
Get-Variable | Format-Table | Out-String | Write-Verbose

Write-Verbose -Message '# ENVIRONMENT VARIABLES'
Get-ChildItem 'env:' |
    Where-Object { $_.Name -notin @( 'POWERSHELL_GALLERY_API_KEY', 'GITHUB_ACCESS_TOKEN' ) } |
    Format-Table |
    Out-String |
    Write-Verbose

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
                'PowerShellGallery' = 'POWERSHELL_GALLERY_API_KEY'
                'github.com' = 'GITHUB_ACCESS_TOKEN'
            }

$apiKeys.Keys |
    Where-Object { Test-Path -Path ('env:{0}' -f $apiKeys[$_]) } |
    ForEach-Object {
        $apiKeyID = $_
        $envVarName = $apiKeys[$apiKeyID]
        Write-Verbose ('Adding API key "{0}" with value from environment variable "{1}".' -f $apiKeyID,$envVarName)
        Add-WhiskeyApiKey -Context $context -ID $apiKeyID -Value (Get-Item -Path ('env:{0}' -f $envVarName)).Value
    }
Invoke-WhiskeyBuild -Context $context @optionalArgs
