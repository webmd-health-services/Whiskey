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
        Set-StrictMode -version 'latest'        
        $package = 'NUnit.Runners'
        $version = '2.6.4'

        $nunitRoot = Install-WhsCITool -NuGetPackageName $package -Version $version
        if( -not (Test-Path -Path $nunitRoot -PathType Container) )
        {
            #Write-Error -Message ('Failed to install {0} {1}!' -f $package,$version)
            throw ('Package {0} {1} failed to install!' -f $package,$version)
        }
        $nunitRoot = Get-Item -Path $nunitRoot | Select-Object -First 1
        $nunitRoot = Join-Path -Path $nunitRoot -ChildPath 'tools'
        $nunitConsolePath = Join-Path -Path $nunitRoot -ChildPath 'nunit-console.exe' -Resolve

        & $nunitConsolePath $Path /noshadow /framework=4.0 /domain=Single /labels ('/xml={0}' -f $ReportPath)
        if( $LastExitCode )
        {
            throw ('NUnit2 tests failed. {0} returned exit code {1}.' -f $nunitConsolePath,$LastExitCode)
        }
    }

}