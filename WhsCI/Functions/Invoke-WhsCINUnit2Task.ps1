function Invoke-WhsCINUnit2Task
{
    <#
    .SYNOPSIS
    Invoke-WhsCINUnit2Task runs NUnit tests.

    .DESCRIPTION
    The NUnit2 task runs NUnit tests. The latest version of NUnit 2 is downloaded from nuget.org for you (into `$env:LOCALAPPDATA\WebMD Health Services\WhsCI\packages`).

    The task should pass the paths to the assemblies to test to the Path parameter.
        
    The build will fail if any of the tests fail (i.e. if the NUnit console returns a non-zero exit code).

    .EXAMPLE
    Invoke-WhsCINunit2Task -Path 'C:\Projects\WhsCI\bin\WhsCI.Test.dll' -ReportPath 'C:\Projects\WhsCI\.output\nunit.xml'

    Demonstates how to run the NUnit tests in some assemblies and save the result to a specific file. 
    In this example, the assemblies to run are in 'C:\Projects\WhsCI\bin\WhsCI.Test.dll' and the test report will be saved to the file 'C:\Projects\WhsCI\.output\nunit.xml'. 
    #>
    [CmdletBinding()]
    param(
    [Parameter(Mandatory=$true)]
    [object]
    $TaskContext,
    
    [Parameter(Mandatory=$true)]
    [hashtable]
    $TaskParameter
 )
    <#
    param(
        [parameter(Mandatory=$true)]
        [string[]]
        # an array of taskpaths passed in from the Build function
        $Path,

        
        [Parameter(Mandatory=$true)]
        [string]
        # The directory where the test results will be saved.
        $ReportPath
    )
    
  
    Process
    {
    #>        
        Set-StrictMode -version 'latest'        
        $package = 'NUnit.Runners'
        $version = '2.6.4'
        # Make sure the Taskpath contains a Path parameter.
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
        #$reportPath = Join-path -Path $TaskContext.OutputDirectory -ChildPath 'NUnit.xml'

        $nunitRoot = Install-WhsCITool -NuGetPackageName $package -Version $version
        if( -not (Test-Path -Path $nunitRoot -PathType Container) )
        {
            throw ('Package {0} {1} failed to install!' -f $package,$version)
        }
        $nunitRoot = Get-Item -Path $nunitRoot | Select-Object -First 1
        $nunitRoot = Join-Path -Path $nunitRoot -ChildPath 'tools'
        $nunitConsolePath = Join-Path -Path $nunitRoot -ChildPath 'nunit-console.exe' -Resolve

        & $nunitConsolePath $Path /noshadow /framework=4.0 /domain=Single /labels ('/xml={0}' -f $reportPath) 
        <#
        $rptPath = ('/xml={0}' -f $ReportPath)
        $params = @( "$Path",'/noshadow','/framework=4.0','/domain=Single','/labels',"$rptPath")
        & $nunitConsolePath $params
        #>
        if( $LastExitCode )
        {
            throw ('NUnit2 tests failed. {0} returned exit code {1}.' -f $nunitConsolePath,$LastExitCode)
        }
    #}

}