
function Get-MSBuild
{
    $toolsVersionRegPath = 'hklm:\software\Microsoft\MSBuild\ToolsVersions'
    foreach( $key in (Get-ChildItem -Path $toolsVersionRegPath) )
    {
        $name = $key.Name | Split-Path -Leaf
        $toolsPath = Get-ItemProperty -Path $key.PSPath -Name 'MSBuildToolsPath' | Select -ExpandProperty 'MSBuildToolsPath'
        $msbuildPath = Join-Path -Path $toolsPath -ChildPath 'MSBuild.exe'
        if( (Test-Path -Path $msbuildPath -PathType Leaf) )
        {
            [pscustomobject]@{
                Name = $name;
                Version = [version]$name;
                Path = $msbuildPath;
            }
        }
    }

    Get-VSSetupInstance |
        ForEach-Object {
            $msbuildPath = Join-Path -Path $_.InstallationPath -ChildPath 'MSBuild\*\Bin\MSBuild.exe'
            if( -not (Test-Path -Path $msbuildPath -PathType Leaf) )
            {
                return 
            }
                                                
            Resolve-Path -Path $msbuildPath |
                Get-Item |
                ForEach-Object {
                    $name = $_.Directory.Parent.Name
                    [pscustomobject]@{
                                        Name =  $name;
                                        Version = [version]$name;
                                        Path = $_.FullName
                                    }
                }
        }
}
