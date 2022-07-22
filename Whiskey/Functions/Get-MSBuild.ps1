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

        $toolsPath =
            Get-ItemProperty -Path $Key.PSPath -Name 'MSBuildToolsPath' -ErrorAction Ignore |
            Select-Object -ExpandProperty 'MSBuildToolsPath' -ErrorAction Ignore
        if( -not $toolsPath )
        {
            $msg = "$($indent)Skipping registry key ""$($Key | Convert-Path)"": key value ""MSBuildToolsPath"" " +
                   'doesn''t exist.'
            Write-WhiskeyVerbose -Message $msg
            return ''
        }

        $path = Join-Path -Path $toolsPath -ChildPath 'MSBuild.exe'
        if( (Test-Path -Path $path -PathType Leaf) )
        {
            return $path
        }

        $msg = "$($indent)Skipping registry key ""$($Key | Convert-Path)"": key value ""MSBuildToolsPath"" " +
                "is path ""$($path)"", which doesn't exist."
        Write-WhiskeyVerbose -Message $msg
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

    Write-WhiskeyVerbose '[Get-MSBuild]'
    $indent = '  '

    $toolsVersionRegPath = 'HKLM:\SOFTWARE\Microsoft\MSBuild\ToolsVersions'
    $toolsVersionRegPath32 = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\MSBuild\ToolsVersions'
    $tools32Exists = Test-Path -Path $toolsVersionRegPath32 -PathType Container

    foreach( $key in (Get-ChildItem -Path $toolsVersionRegPath) )
    {
        $name = $key.Name | Split-Path -Leaf
        if( -not ($name | Test-Version) )
        {
            $msg = "$($preindentfix)Skipping registry key ""$($key | Convert-Path)"": name isn't a version number."
            Write-WhiskeyVerbose -Message $msg
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

        Write-WhiskeyVerbose ("$($indent)Found MSBuild $($name) at ""$($msbuildPath)"".")
        [pscustomobject]@{
            Name = $name;
            Version = [Version]$name;
            Path = $msbuildPath;
            Path32 = $msbuildPath32;
            PathArm64 = '';
        }
    }

    foreach( $instance in (Get-VSSetupInstance) )
    {
        $msbuildRoot = Join-Path -Path $instance.InstallationPath -ChildPath 'MSBuild'
        if( -not (Test-Path -Path $msbuildRoot -PathType Container) )
        {
            $msg = "$($indent)Skipping $($instance.DisplayName): its MSBuild directory ""$($msbuildRoot)"" doesn''t " +
                   'exist.'
            Write-WhiskeyVerbose -Message $msg
            continue
        }

        $path32 = Join-Path -Path $msbuildRoot -ChildPath '*\Bin\MSBuild.exe' -Resolve -ErrorAction Ignore
        if( -not $path32 )
        {
            $msg = "$($indent)Skipping $($instance.DisplayName): " +
                   """$(Join-Path -Path $msbuildRoot -ChildPath '*\Bin\MSBuild.exe')"" doesn't exist."
                   """$($msbuildRoot)"" doesn''t exist."
            Write-WhiskeyVerbose -Message $msg
            continue
        }

        $msbuildRoot = $path32 | Split-Path | Split-Path
        $path = Join-Path -Path $msbuildRoot -ChildPath 'Bin\amd64\MSBuild.exe' -Resolve -ErrorAction Ignore
        $pathArm64 =
            Join-Path -Path $msbuildRoot -ChildPath 'Bin\arm64\MSBuild.exe' -Resolve -ErrorAction Ignore

        if( -not $path -and $path32 )
        {
            $path = $path32
        }

        if( -not $path )
        {
            $msg = "$($indent)Skipping $($instance.DisplayName) $($instance.InstallationVersion): " +
                   """$(Join-Path -Path $msbuildRoot -ChildPath 'Bin\amd64\MSBuild.exe')"" doesn't exist."
                   """$($msbuildRoot)"" doesn''t exist."
            Write-WhiskeyVerbose -Message $msg
            continue
        }

        $majorVersion =
            Get-Item -Path $path |
            Select-Object -ExpandProperty 'VersionInfo' |
            Select-Object -ExpandProperty 'ProductMajorPart'

        $majorMinor = '{0}.0' -f $majorVersion

        Write-WhiskeyVerbose ("$($indent)Found MSBuild $($majorMinor) at ""$($path)"".")
        [pscustomobject]@{
            Name =  $majorMinor;
            Version = [Version]$majorMinor;
            Path = $path;
            Path32 = $path32;
            PathArm64 = $pathArm64;
        } | Write-Output
    }
    Write-WhiskeyVerbose '[Get-MSBuild]'
}