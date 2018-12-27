
function New-WhiskeyZipArchive
{
    [Whiskey.Task("Zip")]
    [Whiskey.RequiresTool('PowerShellModule::Zip','ZipPath',Version='0.2.*',VersionParameterName='ZipVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $archivePath = $TaskParameter['ArchivePath']
    $archivePath = Join-Path -Path $TaskContext.BuildRoot -ChildPath $archivePath

    $behaviorParams = @{ }
    if( $TaskParameter['CompressionLevel'] )
    {
        [IO.Compression.CompressionLevel]$compressionLevel = [IO.Compression.CompressionLevel]::NoCompression
        if( -not [Enum]::TryParse($TaskParameter['CompressionLevel'], [ref]$compressionLevel) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'CompressionLevel' -Message ('Value "{0}" is an invalid compression level. Must be one of: {1}.' -f $TaskParameter['CompressionLevel'],([enum]::GetValues([IO.Compression.CompressionLevel]) -join ', '))
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

    $parentPathParam = @{ }
    $sourceRoot = $TaskContext.BuildRoot
    if( $TaskParameter.ContainsKey('SourceRoot') )
    {
        $sourceRoot = $TaskParameter['SourceRoot'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'SourceRoot'
        $parentPathParam['ParentPath'] = $sourceRoot
    }

    $sourceRootRegex = '^{0}' -f ([regex]::Escape($sourceRoot))

    Write-WhiskeyInfo -Context $TaskContext -Message ('Creating ZIP archive "{0}".' -f ($archivePath -replace $sourceRootRegex,'').Trim('\','/'))
    New-ZipArchive -Path $archivePath @behaviorParams

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
        $pathparam = 'Path'

        $sourcePaths = $sourcePath | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path' @parentPathParam
        if( -not $sourcePaths )
        {
            return
        }

        foreach( $sourcePath in $sourcePaths )
        {
            $relativePath = $sourcePath -replace $sourceRootRegex,''
            $relativePath = $relativePath.Trim('\')

            $addParams = @{ BasePath = $sourceRoot }
            $overrideInfo = ''
            if( $override )
            {
                $addParams = @{ PackageItemName = $destinationItemName }
                $overrideInfo = ' -> {0}' -f $destinationItemName
            }

            if( (Test-Path -Path $sourcePath -PathType Leaf) )
            {
                Write-WhiskeyInfo -Context $TaskContext -Message ('  compressing file               {0}{1}' -f $relativePath,$overrideInfo)
                Add-ZipArchiveEntry -ZipArchivePath $archivePath -InputObject $sourcePath @addParams @behaviorParams
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
                $addParams['BasePath'] = $sourcePath
                $addParams['EntryParentPath'] = $destinationItemName
                $addParams.Remove('PackageItemName')
                $overrideInfo = ' -> {0}' -f $destinationItemName
            }

            $typeDesc = 'directory         '
            if( $TaskParameter['Include'] -or $TaskParameter['Exclude'] )
            {
                $typeDesc = 'filtered directory'
            }

            Write-WhiskeyInfo -Context $TaskContext -Message ('  compressing {0} {1}{2}' -f $typeDesc,$relativePath,$overrideInfo)
            Find-Item -Path $sourcePath |
                Add-ZipArchiveEntry -ZipArchivePath $archivePath @addParams @behaviorParams
        }
    }
}
