
 function Set-WhiskeyVersion
{
    [CmdletBinding()]
    [Whiskey.Task('Version')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context] $TaskContext,

        [Parameter(Mandatory)]
        [hashtable] $TaskParameter,

        [Whiskey.Tasks.ValidatePath(PathType='File')]
        [String] $Path,

        [String] $NuGetPackageID,

        [String] $UPackName,

        [Uri] $UPackFeedUrl,

        [switch] $SkipPackageLookup,

        [switch] $IncrementPatchVersion
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

    [int]$prereleaseVersion = 1
    [Whiskey.BuildVersion]$buildVersion = $TaskContext.Version
    [SemVersion.SemanticVersion]$semver = $buildVersion.SemVer2
    [String[]] $versions = @()

    if( $TaskParameter[''] )
    {
        $rawVersion = $TaskParameter['']
        $semVer = $rawVersion | ConvertTo-SemVer -PropertyName 'Version'
    }
    elseif( $TaskParameter['Version'] )
    {
        $rawVersion = $TaskParameter['Version']
        $semVer = $rawVersion | ConvertTo-SemVer -PropertyName 'Version'
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

                $prerelease = ''
                if( ($moduleManifest | Get-Member -Name 'Prerelease') )
                {
                    $Prerelease = $moduleManifest.Prerelease
                }
                elseif( $moduleManifest.PrivateData -and `
                        $moduleManifest.PrivateData.ContainsKey('PSData') -and `
                        $moduleManifest.PrivateData['PSData'].ContainsKey('Prerelease') )
                {
                    $prerelease = $moduleManifest.PrivateData['PSData']['Prerelease']
                }

                if( $prerelease )
                {
                    $rawVersion = "$($rawVersion)-$($prerelease)"
                }

                $msg = "Read version ""$($rawVersion)"" from PowerShell module manifest ""$($Path)""."
                Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                $semver = $rawVersion | ConvertTo-SemVer -VersionSource "from PowerShell module manifest ""$($Path)"""

                if( -not $SkipPackageLookup )
                {
                    $msg = "Retrieving versions for PowerShell module $($moduleManifest.Name)."
                    Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                    Import-WhiskeyPowerShellModule -Name 'PackageManagement' -PSModulesRoot $TaskContext.BuildRoot -MinVersion $script:pkgMgmtMinVersion -MaxVersion $script:pkgMgmtMaxVersion
                    Import-WhiskeyPowerShellModule -Name 'PowerShellGet' -PSModulesRoot $TaskContext.BuildRoot -MinVersion $script:psGetMinVersion -MaxVersion $script:psGetMaxVersion
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
                if( $pkgName -and -not $SkipPackageLookup )
                {
                    $msg = "Retrieving versions for NPM package $($pkgName)."
                    Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                    Install-WhiskeyNode -InstallRootPath $TaskContext.BuildRoot `
                                        -OutFileRootPath $TaskContext.OutputDirectory
                    $versions = Invoke-WhiskeyNpmCommand -Name 'show' `
                                                         -ArgumentList @($pkgName, 'versions', '--json') `
                                                         -BuildRoot $TaskContext.BuildRoot `
                                                         -ForDeveloper:($TaskContext.ByDeveloper) `
                                                         -ErrorAction Ignore 2>$null |
                        ConvertFrom-Json
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

                if( -not $SkipPackageLookup )
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
                        Import-WhiskeyPowerShellModule -Name 'PackageManagement' -PSModulesRoot $TaskContext.Buildroot -MinVersion $script:pkgMgmtMinVersion -MaxVersion $script:pkgMgmtMaxVersion
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

    if( -not $SkipPackageLookup )
    {
        if( $UPackName )
        {
            $msg = "Retrieving versions for universal package $($UPackName)."
            Write-WhiskeyVerbose -Context $TaskContext -Message $msg
            $numErr = $Global:Error.Count
            try
            {
                $versions = 
                    Invoke-RestMethod -Uri "$($UPackFeedUrl)/packages?name=$([Uri]::EscapeDataString($UpackName))" |
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
            Import-WhiskeyPowerShellModule -Name 'PackageManagement' -PSModulesRoot $TaskContext.Buildroot -MinVersion $script:pkgMgmtMinVersion -MaxVersion $script:pkgMgmtMaxVersion
            $allowPrereleaseArg = Get-AllowPrereleaseArg -CommandName 'Find-Package' -AllowPrerelease
            $versions = 
                Find-Package -Name $NuGetPackageID -ProviderName 'NuGet' -AllVersions @allowPrereleaseArg |
                Select-Object -ExpandProperty 'Version'
        }
    }

    $prerelease = $TaskParameter['Prerelease']
    if( $prerelease -isnot [String] )
    {
        $foundLabel = $false
        foreach( $object in $prerelease )
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
                        $prerelease = $map[$wildcardPattern]
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
            $prerelease = ''
        }
    }

    if( $prerelease )
    {
        $buildSuffix = ''
        if( $semver.Build )
        {
            $buildSuffix = '+{0}' -f $semver.Build
        }

        $rawVersion = '{0}.{1}.{2}-{3}{4}' -f $semver.Major,$semver.Minor,$semver.Patch,$prerelease,$buildSuffix
        if( -not [SemVersion.SemanticVersion]::TryParse($rawVersion,[ref]$semver) )
        {
            $msg = """$($prerelease)"" is not a valid prerelease version. Only letters, numbers, hyphens, and " +
                   'periods are allowed. See https://semver.org for full documentation.'
            Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Prerelease' -Message $msg
            return
        }
    }

    if( $semver.Prerelease -match '(\d+)' )
    {
        $prereleaseVersion = $Matches[1]
    }
    else
    {
        $prereleaseVersion = 1
    }

    if( $versions )
    {
        [SemVersion.SemanticVersion[]] $semVersions = $versions | ConvertTo-SemVer -ErrorAction Ignore
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

            $semver = [SemVersion.SemanticVersion]::New($semver.Major, $semver.Minor, $patchVersion, $semver.Prerelease,
                                                        $semver.Build)
        }
        
        $baseVersion = @($semver.Major, $semver.Minor, $semver.Patch) -join '.'
        $prereleaseIdentifier = $semver.Prerelease -replace '[^A-Za-z]', ''
        $lastVersion =
            $semVersions |
            Where-Object { (@($_.Major,$_.Minor,$_.Patch) -join '.') -eq $baseVersion } |
            Where-Object { ($_.Prerelease -replace '[^A-Za-z]', '') -eq $prereleaseIdentifier } |
            Select-Object -First 1
        if( $lastVersion -and $lastVersion.Prerelease -match '(\d+)' )
        {
            $prereleaseVersion = $Matches[1]
            $prereleaseVersion += 1
        }
        else
        {
            $prereleaseVersion = 1
        }
    }

    $build = $TaskParameter['Build']
    if( $build )
    {
        $prereleaseSuffix = ''
        if( $semver.Prerelease )
        {
            $prereleaseSuffix = '-{0}' -f $semver.Prerelease
        }

        $build = $build -replace '[^A-Za-z0-9\.-]', '-'
        $rawVersion = '{0}.{1}.{2}{3}+{4}' -f $semver.Major,$semver.Minor,$semver.Patch,$prereleaseSuffix,$build
        if( -not [SemVersion.SemanticVersion]::TryParse($rawVersion,[ref]$semver) )
        {
            $msg = """$($build)"" is not valid build metadata. Only letters, numbers, hyphens, and periods are " +
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

    if( $prereleaseVersion -and $semver.Prerelease -match '\d+' )
    {
        $prerelease = $semver.Prerelease -replace '\d+', $prereleaseVersion
        $semver =
            [SemVersion.SemanticVersion]::New($semver.Major, $semver.Minor, $semver.Patch, $prerelease, $semver.Build)
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
