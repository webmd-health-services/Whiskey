
[CmdletBinding()]
param(
)

$originalVerbosePreference = $Global:VerbosePreference

$timer = New-Object 'Diagnostics.Stopwatch'
$timer.Start()

function Write-Timing
{
    param(
        $Message
    )

    $DebugPreference = 'Continue'
    Write-Debug -Message ('[{0:hh":"mm":"ss"."ff}]  {1}' -f $timer.Elapsed,$Message)
}

function Test-Import
{
    param(
        [string]$Name
    )

    $module = Get-Module -Name $Name -ErrorAction Ignore
    if( -not $module )
    {
        Write-Timing ('Module "{0}" not loaded.' -f $Name)
        return $true
    }

    if( (Test-Path -Path 'env:APPVEYOR') )
    {
        return $false
    }

    if( -not ($module | Get-Member 'ImportedAt') )
    {
        Write-Timing ('Module "{0}" not loaded by WhiskeyTest.' -f $Name)
        return $true
    }

    $moduleRoot = $module.Path
    if( $module.Name -ne 'WhiskeyTest' )
    {
        $moduleRoot = $module.Path | Split-Path
    }

    Write-Timing ('Testing "{0}" for changes.' -f $moduleRoot)
    $filesChanged = 
        & {
            if( (Test-Path -Path $moduleRoot -PathType Leaf) )
            {
                Get-Item -Path $moduleRoot
            }
            else
            {
                Get-ChildItem -Path $moduleRoot -File -Recurse
            }
        } |
        Where-Object { $module.ImportedAt -lt $_.LastWriteTime } 

    if( $filesChanged )
    {
        Write-Timing ('Found {0} file(s) modified after "{1}" was last imported.' -f ($filesChanged | Measure-Object).Count, $Name)
        return $true
    }

    return $false
}

try
{
    $Global:VerbosePreference = 'SilentlyContinue'

    Write-Timing ('Initialize-WhiskeyTest.ps1')
    # Some tests load ProGetAutomation from a Pester test drive. Forcibly remove the module if it is loaded to avoid errors.

    if( Test-Import -Name 'Whiskey' )
    {
        Write-Timing ('    Importing Whiskey')
        & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1' -Resolve)
    }

    if( Test-Import -Name 'WhiskeyTest' )
    {
        Write-Timing ('    Importing WhiskeyTest')
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhiskeyTest.psm1') -Force 
    }

    # We load these because they have assemblies and we need to make sure they get loaded from the global location,
    # otherwise Pester can't delete the test drive (module assemblies are locked) and tests fail.
    foreach( $name in @( 'PackageManagement', 'PowerShellGet' ) )
    {
        if( -not (Test-Import -Name $name) )
        {
            continue
        }

        if( (Get-Module -Name $name) )
        {
            Write-Timing ('    Removing {0}' -f $name)
            Remove-Module -Name $name -Force 
        }

        Write-Timing ('    Importing {0}' -f $name)
        Import-WhiskeyTestModule -Name $name -Force
    }

    foreach( $name in @('Whiskey','WhiskeyTest','PackageManagement','PowerShellGet') )
    {
        Get-Module -Name $name |
            Add-Member -Name 'ImportedAt' -MemberType NoteProperty -Value (Get-Date) -Force
    }
}
finally
{
    Write-Timing ('Initialize-WhiskeyTest.ps1')
    $Global:VerbosePreference = $originalVerbosePreference
}