function Resolve-WhiskeyNuGetPackageVersion
{
    [CmdletBinding()]
    param(

        [Parameter(Mandatory)]
        # The name of the NuGet package to download.
        [String]$NuGetPackageName,

        # The version of the package to download. Must be a three part number, i.e. it must have a MAJOR, MINOR, and BUILD number.
        [String]$Version,

        [String]$NugetPath = ($whiskeyNuGetExePath)
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $Version )
    {
        Set-Item -Path 'env:EnableNuGetPackageRestore' -Value 'true'
        $NuGetPackage = Invoke-Command -NoNewScope -ScriptBlock {
            & $NugetPath list ('packageid:{0}' -f $NuGetPackageName)
        }
        $Version = $NuGetPackage |
            Where-Object { $_ -match $NuGetPackageName } |
            Where-Object { $_ -match ' (\d+\.\d+\.\d+.*)' } |
            ForEach-Object { $Matches[1] } |
            Select-Object -First 1

        if( -not $Version )
        {
            Write-WhiskeyError -Message ("Unable to find latest version of package '{0}'." -f $NuGetPackageName)
            return
        }
    }
    elseif( [Management.Automation.WildcardPattern]::ContainsWildcardCharacters($version) )
    {
        Write-WhiskeyError -Message "Wildcards are not allowed for NuGet packages yet because of a bug in the nuget.org search API (https://github.com/NuGet/NuGetGallery/issues/3274)."
        return
    }
    return $Version
}
