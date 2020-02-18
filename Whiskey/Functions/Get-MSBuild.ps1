
function Get-MSBuild
{
    [CmdletBinding()]
    param(
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    function Resolve-MSBuildToolsPath
    {
        param(
            [Microsoft.Win32.RegistryKey]$Key
        )

        $toolsPath = Get-ItemProperty -Path $Key.PSPath -Name 'MSBuildToolsPath' -ErrorAction Ignore | Select-Object -ExpandProperty 'MSBuildToolsPath' -ErrorAction Ignore
        if( -not $toolsPath )
        {
            return ''
        }

        $path = Join-Path -Path $toolsPath -ChildPath 'MSBuild.exe'
        if( (Test-Path -Path $path -PathType Leaf) )
        {
            return $path
        }

        return ''
    }

    filter Test-Version
    {
        param(
            [Parameter(Mandatory,ValueFromPipeline)]
            $InputObject
        )

        [Version]$version = $null
        [Version]::TryParse($InputObject,[ref]$version)

    }

    $toolsVersionRegPath = 'HKLM:\SOFTWARE\Microsoft\MSBuild\ToolsVersions'
    $toolsVersionRegPath32 = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\MSBuild\ToolsVersions'
    $tools32Exists = Test-Path -Path $toolsVersionRegPath32 -PathType Container

    foreach( $key in (Get-ChildItem -Path $toolsVersionRegPath) )
    {
        $name = $key.Name | Split-Path -Leaf
        if( -not ($name | Test-Version) )
        {
            continue
        }

        $msbuildPath = Resolve-MSBuildToolsPath -Key $key
        if( -not $msbuildPath )
        {
            continue
        }

        $msbuildPath32 = $msbuildPath
        if( $tools32Exists )
        {
            $key32 = Get-ChildItem -Path $toolsVersionRegPath32 | Where-Object { ($_.Name | Split-Path -Leaf) -eq $name }
            if( $key32 )
            {
                $msbuildPath32 = Resolve-MSBuildToolsPath -Key $key32
            }
            else
            {
                $msbuildPath32 = ''
            }
        }

        [pscustomobject]@{
            Name = $name;
            Version = [Version]$name;
            Path = $msbuildPath;
            Path32 = $msbuildPath32;
        }
    }

    foreach( $instance in (Get-VSSetupInstance) )
    {
        $msbuildRoot = Join-Path -Path $instance.InstallationPath -ChildPath 'MSBuild'
        if( -not (Test-Path -Path $msbuildRoot -PathType Container) )
        {
            Write-WhiskeyVerbose -Message ('Skipping {0} {1}: its MSBuild directory ''{2}'' doesn''t exist.' -f $instance.DisplayName,$instance.InstallationVersion,$msbuildRoot)
            continue
        }

        $versionRoots =
            Get-ChildItem -Path $msbuildRoot -Directory |
            Where-Object { Get-ChildItem -Path $_.FullName -Filter 'MSBuild.exe' -Recurse }

        foreach( $versionRoot in $versionRoots )
        {
            $paths = Get-ChildItem -Path $versionRoot.FullName -Filter 'MSBuild.exe' -Recurse

            $path =
                $paths |
                Where-Object { $_.Directory.Name -eq 'amd64' } |
                Select-Object -ExpandProperty 'FullName'

            $path32 =
                $paths |
                Where-Object { $_.Directory.Name -ne 'amd64' } |
                Select-Object -ExpandProperty 'FullName'

            if( -not $path )
            {
                $path = $path32
            }

            if( -not $path )
            {
                continue
            }

            if( -not $path32 )
            {
                $path32 = ''
            }

            $majorVersion =
                Get-Item -Path $path |
                Select-Object -ExpandProperty 'VersionInfo' |
                Select-Object -ExpandProperty 'ProductMajorPart'

            $majorMinor = '{0}.0' -f $majorVersion

            [pscustomobject]@{
                                Name =  $majorMinor;
                                Version = [Version]$majorMinor;
                                Path = $path;
                                Path32 = $path32;
                            }
        }
    }
}
