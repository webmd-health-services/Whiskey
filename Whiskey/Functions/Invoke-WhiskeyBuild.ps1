
function Invoke-WhiskeyBuild
{
    [CmdletBinding(DefaultParameterSetName='Build')]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context for the build. Use `New-WhiskeyContext` to create context objects.
        $Context,

        [Parameter(Mandatory=$true,ParameterSetName='Clean')]
        [Switch]
        $Clean,

        [Parameter(Mandatory=$true,ParameterSetName='Initialize')]
        [Switch]
        $Initialize
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Set-WhiskeyBuildStatus -Context $Context -Status Started

    $succeeded = $false
    Push-Location -Path $Context.BuildRoot
    try
    {
        Write-Verbose -Message ('Building version {0}' -f $Context.Version.SemVer2)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.SemVer2NoBuildMetadata)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.Version)
        Write-Verbose -Message ('                 {0}' -f $Context.Version.SemVer1)

        $Context.RunMode = $PSCmdlet.ParameterSetName
            
        Invoke-WhiskeyPipeline -Context $Context -Name 'BuildTasks'

        $config = $Context.Configuration
        if( $Context.Publish -and $config.ContainsKey('PublishTasks') )
        {
            Invoke-WhiskeyPipeline -Context $Context -Name 'PublishTasks'
        }

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
    }
}

