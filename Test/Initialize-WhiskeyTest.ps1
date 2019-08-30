
[CmdletBinding()]
param(
    [string[]]$ExportedPrivateCommand
)
$originalVerbosePreference = $Global:VerbosePreference

try
{
    $Global:VerbosePreference = 'SilentlyContinue'


    # Some tests load ProGetAutomation from a Pester test drive. Forcibly remove the module if it is loaded to avoid errors.
    if( (Get-Module -Name 'ProGetAutomation') )
    {
        Remove-Module -Name 'ProGetAutomation' -Force
    }

    if( (Test-Path -Path 'env:WHISKEY_EXPORTED_PRIVATE_COMMAND' ) )
    {
        Remove-Item -Path 'env:WHISKEY_EXPORTED_PRIVATE_COMMAND'
    }
    if( $ExportedPrivateCommand )
    {
        $env:WHISKEY_EXPORTED_PRIVATE_COMMAND = $ExportedPrivateCommand -join ','
    }
    & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Import-Whiskey.ps1' -Resolve)

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\BuildMasterAutomation' -Resolve) -Force
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\ProGetAutomation' -Resolve) -Force

    foreach( $name in @( 'PackageManagement', 'PowerShellGet' ) )
    {
        if( (Get-Module -Name $name) )
        {
            Remove-Module -Name $name -Force
        }

        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath ('..\Whiskey\Modules\{0}' -f $name) -Resolve) -Force
    }

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhiskeyTest.psm1') -Force
}
finally
{
    $Global:VerbosePreference = $originalVerbosePreference
}