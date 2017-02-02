function Invoke-WhsCINUnit2Task
{
    <#
    .SYNOPSIS
        Runs NUnit tests.

    .DESCRIPTION
        The NUnit2 task runs NUnit tests. The latest version of NUnit 2 is downloaded from nuget.org for you (into `$env:LOCALAPPDATA\WebMD Health Services\WhsCI\packages`).
        The task should have a `Path` list which should be a list of assemblies whose tests to run.
        The build will fail if any of the tests fail (i.e. if the NUnit console returns a non-zero exit code).

    
    .EXAMPLE
          
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true)]
        [string]
        # The place where downloaded tools should be saved. The default is `$env:LOCALAPPDATA\WebMD Health Services\WhsCI`.
        $DownloadRoot,

        [parameter(Mandatory=$true)]
        [string[]]
        # an array of taskpaths passed in from the Build function
        $Path,

        
        [Parameter(Mandatory=$true)]
        [string]
        # The directory where the test results will be saved.
        $ReportPath


    )
    Begin{
        
    }

    Process{
        
        Set-StrictMode -version 'latest'

        $packagesRoot = Join-Path -Path $DownloadRoot -ChildPath 'packages'
        $nunitRoot = Join-Path -Path $packagesRoot -ChildPath 'NUnit.Runners.2.6.4'
        if( -not (Test-Path -Path $nunitRoot -PathType Container) )
        {
           & $nugetPath install 'NUnit.Runners' -version '2.6.4' -OutputDirectory $packagesRoot
        }
        $nunitRoot = Get-Item -Path $nunitRoot | Select-Object -First 1
                        
        $nunitRoot = Join-Path -Path $nunitRoot -ChildPath 'tools'

        
        $nunitConsolePath = Join-Path -Path $nunitRoot -ChildPath 'nunit-console.exe' -Resolve

        $assemblyNames = $paths | ForEach-Object { $_ -replace ([regex]::Escape($root)),'.' }
        $testResultPath = Join-Path -Path $OutputDirectory -ChildPath ('nunit2-{0:00}.xml' -f $taskIdx)
        & $nunitConsolePath $assemblyNames /noshadow /framework=4.0 /domain=Single /labels ('/xml={0}' -f $testResultPath)
        if( $LastExitCode )
        {
            throw ('NUnit2 tests failed. {0} returned exit code {1}.' -f $nunitConsolePath,$LastExitCode)
        }

        <#
        #Code from Build.ps1 for reference.
 #goto packages root dir
        $packagesRoot = Join-Path -Path $DownloadRoot -ChildPath 'packages'
 #goto nunit root dir     
        $nunitRoot = Join-Path -Path $packagesRoot -ChildPath 'NUnit.Runners.2.6.4'
 #verify that the nunit root dir is a dir, else install nunit.runners
        if( -not (Test-Path -Path $nunitRoot -PathType Container) )
        {
           & $nugetPath install 'NUnit.Runners' -version '2.6.4' -OutputDirectory $packagesRoot
        }
 #get the first object in that dir?
        $nunitRoot = Get-Item -Path $nunitRoot | Select-Object -First 1
 #goto the tools dir
        $nunitRoot = Join-Path -Path $nunitRoot -ChildPath 'tools'
 #group the task paths by parent?
        $binRoots = $taskPaths | Group-Object -Property { Split-Path -Path $_ -Parent } 
 #get the path to nunit-console.exe
        $nunitConsolePath = Join-Path -Path $nunitRoot -ChildPath 'nunit-console.exe' -Resolve
 #Turns the absolute paths in to relative paths to shorten the command line arguments.
        $assemblyNames = $taskPaths | ForEach-Object { $_ -replace ([regex]::Escape($root)),'.' }
 #Calculates the paths to save the results from the tests as xml files and save them in that calculated output path.
        $testResultPath = Join-Path -Path $outputRoot -ChildPath ('nunit2-{0:00}.xml' -f $taskIdx)
 #
        & $nunitConsolePath $assemblyNames /noshadow /framework=4.0 /domain=Single /labels ('/xml={0}' -f $testResultPath)
        if( $LastExitCode )
        {
            throw ('NUnit2 tests failed. {0} returned exit code {1}.' -f $nunitConsolePath,$LastExitCode)
        }
        #>

    }

}