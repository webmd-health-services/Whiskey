
function Install-WhiskeyDotnetSdk
{
    <#
    .SYNOPSIS
    Installs the .NET Core SDK tooling.

    .DESCRIPTION
    The `Install-WhiskeyDotnetSdk` function will install the .NET Core SDK tools and return the path to the installed `dotnet.exe` command. If you specify the `SearchExisting` switch then the function will first look for any globally installed .NET Core SDK's with the desired version already installed. If one is found, then install is skipped and the path to the global install is returned. The function uses the `dotnet-install.ps1` script from the [dotnet-cli](https://github.com/dotnet/cli) GitHub repository to download and install the SDK.

    .EXAMPLE
    Install-WhiskeyDotnetSdk -InstallRoot 'C:\Build\.dotnet' -Version '2.1.4'

    Demonstrates installing .NET Core SDK version 2.1.4 to the 'C:\Build\.dotnet' directory. After install the function will return the path 'C:\Build\.dotnet\dotnet.exe'.

    .EXAMPLE
    Install-WhiskeyDotnetSdk -InstallRoot 'C:\Build\.dotnet' -Version '2.1.4' -SearchExisting

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
        $SearchExisting
    )

    Set-StrictMode -version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if ($SearchExisting)
    {
        $dotnetGlobalInstalls = Get-Command -Name 'dotnet.exe' -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Source'
        if ($dotnetGlobalInstalls)
        {
            Write-Verbose -Message ('[{0}] Found global installs of .NET Core SDK: "{1}"' -f $MyInvocation.MyCommand,($dotnetGlobalInstalls -join '","'))

            Write-Verbose -Message ('[{0}] Checking global installs for SDK version ''{1}''' -f $MyInvocation.MyCommand,$Version)
            foreach ($dotnetPath in $dotnetGlobalInstalls)
            {
                $sdkPath = Join-Path -Path ($dotnetPath | Split-Path -Parent) -ChildPath ('sdk\{0}' -f $Version)

                if (Test-Path -Path $sdkPath -PathType Container)
                {
                    Write-Verbose ('[{0}] Found SDK version ''{1}'' at ''{2}''' -f $MyInvocation.MyCommand,$Version,$sdkPath)
                    return $dotnetPath
                }
            }
        }

        Write-Verbose -Message ('[{0}] .NET Core SDK version ''{1}'' not found globally' -f $MyInvocation.MyCommand,$Version)
    }

    $verboseParam = @{}
    if ($VerbosePreference -eq 'Continue')
    {
        $verboseParam['Verbose'] = $true
    }

    Write-Verbose -Message ('[{0}] Installing .NET Core SDK version ''{1}'' to ''{2}''' -f $MyInvocation.MyCommand,$Version,$InstallRoot)

    $dotnetInstallScript = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\dotnet-install.ps1' -Resolve
    Invoke-Command -NoNewScope -ArgumentList $dotnetInstallScript,$InstallRoot,$Version,$verboseParam -ScriptBlock {
        param(
            $dotnetInstall,
            $InstallDir,
            $VersionNumber,
            $Verbose
        )

        & $dotnetInstall -NoPath -InstallDir $InstallDir -Version $VersionNumber @Verbose
    }

    return Join-Path -Path $InstallRoot -ChildPath 'dotnet.exe' -Resolve
}
