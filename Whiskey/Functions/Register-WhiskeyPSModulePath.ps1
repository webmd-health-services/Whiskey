
function Register-WhiskeyPSModulePath
{
    # If there are older versions of the PackageManagement and/or PowerShellGet
    # modules available on this system, the modules that ship with Whiskey will use
    # those global versions instead of the versions we load from inside Whiskey. So,
    # we have to put the ones that ship with Whiskey first. See
    # https://github.com/PowerShell/PowerShellGet/issues/55 .

    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ParameterSetName='FromUser')]
        [String]$Path,

        [Parameter(Mandatory,ParameterSetName='FromWhiskey')]
        [String]$PSModulesRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    if( $PSCmdlet.ParameterSetName -eq 'FromWhiskey' )
    {
        $Path = Get-WhiskeyPSModulePath -PSModulesRoot $PSModulesRoot
    }

    $pathBefore = $env:PSModulePath -split [IO.Path]::PathSeparator
    try
    {
        if( $pathBefore -contains $Path )
        {
            return
        }

        $env:PSModulePath = $Path,$env:PSModulePath -join [IO.Path]::PathSeparator
    }
    finally
    {
        Write-WhiskeyDebug "[Register-WhiskeyPSModulePath]  Changes to PSModulePath:"
        $pathNow = $env:PSModulePath -split [IO.Path]::PathSeparator
        $diff = Compare-Object -ReferenceObject $pathBefore -DifferenceObject $pathNow -IncludeEqual
        if( $diff )
        {
            $diff | Format-Table -AutoSize | Out-String | Write-WhiskeyDebug
        }
    }
}