function Invoke-WhiskeyNUnit2Task
{
    <#
    .SYNOPSIS
    Invoke-WhiskeyNUnit2Task runs NUnit tests.

    .DESCRIPTION
    The NUnit2 task runs NUnit tests. The latest version of NUnit 2 is downloaded from nuget.org for you (into a `packages` directory in your build root).

    The task should pass the paths to the assemblies to test within the `TaskParameter.Path` parameter.
        
    The build will fail if any of the tests fail (i.e. if the NUnit console returns a non-zero exit code).

    You *must* include paths to build with the `Path` parameter.

    .EXAMPLE
    Invoke-WhiskeyNUnit2Task -TaskContext $TaskContext -TaskParameter $taskParameter

    Demonstates how to run the NUnit tests in some assemblies and save the result to a specific file. 
    In this example, the assemblies to run are in `$TaskParameter.path` and the test report will be saved in an xml file relative to the indicated `$TaskContext.OutputDirectory` 
    #>
    [Whiskey.Task("NUnit2",SupportsClean=$true)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
     )    
  
    Set-StrictMode -version 'latest'        
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
     
    $package = 'NUnit.Runners'
    $version = '2.6.4'
    $openCoverVersionArg  = @{}
    $reportGeneratorVersionArg = @{}
    if( $TaskParameter['OpenCoverVersion'] )
    {
        $openCoverVersionArg['Version'] = $TaskParameter['OpenCoverVersion']
    }
    if( $TaskParameter['ReportGeneratorVersion'] )
    {
        $reportGeneratorVersionArg['Version'] = $TaskParameter['ReportGeneratorVersion']
    }

    if( $TaskContext.ShouldClean() )
    {
        Uninstall-WhiskeyTool -NuGetPackageName 'ReportGenerator' -BuildRoot $TaskContext.BuildRoot @reportGeneratorVersionArg
        Uninstall-WhiskeyTool -NuGetPackageName 'OpenCover' -BuildRoot $TaskContext.BuildRoot @openCoverVersionArg
        Uninstall-WhiskeyTool -NuGetPackageName $package -BuildRoot $TaskContext.BuildRoot -Version $version                
        return
    }

    # Be sure that the Taskparameter contains a 'Path'.
    if( -not ($TaskParameter.ContainsKey('Path')))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should be one or more paths, which should be a list of assemblies whose tests to run, e.g. 
        
        BuildTasks:
        - NUnit2:
            Path:
            - Assembly.dll
            - OtherAssembly.dll')
    }

    $path = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
    $reportPath = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('nunit2-{0:00}.xml' -f $TaskContext.TaskIndex)

    $includeParam = $null
    if( $TaskParameter.ContainsKey('Include') )
    {
        $includeParam = '/include=\"{0}\"' -f ($TaskParameter['Include'] -join ',')
    }
        
    $excludeParam = $null
    if( $TaskParameter.ContainsKey('Exclude') )
    {
        $includeParam = '/exclude=\"{0}\"' -f ($TaskParameter['Exclude'] -join ',')
    }

    $frameworkParam = '4.0'
    if( $TaskParameter.ContainsKey('Framework') )
    {
        $frameworkParam = $TaskParameter['Framework']
    }
    $frameworkParam = '/framework={0}' -f $frameworkParam
      
    $nunitRoot = Install-WhiskeyTool -NuGetPackageName $package -Version $version -DownloadRoot $TaskContext.BuildRoot
    if( -not (Test-Path -Path $nunitRoot -PathType Container) )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Package {0} {1} failed to install!' -f $package,$version)
    }
    $nunitRoot = Get-Item -Path $nunitRoot | Select-Object -First 1
    $nunitRoot = Join-Path -Path $nunitRoot -ChildPath 'tools'
    $nunitConsolePath = Join-Path -Path $nunitRoot -ChildPath 'nunit-console.exe' -Resolve
    if( -not ($nunitConsolePath))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0} {1} was installed, but couldn''t find nunit-console.exe at ''{2}''.' -f $package,$version,$nunitConsolePath)
    }

    $openCoverPath = Install-WhiskeyTool -NuGetPackageName 'OpenCover' -DownloadRoot $TaskContext.BuildRoot @openCoverVersionArg
    if( -not (Test-Path -Path $openCoverPath -PathType Container))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0} {1} was installed, but couldn''t find nunit-console.exe at ''{2}''.' -f $package,$version,$nunitConsolePath)
    }
    $openCoverPath = Join-Path -Path $openCoverPath -ChildPath 'tools'
    $openCoverConsolePath = Join-Path -Path $openCoverPath -ChildPath 'OpenCover.Console.exe' -Resolve

    $reportGeneratorPath = Install-WhiskeyTool -NuGetPackageName 'ReportGenerator' -DownloadRoot $TaskContext.BuildRoot @reportGeneratorVersionArg
    if( -not (Test-Path -Path $reportGeneratorPath -PathType Container))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0} {1} was installed, but couldn''t find nunit-console.exe at ''{2}''.' -f $package,$version,$nunitConsolePath)
    }
    $reportGeneratorPath = Join-Path -Path $reportGeneratorPath -ChildPath 'tools'
    $reportGeneratorConsolePath = Join-Path -Path $reportGeneratorPath -ChildPath 'ReportGenerator.exe' -Resolve

    $coverageReportDir = Join-Path -Path $TaskContext.outputDirectory -ChildPath "opencover"
    New-Item -Path $coverageReportDir -ItemType 'Directory' -Force | Out-Null
    $openCoverReport = Join-Path -Path $coverageReportDir -ChildPath 'openCover.xml'

    $extraArgs = $TaskParameter['Argument'] | Where-Object { $_ }
    $separator = '{0}VERBOSE:               ' -f [Environment]::NewLine
    Write-Verbose -Message ('  Path                {0}' -f ($Path -join $separator))
    Write-Verbose -Message ('  Framework           {0}' -f $frameworkParam)
    Write-Verbose -Message ('  Include             {0}' -f $includeParam)
    Write-Verbose -Message ('  Exclude             {0}' -f $excludeParam)
    Write-Verbose -Message ('  Argument            {0}' -f ($extraArgs -join $separator))
    Write-Verbose -Message ('                      /xml={0}' -f $reportPath)
    Write-Verbose -Message ('  Filter              {0}' -f $TaskParameter['CoverageFilter'] -join ' ')
    Write-Verbose -Message ('  Output              {0}' -f $openCoverReport)
    Write-Verbose -Message ('  DisableCodeCoverage {0}' -f $TaskParameter['DisableCodeCoverage'])

    $pathString = ($path -join '\" \"')
    $extraArgString = ($extraArgs -join " ")
    $coverageFilterString = ($TaskParameter['CoverageFilter'] -join " ")
    $nunitArgs = "\""${pathString}\"" /noshadow ${frameworkParam} /xml=\`"${reportPath}\`" ${includeParam} ${excludeParam} ${extraArgString}"
    if( -not $TaskParameter['DisableCodeCoverage'] )
    {
        & $openCoverConsolePath "-target:${nunitConsolePath}" "-targetargs:${nunitArgs}" "-filter:${coverageFilterString}" '-register:user' "-output:${openCoverReport}" '-returntargetcode'
        $testsFailed = $LastExitCode;
        & $reportGeneratorConsolePath "-reports:${openCoverReport}" "-targetdir:$coverageReportDir"
        if( $LastExitCode -or $testsFailed )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NUnit2 tests failed. {0} returned exit code {1}.' -f $openCoverConsolePath,$LastExitCode)
        }
    }
    else
    {
        & $nunitConsolePath $path $frameworkParam $includeParam $excludeParam $extraArgs ('/xml={0}' -f $reportPath) 
        if( $LastExitCode )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NUnit2 tests failed. {0} returned exit code {1}.' -f $nunitConsolePath,$LastExitCode)
        }
    }
}
