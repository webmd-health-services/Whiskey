function Invoke-WhiskeyPublishPowerShellModuleTask
{
    <#
    .SYNOPSIS
    Publishes a Whs PowerShell Module to Proget.

    .DESCRIPTION
    The "Invoke-WhiskeyPublishPowerShellModuleTask" will publish a PowerShell Module to Proget when being run by the build server. It will only publish new packages, or new versions of packages that are already published on proget.

    By default, it will only publish from the 'develop', 'release', or 'master' branches, but you can specify in the `whsbuild.yml` if you want to publish packages from a specific branch.
    
    Here is a sample whsbuild.yml file showing how to specify, in the whsbuild.yml file, what branches the build should publish packages from/on:

        PublishFor:
        -Master
        -Develop
        BuildTasks:
        - PublishPowerShellModule:
            Path:
            - mymodule.ps1            
  

    .EXAMPLE
    Invoke-WhiskeyPublishPowerShellModuleTask -TaskContext $TaskContext -TaskParameter $TaskParameter

    Demonstrates how to call the `WhiskeyPublishPowerShellModuleTask`. In this case  element in $TaskParameter relative to your whsbuild.yml file, will be built with MSBuild.exe given the build configuration contained in $TaskContext.
    #> 
    [Whiskey.Task("PublishPowerShellModule")]
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
 
    process{

        if( $Clean -or -not $TaskContext.Publish )
        {
            return
        }     
        
        $repositoryName = 'WhsPowerShell'
        if( $TaskParameter.ContainsKey('RepositoryName') )
        {
            $repositoryName = $TaskParameter.RepositoryName
        }
        $feedName = 'nuget/PowerShell'
        if( $TaskParameter.ContainsKey('FeedName') )
        {
            $feedName = $TaskParameter.FeedName
        }

        if( -not ($TaskParameter.ContainsKey('Path')))
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should a path relative to your whsbuild.yml file, to the module directory of the module to publish, e.g. 
        
            BuildTasks:
            - PublishPowerShellModule:
                Path:
                - mymodule')
        }

        $path = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'        
        $publishLocation = $TaskContext.ProgetSession.PowerShellFeedUri
        if( -not (Test-Path $path -PathType Container) )
        {
            throw('Element ''Path'' must point to a directory, specifically the module directory of the module to publish.')
        }
                
        $manifestPath = '{0}\{1}.psd1' -f $path,($path | Split-Path -Leaf)
        if( $TaskParameter.ContainsKey('ModuleManifestPath') )
        {
            $manifestPath = $TaskParameter.ModuleManifestPath
        }
        if( -not (Test-Path -Path $manifestPath -PathType Leaf) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Module Manifest Path {0} is invalid, please check that the {1}.psd1 file is valid and in the correct location.' -f $manifestPath, ($path | Split-Path -Leaf))
        }
        $manifest = Get-Content $manifestPath
        $versionString = "ModuleVersion = '{0}.{1}.{2}'" -f ( $TaskContext.Version.SemVer2.Major, $TaskContext.Version.SemVer2.Minor, $TaskContext.Version.SemVer2.Patch )
        $manifest = $manifest -replace "ModuleVersion\s*=\s*('|"")[^'""]*('|"")", $versionString 
        $manifest | Set-Content $manifestPath

        if( -not (Get-PSRepository -Name $RepositoryName -ErrorAction Ignore) )
        {
            Register-PSRepository -Name $RepositoryName -SourceLocation $publishLocation -PublishLocation $publishLocation -InstallationPolicy Trusted -PackageManagementProvider NuGet  -Verbose
        }
  
        # Publish-Module needs nuget.exe. If it isn't in the PATH, it tries to install it, which doesn't work when running non-interactively.
        $binPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin' -Resolve
        $originalPath = $env:PATH
        Set-Item -Path 'env:PATH' -Value ('{0};{1}' -f $binPath,$env:PATH)
        try
        {
            Publish-Module -Path $path -Repository $repositoryName -Verbose -NuGetApiKey ('{0}:{1}' -f $TaskContext.ProGetSession.Credential.UserName, $TaskContext.ProGetSession.Credential.GetNetworkCredential().Password)
        }
        finally
        {
            Set-Item -Path 'env:PATH' -Value $originalPath
        }
    }
}

