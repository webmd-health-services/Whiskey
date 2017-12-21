
function New-WhiskeyProGetUniversalPackage
{
    <#
    .SYNOPSIS
    Creates a ProGet universal package.

    .DESCRIPTION
    The `ProGetUniversalPackage` task creates a universal ProGet package of your application.

    You must specify a package name and description with the Name and Description properties, respecitvely.

    Specify the directories and files you want in the package with the `Path` property. The paths should be relative to the whiskey.yml file. Each item is added to your package at the same relative path. The contents directories are filtered by the `Include` property, which is a list of filenames and/or wildcard patterns. Only files that match at least one item in this list will be included in your package.  We use whitelists so we know what files are getting packaged and deployed. Without a whitelist, any file put into a directory that gets packaged would be included. This is a security risk. We can audit whitelists. Using whitelists also helps keep the size of our packages to a minimum.

    This PowerShell command will create a YAML whitelist for all files under a path:

        Get-ChildItem -Path $PATH -Recurse |
            Select-Object -ExpandProperty 'Extension' |
            Select-Object -unique |
            Sort-Object |
            ForEach-Object { '- "*{0}"' -f $_ }

    The package is saved to the output directory as `$Name.upack` where `$Name is replaced with the name of your package.

    A version.json file is put into the root of your package. It contains the version information for the current build. It looks like this:

        {
            "SemVer2":  "2017.412.286-rc.1+master.1acb317",
            "SemVer2NoBuildMetadata":  "2017.412.286-rc.1",
            "PrereleaseMetadata":  "rc.1",
            "BuildMetadata":  "master.1acb317",
            "SemVer1": "2017.412.286-rc1",
            "Version":  "2017.412.286"
        }

    It has these properties:
    
    * `BuildMetadata`: this is either the build number, branch, and commit ID or the branch and commit ID, each separated by a period ..
    * `PrereleasMetadata`: this is any pre-release metadata from the Version property from your whiskey.yml file. If there is not Version in your whiskey.yml file, this field will be empty.
    * `SemVer2`: the full semantic version of the application.
    * `SemVer2NoBuildMetadata`: this is the version number used when creating packages. We omit the build metadata so that we don't upload duplicate packages (i.e. every build generates unique build metadata even if that version of code was already built and published.
    * `SemVer1`: a semantic version compatible for use with systems that don't yet support the v2 semantic version spec, e.g. NuGet.
    * `Version`: the MAJOR.MINOR.PATCH version number of the application.

    ## Properties

    * `Name` (mandatory): the package's name.
    * `Description` (mandatory): the package's description. This shows in ProGet and helps people know about your application.
    * `Path` (mandatory): the directories and filenames to include in the package. Each path must relative to the whiskey.yml file. You can change the root path the task uses to resolve these paths with the `SourceRoot` property. Each item is added to the package at the same relative path as its source item. If you have two paths with the same name, the second item will replace the first. You can customize the path of the item in the package by converting the value into a key/value pair, e.g. `source_dir\source_file.ps1`: `destination_dir\destination_file.ps1`.
    * `Include` (mandatory): a whitelist of wildcards and file names. All directories in the `Path` property are filtered with this list, i.e. only items under each directory in `Path` that matches an item in `Include` will be added to your package.
    * `Exclude`: a list of wildcards, file names, and directory names to exclude from the package. Sometimes a whitelist can be a little greedy and include some files or directories you might not want. Any file or directory that matches an item in this list will be excluded from the package.
    * `ThirdPartyPath`: a list of directores and files that should be included in the package unfiltered. These are paths that are copied without using the Include or Exclude elements. This is useful to include items you depend on but have no control over, like Node.js applications' node_modules directory.
    * `SourceRoot`: this changes the root path used to resolve the relative paths in the Path property. Use this element when your application's root directory isn't the same directory your whiskey.yml file is in. This path should be relative to the whiskey.yml file.
    * `CompressionLevel`: the compression level to use when creating the package. Can be a value from 1 (fastest but largest file) to 9 (slowest but smallest file). The default is `1`.
    * `Version`: the package version (MAJOR.MINOR.PATCH), without any prerelease or build metadata. Usually, the version for the current build is used. Prerelease and build metadata for the current build is added.

    ## Examples

    ### Example 1

        BuildTasks:
        - ProGetUniversalPackage:
            Name: Example1
            Description: This package demonstrates the YAML for using the ProGetUniversalPackage task.
            Path:
            - bin
            - REAMDE.md
            Include:
            - "*.dll"

    The above example shows the YAML for creating a ProGet Universal Package. Given the file system looks like this:
    
        bin\
            Assembly.dll
            Assembly.pdb
            Assembly.xml
        src\
            Assembly.cs
        README.md
        whiskey.yml

    The package will look like this:

        package\
            bin\
                Assembly.dll
            README.md
            version.json
        upack.json

    Because the `Include` list only includes `*.dll`, the `Assembly.pdb` and `Assembly.xml` files are not included in the package.

    The `version.json` file is created by the task and contains the version metadata for this build.

    The `upack.json` file contains the universal package metadata required by ProGet.

    ### Example 2

        BuildTasks:
        - ProGetUniversalPackage
            Name: Example2
            Description: This package demonstrates the YAML for using the ProGetUniversalPackage task.
            Path:
            - bin
            Include:
            - "*.dll"
            - "*.pdb"
            Exclude:
            - SomeOtherAssembly.pdb

    The above demonstrates how to use the `Exclude` property to exclude files from the package. If this is what's on the file system:
    
        bin\
            Assembly.dll
            Assembly.pdb
            SomeOtherAssembly.dll
            SomeOtherAssembly.pdb
        whiskey.yml

    The package will look like this:

        package\
            bin\
                Assembly.dll
                Assembly.pdb
                SomeOtherAssembly.dll
            version.json
        upack.json

    Note that the `bin\SomeOtherAssembly.pdb` file is not in the package even though it matches an item in the `Include` whitelist. It is excluded because it matches an item in the `Exclude` blacklist.

    ## Example 3

        BuildTasks:
        - ProGetUniversalPackage
            Name: Example3
            Description: This package demonstrates how the `ThirdPartyPath` property works.
            Path:
            - dist
            Include:
            - "*.js"
            - "*.json"
            - "*.css"
            ThirdPartyPath:
            - node_modules

    Thie example demonstrates how to use the `ThirdPartyPath` property. If the file system looks like this:

        dist\
            index.js
            default.css
            data.json
        node_modules\
            rimraf\
                LICENSE
                otherfiles
        whiskey.yml

    the package will look like this:

        package\
            dist\
                index.js
                default.css
                data.json
            node_modules\
                rimraf\
                    LICENSE
                    otherfiles
            version.json
        upack.json

    Notice that all files/directories under `node_modules` are included because `node_modules` is in the `ThirdPartyPath` list. Directores in `ThirdPartyPath` are included in the package as-is, with no filtering.

    ## Example 4

        BuildTasks:
        - ProGetUniversalPackage
            Name: Example4
            Description: This package demonstrates how the customize paths in the package.
            Path:
            - source: destination
            Include:
            - "*.dll"

    Thie example demonstrates how to use customize the path an item should have in the package. If this is the file system:

        source\
            Assembly.dll
            Assembly.pdb
        whiskey.yml

    the package will look like this:

        package\
            destination\
                Assembly.dll
            version.json
        upack.json

    Notice that the `source` directory is added to the package as `destination`. This is done by making the value of an item in the `Path` list from a string into a key/value pair (e.g. `key: value`).

    ## Example 5

        BuildTasks:
        - ProGetUniversalPackage
            Name: Example5
            Description: Demonstration of the SourceRoot property.
            SourceRoot: Whiskey
            Path:
            - Functions
            - "*.ps*1"
            Include:
            - "*.ps*1"
            ThirdPartyPath:
            - ProGetAutomation

    Thie example demonstrates how to change the root directory the task uses to resolve the relative paths in the `Path`. If the file system is:

        Whiskey\
            Functions\
                New-WhiskeyContext.ps1
            Whiskey.psd1
            Whiskey.psm1
            BuildMasterAutomation\
                BuildMasterAutomation.psd1
                BuildMasterAutomation.psm1
        whiskey.yml

    the package will be:

        package\
            Functions\
                New-WhiskeyContext.ps1
            Whiskey.psd1
            Whiskey.psm1
            BuildMasterAutomation\
                BuildMasterAutomation.psd1
                BuildMasterAutomation.psm1
            version.json
        upack.json

    Notice that the top-level Whiskey directory found on the file system isn't part of the package. Because it is defined as the source root, it is considered the root of the files to put in the package, so is omitted from the package.
    #>
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
                        $robocopyExclude = @()
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

                        $robocopyExclude = & { $TaskParameter['Exclude'] ; (Join-Path -Path $destination -ChildPath 'version.json') } 
                        $operationDescription = 'packaging {0} -> {1}' -f $sourcePath,$destinationDisplay
                        $whitelist = & { 'upack.json' ; $TaskParameter['Include'] }
                    }

                    Write-Verbose -Message $operationDescription
                    Invoke-WhiskeyRobocopy -Source $sourcePath.trim("\") -Destination $destination.trim("\") -WhiteList $whitelist -Exclude $robocopyExclude | Write-Verbose
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
