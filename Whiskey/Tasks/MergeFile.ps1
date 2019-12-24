
function Merge-WhiskeyFile
{
    [CmdletBinding()]
    [Whiskey.Task('MergeFile')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String[]]$Path,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',AllowNonexistent,Create)]
        [String]$DestinationPath,

        [switch]$DeleteSourceFiles,

        [String]$TextSeparator,

        [Byte[]]$BinarySeparator,

        [switch]$Clear,

        [String[]]$Exclude
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $Clear )
    {
        Clear-Content -Path $DestinationPath
    }

    if( $TextSeparator -and $BinarySeparator )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext `
                         -Message ('You can''t use both a text separator and binary separator when merging files. Please use only the TextSeparator or BinarySeparator property, not both.')
        return
    }

    [Byte[]]$separatorBytes = $BinarySeparator
    if( $TextSeparator )
    {
        $separatorBytes = [Text.Encoding]::UTF8.GetBytes($TextSeparator)
    }

    $relativePath = Resolve-Path -Path $DestinationPath -Relative
    $writer = [IO.File]::OpenWrite($relativePath)
    try 
    {
        Write-WhiskeyInfo -Context $TaskContext -Message $relativePath 

        # Move to the end of the file.
        $writer.Position = $writer.Length

        # Only add the separator first if we didn't clear the file's original contents.
        $addSeparator = (-not $Clear) -and ($writer.Length -gt 0)

        # Normalize the exclusion pattern so it works across platforms.
        $Exclude = 
            $Exclude | 
            ForEach-Object { $_ -replace '\\|/',[IO.Path]::DirectorySeparatorChar }
        foreach( $filePath in $Path )
        {
            $excluded = $false
            foreach( $pattern in $Exclude )
            {
                if( $filePath -like $pattern )
                {
                    Write-WhiskeyVerbose -Context $TaskContext -Message ('Skipping file "{0}": it matches exclusion pattern "{1}".' -f $filePath,$pattern)
                    $excluded = $true
                    break
                }
                else 
                {
                    Write-WhiskeyDebug -Context $TaskContext -Message ('"{0}" -notlike "{1}"' -f $filePath,$pattern)
                }
            }

            if( $excluded )
            {
                continue
            }

            $relativePath = Resolve-Path -Path $filePath -Relative
            Write-WhiskeyInfo -Context $TaskContext -Message ('    + {0}' -f $relativePath)

            if( $addSeparator -and $separatorBytes )
            {
                $writer.Write($separatorBytes,0,$separatorBytes.Length)
            }
            $addSeparator = $true

            $reader = [IO.File]::OpenRead($filePath)
            try
            {
                $bufferSize = 4kb
                [Byte[]]$buffer = New-Object 'byte[]' ($bufferSize)
                while( $bytesRead = $reader.Read($buffer,0,$bufferSize) )
                {
                    $writer.Write($buffer,0,$bytesRead)
                }
            }
            finally
            {
                $reader.Close()
            }

            if( $DeleteSourceFiles )
            {
                Remove-Item -Path $filePath -Force
            }
        }
    }
    finally
    {
        $writer.Close()
    }
}
