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
        $Clean
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
        
        $nunitRoot = Install-WhsCITool -NuGetPackageName $package -Version $version
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

        $extraArgs = $TaskParameter['Options'] | Where-Object { $_ }
        $separator = '{0}VERBOSE:               ' -f [Environment]::NewLine
        Write-Verbose -Message ('  Paths       {0}' -f ($Path -join $separator))
        Write-Verbose -Message ('  Framework   {0}' -f $frameworkParam)
        Write-Verbose -Message ('  Include     {0}' -f $includeParam)
        Write-Verbose -Message ('  Exclude     {0}' -f $excludeParam)
        Write-Verbose -Message ('  Arguments   {0}' -f ($extraArgs -join $separator))
        Write-Verbose -Message ('              /xml={0}' -f $reportPath)
        & $nunitConsolePath $Path $frameworkParam $includeParam $excludeParam $extraArgs ('/xml={0}' -f $reportPath) 
        if( $LastExitCode )
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('NUnit2 tests failed. {0} returned exit code {1}.' -f $nunitConsolePath,$LastExitCode)
        }
    }

}