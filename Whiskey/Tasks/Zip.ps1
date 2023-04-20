
function New-WhiskeyZipArchive
{
    [Whiskey.Task('Zip')]
    [Whiskey.RequiresPowerShellModule('Zip', Version='0.3.*', VersionParameterName='ZipVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath()]
        [String]$SourceRoot,

        [Whiskey.Tasks.ValidatePath(Mandatory,AllowNonexistent)]
        [String]$ArchivePath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    function Write-CompressionInfo
    {
        param(
            [Parameter(Mandatory)]
            [ValidateSet('file','directory','filtered directory')]
            [String]$What,
            [String]$Source,
            [String]$Destination
        )

        if( $Destination )
        {
            $Destination = ' -> {0}' -f ($Destination -replace '\\','/')
        }

        if( [IO.Path]::DirectorySeparatorChar -eq [IO.Path]::AltDirectorySeparatorChar )
        {
            $Source = $Source -replace '\\','/'
        }
        Write-WhiskeyInfo -Context $TaskContext -Message ('  compressing {0,-18} {1}{2}' -f $What,$Source,$Destination)
    }

    $behaviorParams = @{ }
    if( $TaskParameter['CompressionLevel'] )
    {
        [IO.Compression.CompressionLevel]$compressionLevel = [IO.Compression.CompressionLevel]::NoCompression
        if( -not [Enum]::TryParse($TaskParameter['CompressionLevel'], [ref]$compressionLevel) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'CompressionLevel' -Message ('Value "{0}" is an invalid compression level. Must be one of: {1}.' -f $TaskParameter['CompressionLevel'],([Enum]::GetValues([IO.Compression.CompressionLevel]) -join ', '))
            return
        }
        $behaviorParams['CompressionLevel'] = $compressionLevel
    }

    if( $TaskParameter['EntryNameEncoding'] )
    {
        $entryNameEncoding = $TaskParameter['EntryNameEncoding']
        [int]$codePage = 0
        if( [int]::TryParse($entryNameEncoding,[ref]$codePage) )
        {
            try
            {
                $entryNameEncoding = [Text.Encoding]::GetEncoding($codePage)
            }
            catch
            {
                Write-Error -ErrorRecord $_
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('EntryNameEncoding: An encoding with code page "{0}" does not exist. To get a list of encodings, run `[Text.Encoding]::GetEncodings()` or see https://docs.microsoft.com/en-us/dotnet/api/system.text.encoding . Use the encoding''s `CodePage` or `WebName` property as the value of this property.' -f $entryNameEncoding)
                return
            }
        }
        else
        {
            try
            {
                $entryNameEncoding = [Text.Encoding]::GetEncoding($entryNameEncoding)
            }
            catch
            {
                Write-Error -ErrorRecord $_
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('EntryNameEncoding: An encoding named "{0}" does not exist. To get a list of encodings, run `[Text.Encoding]::GetEncodings()` or see https://docs.microsoft.com/en-us/dotnet/api/system.text.encoding . Use the encoding''s "CodePage" or "WebName" property as the value of this property.' -f $entryNameEncoding)
                return
            }
        }
        $behaviorParams['EntryNameEncoding'] = $entryNameEncoding
    }

    Write-WhiskeyInfo -Context $TaskContext -Message ('Creating ZIP archive "{0}".' -f $ArchivePath)
    $archiveDirectory = $ArchivePath | Split-Path -Parent
    if( $archiveDirectory -and -not (Test-Path -Path $archiveDirectory -PathType Container) )
    {
        New-Item -Path $archiveDirectory -ItemType 'Directory' -Force | Out-Null
    }

    if( -not $TaskParameter['Path'] )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Path" is required. It must be a list of paths, relative to your whiskey.yml file, of files or directories to include in the ZIP archive.')
        return
    }

    New-ZipArchive -Path $ArchivePath @behaviorParams -Force | Out-Null

    if( $SourceRoot )
    {
        Write-WhiskeyWarning -Context $TaskContext -Message ('The "SourceRoot" property is obsolete. Please use the "WorkingDirectory" property instead.')
        $ArchivePath = Resolve-Path -Path $ArchivePath | Select-Object -ExpandProperty 'ProviderPath'
        Push-Location -Path $SourceRoot
    }

    try
    {
        foreach( $item in $TaskParameter['Path'] )
        {
            $override = $False
            if( (Get-Member -InputObject $item -Name 'Keys') )
            {
                $sourcePath = $null
                $override = $True
                foreach( $key in $item.Keys )
                {
                    $destinationItemName = $item[$key]
                    $sourcePath = $key
                }
            }
            else
            {
                $sourcePath = $item
            }

            $sourcePaths =
                $sourcePath |
                Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
            if( -not $sourcePaths )
            {
                return
            }

            $basePath = (Get-Location).Path
            foreach( $sourcePath in $sourcePaths )
            {
                $addParams = @{ BasePath = $basePath }
                $destinationParam = @{ }
                if( $override )
                {
                    $addParams = @{ EntryName = $destinationItemName }
                    $destinationParam['Destination'] = $destinationItemName
                }

                if( (Test-Path -Path $sourcePath -PathType Leaf) )
                {
                    Write-CompressionInfo -What 'file' -Source $sourcePath @destinationParam
                    Add-ZipArchiveEntry -ZipArchivePath $ArchivePath -InputObject $sourcePath @addParams @behaviorParams
                    continue
                }

                function Find-Item
                {
                    param(
                        [Parameter(Mandatory)]
                        $Path
                    )

                    if( (Test-Path -Path $Path -PathType Leaf) )
                    {
                        return Get-Item -Path $Path
                    }

                    $Path = Join-Path -Path $Path -ChildPath '*'
                    & {
                            Get-ChildItem -Path $Path -Include $TaskParameter['Include'] -Exclude $TaskParameter['Exclude'] -File
                            Get-Item -Path $Path -Exclude $TaskParameter['Exclude'] |
                                Where-Object { $_.PSIsContainer }
                        }  |
                        ForEach-Object {
                            if( $_.PSIsContainer )
                            {
                                Find-Item -Path $_.FullName
                            }
                            else
                            {
                                $_
                            }
                        }
                }

                if( $override )
                {
                    $overrideBasePath =
                        Resolve-Path -Path $sourcePath |
                        Select-Object -ExpandProperty 'ProviderPath'

                    if( (Test-Path -Path $overrideBasePath -PathType Leaf) )
                    {
                        $overrideBasePath = Split-Path -Parent -Path $overrideBasePath
                    }

                    $addParams['BasePath'] = $overrideBasePath
                    $addParams['EntryParentPath'] = $destinationItemName
                    $addParams.Remove('EntryName')
                    $destinationParam['Destination'] = $destinationItemName
                }

                $typeDesc = 'directory'
                if( $TaskParameter['Include'] -or $TaskParameter['Exclude'] )
                {
                    $typeDesc = 'filtered directory'
                }

                Write-CompressionInfo -What $typeDesc -Source $sourcePath @destinationParam
                Find-Item -Path $sourcePath |
                    Add-ZipArchiveEntry -ZipArchivePath $ArchivePath @addParams @behaviorParams
            }
        }
    }
    finally
    {
        if( $SourceRoot )
        {
            Pop-Location
        }
    }
}