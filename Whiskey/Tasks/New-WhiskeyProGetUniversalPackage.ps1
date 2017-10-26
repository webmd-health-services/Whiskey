
function New-WhiskeyProGetUniversalPackage
{
    [CmdletBinding()]
    [Whiskey.Task("ProGetUniversalPackage",SupportsClean=$true, SupportsInitialize=$true)]
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

    $7zipPackageName = '7-zip.x64'
    $7zipVersion = '16.2.1'
    # The directory name where NuGet puts this package is different than the version number.
    $7zipDirNameVersion = '16.02.1'
    if( $TaskContext.ShouldClean() )
    {
        Uninstall-WhiskeyTool -NuGetPackageName $7zipPackageName -Version $7zipDirNameVersion -BuildRoot $TaskContext.BuildRoot
        return
    }
    $7zipRoot = Install-WhiskeyTool -NuGetPackageName $7zipPackageName -Version $7zipVersion -DownloadRoot $TaskContext.BuildRoot
    $7zipRoot = $7zipRoot -replace [regex]::Escape($7zipVersion),$7zipDirNameVersion
    $7zExePath = Join-Path -Path $7zipRoot -ChildPath 'tools\7z.exe' -Resolve

    if( $TaskContext.ShouldInitialize() )
    {
        return
    }

    foreach( $mandatoryName in @( 'Name', 'Description', 'Include' ) )
    {
        if( -not $TaskParameter.ContainsKey($mandatoryName) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''{0}'' is mandatory.' -f $mandatoryName)
        }
    }

    # ProGet uses build metadata to distinguish different versions, so we can't use a full semantic version.
    $version = $TaskContext.Version.SemVer2NoBuildMetadata
    $name = $TaskParameter['Name']
    $description = $TaskParameter['Description']
    $path = $TaskParameter['Path']
    $include = $TaskParameter['Include']
    $exclude = $TaskParameter['Exclude']
    $thirdPartyPath = $TaskParameter['ThirdPartyPath']
    
    $compressionLevel = 1
    if( $TaskParameter['CompressionLevel'] )
    {
        $compressionLevel = $TaskParameter['CompressionLevel'] | ConvertFrom-WhiskeyYamlScalar -ErrorAction Ignore
        if( $compressionLevel -eq $null )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ComressionLevel: ''{0}'' is not a valid compression level. It must be an integer between 0-9.' -f $TaskParameter['CompressionLevel']);
        }
    }

    $parentPathParam = @{ }
    $sourceRoot = $TaskContext.BuildRoot
    if( $TaskParameter.ContainsKey('SourceRoot') )
    {
        $sourceRoot = $TaskParameter['SourceRoot'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'SourceRoot'
        $parentPathParam['ParentPath'] = $sourceRoot
    }
    $badChars = [IO.Path]::GetInvalidFileNameChars() | ForEach-Object { [regex]::Escape($_) }
    $fixRegex = '[{0}]' -f ($badChars -join '')
    $fileName = '{0}.{1}.upack' -f $name,($version -replace $fixRegex,'-')
    $outDirectory = $TaskContext.OutputDirectory

    $outFile = Join-Path -Path $outDirectory -ChildPath $fileName

    $tempRoot = [IO.Path]::GetRandomFileName()
    $tempBaseName = 'Whiskey+New-WhiskeyProGetUniversalPackage+{0}' -f $name
    $tempRoot = '{0}+{1}' -f $tempBaseName,$tempRoot
    $tempRoot = Join-Path -Path $env:TEMP -ChildPath $tempRoot
    New-Item -Path $tempRoot -ItemType 'Directory' | Out-String | Write-Verbose
    $tempPackageRoot = Join-Path -Path $tempRoot -ChildPath 'package'
    New-Item -Path $tempPackageRoot -ItemType 'Directory' | Out-String | Write-Verbose

    try
    {
        $upackJsonPath = Join-Path -Path $tempRoot -ChildPath 'upack.json'
        @{
            name = $name;
            version = $version.ToString();
            title = $name;
            description = $description
        } | ConvertTo-Json | Set-Content -Path $upackJsonPath
        
        # Add the version.json file
        @{
            Version = $TaskContext.Version.Version.ToString();
            SemVer2 = $TaskContext.Version.SemVer2.ToString();
            SemVer2NoBuildMetadata = $TaskContext.Version.SemVer2NoBuildMetadata.ToString();
            PrereleaseMetadata = $TaskContext.Version.SemVer2.Prerelease;
            BuildMetadata = $TaskContext.Version.SemVer2.Build;
            SemVer1 = $TaskContext.Version.SemVer1.ToString();
        } | ConvertTo-Json -Depth 1 | Set-Content -Path (Join-Path -Path $tempPackageRoot -ChildPath 'version.json')
        
        function Copy-ToPackage
        {
            param(
                [Parameter(Mandatory=$true)]
                [object[]]
                $Path,
        
                [Switch]
                $AsThirdPartyItem
            )
    
            foreach( $item in $Path )
            {
                $override = $False
                if( $item -is [hashtable] )
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
                $pathparam = 'path'
                if( $AsThirdPartyItem )
                {
                    $pathparam = 'ThirdPartyPath'
                }

                $sourcePaths = $sourcePath | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName $pathparam @parentPathParam
                if( -not $sourcePaths )
                {
                    return
                }

                foreach( $sourcePath in $sourcePaths )
                {
                    $relativePath = $sourcePath -replace ('^{0}' -f ([regex]::Escape($sourceRoot))),''
                    $relativePath = $relativePath.Trim("\")
                    if( -not $override )
                    {
                        $destinationItemName = $relativePath
                    }

                    $destination = Join-Path -Path $tempPackageRoot -ChildPath $destinationItemName
                    $parentDestinationPath = ( Split-Path -Path $destination -Parent)

                    #if parent doesn't exist in the destination dir, create it
                    if( -not ( Test-Path -Path $parentDestinationPath ) )
                    {
                        New-Item -Path $parentDestinationPath -ItemType 'Directory' -Force | Out-String | Write-Verbose
                    }

                    if( (Test-Path -Path $sourcePath -PathType Leaf) )
                    {
                        Copy-Item -Path $sourcePath -Destination $destination
                    }
                    else
                    {
                        $destinationDisplay = $destination -replace [regex]::Escape($tempRoot),''
                        $destinationDisplay = $destinationDisplay.Trim('\')
                        if( $AsThirdPartyItem )
                        {
                            $exclude = @()
                            $whitelist = @()
                            $operationDescription = 'packaging third-party {0} -> {1}' -f $sourcePath,$destinationDisplay
                        }
                        else
                        {
                            $exclude = & { '.git' ;  '.hg' ; 'obj' ; $exclude ; (Join-Path -Path $destination -ChildPath 'version.json') } 
                            $operationDescription = 'packaging {0} -> {1}' -f $sourcePath,$destinationDisplay
                            $whitelist = Invoke-Command {
                                            'upack.json'
                                            $include
                                            }
                        }

                        Write-Verbose -Message $operationDescription
                        Invoke-WhiskeyRobocopy -Source $sourcePath.trim("\") -Destination $destination.trim("\") -WhiteList $whitelist -Exclude $exclude | Write-Verbose -Verbose
                    }
                }
            }
        }

        if( $TaskParameter['Path'] )
        {
            Copy-ToPackage -Path $TaskParameter['Path']
        }

        if( $TaskParameter.ContainsKey('ThirdPartyPath') -and $TaskParameter['ThirdPartyPath'] )
        {
            Copy-ToPackage -Path $TaskParameter['ThirdPartyPath'] -AsThirdPartyItem
        }

        Write-Verbose -Message ('Creating universal package {0}' -f $outFile)
        & $7zExePath 'a' '-tzip' ('-mx{0}' -f $compressionLevel) $outFile (Join-Path -Path $tempRoot -ChildPath '*')

        Write-Verbose -Message ('returning package path ''{0}''' -f $outFile)
        $outFile
    }
    finally
    {
        $maxTries = 50
        $tryNum = 0
        $failedToCleanUp = $true
        do
        {
            if( -not (Test-Path -Path $tempRoot -PathType Container) )
            {
                $failedToCleanUp = $false
                break
            }
            Write-Verbose -Message ('[{0,2}] Deleting directory ''{1}''.' -f $tryNum,$tempRoot)
            Start-Sleep -Milliseconds 100
            Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction Ignore
        }
        while( $tryNum++ -lt $maxTries )

        if( $failedToCleanUp )
        {
            Write-Warning -Message ('Failed to delete temporary directory ''{0}''.' -f $tempRoot)
        }
    }
}
