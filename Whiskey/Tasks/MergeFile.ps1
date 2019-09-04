
function Merge-WhiskeyFile
{
    [CmdletBinding()]
    [Whiskey.Task('MergeFile')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [string[]]$Path,

        [string]$DestinationPath,

        [switch]$DeleteSourceFiles,

        [string]$TextSeparator,

        [byte[]]$BinarySeparator,

        [switch]$Clear,

        [string[]]$Exclude
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $DestinationPath = Resolve-WhiskeyTaskPath -TaskContext $TaskContext `
                                               -Path $DestinationPath `
                                               -PropertyName 'DestinationPath' `
                                               -PathType 'File' `
                                               -Force
    
    $normalizedBuildRoot = $TaskContext.BuildRoot.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $normalizedBuildRoot = Join-Path -Path $normalizedBuildRoot -ChildPath ([IO.Path]::DirectorySeparatorChar)
    if( -not $DestinationPath.StartsWith($normalizedBuildRoot) )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'DestinationPath' -Message ('"{0}" resolves to "{1}", which is outside the build root "{2}".' -f $PSBoundParameters['DestinationPath'],$DestinationPath,$TaskContext.BuildRoot.FullName)
        return
    }

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

    [byte[]]$separatorBytes = $BinarySeparator
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
                    Write-Debug -Message ('"{0}" -notlike "{1}"' -f $filePath,$pattern)
                }
            }

            if( $excluded )
            {
                continue
            }

            $relativePath = Resolve-Path -Path $filePath -Relative
            Write-WhiskeyInfo -Context $TaskContext -Message ('    + {0}' -f $relativePath) -Verbose

            if( $addSeparator -and $separatorBytes )
            {
                $writer.Write($separatorBytes,0,$separatorBytes.Length)
            }
            $addSeparator = $true

            $reader = [IO.File]::OpenRead($filePath)
            try
            {
                $bufferSize = 4kb
                [byte[]]$buffer = New-Object 'byte[]' ($bufferSize)
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
