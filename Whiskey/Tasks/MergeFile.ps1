
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

        [byte[]]$BinarySeparator
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

    Clear-Content -Path $DestinationPath

    [byte[]]$separatorBytes = $BinarySeparator
    if( $TextSeparator )
    {
        $separatorBytes = [Text.Encoding]::UTF8.GetBytes($TextSeparator)
    }

    $relativePath = Resolve-Path -Path $DestinationPath -Relative
    $writer = [IO.File]::OpenWrite($relativePath)
    try 
    {
        Write-WhiskeyInfo -Context $TaskContext -Message $relativePath -Verbose
        $afterFirst = $false
        foreach( $filePath in $Path )
        {
            $relativePath = Resolve-Path -Path $filePath -Relative
            Write-WhiskeyInfo -Context $TaskContext -Message ('    + {0}' -f $relativePath) -Verbose

            if( $afterFirst -and $separatorBytes )
            {
                $writer.Write($separatorBytes,0,$separatorBytes.Length)
            }
            $afterFirst = $true

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