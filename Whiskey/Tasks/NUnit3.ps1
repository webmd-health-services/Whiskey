
function Invoke-WhiskeyNUnit3Task
{
    [CmdletBinding()]
    [Whiskey.Task('NUnit3', Platform='Windows')]
    [Whiskey.RequiresNuGetPackage('NUnit.Console', Version='3.*')]
    [Whiskey.RequiresNuGetPackage('NUnit.ConsoleRunner', Version='3.*', PathParameterName='NUnitPath')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        [Parameter(Mandatory)]
        [hashtable] $TaskParameter,

        # TODO: Once this task uses NuGet tool provider, make this Mandatory and remove the test that Path has a value.
        [Whiskey.Tasks.ValidatePath(AllowNonexistent, PathType='File')]
        [String[]] $Path,

        [String] $NUnitPath,

        [String] $OpenCoverPath,

        [String] $ReportGeneratorPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $reportFormat = 'nunit3';
    if ($TaskParameter['ResultFormat'])
    {
        $reportFormat = $TaskParameter['ResultFormat']
    }

    # NUnit3 currently allows 'nunit2' and 'nunit3' which aligns with output filename usage
    $nunitReport = Join-Path -Path ($TaskContext.OutputDirectory | Resolve-Path -Relative) `
                             -ChildPath ('{0}+{1}.xml' -f  $reportFormat, [IO.Path]::GetRandomFileName())
    $nunitReportParam = '--result={0};format={1}' -f $nunitReport, $reportFormat


    $framework = 'net-4.0'
    if ($TaskParameter['Framework'])
    {
        $framework = $TaskParameter['Framework']
    }
    $frameworkParam = '--framework={0}' -f $framework

    $testFilter = ''
    $testFilterParam = $null
    if ($TaskParameter['TestFilter'])
    {
        $testFilter = $TaskParameter['TestFilter'] | ForEach-Object { '({0})' -f $_ }
        $testFilter = $testFilter -join ' or '
        $testFilterParam = '--where={0}' -f $testFilter
    }

    $nunitExtraArgument = $null
    if ($TaskParameter['Argument'])
    {
        $nunitExtraArgument = $TaskParameter['Argument']
    }

    $nunitConsolePath =
        Get-ChildItem -Path $nunitPath -Filter 'nunit3-console.exe' -Recurse |
        Select-Object -First 1 |
        Select-Object -ExpandProperty 'FullName'

    if( -not $nunitConsolePath )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Unable to find "nunit3-console.exe" in NUnit3 NuGet package at "{0}".' -f $nunitPath)
        return
    }

    if( -not $Path )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Path" is mandatory. It should be one or more paths to the assemblies whose tests should be run, e.g.

            Build:
            - NUnit3:
                Path:
                - Assembly.dll
                - OtherAssembly.dll

        ')
        return
    }

    foreach( $pathItem in $Path )
    {
        if (-not (Test-Path -Path $pathItem -PathType Leaf))
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('"Path" item "{0}" does not exist.' -f $pathItem)
            return
        }
    }

    $separator = '{0}VERBOSE:                       ' -f [Environment]::NewLine
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Path                {0}' -f ($Path -join $separator))
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Framework           {0}' -f $framework)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  TestFilter          {0}' -f $testFilter)
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Argument            {0}' -f ($nunitExtraArgument -join $separator))
    Write-WhiskeyVerbose -Context $TaskContext -Message ('  NUnit Report        {0}' -f $nunitReport)

    $nunitExitCode = 0

    Write-WhiskeyCommand -Path $nunitConsolePath `
                         -ArgumentList $Path, $frameworkParam, $testFilterParam, $nunitReportParam, $nunitExtraArgument
    & $nunitConsolePath $Path $frameworkParam $testFilterParam $nunitReportParam $nunitExtraArgument
    $nunitExitCode = $LASTEXITCODE
    if( $nunitExitCode -ne 0 )
    {
        if (-not (Test-Path -Path $nunitReport -PathType Leaf))
        {
            $msg = "NUnit didn't run successfully: NUnit returned exit code ""$($nunitExitCode)""."
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
            return
        }
        else
        {
            $msg = "NUnit tests failed: NUnit returned exit code ""$($nunitExitCode)""."
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
            return
        }
    }
}
