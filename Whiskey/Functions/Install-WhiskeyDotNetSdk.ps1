
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

    .EXAMPLE
    Install-WhiskeyDotNetSdk -InstallRoot 'C:\Build\.dotnet' -Version '2.1.4' -Global

    Demonstrates searching for an existing global install of the .NET Core SDK version '2.1.4'. If not found globally, the SDK will be installed to 'C:\Build\.dotnet'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # Directory where the .NET Core SDK will be installed.
        $InstallRoot,

        [Parameter(Mandatory=$true)]
        [string]
        # Version of the .NET Core SDK to install.
        $Version,

        [switch]
        # Search for the desired version from existing global installs of the .NET Core SDK. If found, the install is skipped and the path to the global install is returned.
        $Global
    )

    Set-StrictMode -version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if ($Global)
    {
        $dotnetGlobalInstalls = Get-Command -Name 'dotnet' -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Path'
        if ($dotnetGlobalInstalls)
        {
            Write-Verbose -Message ('[{0}] Found global installs of .NET Core SDK: "{1}"' -f $MyInvocation.MyCommand,($dotnetGlobalInstalls -join '","'))

            Write-Verbose -Message ('[{0}] Checking global installs for SDK version "{1}"' -f $MyInvocation.MyCommand,$Version)
            foreach ($dotnetPath in $dotnetGlobalInstalls)
            {
                $sdkPath = Join-Path -Path ($dotnetPath | Split-Path -Parent) -ChildPath ('sdk\{0}' -f $Version)

                if (Test-Path -Path $sdkPath -PathType Container)
                {
                    Write-Verbose ('[{0}] Found SDK version "{1}" at "{2}"' -f $MyInvocation.MyCommand,$Version,$sdkPath)
                    return $dotnetPath
                }
            }
        }

        Write-Verbose -Message ('[{0}] .NET Core SDK version "{1}" not found globally' -f $MyInvocation.MyCommand,$Version)
    }

    $verboseParam = @{}
    if ($VerbosePreference -eq 'Continue')
    {
        $verboseParam['Verbose'] = $true
    }

    Write-Verbose -Message ('[{0}] Installing .NET Core SDK version "{1}" to "{2}"' -f $MyInvocation.MyCommand,$Version,$InstallRoot)

    $dotnetInstallScript = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\dotnet-install.ps1' -Resolve
    $errorActionParam = @{ ErrorAction = 'Stop' }
    $installingWithShell = $false
    $executableName = 'dotnet.exe'
    if( $IsLinux -or $IsMacOS )
    {
        $dotnetInstallScript = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\dotnet-install.sh' -Resolve
        $errorActionParam = @{ }
        $installingWithShell = $true
        $executableName = 'dotnet'  
    }
    Invoke-Command -NoNewScope -ArgumentList $dotnetInstallScript,$InstallRoot,$Version,$verboseParam -ScriptBlock {
        param(
            $dotnetInstall,
            $InstallDir,
            $VersionNumber,
            $Verbose
        )

        $errCount = $Global:Error.Count
        & {
            if( $installingWithShell )
            {
                Write-Verbose ('bash {0} -InstallDir "{1}" -Version "{2}" -NoPath' -f $dotnetInstall,$InstallDir,$VersionNumber)
                bash $dotnetInstall -InstallDir $InstallDir -Version $VersionNumber -NoPath
            }
            else 
            {
                Write-Verbose ('{0} -InstallDir "{1}" -Version "{2}" -NoPath' -f $dotnetInstall,$InstallDir,$VersionNumber)
                & $dotnetInstall -InstallDir $InstallDir -Version $VersionNumber -NoPath @Verbose @errorActionParam
            }
        } | Write-Verbose -Verbose
        if( $installingWithShell -and $LASTEXITCODE )
        {
            Write-Error -Message ('{0} exited with code "{1}". Failed to install .NET Core.' -f $dotnetInstall,$LASTEXITCODE) -ErrorAction Stop
            return
        }
        $newErrCount = $Global:Error.Count
        for( $count = 0; $count -lt $newErrCount; ++$count )
        {
            $Global:Error.RemoveAt(0)
        }
    }

    $dotnetPath = Join-Path -Path $InstallRoot -ChildPath $executableName -Resolve -ErrorAction Ignore
    if (-not $dotnetPath)
    {
        Write-Error -Message ('After attempting to install .NET Core SDK version "{0}", the "{1}" executable was not found in "{2}"' -f $Version,$executableName,$InstallRoot)
        return
    }

    $sdkPath = Join-Path -Path $InstallRoot -ChildPath ('sdk\{0}' -f $Version)
    if (-not (Test-Path -Path $sdkPath -PathType Container))
    {
        Write-Error -Message ('The "{0}" command was installed but version "{1}" of the SDK was not found at "{2}"' -f $executableName,$Version,$sdkPath)
        return
    }

    return $dotnetPath
}
