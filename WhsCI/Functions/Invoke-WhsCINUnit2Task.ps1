function Invoke-WhsCINUnit2Task
{
    <#
    .SYNOPSIS
    Invoke-WhsCINUnit2Task runs NUnit tests.

    .DESCRIPTION
    The NUnit2 task runs NUnit tests. The latest version of NUnit 2 is downloaded from nuget.org for you (into `$env:LOCALAPPDATA\WebMD Health Services\WhsCI\packages`).

    The task should pass the paths to the assemblies to test within the `TaskParameter.Path` parameter.
        
    The build will fail if any of the tests fail (i.e. if the NUnit console returns a non-zero exit code).

    You *must* include paths to build with the `Path` parameter.

    .EXAMPLE
    Invoke-WhsCINUnit2Task -TaskContext $TaskContext -TaskParameter $taskParameter

    Demonstates how to run the NUnit tests in some assemblies and save the result to a specific file. 
    In this example, the assemblies to run are in `$TaskParameter.path` and the test report will be saved in an xml file relative to the indicated `$TaskContext.OutputDirectory` 
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter,

        [Switch]
        $Clean,

        [Version]
        $OpenCoverVersion,

        [Version]
        $ReportGeneratorVersion,

        [Switch]
        $DisableCodeCoverage,

        [String[]]
        $CoverageFilter
     )    
  
    Process
    {
        if( $Clean )
        {
            return
        }
          
        Set-StrictMode -version 'latest'        
        $package = 'NUnit.Runners'
        $version = '2.6.4'
        # Be sure that the Taskparameter contains a 'Path'.
        if( -not ($TaskParameter.ContainsKey('Path')))
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should be one or more paths, which should be a list of assemblies whose tests to run, e.g. 
        
            BuildTasks:
            - NUnit2:
                Path:
                - Assembly.dll
                - OtherAssembly.dll')
        }

        $path = $TaskParameter['Path'] | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'Path'
        $reportPath = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('nunit2-{0:00}.xml' -f $TaskContext.TaskIndex)

        $includeParam = $null
        if( $TaskParameter.ContainsKey('Include') )
        {
            $includeParam = '/include={0}' -f ($TaskParameter['Include'] -join ',')
        }
        
        $excludeParam = $null
        if( $TaskParameter.ContainsKey('Exclude') )
        {
            $excludeParam = '/exclude={0}' -f ($TaskParameter['Exclude'] -join ',')
        }

        $frameworkParam = '4.0'
        if( $TaskParameter.ContainsKey('Framework') )
        {
            $frameworkParam = $TaskParameter['Framework']
        }
        $frameworkParam = '/framework={0}' -f $frameworkParam
      
        $nunitRoot = Install-WhsCITool -NuGetPackageName $package -Version $version -DownloadRoot $TaskContext.BuildRoot
        if( -not (Test-Path -Path $nunitRoot -PathType Container) )
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('Package {0} {1} failed to install!' -f $package,$version)
        }
        $nunitRoot = Get-Item -Path $nunitRoot | Select-Object -First 1
        $nunitRoot = Join-Path -Path $nunitRoot -ChildPath 'tools'
        $nunitConsolePath = Join-Path -Path $nunitRoot -ChildPath 'nunit-console.exe' -Resolve
        if( -not ($nunitConsolePath))
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('{0} {1} was installed, but couldn''t find nunit-console.exe at ''{2}''.' -f $package,$version,$nunitConsolePath)
        }

        $optionalArgs = @{}
        
        if( $OpenCoverVersion )
        {
            $optionalArgs['Version'] = $OpenCoverVersion
        }
        $openCoverPath = Install-WhsCITool -NuGetPackageName 'OpenCover' -DownloadRoot $TaskContext.BuildRoot @optionalArgs
        if( -not (Test-Path -Path $openCoverPath -PathType Container))
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('{0} {1} was installed, but couldn''t find nunit-console.exe at ''{2}''.' -f $package,$version,$nunitConsolePath)
        }
        $openCoverPath = Join-Path -Path $openCoverPath -ChildPath 'tools'
        $openCoverConsolePath = Join-Path -Path $openCoverPath -ChildPath 'OpenCover.Console.exe' -Resolve

        $optionalArgs.clear()
        if( $ReportGeneratorVersion )
        {
            $optionalArgs['Version'] = $ReportGeneratorVersion
        }
        $reportGeneratorPath = Install-WhsCITool -NuGetPackageName 'ReportGenerator' -DownloadRoot $TaskContext.BuildRoot @optionalArgs
        if( -not (Test-Path -Path $reportGeneratorPath -PathType Container))
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('{0} {1} was installed, but couldn''t find nunit-console.exe at ''{2}''.' -f $package,$version,$nunitConsolePath)
        }
        $reportGeneratorPath = Join-Path -Path $reportGeneratorPath -ChildPath 'tools'
        $reportGeneratorConsolePath = Join-Path -Path $reportGeneratorPath -ChildPath 'ReportGenerator.exe' -Resolve

        $coverageReportDir = Join-Path -Path $TaskContext.outputDirectory -ChildPath "opencover"
        New-Item -Path $coverageReportDir -ItemType 'Directory' -Force | Out-Null
        $openCoverReport = Join-Path -Path $coverageReportDir -ChildPath 'openCover.xml'

        $extraArgs = $TaskParameter['Argument'] | Where-Object { $_ }
        $separator = '{0}VERBOSE:               ' -f [Environment]::NewLine
        Write-Verbose -Message ('  Path        {0}' -f ($Path -join $separator))
        Write-Verbose -Message ('  Framework   {0}' -f $frameworkParam)
        Write-Verbose -Message ('  Include     {0}' -f $includeParam)
        Write-Verbose -Message ('  Exclude     {0}' -f $excludeParam)
        Write-Verbose -Message ('  Argument    {0}' -f ($extraArgs -join $separator))
        Write-Verbose -Message ('              /xml={0}' -f $reportPath)
        Write-Verbose -Message ('  Filter      {0}' -f $CoverageFilter -join ' ')
        Write-Verbose -Message ('  Output     {0}' -f $openCoverReport)

        #$pathString = "\`"" + ($path -Join "\`" \`"") + "\`""   
        $pathString = ($path -join " ")
        $nunitArgs = "${pathString} /nologo /noshadow `"${frameworkParam}`" `"${includeParam}`" `"${excludeParam}`" /xml=`"${reportPath}/nunit-results.xml`""
        #$argString = $pathString = "\`"" + ($nunitArgs -Join "\`" \`"") + "\`"" 
        #$nunitArgs = "${pathString} /nologo /noshadow `"${frameworkParam}`" `"${includeParam}`" `"${excludeParam}`" `"${extraArgs}`" /xml=\`"${reportPath}/nunit-results.xml\`""
        #$nunitArgs = '${pathString} /nologo /noshadow ''${frameworkParam}'' ''${includeParam}'' ''${excludeParam}'' /xml=\''${reportPath}/nunit-results.xml\'''
        if( -not $DisableCodeCoverage )
        {
            #this works
            #& $openCoverConsolePath '-register:user' '-target:C:\Users\esmelser\Projects\whsci\Test\Assemblies\packages\NUnit.Runners.2.6.4\tools\nunit-console.exe' '-targetargs:C:\Users\esmelser\Projects\whsci\Test\Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll C:\Users\esmelser\Projects\whsci\Test\Assemblies\NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll /noshadow /framework=4.0' '-output:C:\Users\esmelser\Projects\whsci\Test\Assemblies\.output\opencover\openCover.xml' '-filter:' -returntargetcode
            & $openCoverConsolePath '-target:${nunitConsolePath}' '-targetargs:${nunitArgs}' ('-filter:{0}' -f $CoverageFilter -join ' ') '-register:user' '-output:${openCoverReport}' '-returntargetcode'
            & $reportGeneratorConsolePath "-reports:${openCoverReport}" "-targetdir:$coverageReportDir"
        }
        else
        {
            & $nunitConsolePath $path $frameworkParam $includeParam $excludeParam $extraArgs ('/xml={0}' -f $reportPath) 
        }
        if( $LastExitCode )
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('NUnit2 tests failed. {0} returned exit code {1}.' -f $nunitConsolePath,$LastExitCode)
        }
    }

}