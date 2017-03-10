function Invoke-WhsCIPublishPowerShellModuleTask
 
{
    <#
    .SYNOPSIS
    Publishes a Whs PowerShell Module to Proget.

    .DESCRIPTION
    The "Invoke-WhsCIPublishPowerShellModuleTask" will publish a PowerShell Module to Proget when being run by the build server. It will only publish new packages, or new versions of packages that are already published on proget.

    By default, it will only publish from the 'develop', 'release', or 'master' branches, but you can specify in the `whsbuild.yml` if you want to publish packages from a specific branch.
    
    Here is a sample whsbuild.yml file showing how to specify, in the whsbuild.yml file, what branches the build should publish packages from/on:

        PublishFor:
        -Master
        -Develop
        BuildTasks:
        - PublishPowerShellModule:
            Path:
            - mymodule.ps1
            - myothermodule.ps1
            
  

    .EXAMPLE
    Invoke-WhsCIPublishPowerShellModuleTask -TaskContext $TaskContext -TaskParameter $TaskParameter

    Demonstrates how to call the `WhsCIPublishPowerShellModuleTask`. In this case  element in $TaskParameter relative to your whsbuild.yml file, will be built with MSBuild.exe given the build configuration contained in $TaskContext.



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
 
    process{

        if( -not $TaskContext.Publish )
        {
            return
        }     
        
        $repositoryName = 'WhsPowerShellVerification'
        if( $TaskParameter.ContainsKey('RepositoryName') )
        {
            $repositoryName = $TaskParameter.RepositoryName
        }
        $feedName = 'nuget/PowerShellVerification'
        if( $TaskParameter.ContainsKey('FeedName') )
        {
            $feedName = $TaskParameter.FeedName
        }
        
        $publishLocation = New-Object 'Uri' ([uri]$TaskContext.ProgetSession.URI), $feedName
        
        if( -not (Get-PSRepository -Name $RepositoryName -ErrorAction Ignore) )
        {
            Register-PSRepository -Name $RepositoryName -SourceLocation $publishLocation -PublishLocation $publishLocation -InstallationPolicy Trusted -PackageManagementProvider NuGet  -Verbose
        }
  
        Publish-Module -Path .\WhsCI -Repository $repositoryName -Verbose -NuGetApiKey ('{0}:{1}' -f $TaskContext.ProGetSession.Credential.UserName, $TaskContext.ProGetSession.Credential.GetNetworkCredential().Password)
    }
}
 
