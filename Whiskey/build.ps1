[CmdletBinding(DefaultParameterSetName='Build')]
param(
    [Parameter(Mandatory,ParameterSetName='Clean')]
    # Runs the build in clean mode, which removes any files, tools, packages created by previous builds.
    [Switch]$Clean,

    [Parameter(Mandatory,ParameterSetName='Initialize')]
    # Initializes the repository.
    [Switch]$Initialize
)

#Requires -Version 5.1
Set-StrictMode -Version Latest

# Set to a specific version to use a specific version of Whiskey. 
$whiskeyVersion = '0.*'

# Set to `$true` to use prerelease versions of Whiskey.
$allowPrerelease = $false

$psModulesRoot = Join-Path -Path $PSScriptRoot -ChildPath 'PSModules'
$whiskeyModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath 'PSModules\Whiskey'

if( -not (Test-Path -Path $whiskeyModuleRoot -PathType Container) )
{
    if( -not (Test-Path -Path $psModulesRoot -PathType Container) )
    {
        New-Item -Path $psModulesRoot -ItemType 'Directory' | Out-Null
    }

    $job = Start-Job -ScriptBlock {
        $VerbosePreference = $using:VerbosePreference
        $whiskey = 
            Find-Module -Name 'Whiskey' -AllowPrerelease:$using:allowPrerelease -AllVersions |
            Where-Object { $_.Version -like $using:whiskeyVersion } |
            Sort-Object -Property 'Version' -Descending |
            Select-Object -First 1

        if( -not $whiskey )
        {
            Write-Error -Message ('Whiskey matching version "{0}" does not exist.' -f $using:whiskeyVersion)
            return
        }

        Write-Verbose -Message ('Found Whiskey {0} in repository {1}.' -f $whiskey.ModuleVersion,$whiskey.Repository)
        Save-Module -Name 'Whiskey' `
                    -Path $using:psModulesRoot `
                    -RequiredVersion $whiskey.Version `
                    -Repository $whiskey.Repository
    } 
    $job | Wait-Job | Receive-Job -ErrorAction Stop
    $job | Remove-Job
}

& {
    $VerbosePreference = 'SilentlyContinue'
    Import-Module -Name $whiskeyModuleRoot -Force
}

$configPath = Join-Path -Path $PSScriptRoot -ChildPath 'whiskey.yml' 
if( -not (Test-Path -Path $configPath -PathType 'Leaf') )
{
    @'
Build:
- Version:
    Version: 0.0.0

Publish:

'@ | Set-Content -Path $configPath
}

$optionalArgs = @{ }
if( $Clean )
{
    $optionalArgs['Clean'] = $true
}

if( $Initialize )
{
    $optionalArgs['Initialize'] = $true
}

$context = New-WhiskeyContext -Environment 'Dev' -ConfigurationPath $configPath
Invoke-WhiskeyBuild -Context $context @optionalArgs
