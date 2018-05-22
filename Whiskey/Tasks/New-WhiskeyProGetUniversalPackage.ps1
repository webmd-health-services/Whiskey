
function New-WhiskeyProGetUniversalPackage
{
    [CmdletBinding()]
    [Whiskey.Task("ProGetUniversalPackage")]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    foreach( $mandatoryName in @( 'Name', 'Description' ) )
    {
        if( -not $TaskParameter.ContainsKey($mandatoryName) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''{0}'' is mandatory.' -f $mandatoryName)
        }
    }

    # ProGet uses build metadata to distinguish different versions, so we can't use a full semantic version.
    $version = $TaskContext.Version
    if( $TaskParameter.ContainsKey('Version') )
    {
        if( ($TaskParameter['Version'] -notmatch '^\d+\.\d+\.\d+$') )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''Version'' is invalid. It must be a three part version number, i.e. MAJOR.MINOR.PATCH.')
        }
        [SemVersion.SemanticVersion]$semVer = $null
        if( -not ([SemVersion.SemanticVersion]::TryParse($TaskParameter['Version'], [ref]$semVer)) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''Version'' is not a valid semantic version.')
        }
        $semVer = New-Object 'SemVersion.SemanticVersion' $semVer.Major,$semVer.Minor,$semVer.Patch,$version.SemVer2.Prerelease,$version.SemVer2.Build
        $version = New-WhiskeyVersionObject -SemVer $semVer
    }
    $name = $TaskParameter['Name']
    $description = $TaskParameter['Description']
    $exclude = $TaskParameter['Exclude']
    $thirdPartyPath = $TaskParameter['ThirdPartyPath']

    $compressionLevel = 1
    if( $TaskParameter['CompressionLevel'] )
    {
        $compressionLevel = $TaskParameter['CompressionLevel'] | ConvertFrom-WhiskeyYamlScalar -ErrorAction Ignore
        if( $compressionLevel -eq $null )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''CompressionLevel'': ''{0}'' is not a valid compression level. It must be an integer between 0-9.' -f $TaskParameter['CompressionLevel']);
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
    $fileName = '{0}.{1}.upack' -f $name,($version.SemVer2NoBuildMetadata -replace $fixRegex,'-')
    $outDirectory = $TaskContext.OutputDirectory

    $outFile = Join-Path -Path $outDirectory -ChildPath $fileName

    $tempRoot = $TaskContext.Temp
    $tempPackageRoot = Join-Path -Path $tempRoot -ChildPath 'package'
    New-Item -Path $tempPackageRoot -ItemType 'Directory' | Out-Null

    $upackJsonPath = Join-Path -Path $tempRoot -ChildPath 'upack.json'
    @{
        name = $name;
        version = $version.SemVer2NoBuildMetadata.ToString();
        title = $name;
        description = $description
    } | ConvertTo-Json | Set-Content -Path $upackJsonPath

    # Add the version.json file
    @{
        Version = $version.Version.ToString();
        SemVer2 = $version.SemVer2.ToString();
        SemVer2NoBuildMetadata = $version.SemVer2NoBuildMetadata.ToString();
        PrereleaseMetadata = $version.SemVer2.Prerelease;
        BuildMetadata = $version.SemVer2.Build;
        SemVer1 = $version.SemVer1.ToString();
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
                    New-Item -Path $parentDestinationPath -ItemType 'Directory' -Force | Out-String | Write-WhiskeyVerbose -Context $TaskContext
                }

                if( (Test-Path -Path $sourcePath -PathType Leaf) )
                {
                    Copy-Item -Path $sourcePath -Destination $destination
                }
                else
                {
                    $destinationDisplay = $destination -replace [regex]::Escape($tempRoot),''
                    $destinationDisplay = $destinationDisplay.Trim('\')
                    $taskTempDirectory = $TaskContext.Temp.FullName
                    if( $AsThirdPartyItem )
                    {
                        $robocopyExclude = @( $taskTempDirectory )
                        $whitelist = @( )
                        $operationDescription = 'packaging third-party {0} -> {1}' -f $sourcePath,$destinationDisplay
                    }
                    else
                    {
                        if( -not $TaskParameter['Include'] )
                        {
                            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''Include'' is mandatory because ''{0}'' is in your ''Path'' property and it is a directory. The ''Include'' property is a whitelist of files (wildcards supported) to include in your package. Only files in directories that match an item in the ''Include'' list will be added to your package.' -f $sourcePath)
                            return
                        }

                        $robocopyExclude = & {
                            $taskTempDirectory;
                            (Join-Path -Path $destination -ChildPath 'version.json');
                            $TaskParameter['Exclude'];
                        }

                        $operationDescription = 'packaging {0} -> {1}' -f $sourcePath,$destinationDisplay
                        $whitelist = & { 'upack.json' ; $TaskParameter['Include'] }
                    }

                    Write-WhiskeyInfo -Context $TaskContext -Message $operationDescription
                    Invoke-WhiskeyRobocopy -Source $sourcePath.trim("\") -Destination $destination.trim("\") -WhiteList $whitelist -Exclude $robocopyExclude | Write-WhiskeyVerbose -Context $TaskContext
                    # Get rid of empty directories. Robocopy doesn't sometimes.
                    Get-ChildItem -Path $destination -Directory -Recurse |
                        Where-Object { -not ($_ | Get-ChildItem) } |
                        Remove-Item
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

    Write-WhiskeyVerbose -Context $TaskContext -Message ('Creating universal package {0}' -f $outFile)
    & $7z 'a' '-tzip' ('-mx{0}' -f $compressionLevel) $outFile (Join-Path -Path $tempRoot -ChildPath '*')

    Write-WhiskeyVerbose -Context $TaskContext -Message ('returning package path ''{0}''' -f $outFile)
    $outFile
}
