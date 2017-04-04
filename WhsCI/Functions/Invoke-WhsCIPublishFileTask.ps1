
function Invoke-WhsCIPublishFileTask
{
    <#
    .SYNOPSIS
    Publishes one or more files to one or more directories
    
    .DESCRIPTION
    The `Invoke-WhsCIPublishFileTask` function will accept a list of files and a list of directories.

    If a defined directory does not exist, it will be created before any files are copied.

    This task accepts these parameters:

    * `SourceFiles`: a comma-separated list of one or more file paths to be published - path(s) must be relative to the $TaskContext.BuildRoot
    * `DestinationDirectories`: a comma-separated list of one or more target locations where the files will be published - path(s) must be absolute
    
    .EXAMPLE
    Invoke-WhsCIPublishFileTask -TaskContext $context -TaskParameter @{ 
                                                                        SourceFiles = ('\PathToPackage\RelativeTo\WhsBuild.yml', '\Arc\Enable_Arc.ps1');
                                                                        DestinationDirectories = ('C:\Build\Dir1', 'C:\Build\Dir2')
                                                                      }

    Demonstrates how to `publish` the specified files to the two distinct directories.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context the task is running under.
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        # The parameters/configuration to use to run the task. Should be a hashtable that contains the following item:
        #
        # * `SourceFiles` (Required): One or more 'file' paths relative to the directory where the build's `whsbuild.yml` file was found.
        # * `DestinationDirectories` (Required): One or more absolute 'directory' paths to copy the files
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if(!$TaskContext.Publish)
    {
        return
    } 

    if(!$TaskParameter.ContainsKey('SourceFiles'))
    {
        Write-Error -Message 'No source files were defined. Please provide a valid list of files utilizing the `TaskParameter.SourceFiles` parameter.'
        return
    }
    
    if(!$TaskParameter.SourceFiles)
    {
        Write-Error -Message 'No source files were defined. Please provide a valid list of files utilizing the `TaskParameter.SourceFiles` parameter.'
        return
    }

    if(!$TaskParameter.ContainsKey('DestinationDirectories'))
    {
        Write-Error -Message 'No target directory locations were defined. Please provide a valid list of directories utilizing the `TaskParameter.DestinationDirectories` parameter.'
        return
    }

    if(!$TaskParameter.DestinationDirectories)
    {
        Write-Error -Message 'No target directory locations were defined. Please provide a valid list of directories utilizing the `TaskParameter.DestinationDirectories` parameter.'
        return
    }

    foreach ($destDir in $TaskParameter.DestinationDirectories)
    {
        if(!(Test-Path -Path $destDir -PathType Container -IsValid))
        {
            Write-Error ('Cannot find drive. A drive with the name ''{0}'' does not exist.' -f $destDir)
            return
        }
    }
    
    foreach ($destDir in $TaskParameter.DestinationDirectories)
    {
        if(!(Test-Path -Path $destDir -PathType Container))
        {
            Write-Verbose ('The destination directory ''{0}'' does not exist. Creating this directory now..' -f $destDir)
            Install-Directory -Path $destDir
        }
    
        foreach($sourceFile in $TaskParameter.SourceFiles)
        {        
            $sourceFilePath = Join-Path -Path $TaskContext.BuildRoot -ChildPath $sourceFile
            if(!(Test-Path -Path $sourceFilePath -PathType Leaf))
            {
                Write-Warning -Message ('The source file ''{0}'' does not exist. Will not attempt to copy this file.' -f $sourceFile)
            }
            else
            {    
                Write-Verbose ('Copying ''{0}'' to ''{1}''' -f $sourceFile, $destDir)
                Copy-Item -Path $sourceFilePath -Destination $destDir
            }
        }
    }
}
