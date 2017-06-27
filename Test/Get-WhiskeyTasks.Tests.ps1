
#& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCiTest.ps1' -Resolve)

Describe 'Get-WhiskeyTasks.' {
    $expectedTasks = @{
                        AppPackage                     = 'Invoke-WhsCIAppPackageTask';
                        MSBuild                        = 'Invoke-WhsCIMSBuildTask';
                        NUnit2                         = 'Invoke-WhsCINUnit2Task';
                        NodeAppPackage                 = 'Invoke-WhsCINodeAppPackageTask';
                        Node                           = 'Invoke-WhsCINodeTask';
                        Pester3                        = 'Invoke-WhsCIPester3Task';
                        Pester4                        = 'Invoke-WhsCIPester4Task';
                        PowerShell                     = 'Invoke-WhsCIPowerShellTask';
                        PublishFile                    = 'Invoke-WhsCIPublishFileTask';
                        DecoupledWindowsServicePackage = 'Invoke-WhsCIDecoupledWindowsServicePackageTask';
                        PublishNodeModule              = 'Invoke-WhsCIPublishNodeModuleTask';
                        PublishNuGetLibrary            = 'Invoke-WhsCIPublishNuGetLibraryTask';
                        PublishPowerShellModule        ='Invoke-WhsCIPublishPowerShellModuleTask';
                        }

    $Global:error.Clear()
    $failed = $false
    try
    {
        $tasks = Get-WhiskeyTasks
    }
    catch
    {
        $failed = $true
    }

    it 'should not fail' {
        $failed | should be $false
    }
    it 'should not write error' {
        $Global:error | should beNullOrEmpty
    }
    it 'should return the right number of WhiskeyTasks' {
        $tasks.Count | should be $expectedTasks.Count 
    }
    foreach ($key in $expectedTasks.keys)
    {
        it ('it should return the {0} task' -f $key) {
            $tasks[$key] | should be $expectedTasks[$key]
        }
    }


}
