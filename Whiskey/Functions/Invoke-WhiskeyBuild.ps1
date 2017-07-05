
function Invoke-WhiskeyBuild
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context for the build. Use `New-WhiskeyContext` to create context objects.
        $Context,

        [Switch]
        $Clean
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Set-WhiskeyBuildStatus -Context $Context -Status Started

    $succeeded = $false
    Push-Location -Path $Context.BuildRoot
    try
    {
        $nugetPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\NuGet.exe' -Resolve

        Write-Verbose -Message ('Building version {0}' -f $Context.Version.SemVer2)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.SemVer2NoBuildMetadata)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.Version)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.SemVer1)

        $config = $Context.Configuration

        Invoke-WhiskeyPipeline -Context $Context -Name 'BuildTasks'
        New-WhiskeyBuildMasterPackage -TaskContext $Context

        $succeeded = $true
    }
    finally
    {
        if( $Clean )
        {
            Remove-Item -path $Context.OutputDirectory -Recurse -Force | Out-String | Write-Verbose
        }
        Pop-Location

        $status = 'Failed'
        if( $succeeded )
        {
            $status = 'Completed'
        }
        Set-WhiskeyBuildStatus -Context $Context -Status $status

        if( $Context.ByBuildServer -and $succeeded )
        {
            Publish-WhiskeyTag -TaskContext $Context 
        }

    }
}

