
function Publish-WhiskeyFile
{
    [Whiskey.Task("PublishFile")]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $pathErrorMessage = @'
'Path' property is missing. Please set it to the list of files to publish, e.g.

BuildTasks:
- PublishFile:
    Path: myfile.txt
    Destination: \\computer\share
'@
    $destDirErrorMessage = @'
'DestinationDirectories' property is missing. Please set it to the list of target locations to publish to, e.g.

BuildTasks:
- PublishFile:
    Path: myfile.txt
    DestinationDirectories: \\computer\share
'@

    if(!$TaskParameter.ContainsKey('Path'))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ($pathErrorMessage)
    }

    $sourceFiles = $TaskParameter['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'Path'
    if(!$sourceFiles)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ($pathErrorMessage)
    }

    if(!$TaskParameter.ContainsKey('DestinationDirectories'))
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ($destDirErrorMessage)
    }
    
    if(!$TaskParameter['DestinationDirectories'])
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ($destDirErrorMessage)
    }

    foreach($sourceFile in $sourceFiles)
    {
        if((Test-Path -Path $sourceFile -PathType Container))
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Path ''{0}'' is directory. The PublishFile task only publishes files. Please remove this path from your ''Path'' property.' -f $sourceFile)
        }
    }
    
    foreach ($destDir in $TaskParameter['DestinationDirectories'])
    {
        if(!(Test-Path -Path $destDir -PathType Container))
        {
            $null = New-Item -Path $destDir -ItemType 'Directory' -Force
        }
        
        if(!(Test-Path -Path $destDir -PathType Container))
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Failed to create destination directory ''{0}''. Make sure the current user, ''{1}\{2}'' has access to create directories in ''{0}''. If it is a file share, check that the share exists and the share''s permissions.' -f $destDir, $env:USERDOMAIN, $env:USERNAME)
        }
    }

    foreach( $destDir in $TaskParameter['DestinationDirectories'] )
    {
        foreach($sourceFile in $sourceFiles)
        {
            Copy-Item -Path $sourceFile -Destination $destDir
        }
    }
}

