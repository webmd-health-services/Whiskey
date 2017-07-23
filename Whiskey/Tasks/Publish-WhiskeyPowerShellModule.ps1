function Publish-WhiskeyPowerShellModule
{
    [Whiskey.Task("PublishPowerShellModule")]
    [CmdletBinding()]
    param(

        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )
 
    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    if( -not $TaskParameter.ContainsKey('RepositoryName') )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''RepositoryName'' is mandatory. It should be the name of the PowerShell repository you want to publish to, e.g.
            
        BuildTasks:
        - PublishPowerShellModule:
            Path: mymodule
            RepositoryName: PSGallery
        ')
    }
    $repositoryName = $TaskParameter['RepositoryName']

    if( -not ($TaskParameter.ContainsKey('Path')))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Element ''Path'' is mandatory. It should a path relative to your whiskey.yml file, to the module directory of the module to publish, e.g. 
        
        BuildTasks:
        - PublishPowerShellModule:
            Path: mymodule
            RepositoryName: PSGallery
        ')
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

    if( -not (Get-PSRepository -Name $repositoryName -ErrorAction Ignore) )
    {
        Register-PSRepository -Name $repositoryName -SourceLocation $publishLocation -PublishLocation $publishLocation -InstallationPolicy Trusted -PackageManagementProvider NuGet  -Verbose
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
