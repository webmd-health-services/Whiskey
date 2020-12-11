function Test-GlobalPowershellModule
{
    <#
    .SYNOPSIS
    Checks if a module is installed globally.
     
    .DESCRIPTION
    The `Test-GlobalPowerShellModule` function tests if a module is installed globally. If the module is installed globally, it returns true. Otherwise it returns false.
     
    .EXAMPLE
    Test-GlobalPowerShellModule -Name 'Pester'

    Demonstrates checking if any version of the Pester module is installed globally.

    .EXAMPLE
    Test-GlobalPowerShellModule -Name 'Pester' -Version '4.3.0'

    Demonstrates checking if a specific version of a module is installed globally.

    .EXAMPLE
    Test-GlobalPowerShellModule -Name 'Pester' -Version '4.*'

    Demonstrates that you can use a wildcard to check if a major version of a module is installed globally.
    #>
    [CmdletBinding()]
    #[OutputType([Object])]
    param(
        [Parameter(Mandatory)]
        # The name of the module to check if installed globally.
        [String]$Name,

        # The version of the module to check if installed globally.
        [String]$Version
    )
 
    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $installedModules = Get-Module -Name $Name -ListAvailable -ErrorAction Ignore
    if(-Not $Version)
    { 
        $Version = '*'
    }

    foreach ($module in $installedModules) 
    {
        if( $module.Version -like $Version)
        {
            return [PSCustomObject]@{
                Found = $true;
                Path = $module.Path;
            }
        }
    }

    return [PSCustomObject]@{
        Found = $false;
        Path = $null;
    }
}