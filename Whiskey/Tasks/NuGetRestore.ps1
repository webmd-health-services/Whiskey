
function Restore-WhiskeyNuGetPackage
{
    [CmdletBinding()]
    [Whiskey.Task('NuGetRestore', Platform='Windows', Obsolete,
        ObsoleteMessage='The "NuGetRestore" task is obsolete. It will be removed in a future version of Whiskey. Please use "nuget" commands instead.')]
    [Whiskey.RequiresNuGetPackage('NuGet.CommandLine', Version='6.14.*', PathParameterName='NuGetPath')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Tasks.ValidatePath(Mandatory)]
        [String[]] $Path,

        [String[]] $Argument,

        [String] $Version,

        [String] $NuGetPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $NuGetPath = Join-Path -Path $NuGetPath -ChildPath 'tools\NuGet.exe' -Resolve
    if( -not $NuGetPath )
    {
        Stop-WhiskeyTask -Context $TaskContext -Message "NuGet.exe not found at ""$($NuGetPath)""."
        return
    }

    foreach( $item in $Path )
    {
        & $nuGetPath 'restore' $item $Argument
    }
}
