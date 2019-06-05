
function Restore-WhiskeyNuGetPackage
{
    [CmdletBinding()]
    [Whiskey.TaskAttribute("NuGetRestore",Platform='Windows')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Tasks.ValidatePath(Mandatory)]
        [string[]]
        $Path,

        [string[]]
        $Argument,

        [string]
        $Version,

        [Whiskey.Tasks.ParameterValueFromVariable('WHISKEY_BUILD_ROOT')]
        [IO.DirectoryInfo]
        $BuildRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $nuGetPath = Install-WhiskeyNuGet -DownloadRoot $BuildRoot -Version $Version

    foreach( $item in $Path )
    {
        & $nuGetPath 'restore' $item $Argument
    }
}
