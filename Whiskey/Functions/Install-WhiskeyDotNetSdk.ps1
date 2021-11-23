
function Install-WhiskeyDotNetSdk
{
    <#
    .SYNOPSIS
    Installs the .NET SDK.

    .DESCRIPTION
    The `Install-WhiskeyDotNetSdk` function installs the .NET SDK. It uses the `dotnet-install.ps1` and
    `dotnet-install.sh` scripts—provided and supported by Microsoft—on Windows and Linux/macOS, respectively. Any output
    from the install scripts is written instead to PowerShell's information stream. The function returns the path to the
    dotnet command. 

    If a `dotnet` tool is already installed and availble, `Install-WhiskeyDotNetSdk` inspects the contents of its
    installation folder to determine if the version of the SDK is installed globally (it looks for a "sdk\$VERSION"
    directory where the dotnet command is. If the SDK is installed, the path to the global dotnet command is returned.

    .EXAMPLE
    Install-WhiskeyDotNetSdk -InstallRoot 'C:\Build\.dotnet' -Version '2.1.4'

    Demonstrates installing .NET Core SDK version 2.1.4 to the 'C:\Build\.dotnet' directory. After install the function
    will return the path 'C:\Build\.dotnet\dotnet.exe'.
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

    $InstallRoot = $InstallRoot | Resolve-WhiskeyRelativePath
    $msg = "Installing .NET SDK $($Version) to ""$($InstallRoot)""."
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
        $InstallRoot
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
        $dotnetInstallPath =
            Join-Path -Path $whiskeyBinPath -ChildPath 'dotnet-install.ps1' | Resolve-WhiskeyRelativePath
        $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
        Write-WhiskeyCommand -Path $dotnetInstallPath -ArgumentList $displayArgs
        & $dotnetInstallPath -InstallDir $InstallRoot -Version $Version -NoPath @verboseParam |
            ForEach-Object { Write-Information $_ }
    }
    else
    {
        $cmdName = 'dotnet'
        $dotnetInstallPath =
            Join-Path -Path $whiskeyBinPath -ChildPath 'dotnet-install.sh' | Resolve-WhiskeyRelativePath
        $displayArgs[0] = $dotnetInstallPath
        Write-WhiskeyCommand -Path 'bash' -ArgumentList $displayArgs
        bash $dotnetInstallPath -InstallDir $InstallRoot -Version $Version | ForEach-Object { Write-Information $_ }
        Write-WhiskeyDebug 'Install complete.'
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
