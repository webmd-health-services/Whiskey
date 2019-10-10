
function New-WhiskeyProGetUniversalPackage
{
    [CmdletBinding()]
    [Whiskey.Task("ProGetUniversalPackage")]
    [Whiskey.RequiresTool('PowerShellModule::ProGetAutomation','ProGetAutomationPath',Version='0.9.*',VersionParameterName='ProGetAutomationVersion')]
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

    Import-WhiskeyPowerShellModule -Name 'ProGetAutomation'

    $manifestProperties = @{}
    if( $TaskParameter.ContainsKey('ManifestProperties') )
    {
        $manifestProperties = $TaskParameter['ManifestProperties']
        foreach( $taskProperty in @( 'Name', 'Description', 'Version' ))
        {
            if( $manifestProperties.Keys -contains $taskProperty )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('"ManifestProperties" contains key "{0}". This property cannot be manually defined in "ManifestProperties" as it is set automatically from the corresponding task property "{0}".' -f $taskProperty)
                return
            }
        }
    }

    foreach( $mandatoryProperty in @( 'Name', 'Description' ) )
    {
        if( -not $TaskParameter.ContainsKey($mandatoryProperty) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "{0}" is mandatory.' -f $mandatoryProperty)
            return
        }
    }

    $name = $TaskParameter['Name']
    $validNameRegex = '^[0-9A-z\-\._]{1,50}$'
    if ($name -notmatch $validNameRegex)
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message '"Name" property is invalid. It should be a string of one to fifty characters: numbers (0-9), upper and lower-case letters (A-z), dashes (-), periods (.), and underscores (_).'
        return
    }

    $version = $TaskParameter['Version']

    # ProGet uses build metadata to distinguish different versions, so we can't use a full semantic version.
    if( $version )
    {
        if( ($version -notmatch '^\d+\.\d+\.\d+$') )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Version" is invalid. It must be a three part version number, i.e. MAJOR.MINOR.PATCH.')
            return
        }
        [SemVersion.SemanticVersion]$semVer = $null
        if( -not ([SemVersion.SemanticVersion]::TryParse($version, [ref]$semVer)) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Version" is not a valid semantic version.')
            return
        }
        $semVer = New-Object 'SemVersion.SemanticVersion' $semVer.Major,$semVer.Minor,$semVer.Patch,$TaskContext.Version.SemVer2.Prerelease,$TaskContext.Version.SemVer2.Build
        $version = New-WhiskeyVersionObject -SemVer $semVer
    }
    else
    {
        $version = $TaskContext.Version
    }

    $compressionLevel = [IO.Compression.CompressionLevel]::Optimal
    if( $TaskParameter['CompressionLevel'] )
    {
        $expectedValues = [enum]::GetValues([IO.Compression.CompressionLevel])
        $compressionLevel = $TaskParameter['CompressionLevel']
        if( $compressionLevel -notin $expectedValues )
        {
            [int]$intCompressionLevel = 0
            if( -not [int]::TryParse($TaskParameter['CompressionLevel'],[ref]$intCompressionLevel) )
            {
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "CompressionLevel": "{0}" is not a valid compression level. It must be one of: {1}' -f $TaskParameter['CompressionLevel'],($expectedValues -join ', '));
                return
            }
            $compressionLevel = $intCompressionLevel
            if( $compressionLevel -ge 5 )
            {
                $compressionLevel = [IO.Compression.CompressionLevel]::Optimal
            }
            else
            {
                $compressionLevel = [IO.Compression.CompressionLevel]::Fastest
            }
            Write-Warning -Message ('The ProGetUniversalPackage task no longer supports integer-style compression levels. Please update your task in your whiskey.yml file to use one of the new values: {0}. We''re converting the number you provided, "{1}", to "{2}".' -f ($expectedValues -join ', '),$TaskParameter['CompressionLevel'],$compressionLevel)
        }
    }

    $parentPathParam = @{ }
    $sourceRoot = $TaskContext.BuildRoot
    if( $TaskParameter.ContainsKey('SourceRoot') )
    {
        $sourceRoot = $TaskParameter['SourceRoot'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName 'SourceRoot'
        $parentPathParam['ParentPath'] = $sourceRoot
    }

    $tempRoot = Join-Path -Path $TaskContext.Temp -ChildPath 'upack'
    New-Item -Path $tempRoot -ItemType 'Directory' | Out-Null

    $tempPackageRoot = Join-Path -Path $tempRoot -ChildPath 'package'
    New-Item -Path $tempPackageRoot -ItemType 'Directory' | Out-Null

    $upackJsonPath = Join-Path -Path $tempRoot -ChildPath 'upack.json'
    $manifestProperties | ConvertTo-Json | Set-Content -Path $upackJsonPath

    # Add the version.json file
    $versionJsonPath = Join-Path -Path $tempPackageRoot -ChildPath 'version.json'
    @{
        Version = $version.Version.ToString();
        SemVer2 = $version.SemVer2.ToString();
        SemVer2NoBuildMetadata = $version.SemVer2NoBuildMetadata.ToString();
        PrereleaseMetadata = $version.SemVer2.Prerelease;
        BuildMetadata = $version.SemVer2.Build;
        SemVer1 = $version.SemVer1.ToString();
    } | ConvertTo-Json -Depth 1 | Set-Content -Path $versionJsonPath

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
                $relativePath = $relativePath.Trim([IO.Path]::DirectorySeparatorChar)

                $addParams = @{ BasePath = $sourceRoot }
                $overrideInfo = ''
                if( $override )
                {
                    $addParams = @{ PackageItemName = $destinationItemName }
                    $overrideInfo = ' -> {0}' -f $destinationItemName
                }
                $addParams['CompressionLevel'] = $compressionLevel

                if( $AsThirdPartyItem )
                {
                    Write-WhiskeyInfo -Context $TaskContext -Message ('  packaging unfiltered item    {0}{1}' -f $relativePath,$overrideInfo)
                    Get-Item -Path $sourcePath |
                        Add-ProGetUniversalPackageFile -PackagePath $outFile @addParams -ErrorAction Stop
                    continue
                }

                if( (Test-Path -Path $sourcePath -PathType Leaf) )
                {
                    Write-WhiskeyInfo -Context $TaskContext -Message ('  packaging file               {0}{1}' -f $relativePath,$overrideInfo)
                    Add-ProGetUniversalPackageFile -PackagePath $outFile -InputObject $sourcePath @addParams -ErrorAction Stop
                    continue
                }

                if( -not $TaskParameter['Include'] )
                {
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Include" is mandatory because "{0}" is in your "Path" property and it is a directory. The "Include" property is a whitelist of files (wildcards supported) to include in your package. Only files in directories that match an item in the "Include" list will be added to your package.' -f $sourcePath)
                    return
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
                    $addParams.Remove('PackageItemName')
                    $overrideInfo = ' -> {0}' -f $destinationItemName

                    if ($destinationItemName -ne '.')
                    {
                        $addParams['PackageParentPath'] = $destinationItemName
                    }
                }

                Write-WhiskeyInfo -Context $TaskContext -Message ('  packaging filtered directory {0}{1}' -f $relativePath,$overrideInfo)
                Find-Item -Path $sourcePath |
                    Add-ProGetUniversalPackageFile -PackagePath $outFile @addParams -ErrorAction Stop
            }
        }
    }

    $badChars = [IO.Path]::GetInvalidFileNameChars() | ForEach-Object { [regex]::Escape($_) }
    $fixRegex = '[{0}]' -f ($badChars -join '')
    $fileName = '{0}.{1}.upack' -f $name,($version.SemVer2NoBuildMetadata -replace $fixRegex,'-')

    $outFile = Join-Path -Path $TaskContext.OutputDirectory -ChildPath $fileName

    if( (Test-Path -Path $outFile -PathType Leaf) )
    {
        Remove-Item -Path $outFile -Force
    }

    if( -not $manifestProperties.ContainsKey('title') )
    {
        $manifestProperties['title'] = $TaskParameter['Name']
    }

    $outFileDisplay = $outFile -replace ('^{0}' -f [regex]::Escape($TaskContext.BuildRoot)),''
    $outFileDisplay = $outFileDisplay.Trim([IO.Path]::DirectorySeparatorChar)
    Write-WhiskeyInfo -Context $TaskContext -Message ('Creating universal package "{0}".' -f $outFileDisplay)
    New-ProGetUniversalPackage -OutFile $outFile `
                               -Version $version.SemVer2NoBuildMetadata.ToString() `
                               -Name $TaskParameter['Name'] `
                               -Description $TaskParameter['Description'] `
                               -AdditionalMetadata $manifestProperties

    Add-ProGetUniversalPackageFile -PackagePath $outFile -InputObject $versionJsonPath -ErrorAction Stop

    if( $TaskParameter['Path'] )
    {
        Copy-ToPackage -Path $TaskParameter['Path']
    }

    if( $TaskParameter.ContainsKey('ThirdPartyPath') -and $TaskParameter['ThirdPartyPath'] )
    {
        Copy-ToPackage -Path $TaskParameter['ThirdPartyPath'] -AsThirdPartyItem
    }
}
