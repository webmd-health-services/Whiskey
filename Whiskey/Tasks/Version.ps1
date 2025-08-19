
function Set-WhiskeyVersion
{
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingPlainTextForPassword', '')]
    [Whiskey.Task('Version', DefaultParameterName='Version')]
    [Whiskey.RequiresPowerShellModule('ProGetAutomation',
                                        Version='3.*',
                                        VersionParameterName='ProGetAutomationVersion',
                                        ModuleInfoParameterName='ProGetAutomationModuleInfo')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        [String] $Version,

        [String] $DateFormat,

        [Object] $Prerelease,

        [String] $Build,

        [Whiskey.Tasks.ValidatePath(PathType='File')]
        [String] $Path,

        [String] $NuGetPackageID,

        [Uri] $UPackFeedUrl,

        [Uri] $ProGetUrl,

        [String] $UPackFeedName,

        [String] $UPackFeedCredentialID,

        [String] $UPackFeedApiKeyID,

        [String] $UPackGroupName,

        [String] $UPackName,

        [switch] $IncrementPatchVersion,

        [switch] $IncrementPrereleaseVersion
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    function ConvertTo-SemVer
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory,ValueFromPipeline)]
            $InputObject,

            $PropertyName,

            $VersionSource
        )

        process
        {
            [SemVersion.SemanticVersion]$semver = $null
            if( -not [SemVersion.SemanticVersion]::TryParse($InputObject, [ref]$semver) )
            {
                if( $VersionSource )
                {
                    $VersionSource = ' ({0})' -f $VersionSource
                }
                $optionalParam = @{ }
                if( $PropertyName )
                {
                    $optionalParam['PropertyName'] = $PropertyName
                }
                $msg = """$($InputObject)""$($VersionSource) is not a semantic version. See https://semver.org for " +
                       'documentation on semantic versions.'
                Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg @optionalParam
                return
            }
            return $semver
        }
    }

    if ($Version -and $DateFormat)
    {
        $msg = 'Properties "Version" and "DateFormat" are mutually exclusive. Use one or the other but not both.'
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    [int]$nextPrereleaseVersion = 1
    [Whiskey.BuildVersion]$buildVersion = $TaskContext.Version
    [SemVersion.SemanticVersion]$semver = $buildVersion.SemVer2
    [String[]] $versions = @()
    [bool] $skipPackageLookup = -not $IncrementPatchVersion -and -not $IncrementPrereleaseVersion

    if ($Version)
    {
        $rawVersion = $Version
        $semVer = $rawVersion | ConvertTo-SemVer -PropertyName 'Version'
    }
    elseif ($DateFormat)
    {
        $rawVersion = Get-Date $TaskContext.StartedAt -Format $DateFormat
        if (-not $rawVersion)
        {
            $msg = "Failed to get date-based version number from .NET date format string ""${DateFormat}""."
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
            return
        }

        # Trim any leading zeroes from each of the version parts since semantic versioning doesn't allow leading zeros.
        $parts = $rawVersion.Split('.')
        for ($idx = 0; $idx -lt $parts.Length; ++$idx)
        {
            $part = $parts[$idx].TrimStart('0')
            if (-not $part)
            {
                $part = '0'
            }
            $parts[$idx] = $part
        }
        $rawVersion = $parts -join '.'

        $semVer =
            $rawVersion |
            ConvertTo-SemVer -PropertyName 'DateFormat' -VersionSource "from date format ""${DateFormat}"""
    }
    else
    {
        if( $Path )
        {
            $fileInfo = Get-Item -Path $Path
            if( $fileInfo.Extension -eq '.psd1' )
            {
                $moduleManifest = Test-ModuleManifest -Path $Path -ErrorAction Ignore -WarningAction Ignore
                $rawVersion = $moduleManifest.Version
                if( -not $rawVersion )
                {
                    $msg = "Unable to read version from PowerShell module manifest ""$($Path)"": the manifest is invalid " +
                        'or doesn''t contain a "ModuleVersion" property.'
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                    return
                }

                $nextPrerelease = ''
                if( ($moduleManifest | Get-Member -Name 'Prerelease') )
                {
                    $nextPrerelease = $moduleManifest.Prerelease
                }
                elseif( $moduleManifest.PrivateData -and `
                        $moduleManifest.PrivateData.ContainsKey('PSData') -and `
                        $moduleManifest.PrivateData['PSData'].ContainsKey('Prerelease') )
                {
                    $nextPrerelease = $moduleManifest.PrivateData['PSData']['Prerelease']
                }

                if( $nextPrerelease )
                {
                    $rawVersion = "$($rawVersion)-$($nextPrerelease)"
                }

                $msg = "Read version ""$($rawVersion)"" from PowerShell module manifest ""$($Path)""."
                Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                $semver = $rawVersion | ConvertTo-SemVer -VersionSource "from PowerShell module manifest ""$($Path)"""

                if( -not $skipPackageLookup )
                {
                    $msg = "Retrieving versions for PowerShell module $($moduleManifest.Name)."
                    Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                    $allowPrereleaseArg = Get-AllowPrereleaseArg -CommandName 'Find-Module' -AllowPrerelease
                    $versions =
                        Find-Module -Name $moduleManifest.Name -AllVersions @allowPrereleaseArg -ErrorAction Ignore |
                        Select-Object -ExpandProperty 'Version'
                }
            }
            elseif( $fileInfo.Name -eq 'package.json' )
            {
                $npmPackage = [pscustomobject]::New()
                try
                {
                    $npmPackage = Get-Content -Path $Path -Raw | ConvertFrom-Json
                }
                catch
                {
                    $msg = "Node package.json file ""$($Path)"" contains invalid JSON."
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                    return
                }
                $rawVersion = $npmPackage | Select-Object -ExpandProperty 'Version' -ErrorAction Ignore
                if( -not $rawVersion )
                {
                    $msg = "Unable to read version from Node package.json ""$($Path)"": the ""Version"" property is " +
                        'missing.'
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                    return
                }
                $msg = "Read version ""$($rawVersion)"" from Node package.json ""$($Path)""."
                Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                $semVer = $rawVersion | ConvertTo-SemVer -VersionSource "from Node package.json file ""$($Path)"""

                $pkgName = $npmPackage | Select-Object -ExpandProperty 'name' -ErrorAction Ignore
                if( $pkgName -and -not $skipPackageLookup )
                {
                    $msg = "Retrieving versions for NPM package $($pkgName)."
                    Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                    Install-WhiskeyNode -InstallRootPath $TaskContext.BuildRoot `
                                        -OutFileRootPath $TaskContext.OutputDirectory
                    $packageVersions =
                        Invoke-WhiskeyNpmCommand -Name 'show' `
                                                 -ArgumentList @($pkgName, 'versions', '--json') `
                                                 -BuildRoot $TaskContext.BuildRoot `
                                                 -ForDeveloper:($TaskContext.ByDeveloper) `
                                                 -ErrorAction Ignore 2>$null |
                        ConvertFrom-Json

                    if ($packageVersions | Get-Member -Name 'error')
                    {
                        $errCode = $packageVersions.error | Select-Object -ExpandProperty 'code' -ErrorAction 'Ignore'
                        $errSummary = $packageVersions.error | Select-Object -ExpandProperty 'summary' -ErrorAction 'Ignore'

                        if ($errCode -eq 'E404')
                        {
                            $msg = "NPM package ""${pkgName}"" has never been published to the registry. No existing versions."
                        }
                        else
                        {
                            $msg = "Failed to retrieve versions for NPM package ""${pkgName}"": [${errCode}] ${errSummary}"
                        }

                        Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                        $IncrementPrereleaseVersion = $false
                        $versions = $semver
                    }
                    else
                    {
                        $versions = $packageVersions
                    }
                }
            }
            elseif( $fileInfo.Extension -eq '.csproj' )
            {
                [xml]$csprojXml = $null
                try
                {
                    $csprojxml = Get-Content -Path $Path -Raw
                }
                catch
                {
                    $msg = ".NET .csproj file ""$($Path)"" contains invalid XMl."
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                    return
                }

                if( $csprojXml.DocumentElement.Attributes['xmlns'] )
                {
                    $msg = ".NET .csproj file ""$($Path)"" has an ""xmlns"" attribute. .NET Core/Standard .csproj " +
                           'files should not have a default namespace anymore ' +
                           '(see https://docs.microsoft.com/en-us/dotnet/core/migration/). Please remove the "xmlns" ' +
                           'attribute from the root "Project" document element. If this is a .NET framework .csproj, it ' +
                           'doesn''t support versioning. Use the Whiskey Version task''s Version property to version ' +
                           'your assemblies.'
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                    return
                }

                $csprojVersionNode = $csprojXml.SelectSingleNode('/Project/PropertyGroup/Version')
                if( -not $csprojVersionNode )
                {
                    $msg = "Element ""/Project/PropertyGroup/Version"" does not exist in .NET .csproj file ""$($Path)"". " +
                        'Please create this element and set it to the MAJOR.MINOR.PATCH version of the next version ' +
                        'of your assembly.'
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                    return
                }
                $rawVersion = $csprojVersionNode.InnerText
                $msg = "Read version ""$($rawVersion)"" from .csproj file ""$($Path)"".'"
                Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                $semver = $rawVersion | ConvertTo-SemVer -VersionSource "from .csproj file ""$($Path)"""

                if( -not $skipPackageLookup )
                {
                    if( -not $NuGetPackageID )
                    {
                        $node = $csprojXml.SelectSingleNode('/Project/PropertyGroup/PackageId')
                        if( $node )
                        {
                            $NuGetPackageID = $node.InnerText
                        }
                    }

                    if( $NuGetPackageID )
                    {
                        $msg = "Retrieving versions for NuGet package ""$($NuGetPackageID)""."
                        Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                        $allowPrereleaseArg = Get-AllowPrereleaseArg -CommandName 'Find-Package' -AllowPrerelease
                        $versions =
                            Find-Package -Name $NuGetPackageID -ProviderName 'NuGet' -AllVersions @allowPrereleaseArg |
                            Select-Object -ExpandProperty 'Version'
                    }
                }
            }
            elseif( $fileInfo.Name -eq 'metadata.rb' )
            {
                $metadataContent = Get-Content -Path $Path -Raw
                $metadataContent = $metadataContent.Split([Environment]::NewLine) | Where-Object { $_ -ne '' }

                $rawVersion = $null
                foreach( $line in $metadataContent )
                {
                    if( $line -match '^\s*version\s+[''"](\d+\.\d+\.\d+)[''"]' )
                    {
                        $rawVersion = $Matches[1]
                        break
                    }
                }

                if( -not $rawVersion )
                {
                    $msg = "Unable to locate property ""version 'x.x.x'"" in metadata.rb file ""$($Path)"""
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                    return
                }

                $msg = "Read version ""$($rawVersion)"" from metadata.rb file ""$($Path)""."
                Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                $semver = $rawVersion | ConvertTo-SemVer -VersionSource "from metadata.rb file ""$($Path)"""
            }
        }
    }

    if( -not $skipPackageLookup )
    {
        if( $UPackName )
        {
            $credArgs = @{}
            if ($UPackFeedCredentialID)
            {
                $credArgs['Credential'] = Get-WhiskeyCredential -Context $TaskContext `
                                                                -ID $UPackFeedCredentialID `
                                                                -PropertyName 'UPackFeedCredentialID'
            }
            if ($UPackFeedApiKeyID)
            {
                $credArgs['ApiKey'] =
                    Get-WhiskeyApiKey -Context $TaskContext -ID $UPackFeedApiKeyID -PropertyName 'UPackFeedApiKeyID'
            }

            if ($UPackFeedUrl)
            {
                $msg = 'The "UPackFeedUrl" property is obsolete. Use the "ProGetUrl" and "UPackFeedName" properties ' +
                       'instead.'
                Write-WhiskeyWarning $msg

                $ProGetUrl = "$($UPackFeedUrl.Scheme)://$($UPackFeedUrl.Authority)"
                $UPackFeedName = $UPackFeedUrl.Segments[-1]
            }

            $pgSession = New-ProGetSession -Url $ProGetUrl @credArgs

            $groupArg = @{}
            if ($UPackGroupName)
            {
                $groupArg['GroupName'] = $UPackGroupName
            }

            $msg = "Retrieving versions for universal package $($UPackName)."
            Write-WhiskeyVerbose -Context $TaskContext -Message $msg
            $numErr = $Global:Error.Count
            try
            {
                $versions = Get-ProGetUniversalPackage -Session $pgSession `
                                                        -FeedName $UPackFeedName `
                                                        -Name $UPackName `
                                                        @groupArg |
                                Select-Object -ExpandProperty 'versions'
            }
            catch
            {
                $versions = @()
                for( $idx = $Global:Error.Count ; $idx -gt $numErr ; --$idx )
                {
                    $Global:Error.RemoveAt(0)
                }
            }
        }
        elseif( $NuGetPackageID )
        {
            $msg = "Retrieving versions for NuGet package ""$($NuGetPackageID)""."
            Write-WhiskeyVerbose -Context $TaskContext -Message $msg
            $allowPrereleaseArg = Get-AllowPrereleaseArg -CommandName 'Find-Package' -AllowPrerelease
            $versions =
                Find-Package -Name $NuGetPackageID -ProviderName 'NuGet' -AllVersions @allowPrereleaseArg |
                Select-Object -ExpandProperty 'Version'
        }
    }

    $nextPrerelease = $Prerelease
    if( $nextPrerelease -isnot [String] )
    {
        $foundLabel = $false
        foreach( $object in $nextPrerelease )
        {
            foreach( $map in $object )
            {
                if( -not ($map | Get-Member -Name 'Keys') )
                {
                    $msg = "Unable to find keys in ""[$($map.GetType().Name)]$($map)"". It looks like you're trying " +
                           'use the Prerelease property to map branches to prerelease versions. If you want a static ' +
                           "prerelease version, the syntax should be:

    Build:
    - Version:
        Prerelease: $($map)

If you want certain branches to always have certain prerelease versions, set Prerelease to a list of key/value pairs:

    Build:
    - Version:
        Prerelease:
        - feature/*: alpha.`$(WHISKEY_PRERELEASE_VERSION)
        - develop: beta.`$(WHISKEY_PRERELEASE_VERSION)
    "

                    Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Prerelease' -Message $msg
                    return
                }

                $buildInfo = $TaskContext.BuildMetadata
                $branch = $buildInfo.ScmBranch
                if( $buildInfo.IsPullRequest )
                {
                    $branch = $buildInfo.ScmSourceBranch
                }

                foreach( $wildcardPattern in $map.Keys )
                {
                    if( $branch -like $wildcardPattern )
                    {
                        Write-WhiskeyVerbose -Context $TaskContext -Message "$($branch)     -like  $($wildcardPattern)"
                        $foundLabel = $true
                        $nextPrerelease = $map[$wildcardPattern]
                        break
                    }
                    else
                    {
                        Write-WhiskeyVerbose -Context $TaskContext -Message "$($branch)  -notlike  $($wildcardPattern)"
                    }
                }

                if( $foundLabel )
                {
                    break
                }
            }

            if( $foundLabel )
            {
                break
            }
        }

        if( -not $foundLabel )
        {
            $nextPrerelease = ''
        }
    }

    if( $nextPrerelease )
    {
        $buildSuffix = ''
        if( $semver.Build )
        {
            $buildSuffix = '+{0}' -f $semver.Build
        }

        $rawVersion = '{0}.{1}.{2}-{3}{4}' -f $semver.Major,$semver.Minor,$semver.Patch,$nextPrerelease,$buildSuffix
        if( -not [SemVersion.SemanticVersion]::TryParse($rawVersion,[ref]$semver) )
        {
            $msg = """$($nextPrerelease)"" is not a valid prerelease version. Only letters, numbers, hyphens, and " +
                   'periods are allowed. See https://semver.org for full documentation.'
            Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Prerelease' -Message $msg
            return
        }
    }

    if( $semver.Prerelease -match '(\d+)' )
    {
        $nextPrereleaseVersion = $Matches[1]
    }
    else
    {
        $nextPrereleaseVersion = 1
    }

    if( $versions )
    {
        [SemVersion.SemanticVersion[]] $semVersions =
            $versions |
            ConvertTo-SemVer -ErrorAction Ignore |
            ForEach-Object {
                if ($_.Prerelease -notmatch '^([A-Za-z-]+)(\d+)$')
                {
                    return $_
                }

                $nextPrerelease = "$($Matches[1]).$($Matches[2])"
                return [SemVersion.SemanticVersion]::New($_.Major, $_.Minor, $_.Patch, $nextPrerelease, $_.Build)
            }
        $sortedSemVersions = [Collections.Generic.SortedSet[SemVersion.SemanticVersion]]::New($semversions)
        $semVersions = [SemVersion.SemanticVersion[]]::New($sortedSemVersions.Count)
        $sortedSemVersions.CopyTo($semVersions)
        [Array]::Reverse($semVersions)

        $semVersions | Write-WhiskeyDebug -Context $TaskContext

        if( $IncrementPatchVersion )
        {
            $patchVersion = 0
            $baseMajorMinorVersion = @($semver.Major,$semver.Minor) -join '.'
            $lastVersion =
                $semVersions |
                Where-Object { (@($_.Major,$_.Minor) -join '.') -eq $baseMajorMinorVersion } |
                Select-Object -First 1
            if( $lastVersion )
            {
                $patchVersion = $lastVersion.Patch + 1
            }

            $nextPrerelease = $semver.Prerelease -replace '\d+', 1
            $semver = [SemVersion.SemanticVersion]::New($semver.Major, $semver.Minor, $patchVersion, $nextPrerelease,
                                                        $semver.Build)
        }

        if ($IncrementPrereleaseVersion -and $semver.Prerelease)
        {
            $baseVersion = @($semver.Major, $semver.Minor, $semver.Patch) -join '.'
            $prereleaseIdentifier = $semver.Prerelease -replace '[^A-Za-z]', ''
            $lastVersion =
                $semVersions |
                Where-Object { (@($_.Major,$_.Minor,$_.Patch) -join '.') -eq $baseVersion } |
                Where-Object { ($_.Prerelease -replace '[^A-Za-z]', '') -eq $prereleaseIdentifier } |
                Select-Object -First 1

            $nextPrereleaseVersion = 1
            if ($lastVersion -and $lastVersion.Prerelease -match '(\d+)')
            {
                $nextPrereleaseVersion = [int]$Matches[1]
                $nextPrereleaseVersion += 1
            }

            $nextPrerelease = "$($semver.Prerelease).${nextPrereleaseVersion}"
            if ($semver.Prerelease -match '\d+')
            {
                $nextPrerelease = $semver.Prerelease -replace '\d+', $nextPrereleaseVersion
            }

            $semver = [SemVersion.SemanticVersion]::New($semver.Major, $semver.Minor, $semver.Patch, $nextPrerelease,
                                                        $semver.Build)
        }
    }

    if ($Build)
    {
        $prereleaseSuffix = ''
        if( $semver.Prerelease )
        {
            $prereleaseSuffix = '-{0}' -f $semver.Prerelease
        }

        $Build = $Build -replace '[^A-Za-z0-9\.-]', '-'
        $rawVersion = '{0}.{1}.{2}{3}+{4}' -f $semver.Major,$semver.Minor,$semver.Patch,$prereleaseSuffix,$Build
        if( -not [SemVersion.SemanticVersion]::TryParse($rawVersion,[ref]$semver) )
        {
            $msg = """$($Build)"" is not valid build metadata. Only letters, numbers, hyphens, and periods are " +
                   'allowed. See https://semver.org for full documentation.'
            Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Build' -Message $msg
            return
        }
    }

    # Build metadata is only available when running under a build server.
    if( $TaskContext.ByDeveloper )
    {
        $semver = New-Object -TypeName 'SemVersion.SemanticVersion' `
                             -ArgumentList $semver.Major,$semVer.Minor,$semVer.Patch,$semver.Prerelease
    }

    $buildVersion.SemVer2 = $semver
    Write-WhiskeyInfo -Context $TaskContext -Message "Building version $($semver)"
    $buildVersion.Version = [Version](@($semver.Major,$semver.Minor,$semver.Patch) -join '.')
    Write-WhiskeyVerbose -Context $TaskContext -Message "Version                 $($buildVersion.Version)"
    $buildVersion.SemVer2NoBuildMetadata =
        New-Object 'SemVersion.SemanticVersion' ($semver.Major,$semver.Minor,$semver.Patch,$semver.Prerelease)
    $msg = "SemVer2NoBuildMetadata  $($buildVersion.SemVer2NoBuildMetadata)"
    Write-WhiskeyVerbose -Context $TaskContext -Message $msg
    $semver1Prerelease = $semver.Prerelease
    if( $semver1Prerelease )
    {
        $semver1Prerelease = $semver1Prerelease -replace '[^A-Za-z0-9]',''
    }
    $buildVersion.SemVer1 =
        New-Object 'SemVersion.SemanticVersion' ($semver.Major,$semver.Minor,$semver.Patch,$semver1Prerelease)
    Write-WhiskeyVerbose -Context $TaskContext -Message "SemVer1                 $($buildVersion.SemVer1)"
}
