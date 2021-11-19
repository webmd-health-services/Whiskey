
function Install-WhiskeyDotNetSdk
{
    <#
    .SYNOPSIS
    Installs the .NET Core SDK tooling.

    .DESCRIPTION
    The `Install-WhiskeyDotNetSdk` function will install the .NET Core SDK tools and return the path to the installed `dotnet.exe` command. If you specify the `Global` switch then the function will first look for any globally installed .NET Core SDK's with the desired version already installed. If one is found, then install is skipped and the path to the global install is returned. The function uses the `dotnet-install.ps1` script from the [dotnet-cli](https://github.com/dotnet/cli) GitHub repository to download and install the SDK.

    .EXAMPLE
    Install-WhiskeyDotNetSdk -InstallRoot 'C:\Build\.dotnet' -Version '2.1.4'

    Demonstrates installing .NET Core SDK version 2.1.4 to the 'C:\Build\.dotnet' directory. After install the function will return the path 'C:\Build\.dotnet\dotnet.exe'.
    #>
    [CmdletBinding()]
    param(
        # Directory where the .NET Core SDK will be installed.
        [Parameter(Mandatory)]
        [String] $InstallRoot,

        # Version of the .NET Core SDK to install.
        [Parameter(Mandatory)]
        [String] $Version
    )

    Set-StrictMode -version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $dotnetPaths = Get-Command -Name 'dotnet' -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Source'
    if( $dotnetPaths )
    {
        $msg = "Checking for installed .NET SDK $($Version)."
        Write-WhiskeyVerbose -Message $msg
        foreach( $dotnetPath in $dotnetPaths )
        {
            $sdkPath = Join-Path -Path ($dotnetPath | Split-Path -Parent) -ChildPath ('sdk\{0}' -f $Version)

            if (Test-Path -Path $sdkPath -PathType Container)
            {
                $msg = "Found .NET SDK $($Version) at ""$($sdkPath)""."
                Write-WhiskeyVerbose -Message $msg
                return $dotnetPath
            }
        }
    }

    $msg = "Installing .NET SDK $($Version) to ""$($InstallRoot | Resolve-WhiskeyRelativePath)""."
    Write-WhiskeyInfo -Message $msg

    if( -not (Test-Path -Path $InstallRoot) )
    {
        New-Item -Path $InstallRoot -ItemType 'Directory' | Out-Null
    }

    $verboseParam = @{}
    [String[]] $displayArgs = & {
        if( -not $IsWindows )
        {
            ''
        }
        '-InstallDir'
        $InstallRoot | Resolve-WhiskeyRelativePath
        '-Version'
        $Version
        if( $IsWindows )
        {
            '-NoPath'
            if( $VerbosePreference -eq 'Continue' )
            {
                '-Verbose'
                $verboseParam['Verbose'] = $true
            }
        }
    }

    # Both scripts handle if the .NET SDK is installed or not.
    if( $IsWindows )
    {
        $cmdName = 'dotnet.exe'
        $dotnetInstallPath = Join-Path -Path $whiskeyBinPath -ChildPath 'dotnet-install.ps1' -Resolve
        $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
        Write-WhiskeyCommand -Path $dotnetInstallPath -ArgumentList $displayArgs
        & $dotnetInstallPath -InstallDir $InstallRoot -Version $Version -NoPath @verboseParam
    }
    else
    {
        $cmdName = 'dotnet'
        $dotnetInstallPath = Join-Path -Path $whiskeyBinPath -ChildPath 'dotnet-install.sh' -Resolve
        $displayArgs[0] = $dotnetInstallPath
        Write-WhiskeyCommand -Path 'bash' -ArgumentList $displayArgs
        bash $dotnetInstallPath -InstallDir $InstallRot -Version $Version
    }
    
    $dotnetPath = Join-Path -Path $InstallRoot -ChildPath $cmdName -Resolve -ErrorAction Ignore
    if( -not $dotnetPath )
    {
        $msg = "After attempting to install .NET Core SDK version ""$($Version)"", the ""$($cmdName)"" command was " +
               "not found in ""$($InstallRoot)""."
        Write-WhiskeyError -Message $msg
        return
    }

    $sdkPath = Join-Path -Path $InstallRoot -ChildPath ('sdk\{0}' -f $Version) -Resolve -ErrorAction Ignore
    if( -not $sdkPath )
    {
        $msg = "The ""$($cmdName)"" command was installed but .NET SDK ""$($Version)"" doesn't exist in " +
               """$(Join-Path -Path $InstallRoot -ChildPath 'sdk')""."
        Write-WhiskeyError -Message $msg
        return
    }

    return $dotnetPath
}
