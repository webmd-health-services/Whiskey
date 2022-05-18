
function Restore-WhiskeyNuGetPackage
{
    [CmdletBinding()]
    [Whiskey.TaskAttribute('NuGetRestore', Platform='Windows')]
    [Whiskey.RequiresNuGetPackage('NuGet.CommandLine', Version='6.*', PathParameterName='NuGetPath')]
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
