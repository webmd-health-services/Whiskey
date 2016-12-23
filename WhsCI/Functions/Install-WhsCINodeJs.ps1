
function Install-WhsCINodeJs
{
    <#
    .SYNOPSIS
    Installs a specific version of Node.js and returns its path.

    .DESCRIPTION
    The `Install-WhsCINodeJs` function installs a specific version of Node.js and returns the path to its `node.exe` program. It uses NVM to to the installation. If NVM isn't installed/available, it will download it and install it to `%APPDATA%\nvm`.

    If the requested version of Node.js is installed, nothing happens, but the path to that version's `node.exe` is still returned.

    After installation, both Node *and* NPM will be installed together in the same directory.

    IF NVM is downloaded, the `NVM_HOME` environment variable for the current user is created to point to where NVM is installed.

    .EXAMPLE
    Install-WhsCINodeJs -Version '4.4.7'

    Installs version `4.4.7` of Node.js and returns the path to its `node.exe` file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The version to install.
        $Version,

        [string]
        # The directory where NVM should be installed to. Only used if NVM isn't already installed. NVM is installed to `$NvmInstallDirectory\nvm`.
        $NvmInstallDirectory
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( -not $NvmInstallDirectory )
    {
        $NvmInstallDirectory = $env:APPDATA
    }

    if( (Test-Path -Path 'env:NVM_HOME') )
    {
        $nvmRoot = $env:NVM_HOME
    }
    else
    {
        if( -not (Test-WhsCIRunByBuildServer) )
        {
            Write-Error -Message (@"
NVM for Windows is not installed. To install it:

1. Uninstall any existing versions of Node.js using the "Programs and Features" Control Panel.
2. Reboot
3. Delete these folders, if they still exist:
   * C:\Program Files (x86)\Nodejs
   * C:\Program Files\Nodejs
   * C:\Users\$($env:USERNAME)\AppData\Roaming\npm (i.e. ``%APPDATA%\Roaming\npm``)
   * C:\Users\$($env:USERNAME)\AppData\Roaming\npm-cache (i.e. ``%APPDATA%\Roaming\npm-cache``)
   * C:\Users\$($env:USERNAME)\.npmrc
   * C:\Users\$($env:USERNAME)\npmrc
4. Remove any nodejs or npm paths from your %PATH% environment variable.
5. Download the latest version of NVM for Windows from Github: https://github.com/coreybutler/nvm-windows/releases
6. Right-click the .zip file, choose Properties, and click the "Unblock" button.
7. Unzip the installer
8. Run nvm-setup.exe. Leave all installation options to their defaults.
6. Restart PowerShell
"@)
            return
        }

        $nvmRoot = Join-Path -Path $NvmInstallDirectory -ChildPath 'nvm'

        $tempZipFile = 'WhsCI+Install-WhsCINodeJs+nvm-setup.zip+{0}' -f [IO.Path]::GetRandomFileName()
        $tempZipFile = Join-Path -Path $env:TEMP -ChildPath $tempZipFile

        $nvmUri = 'https://github.com/coreybutler/nvm-windows/releases/download/1.1.1/nvm-noinstall.zip'
        Invoke-WebRequest -UseBasicParsing -Uri $nvmUri -OutFile $tempZipFile
        if( -not (Test-Path -Path $tempZipFile -PathType Leaf) )
        {
            Write-Error -Message ('Failed to download NVM from {0}' -f $nvmUri)
            return
        }

        $nvmSymlink = Join-Path -Path $env:ProgramFiles -ChildPath 'nodejs'

        Add-Type -AssemblyName 'System.IO.Compression.FileSystem'
        [IO.Compression.ZipFile]::ExtractToDirectory($tempZipFile,$nvmRoot)

        @"
root: $($nvmRoot)
path: $($nvmSymlink)
"@ | Set-Content -Path (Join-Path -Path $nvmRoot -ChildPath 'settings.txt')

        Set-Item -Path 'env:NVM_HOME' -Value $nvmRoot
    }

    $nvmPath = Join-Path -Path $nvmRoot -ChildPath 'nvm.exe'
    $activity = 'Installing Node.js {0}' -f $Version
    Write-Progress -Activity $activity
    $output = & $nvmPath install $Version | 
                Where-Object { $_ } |
                ForEach-Object { Write-Progress -Activity $activity -Status $_; $_ }
    Write-Progress -Activity $activity -Completed

    $nodePath = Join-Path -Path $nvmRoot -ChildPath ('v{0}\node64.exe' -f $Version)
    if( (Test-Path -Path $nodePath -PathType Leaf) )
    {
        return $nodePath
    }

    Write-Error -Message ('Failed to install Node.js version {0}.{1}{2}' -f $Version,[Environment]::NewLine,($output -join [Environment]::NewLine))
}