
function Invoke-WhsCIPublishFileTask
{
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

    if(!$TaskContext.Publish)
    {
        return
    } 

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
        Stop-WhsCITask -TaskContext $TaskContext -Message ($pathErrorMessage)
    }

    $sourceFiles = $TaskParameter['Path'] | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'Path'
    if(!$sourceFiles)
    {
        Stop-WhsCITask -TaskContext $TaskContext -Message ($pathErrorMessage)
    }

    if(!$TaskParameter.ContainsKey('DestinationDirectories'))
    {
        Stop-WhsCITask -TaskContext $TaskContext -Message ($destDirErrorMessage)
    }
    
    if(!$TaskParameter['DestinationDirectories'])
    {
        Stop-WhsCITask -TaskContext $TaskContext -Message ($destDirErrorMessage)
    }

    foreach($sourceFile in $sourceFiles)
    {
        if((Test-Path -Path $sourceFile -PathType Container))
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('File paths must resolve to individual files and not directories. Please adjust your ''Path'' property to a valid list of files to publish.')
        }
    }
    
    foreach ($destDir in $TaskParameter['DestinationDirectories'])
    {
        if(!(Test-Path -Path $destDir -PathType Container))
        {
            Write-Verbose ('The destination directory ''{0}'' does not exist. Creating this directory now..' -f $destDir)
            $null = New-Item -Path $destDir -ItemType 'Directory' -Force
        }
        
        if(!(Test-Path -Path $destDir -PathType Container))
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('Failed to create destination directory ''{0}''. Make sure the current user, ''{1}\{2}'' has access to ''{0}''. If it is a share, check that the share exists.' -f $destDir, $env:USERDOMAIN, $env:USERNAME)
        }
    
        foreach($sourceFile in $sourceFiles)
        {
            Write-Verbose ('Copying ''{0}'' to ''{1}''' -f $sourceFile, $destDir)
            Copy-Item -Path $sourceFile -Destination $destDir
        }
    }
}
