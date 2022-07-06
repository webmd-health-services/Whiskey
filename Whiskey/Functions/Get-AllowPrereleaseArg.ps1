
function Get-AllowPrereleaseArg
{
    <#
    .SYNOPSIS
    Return a hashtable that can be splatted for a command that can or can't have an AllowPrerelease parameter.

    .DESCRIPTION
    Whiskey has to support older versions of PowerShellGet and PackageManagement. Some of these older versions don't
    have support for the `AllowPrerelease` switch and some of them have switches that function to allow prereleases, but
    the parameter name is different. This function determines if the function supports `AllowPrerelease` or not, and if
    it does *and* this function's `AllowPrerelease` switch is set, returns a hashtable with an `AllowPrerelease` key 
    (or whatever the parameter name is for that function) whose value is set to `$true`. Otherwise, it returns an empty
    hashtable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $CommandName,

        [switch] $AllowPrerelease
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $AllowPrerelease )
    {
        return @{}
    }

    $cmd = Get-Command -Name $CommandName -ParameterName 'AllowPrerelease*' -ErrorAction Ignore
    if( $cmd )
    {
        $allowPrereleaseArg = @{}
        $cmd.Parameters.Keys |
            Where-Object { $_ -like 'AllowPrerelease*' } |
            ForEach-Object { $allowPrereleaseArg[$cmd.Parameters[$_].Name] = $true }
        return $allowPrereleaseArg
    }

    return @{}
}