function Invoke-WhiskeyNUnit2Task
{
    [Whiskey.Task('NUnit2', Platform='Windows')]
    [Whiskey.RequiresNuGetPackage('NUnit.Runners', Version='2.*', PathParameterName='NUnitPath')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        [Parameter(Mandatory)]
        [hashtable] $TaskParameter,

        # TODO: Once this task uses NuGet tool provider, make this Mandatory and remove the test that Path has a value.
        [Whiskey.Tasks.ValidatePath(AllowNonexistent, PathType='File')]
        [String[]]$Path,

        [String] $NUnitPath
    )

    Set-StrictMode -version 'latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $includeParam = $null
    if( $TaskParameter.ContainsKey('Include') )
    {
        $includeParam = '/include={0}' -f $TaskParameter['Include'].Trim('"')
    }

    $excludeParam = $null
    if( $TaskParameter.ContainsKey('Exclude') )
    {
        $excludeParam = '/exclude={0}' -f $TaskParameter['Exclude'].Trim('"')
    }

    $frameworkParam = '4.0'
    if( $TaskParameter.ContainsKey('Framework') )
    {
        $frameworkParam = $TaskParameter['Framework']
    }
    $frameworkParam = '/framework={0}' -f $frameworkParam

    $nunitToolsRoot = Join-Path -Path $NUnitPath -ChildPath 'tools'
    $nunitConsolePath = Join-Path -Path $nunitToolsRoot -ChildPath 'nunit-console.exe'
    if( -not (Test-Path -Path $nunitConsolePath) )
    {
        $msg = "NUnit doesn't exist at ""$($nunitConsolePath)""."
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if( -not $Path )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Path" is mandatory. It should be one or more paths, which should be a list of assemblies whose tests to run, e.g.

        Build:
        - NUnit2:
            Path:
            - Assembly.dll
            - OtherAssembly.dll')
        return
    }

    $missingPaths = $Path | Where-Object { -not (Test-Path -Path $_ -PathType Leaf) }
    if( $missingPaths )
    {
        $missingPaths = $missingPaths -join ('{0}*' -f [Environment]::NewLine)
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('The following paths do not exist.{0} {0}*{1}{0} ' -f [Environment]::NewLine,$missingPaths)
        return
    }

    $reportPath = Join-Path -Path ($TaskContext.OutputDirectory | Resolve-Path -Relative) `
                            -ChildPath ('nunit2+{0}.xml' -f [IO.Path]::GetRandomFileName())

    $extraArgs = $TaskParameter['Argument'] | Where-Object { $_ }

    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Path                {0}' -f ($Path | Select-Object -First 1))
    $Path | Select-Object -Skip 1 | ForEach-Object { Write-WhiskeyVerbose -Context $TaskContext -Message ('                      {0}' -f $_) }
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Framework           {0}' -f $frameworkParam)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Include             {0}' -f $includeParam)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Exclude             {0}' -f $excludeParam)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Argument            /xml={0}' -f $reportPath)
    $extraArgs | ForEach-Object { Write-WhiskeyVerbose -Context $TaskContext -Message ('                      {0}' -f $_) }

    Write-WhiskeyDebug -Context $TaskContext -Message ('Running NUnit')
    Write-WhiskeyCommand -Path $nunitConsolePath `
                         -ArgumentList $Path,$frameworkParam,$includeParam,$excludeParam,$extraArgs,"/xml=${reportPath}"
    & $nunitConsolePath $Path $frameworkParam $includeParam $excludeParam $extraArgs ('/xml={0}' -f $reportPath)
    Write-WhiskeyVerbose -Message "$($nunitConsolePath | Resolve-Path -Relative) exited with code $($LastExitCode)."
    if( $LastExitCode )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NUnit2 tests failed. {0} returned exit code {1}.' -f $nunitConsolePath,$LastExitCode)
        return
    }
}
