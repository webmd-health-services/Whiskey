
function Save-NodeJsPackage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $Version,

        [Parameter(Mandatory)]
        [String] $OutputDirectoryPath,

        [String] $Cpu
    )

    $platform = 'win'
    $packageExtension = 'zip'
    if ($IsLinux)
    {
        $platform = 'linux'
        $packageExtension = 'tar.xz'
    }
    elseif ($IsMacOS)
    {
        $platform = 'darwin'
        $packageExtension = 'tar.gz'
    }

    if ($Cpu)
    {
        $arch = $Cpu
    }
    else
    {
        $arch = 'x86'
        if ([Environment]::Is64BitOperatingSystem)
        {
            $arch = 'x64'
        }
    }

    $extractedDirName = "node-${Version}-${platform}-${arch}"
    $filename = "${extractedDirName}.${packageExtension}"

    $pkgChecksum = ''
    $checksumsUrl = "https://nodejs.org/dist/${Version}/SHASUMS256.txt"
    try
    {
        $ProgressPreference = 'SilentlyContinue'
        $pkgChecksum =
            Invoke-WebRequest -Uri $checksumsUrl -UseBasicParsing -ErrorAction Ignore |
            Select-Object -ExpandProperty 'Content' |
            ForEach-Object { $_ -split '\r?\n' } |
            Where-Object { $_ -match "^([^ ]+) +$([regex]::Escape($filename))$" } |
            ForEach-Object { $Matches[1] } |
            Select-Object -First 1

        if (-not $pkgChecksum)
        {
            $msg = "Node.js package will not be validated because the $($filename | Format-Path) package's checksum is " +
                    "missing from ${checksumsUrl}."
            Write-WhiskeyWarning -Context $TaskContext -Message $msg
        }
    }
    catch
    {
        $msg = "Node.js package will not be validated because the request to download the ${Version} checksums " +
                "from ${checksumsUrl} failed: ${_}."
        Write-WhiskeyWarning -Context $TaskContext -Message $msg
    }

    $nodeZipFilePath = Join-Path -Path $OutputDirectoryPath -ChildPath $filename
    if ((Test-Path -Path $nodeZipFilePath))
    {
        $actualChecksum = Get-FileHash -Path $nodeZipFilePath -Algorithm SHA256
        if ($pkgChecksum -and $pkgChecksum -eq $actualChecksum.Hash)
        {
            Write-WhiskeyDebug -Message "Using cached Node.js package $($nodeZipFilePath | Format-Path)."
            return $nodeZipFilePath
        }

        Remove-Item -Path $nodeZipFilePath
    }

    $pkgUrl = "https://nodejs.org/dist/${Version}/${filename}"

    if (-not (Test-Path -Path $OutputDirectoryPath))
    {
        Write-WhiskeyDebug -Message "Creating output directory $($OutputDirectoryPath | Format-Path)."
        New-Item -Path $OutputDirectoryPath -ItemType 'Directory' -Force | Out-Null
    }

    try
    {
        $ProgressPreference = 'SilentlyContinue'
        Write-WhiskeyDebug -Message "Downloading ${pkgUrl} to $($nodeZipFilePath | Split-Path -Parent | Format-Path)."
        Invoke-WebRequest -Uri $pkgUrl -OutFile $nodeZipFilePath -UseBasicParsing | Out-Null
    }
    catch
    {
        $responseInfo = ''
        $notFound = $false
        if( $_.Exception | Get-Member -Name 'Response' )
        {
            $responseStatus = $_.Exception.Response.StatusCode
            $responseInfo = ' Received a {0} ({1}) response.' -f $responseStatus,[int]$responseStatus
            if( $responseStatus -eq [Net.HttpStatusCode]::NotFound )
            {
                $notFound = $true
            }
        }
        else
        {
            Write-WhiskeyError -Message "Exception downloading ${pkgUrl}: $($_)"
            $responseInfo = ' Please see previous error for more information.'
            return
        }

        $errorMsg = "Failed to download Node.js ${Version} from ${pkgUrl}.$($responseInfo)"
        if( $notFound )
        {
            $errorMsg = "$($errorMsg) It looks like this version of Node wasn't packaged as a ZIP file. " +
                        'Please use Node v4.5.0 or newer.'
        }
        Write-WhiskeyError -Message $errorMsg
        return
    }

    if ($pkgChecksum)
    {
        $actualChecksum = Get-FileHash -Path $nodeZipFilePath -Algorithm SHA256
        if ($pkgChecksum -ne $actualChecksum.Hash)
        {
            Remove-Item -Path $nodeZipFilePath

            $msg = "Failed to install Node.js ${Version} because the SHA256 checksum of the file downloaded " +
                    "from ${pkgUrl}, $($actualChecksum.Hash.ToLowerInvariant()), doesn't match the expected " +
                    "checksum, ${pkgChecksum}, from ${checksumsUrl}."
            Write-WhiskeyError -Message $msg
            return
        }
    }

    return $nodeZipFilePath
}