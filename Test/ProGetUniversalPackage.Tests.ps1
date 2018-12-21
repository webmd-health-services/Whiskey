
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$defaultPackageName = 'WhiskeyTest'
$defaultDescription = 'A package created to test the New-WhiskeyProGetUniversalPackage function in the Whiskey module.'
$defaultVersion = '1.2.3'
$packageVersion = $null
$buildVersion = $null
$manifestProperties = $null

$threwException = $false
$context = $null
$expandPath = $null

function Install-ProGetAutomation
{
    param(
        $BuildRoot
    )

    # Copy ProGetAutomation in place otherwise every test downloads it from the gallery
    $psModulesRoot = Join-Path -Path $BuildRoot -ChildPath 'PSModules'
    if( -not (Test-Path -Path $psModulesRoot -PathType Container) )
    {
        New-Item -Path $psModulesRoot -ItemType 'Directory'
    }

    if( -not (Test-Path -Path (Join-Path -Path $psModulesRoot -ChildPath 'ProGetAutomation') -PathType Container ) )
    {
        Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\ProGetAutomation') `
                  -Destination $psModulesRoot `
                  -Recurse
    }
}

function GivenBuildVersion
{
    param(
        [SemVersion.SemanticVersion]
        $Version
    )

    $script:buildVersion = New-WhiskeyVersionObject
    $buildVersion.SemVer2 = [SemVersion.SemanticVersion]$Version
    $buildVersion.Version = [Version]('{0}.{1}.{2}' -f $Version.Major,$Version.Minor,$Version.Patch)
    $buildVersion.SemVer2NoBuildMetadata = [SemVersion.SemanticVersion]('{0}.{1}.{2}-{3}' -f $Version.Major,$Version.Minor,$Version.Patch,$Version.Prerelease)
    $buildVersion.SemVer1 = [SemVersion.SemanticVersion]('{0}.{1}.{2}-{3}' -f $Version.Major,$Version.Minor,$Version.Patch,($Version.Prerelease -replace '[^A-Za-z0-9]',''))
}

function GivenPackageVersion
{
    param(
        $Version
    )

    $script:packageVersion = $Version
}

function GivenManifestProperties
{
    param(
        [hashtable]
        $Content
    )
    $script:manifestProperties = $Content
}

function Init
{
    $script:threwException = $false
    $script:packageVersion = $null
    $script:buildVersion = $null
    $script:context = $null
    $script:expandPath = $null
    $script:manifestProperties = $null

    Remove-Module -Force -Name ProGetAutomation -ErrorAction Ignore
}

function ThenTaskFails
{
    Param(
        [String]
        $error
    )

    It ('should fail with error message that matches "{0}"' -f $error) {
        $Global:Error | Should match $error
    }
}

function ThenTaskSucceeds
{
    It ('should not throw an error message') {
        $Global:Error | Should BeNullOrEmpty
    }
}

function ThenVersionIs
{
    param(
        $Version,
        $PrereleaseMetadata,
        $BuildMetadata,
        $SemVer2,
        $SemVer1,
        $SemVer2NoBuildMetadata
    )

    $versionJsonPath = Join-Path -Path $expandPath -ChildPath 'package\version.json'

    $versionJson = Get-Content -Path $versionJsonPath -Raw | ConvertFrom-Json
    It 'version.json should have Version property' {
        $versionJson.Version | Should -BeOfType ([string])
        $versionJson.Version | Should -Be $Version
    }
    It 'version.json should have PrereleaseMetadata property' {
        $versionJson.PrereleaseMetadata | Should -BeOfType ([string])
        $versionJson.PrereleaseMetadata | Should -Be $PrereleaseMetadata
    }
    It 'version.json shuld have BuildMetadata property' {
        $versionJson.BuildMetadata | Should -BeOfType ([string])
        $versionJson.BuildMetadata | Should -Be $BuildMetadata
    }
    It 'version.json should have v2 semantic version' {
        $versionJson.SemVer2 | Should -BeOfType ([string])
        $versionJson.SemVer2 | Should -Be $SemVer2
    }
    It 'version.json should have v1 semantic version' {
        $versionJson.SemVer1 | Should -BeOfType ([string])
        $versionJson.SemVer1 | Should -Be $SemVer1
    }
    It 'version.json should have v2 semantic version without build metadata' {
        $versionJson.SemVer2NoBuildMetadata | Should -BeOfType ([string])
        $versionJson.SemVer2NoBuildMetadata | Should -Be $SemVer2NoBuildMetadata
    }
}

function Assert-NewWhiskeyProGetUniversalPackage
{
    [CmdletBinding()]
    param(
        [object[]]
        $ForPath,

        [string[]]
        $ThatIncludes,

        [string[]]
        $ThatExcludes,

        [string]
        $Name = $defaultPackageName,

        [string]
        $Description = $defaultDescription,

        [string]
        $Version,

        [string[]]
        $HasRootItems,

        [string[]]
        $HasFiles,

        [string[]]
        $NotHasFiles,

        [string]
        $ShouldFailWithErrorMessage,

        [Switch]
        $ShouldWriteNoErrors,

        [Switch]
        $ShouldReturnNothing,

        [string[]]
        $HasThirdPartyRootItem,

        [object[]]
        $WithThirdPartyRootItem,

        [string[]]
        $HasThirdPartyFile,

        [string]
        $FromSourceRoot,

        [string[]]
        $MissingRootItems,

        [Switch]
        $WhenCleaning,

        [Switch]
        $withInitialize
    )

    if( -not $Version )
    {
        $now = [DateTime]::Now
        $midnight = [DateTime]::Today

        $Version = '{0}.{1}.{2}-final+80.feature-fubarsnafu.deadbee' -f $now.Year,$now.DayOfYear,($now - $midnight).TotalMilliseconds.ToInt32($null)
        Start-Sleep -Milliseconds 1
    }

    $taskParameter = @{
                            Name = $Name;
                            Description = $Description;
                            Path = $ForPath;
                            Include = $ThatIncludes;
                        }
    if( $ThatExcludes )
    {
        $taskParameter['Exclude'] = $ThatExcludes
    }
    if( $HasThirdPartyRootItem )
    {
        $taskParameter['ThirdPartyPath'] = $WithThirdPartyRootItem
    }
    if( $FromSourceRoot )
    {
        $taskParameter['SourceRoot'] = $FromSourceRoot
    }

    $byWhoArg = @{ $PSCmdlet.ParameterSetName = $true }

    $script:context = $taskContext = New-WhiskeyTestContext -ForBuildRoot 'Repo' -ForBuildServer
    
    Install-ProGetAutomation -BuildRoot $context.BuildRoot

    $semVer2 = [SemVersion.SemanticVersion]$Version
    $taskContext.Version.SemVer2 = $semVer2
    $taskContext.Version.Version = [version]('{0}.{1}.{2}' -f $taskContext.Version.SemVer2.Major,$taskContext.Version.SemVer2.Minor,$taskContext.Version.SemVer2.Patch)
    $taskContext.Version.SemVer2NoBuildMetadata = [SemVersion.SemanticVersion]('{0}.{1}.{2}' -f $semVer2.Major,$semVer2.Minor,$semVer2.Patch)
    if( $taskContext.Version.SemVer2.Prerelease )
    {
        $taskContext.Version.SemVer2NoBuildMetadata = [SemVersion.SemanticVersion]('{0}-{1}' -f $taskContext.Version.SemVer2NoBuildMetadata,$taskContext.Version.SemVer2.Prerelease)
    }

    $threwException = $false
    $At = $null

    $Global:Error.Clear()

    if( $WhenCleaning )
    {
        $taskContext.RunMode = 'Clean'
    }
    if( $withInitialize )
    {
        $taskContext.RunMode = 'initialize'
    }

    try
    {
        $At = Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'ProGetUniversalPackage' |
                Where-Object { $_ -like '*.upack' } |
                Where-Object { Test-Path -Path $_ -PathType Leaf }
    }
    catch
    {
        $threwException = $true
        Write-Error -ErrorRecord $_
    }

    if( $ShouldReturnNothing -or $ShouldFailWithErrorMessage )
    {
        It 'should not return package info' {
            $At | Should BeNullOrEmpty
        }
    }
    else
    {
        It 'should return package info' {
            $At | Should Exist
        }
    }

    if( $ShouldWriteNoErrors )
    {
        ThenTaskSucceeds
    }

    if( $ShouldFailWithErrorMessage )
    {
        It 'should fail with a terminating error' {
            $threwException | Should Be $true
        }

        ThenTaskFails $ShouldFailWithErrorMessage
    }
    else
    {
        It 'should not fail' {
            $threwException | Should Be $false
        }
    }

    #region
    $expandPath = Join-Path -Path $TestDrive.FullName -ChildPath 'Expand'
    $packageContentsPath = Join-Path -Path $expandPath -ChildPath 'package'
    $packageName = '{0}.{1}.upack' -f $Name,($taskContext.Version.SemVer2NoBuildMetadata-replace '[\\/]','-')
    $outputRoot = $taskContext.OutputDirectory
    $packagePath = Join-Path -Path $outputRoot -ChildPath $packageName

    It 'should create a package' {
        $packagePath | Should Exist
    }

    Expand-ZipArchive -Path $packagePath -DestinationPath $expandPath

    $upackJsonPath = Join-Path -Path $expandPath -ChildPath 'upack.json'

    Context 'the package' {
        foreach( $itemName in $MissingRootItems )
        {
            It ('should not include {0} item' -f $itemName) {
                Join-Path -Path $packageContentsPath -ChildPath $itemName | Should Not Exist
            }
        }

        foreach( $itemName in $HasRootItems )
        {
            $dirPath = Join-Path -Path $packageContentsPath -ChildPath $itemName
            It ('should include {0} item' -f $itemName) {
                $dirpath | Should Exist
            }
            foreach( $fileName in $HasFiles )
            {
                It ('should include {0}\{1} file' -f $itemName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Exist
                }
            }

            foreach( $fileName in $HasThirdPartyFile )
            {
                It ('should not include {0}\{1} file' -f $itemName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Not Exist
                }
            }
        }

        $versionJsonPath = Join-Path -Path $packageContentsPath -ChildPath 'version.json'
        It 'should include version.json' {
            $versionJsonPath | Should Exist
        }

        $version = Get-Content -Path $versionJsonPath -Raw | ConvertFrom-Json
        It 'version.json should have Version property' {
            $version.Version | Should BeOfType ([string])
            $version.Version | Should Be $taskContext.Version.Version.ToString()
        }
        It 'version.json should have PrereleaseMetadata property' {
            $version.PrereleaseMetadata | Should BeOfType ([string])
            $version.PrereleaseMetadata | Should Be $taskContext.Version.SemVer2.Prerelease.ToString()
        }
        It 'version.json shuld have BuildMetadata property' {
            $version.BuildMetadata | Should BeOfType ([string])
            $version.BuildMetadata | Should Be $taskContext.Version.SemVer2.Build.ToString()
        }
        It 'version.json should have v2 semantic version' {
            $version.SemVer2 | Should BeOfType ([string])
            $version.SemVer2 | Should Be $taskContext.Version.SemVer2.ToString()
        }
        It 'version.json should have v1 semantic version' {
            $version.SemVer1 | Should BeOfType ([string])
            $version.SemVer1 | Should Be $taskContext.Version.SemVer1.ToString()
        }
        It 'version.json should have v2 semantic version without build metadata' {
            $version.SemVer2NoBuildMetadata | Should BeOfType ([string])
            $version.SemVer2NoBuildMetadata | Should Be $taskContext.Version.SemVer2NoBuildMetadata.ToString()
        }

        if( $NotHasFiles )
        {
            foreach( $item in $NotHasFiles )
            {
                It ('should exclude {0} files' -f $item ) {
                    Get-ChildItem -Path $packageContentsPath -Filter $item -Recurse | Should BeNullOrEmpty
                }
            }
        }

        It 'should include ProGet universal package metadata (upack.json)' {
            $upackJsonPath | Should Exist
        }

        foreach( $itemName in $HasThirdPartyRootItem )
        {
            $dirPath = Join-Path -Path $packageContentsPath -ChildPath $itemName
            It ('should include {0} third-party root item' -f $itemName) {
                $dirpath | Should Exist
            }

            foreach( $fileName in $HasThirdPartyFile )
            {
                It ('should include {0}\{1} third-party file' -f $itemName,$fileName) {
                    Join-Path -Path $dirPath -ChildPath $fileName | Should Exist
                }
            }
        }
    }

    Context 'upack.json' {
        $upackInfo = Get-Content -Raw -Path $upackJsonPath | ConvertFrom-Json
        It 'should be valid json' {
            $upackInfo | Should Not BeNullOrEmpty
        }

        It 'should contain name' {
            $upackInfo.Name | Should Be $Name
        }

        It 'should contain title' {
            $upackInfo.title | Should Be $Name
        }

        It 'should contain version' {
            $upackInfo.Version | Should Be $taskContext.Version.SemVer2NoBuildMetadata.ToString()
        }

        It 'should contain description' {
            $upackInfo.Description | Should Be $Description
        }
    }
    #endregion
}

function Initialize-Test
{
    param(
        [string[]]
        $DirectoryName,

        [string[]]
        $FileName,

        [string[]]
        $RootFileName,

        [Switch]
        $WhenUploadFails,

        [Switch]
        $OnFeatureBranch,

        [Switch]
        $OnMasterBranch,

        [Switch]
        $OnReleaseBranch,

        [Switch]
        $OnPermanentReleaseBranch,

        [Switch]
        $OnDevelopBranch,

        [Switch]
        $OnHotFixBranch,

        [Switch]
        $OnBugFixBranch,

        [string]
        $SourceRoot
    )

    $repoRoot = Get-BuildRoot
    if( -not (Test-Path -Path $repoRoot -PathType Container) )
    {
        New-Item -Path $repoRoot -ItemType 'Directory'
    }
    if( -not $SourceRoot )
    {
        $SourceRoot = $repoRoot
    }
    else
    {
        $SourceRoot = Join-Path -Path $repoRoot -ChildPath $SourceRoot
    }
    if( -not (Test-Path -Path $SourceRoot -PathType Container) )
    {
        New-Item -Path $SourceRoot -ItemType 'Directory'
    }

    $DirectoryName | ForEach-Object {
        $dirPath = $_
        $dirPath = Join-Path -Path $SourceRoot -ChildPath $_
        if( -not (Test-Path -Path $dirPath -PathType Container) )
        {
            New-Item -Path $dirPath -ItemType 'Directory'
        }
        foreach( $file in $FileName )
        {
            New-Item -Path (Join-Path -Path $dirPath -ChildPath $file) -ItemType 'File' | Out-Null
        }
    }

    foreach( $itemName in $RootFileName )
    {
        New-Item -Path (Join-Path -Path $SourceRoot -ChildPath $itemName) -ItemType 'File' | Out-Null
    }

    return $repoRoot
}

function Get-BuildRoot
{
    $buildRoot = (Join-Path -Path $TestDrive.FullName -ChildPath 'Repo')
    New-Item -Path $buildRoot -ItemType 'Directory' -Force -ErrorAction Ignore | Out-Null
    return $buildRoot
}

function GivenARepositoryWithItems
{
    param(
        [string[]]
        $Path,

        $ItemType = 'File'
    )

    $buildRoot = Get-BuildRoot

    foreach( $item in $Path )
    {
        $parent = $item | Split-Path
        if( $parent )
        {
            New-Item -Path (Join-Path -Path $buildRoot -ChildPath $parent) -ItemType 'Directory' -Force -ErrorAction Ignore
        }

        $destinationPath = Join-Path -Path $buildRoot -ChildPath $item
        Copy-Item -Path $PSCommandPath -Destination $destinationPath
    }

    Install-ProGetAutomation -BuildRoot $buildRoot
}

function WhenPackaging
{
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName='WithTaskParameter')]
        $WithPackageName = $defaultPackageName,

        [Parameter(ParameterSetName='WithTaskParameter')]
        $WithDescription = $defaultDescription,
        
        [Parameter(ParameterSetName='WithTaskParameter')]
        [object[]]
        $Paths,
        
        [Parameter(ParameterSetName='WithTaskParameter')]
        [object[]]
        $WithWhitelist,
        
        [Parameter(ParameterSetName='WithTaskParameter')]
        [object[]]
        $ThatExcludes,
        
        [Parameter(ParameterSetName='WithTaskParameter')]
        $FromSourceRoot,
        
        [Parameter(ParameterSetName='WithTaskParameter')]
        [object[]]
        $WithThirdPartyPath,
        
        [Parameter(ParameterSetName='WithTaskParameter')]
        $WithVersion = $defaultVersion,
        
        [Parameter(ParameterSetName='WithTaskParameter')]
        $WithApplicationName,
        
        [Parameter(ParameterSetName='WithTaskParameter')]
        $CompressionLevel,
        
        [Parameter(ParameterSetName='WithTaskParameter')]
        [Switch]
        $SkipExpand,

        [Parameter(Mandatory,ParameterSetName='WithYaml')]
        $WithYaml
    )

    if( $PSCmdlet.ParameterSetName -eq 'WithYaml' )
    {
        $script:context = $taskContext = New-WhiskeyTestContext -ForBuildRoot 'Repo' -ForBuildServer -ForYaml $WithYaml
        $taskParameter = $context.Configuration['Build'][0]['ProGetUniversalPackage']
    }
    else
    {
        $taskParameter = @{ }
        if( $WithPackageName )
        {
            $taskParameter['Name'] = $WithPackageName
        }
        if( $WithDescription )
        {
            $taskParameter['Description'] = $WithDescription
        }
        if( $Paths )
        {
            $taskParameter['Path'] = $Paths
        }
        if( $WithWhitelist )
        {
            $taskParameter['Include'] = $WithWhitelist
        }
        if( $ThatExcludes )
        {
            $taskParameter['Exclude'] = $ThatExcludes
        }
        if( $WithThirdPartyPath )
        {
            $taskParameter['ThirdPartyPath'] = $WithThirdPartyPath
        }
        if( $FromSourceRoot )
        {
            $taskParameter['SourceRoot'] = $FromSourceRoot
        }
        if( $CompressionLevel )
        {
            $taskParameter['CompressionLevel'] = $CompressionLevel
        }

        if( $packageVersion )
        {
            $taskParameter['Version'] = $packageVersion
        }

        if( $manifestProperties )
        {
            $taskParameter['ManifestProperties'] = $manifestProperties
        }

        $script:context = $taskContext = New-WhiskeyTestContext -ForBuildRoot 'Repo' -ForBuildServer -ForVersion $WithVersion
        if( $WithApplicationName )
        {
            $taskContext.ApplicationName = $WithApplicationName
        }
        if( $buildVersion )
        {
            $context.Version = $buildVersion
        }
    }

    $threwException = $false
    $At = $null

    $Global:Error.Clear()

    try
    {
        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'ProGetUniversalPackage'
    }
    catch
    {
        $threwException = $true
        Write-Error -ErrorRecord $_
    }

    $packageInfo = Get-ChildItem -Path $taskContext.OutputDirectory -Filter '*.upack'

    if( -not $SkipExpand -and $packageInfo )
    {
        $script:expandPath = Join-Path -Path $taskContext.OutputDirectory -ChildPath 'extracted'
        & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\7-Zip\7z.exe') x $packageInfo.FullName ('-o{0}' -f $expandPath)
    }
}

function Get-PackageSize
{
    param(
        $PackageName = $defaultPackageName,
        $PackageVersion = $defaultVersion
    )

    $packageName = '{0}.{1}.upack' -f $PackageName,($PackageVersion -replace '[\\/]','-')
    $outputRoot = Get-BuildRoot
    $outputRoot = Join-Path -Path $outputRoot -ChildPath '.output'
    $packagePath = Join-Path -Path $outputRoot -ChildPath $packageName
    $packageLength = (get-item $packagePath).Length
    return $packageLength
}

function ThenPackageShouldInclude
{
    param(
        $PackageName = $defaultPackageName,
        $PackageVersion = $defaultVersion,
        [Parameter(Position=0)]
        [string[]]
        $Path
    )

    $Path += @( 'version.json' )
    $packageRoot = Join-Path -Path $expandPath -ChildPath 'package'
    foreach( $item in $Path )
    {
        $expectedPath = Join-Path -Path $packageRoot -ChildPath $item
        It ('should include {0}' -f $item) {
            $expectedPath | Should -Exist
        }
    }
}

function ThenPackageShouldNotInclude
{
    param(
        [string[]]
        $Path
    )

    $packageRoot = Join-Path -Path $expandPath -ChildPath 'package'

    foreach( $item in $Path )
    {
        It ('package should not include {0}' -f $item) {
            (Join-Path -Path $packageRoot -ChildPath $item) | Should -Not -Exist
        }
    }
}

function ThenUpackMetadataIs
{
    param(
        [hashtable]
        $ExpectedContent
    )

    function Assert-HashTableEqual
    {
        param(
            [hashtable]
            $Reference,

            [hashtable]
            $Difference
        )

        # $DebugPreference = 'Continue'
        foreach ($key in $Reference.Keys)
        {
            if ($key -notin $Difference.Keys)
            {
                Write-Debug -Message ('Expected  {0},{1}' -f $key,($Difference.Keys -join ','))
                Write-Debug -Message ('Actual    {0}' -f $Difference.Keys)
                return $false
            }
            elseif ($Reference[$key] | Get-Member -Name 'Keys')
            {
                if (-not ($Difference[$key] | Get-Member -Name 'Keys') -or (-not (Assert-HashTableEqual -Reference $Reference[$key] -Difference $Difference[$key])))
                {
                    Write-Debug -Message ('Expected  {0}' -f $Reference[$key])
                    Write-Debug -Message ('Actual    {0}' -f $Difference[$key])
                    return $false
                }
            }
            elseif (Compare-Object -ReferenceObject $Reference[$key] -DifferenceObject $Difference[$key])
            {
                Write-Debug -Message ('Expected  {0}' -f $Reference[$key])
                Write-Debug -Message ('Actual    {0}' -f $Difference[$key])
                return $false
            }
        }

        return $true
    }

    function ConvertTo-Hashtable {
        param(
            $PSCustomObject
        )

        $result = @{}
        foreach( $property in $PSCustomObject.psobject.properties.name )
        {
            $value = $PSCustomObject.$property
            if ($value -is [System.Management.Automation.PSCustomObject])
            {
                $result[$property] = ConvertTo-HashTable -PSCustomObject $value
            }
            else
            {
                $result[$property] = $value
            }
        }
        return $result
    }

    $upackJson = Get-Content -Raw -Path (Join-Path -Path $expandPath -ChildPath 'upack.json' -Resolve) | ConvertFrom-Json
    $upackContent = ConvertTo-Hashtable -PSCustomObject $upackJson

    It 'should include the upack.json' {
        Assert-HashTableEqual -Reference $ExpectedContent -Difference $upackContent | Should -BeTrue
    }
}

function ThenPackageShouldBeCompressed
{
    param(
        $PackageName = $defaultPackageName,
        $PackageVersion = $defaultVersion,
        [Parameter(Position=0)]
        [string[]]
        $Path,

        [Int]
        $GreaterThan,

        [int]
        $LessThanOrEqualTo
    )

    $packageSize = Get-PackageSize -PackageName $PackageName -PackageVersion $PackageVersion
    Write-Debug -Message ('Package size: {0}' -f $packageSize)
    if( $GreaterThan )
    {
        It ('should have a compressed package size greater than {0}' -f $GreaterThan) {
            $packageSize | Should -BeGreaterThan $GreaterThan
        }
    }

    if( $LessThanOrEqualTo )
    {
        It ('should have a compressed package size less than or equal to {0}' -f $LessThanOrEqualTo) {
            $packageSize | Should -Not -BeGreaterThan $LessThanOrEqualTo
        }
    }

}

Describe 'ProGetUniversalPackage.when packaging everything in a directory' {
    Init
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -HasRootItems $dirNames `
                                            -HasFiles 'html.html'
}

Describe 'ProGetUniversalPackage.when packaging root files' {
    Init
    $file = 'project.json'
    $thirdPartyFile = 'thirdparty.txt'
    $outputFilePath = Initialize-Test -RootFileName $file,$thirdPartyFile
    Assert-NewWhiskeyProGetUniversalPackage -ForPath $file `
                                            -WithThirdPartyRootItem $thirdPartyFile `
                                            -HasThirdPartyRootItem $thirdPartyFile `
                                            -HasRootItems $file
}

Describe 'ProGetUniversalPackage.when packaging whitelisted files in a directory' {
    Init
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'code.cs', 'style.css' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html','*.css' `
                                            -HasRootItems $dirNames `
                                            -HasFiles 'html.html','style.css' `
                                            -NotHasFiles 'code.cs'
}

Describe 'ProGetUniversalPackage.when packaging multiple directories' {
    Init
    $dirNames = @( 'dir1', 'dir1\sub', 'dir2' )
    $fileNames = @( 'html.html', 'code.cs' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1','dir2' `
                                            -ThatIncludes '*.html' `
                                            -HasRootItems $dirNames `
                                            -HasFiles 'html.html' `
                                            -NotHasFiles 'code.cs'
}

Describe 'ProGetUniversalPackage.when whitelist includes items that need to be excluded' {
    Init
    $dirNames = @( 'dir1', 'dir1\sub' )
    $fileNames = @( 'html.html', 'html2.html' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames `
                                      -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -ThatExcludes 'html2.html','sub' `
                                            -HasRootItems 'dir1' `
                                            -HasFiles 'html.html' `
                                            -NotHasFiles 'html2.html','sub'
}

Describe 'ProGetUniversalPackage.when paths don''t exist' {
    Init

    $Global:Error.Clear()

    Initialize-Test

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1','dir2' `
                                            -ThatIncludes '*' `
                                            -ShouldFailWithErrorMessage '(don''t|does not) exist' `
                                            -ErrorAction SilentlyContinue
}

Describe 'ProGetUniversalPackage.when including third-party items' {
    Init
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -ThatExcludes 'thirdparty.txt' `
                                            -HasRootItems 'dir1' `
                                            -HasFiles 'html.html' `
                                            -WithThirdPartyRootItem 'thirdparty','thirdpart2' `
                                            -HasThirdPartyRootItem 'thirdparty','thirdpart2' `
                                            -HasThirdPartyFile 'thirdparty.txt'
}

foreach( $parameterName in @( 'Name', 'Description' ) )
{
    Describe ('ProGetUniversalPackage.when {0} property is omitted' -f $parameterName) {
        Init
        $parameter = @{
                        Name = 'Name';
                        Include = 'Include';
                        Description = 'Description';
                        Path = 'Path'
                      }
        $parameter.Remove($parameterName)

        $context = New-WhiskeyTestContext -ForDeveloper
        Install-ProGetAutomation -BuildRoot $context.BuildRoot
        $Global:Error.Clear()
        $threwException = $false
        try
        {
            Invoke-WhiskeyTask -TaskContext $context -Parameter $parameter -Name 'ProGetUniversalPackage'
        }
        catch
        {
            $threwException = $true
            Write-Error -ErrorRecord $_ -ErrorAction SilentlyContinue
        }

        It 'should fail' {
            $threwException | Should Be $true
            $Global:Error | Should -Match ('\bProperty\ "{0}"\ is\ mandatory\b' -f $parameterName)
        }
    }
}

Describe 'ProGetUniversalPackage.when path to package doesn''t exist' {
    Init
    $context = New-WhiskeyTestContext -ForDeveloper
    Install-ProGetAutomation -BuildRoot $context.BuildRoot
    $Global:Error.Clear()

    It 'should throw an exception' {
        { Invoke-WhiskeyTask -TaskContext $context -Parameter @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = 'fubar' } -Name 'ProGetUniversalPackage' } | Should Throw
    }

    It 'should mention path in error message' {
        $Global:Error | Should BeLike ('* Path`[0`] "{0}*" does not exist.' -f (Join-Path -Path $context.BuildRoot -ChildPath 'fubar'))
    }
}
Describe 'ProGetUniversalPackage.when path to third-party item doesn''t exist' {
    Init
    $context = New-WhiskeyTestContext -ForDeveloper
    Install-ProGetAutomation -BuildRoot $context.BuildRoot

    $Global:Error.Clear()

    It 'should throw an exception' {
        { Invoke-WhiskeyTask -TaskContext $context -Parameter @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = '.'; ThirdPartyPath = 'fubar' } -Name 'ProGetUniversalPackage' } | Should Throw
    }

    It 'should mention path in error message' {
        $Global:Error | Should BeLike ('* ThirdPartyPath`[0`] "{0}*" does not exist.' -f (Join-Path -Path $context.BuildRoot -ChildPath 'fubar'))
    }
}

Describe 'ProGetUniversalPackage.when application root isn''t the root of the repository' {
    Init
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames -SourceRoot 'app'

    Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                            -ThatIncludes '*.html' `
                                            -ThatExcludes 'thirdparty.txt' `
                                            -HasRootItems 'dir1' `
                                            -HasFiles 'html.html' `
                                            -WithThirdPartyRootItem 'thirdparty','thirdpart2' `
                                            -HasThirdPartyRootItem 'thirdparty','thirdpart2' `
                                            -HasThirdPartyFile 'thirdparty.txt' `
                                            -FromSourceRoot 'app'
}

Describe 'ProGetUniversalPackage.when custom application root doesn''t exist' {
    Init
    $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
    $fileNames = @( 'html.html', 'thirdparty.txt' )
    $outputFilePath = Initialize-Test -DirectoryName $dirNames -FileName $fileNames
    $context = New-WhiskeyTestContext -ForDeveloper
    
    Install-ProGetAutomation -BuildRoot $context.BuildRoot
    $Global:Error.Clear()

    $parameter = @{
                    Name = 'fubar' ;
                    Description = 'fubar';
                    Include = 'fubar';
                    Path = '.';
                    ThirdPartyPath = 'fubar'
                    SourceRoot = 'app';
                }

    { Invoke-WhiskeyTask -TaskContext $context -Parameter $parameter -Name 'ProGetUniversalPackage' } | Should Throw

    ThenTaskFails 'SourceRoot\b.*\bapp\b.*\bdoes not exist'
}

Describe 'ProGetUniversalPackage.when packaging given a full relative path' {
    Init
    $file = 'project.json'
    $directory = 'relative'
    $path = ('{0}\{1}' -f ($directory, $file))

    $outputFilePath = Initialize-Test -DirectoryName $directory -FileName $file
    Assert-NewWhiskeyProGetUniversalPackage -ForPath $path -HasRootItems $path
}

Describe 'ProGetUniversalPackage.when packaging given a full relative path to a file with override syntax' {
    Init
    $file = 'project.json'
    $directory = 'relative'
    $path = ('{0}\{1}' -f ($directory, $file))
    $forPath = @{ $path = $file }

    $outputFilePath = Initialize-Test -DirectoryName $directory -FileName $file
    Assert-NewWhiskeyProGetUniversalPackage -ForPath $forPath -HasRootItems $file
}

Describe 'ProGetUniversalPackage.when packaging a directory with custom destination name' {
    Init
    GivenARepositoryWithItems 'dir1\some_file.txt','dir2\dir3\another_file.txt','dir4\dir5\last_file.txt'
    WhenPackaging -WithYaml @'
Build:
- ProGetUniversalPackage:
    Name: Package
    Version: 1.2.3
    Description: Test package
    Path:
    - dir1: dirA
    - dir2\dir3: dir2\dirC
    - dir4\dir5: dirD\dir5
    Include:
    - "*.txt"
'@
    ThenTaskSucceeds
    ThenPackageShouldInclude 'dirA\some_file.txt','dir2\dirC\another_file.txt','dirD\dir5\last_file.txt'
}

Describe 'ProGetUniversalPackage.when including third-party items with override syntax' {
    Init
    GivenARepositoryWithItems 'dir1\thirdparty.txt', 'app\thirdparty\none of your business', 'app\fourthparty\none of your business'
    # Ensures task handles either type of object so we can switch parsers easily.
    $thirdPartyDictionary = New-Object 'Collections.Generic.Dictionary[string,string]'
    $thirdPartyDictionary['app\fourthparty'] = 'fourthparty'
    WhenPackaging -Paths 'dir1' -WithWhitelist @('thirdparty.txt') -WithThirdPartyPath @{ 'app\thirdparty' = 'thirdparty' },$thirdPartyDictionary
    ThenTaskSucceeds
    ThenPackageShouldInclude 'dir1\thirdparty.txt', 'thirdparty\none of your business','fourthparty\none of your business'
}

Describe 'ProGetUniversalPackage.when package is empty' {
    Init
    GivenARepositoryWIthItems 'file.txt'
    WhenPackaging -WithWhitelist "*.txt"
    ThenPackageShouldInclude
}

Describe 'ProGetUniversalPackage.when path contains wildcards' {
    Init
    GivenARepositoryWIthItems 'one.ps1','two.ps1','three.ps1'
    WhenPackaging -Paths '*.ps1' -WithWhitelist '*.txt'
    ThenPackageShouldInclude 'one.ps1','two.ps1','three.ps1'
}


Describe 'ProGetUniversalPackage.when packaging a directory' {
    Init
    GivenARepositoryWIthItems 'dir1\subdir\file.txt'
    WhenPackaging -Paths 'dir1\subdir\' -WithWhitelist "*.txt"
    ThenPackageShouldInclude 'dir1\subdir\file.txt'
    ThenPackageShouldNotInclude ('dir1\{0}' -f $defaultPackageName)
}

Describe 'ProGetUniversalPackage.when packaging a directory with a space' {
    Init
    GivenARepositoryWIthItems 'dir 1\sub dir\file.txt'
    WhenPackaging -Paths 'dir 1\sub dir' -WithWhitelist "*.txt"
    ThenPackageShouldInclude 'dir 1\sub dir\file.txt'
    ThenPackageShouldNotInclude ('dir 1\{0}' -f $defaultPackageName)
}

Describe 'ProGetUniversalPackage.when packaging a directory with a space and trailing backslash' {
    Init
    GivenARepositoryWIthItems 'dir 1\sub dir\file.txt'
    WhenPackaging -Paths 'dir 1\sub dir\' -WithWhitelist "*.txt"
    ThenPackageShouldInclude 'dir 1\sub dir\file.txt'
    ThenPackageShouldNotInclude ('dir 1\{0}' -f $defaultPackageName)
}

foreach( $compressionLevel in @( 9, 'Optimal' ) )
{
    Describe ('ProGetUniversalPackage.when compression level is {0}' -f $compressionLevel) {
        Init
        GivenARepositoryWIthItems 'one.ps1'
        WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1" -CompressionLevel $compressionLevel
        ThenPackageShouldBeCompressed 'one.ps1' -LessThanOrEqualTo 8000
    }
}

foreach( $compressionLevel in @( 1, 'Fastest' ) )
{
    Describe ('ProGetUniversalPackage.when compression level is {0}' -f $compressionLevel) {
        Init
        GivenARepositoryWIthItems 'one.ps1'
        WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1" -CompressionLevel $compressionLevel
        ThenPackageShouldBeCompressed 'one.ps1' -GreaterThan 8000
    }
}

Describe 'ProGetUniversalPackage.when compression level is not included' {
    Init
    GivenARepositoryWIthItems 'one.ps1'
    WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1"
    ThenPackageShouldBeCompressed 'one.ps1' -LessThanOrEqualTo 8000
}

Describe 'ProGetUniversalPackage.when a bad compression level is included' {
    Init
    GivenARepositoryWIthItems 'one.ps1'
    WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1" -CompressionLevel "this is no good" -ErrorAction SilentlyContinue
    ThenTaskFails 'not a valid compression level'
}

Describe 'ProGetUniversalPackage.when package has empty directories' {
    Init
    GivenARepositoryWithItems 'root.ps1','dir1\one.ps1','dir1\emptyDir2\text.txt'
    GivenARepositoryWithItems 'dir1\emptyDir1' -ItemType 'Directory'
    WhenPackaging -Paths '.' -WithWhitelist '*.ps1' -ThatExcludes '.output'
    ThenPackageShouldInclude 'root.ps1','dir1\one.ps1'
    ThenPackageShouldNotInclude 'dir1\emptyDir1', 'dir1\emptyDir2'
}

Describe 'ProGetUniversalPackage.when package has JSON files' {
    Init
    GivenARepositoryWIthItems 'my.json'
    WhenPackaging -Paths '.' -WithWhitelist '*.json' -ThatExcludes '.output'
    ThenPackageShouldInclude 'my.json','version.json'
}

Describe 'New-WhiskeyProGetUniversalPackage.when package contains only third-party paths and only files' {
    Init
    GivenARepositoryWithItems 'my.json','dir\yours.json', 'my.txt'
    WhenPackaging -WithThirdPartyPath 'dir' -Paths 'my.json'
    ThenPackageShouldInclude 'version.json','dir\yours.json', 'my.json'
    ThenPackageShouldNotInclude 'my.txt'
}

Describe 'ProGetUniversalPackage.when package includes a directory but whitelist is empty' {
    Init
    GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
    WhenPackaging -Paths 'dir' -WithWhitelist @() -ErrorAction SilentlyContinue
    ThenTaskFails 'Property\ "Include"\ is\ mandatory\ because'
}

Describe 'ProGetUniversalPackage.when package includes a directory but whitelist is missing' {
    Init
    GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
    WhenPackaging -Paths 'dir' -ErrorAction SilentlyContinue
    ThenTaskFails 'Property\ "Include"\ is\ mandatory\ because'
}

Describe 'ProGetUniversalPackage.when package includes a file and there''s no whitelist' {
    Init
    GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
    WhenPackaging -Paths 'dir\my.json'
    ThenPackageShouldInclude 'dir\my.json'
    ThenTaskSucceeds
    ThenPackageShouldNotInclude 'dir\yours.json'
}

Describe 'ProGetUniversalPackage.when customizing package version' {
    Init
    GivenBuildVersion '1.2.3-rc.1+build.300'
    GivenARepositoryWithItems 'my.file'
    GivenPackageVersion '5.8.2'
    WhenPackaging -Paths 'my.file'
    ThenPackageShouldInclude 'my.file','version.json'
    ThenUpackMetadataIs @{
        'Name' = $defaultPackageName;
        'Title' = $defaultPackageName;
        'Description' = $defaultDescription;
        'Version' = '5.8.2-rc.1';
    }
    ThenVersionIs -Version '5.8.2' `
                  -PrereleaseMetadata 'rc.1' `
                  -BuildMetadata 'build.300' `
                  -SemVer2 '5.8.2-rc.1+build.300' `
                  -SemVer1 '5.8.2-rc1' `
                  -SemVer2NoBuildMetadata '5.8.2-rc.1'
    ThenTaskSucceeds
}

Describe 'ProGetUniversalPackage.when not customizing package version' {
    Init
    GivenBuildVersion '1.2.3-rc.1+build.300'
    GivenARepositoryWithItems 'my.file'
    WhenPackaging -Paths 'my.file'
    ThenPackageShouldInclude 'my.file','version.json'
    ThenUpackMetadataIs @{
        'Name' = $defaultPackageName;
        'Title' = $defaultPackageName;
        'Description' = $defaultDescription;
        'Version' = $context.Version.SemVer2NoBuildMetadata.ToString();
    }
    ThenVersionIs -Version '1.2.3' `
                  -PrereleaseMetadata 'rc.1' `
                  -BuildMetadata 'build.300' `
                  -SemVer2 '1.2.3-rc.1+build.300' `
                  -SemVer1 '1.2.3-rc1' `
                  -SemVer2NoBuildMetadata '1.2.3-rc.1'
    ThenTaskSucceeds
}

Describe 'ProGetUniversalPackage.when Name property is in invalid format' {
    Init
    GivenBuildVersion '1.2.3-rc.1+build.300'
    GivenARepositoryWithItems 'my.file'
    WhenPackaging -WithPackageName 'this@is an invalid+name!' -Path 'my.file' -ErrorAction SilentlyContinue
    ThenTaskFails '"Name"\ property\ is invalid'
}

Describe 'ProGetUniversalPackage.when given ManifestProperties' {
    Init
    GivenBuildVersion '1.2.3-rc.1+build.300'
    GivenARepositoryWithItems 'my.file'
    GivenManifestProperties @{
        '_CustomMetadata' = @{
            'SomethingCustom' = 'Fancy custom metadata'
        }
    }
    WhenPackaging -WithPackageName 'NameTaskProperty' -WithDescription 'DescriptionTaskProperty' -Path 'my.file'
    ThenPackageShouldInclude 'my.file'
    ThenUpackMetadataIs @{
        'Name' = 'NameTaskProperty'
        'Description' = 'DescriptionTaskProperty'
        'Title' = 'NameTaskProperty'
        'Version' = '1.2.3-rc.1'
        '_CustomMetadata' = @{
            'SomethingCustom' = 'Fancy custom metadata'
        }
    }
    ThenTaskSucceeds
}

Describe 'ProGetUniversalPackage.when given ManifestProperties that contain Name, Description, and Version task properties' {
    Init
    GivenBuildVersion '1.2.3-rc.1+build.300'
    GivenARepositoryWithItems 'my.file'
    GivenManifestProperties @{
        'Name' = 'AwesomePackageName'
        'Description' = 'CoolDescription'
        'Version' = '0.0.0'
        '_CustomMetadata' = @{
            'SomethingCustom' = 'Fancy custom metadata'
        }
    }
    WhenPackaging -Path 'my.file' -ErrorAction SilentlyContinue
    ThenTaskFails 'This property cannot be manually defined in "ManifestProperties"'
}

Describe 'ProGetUniversalPackage.when missing required properties' {
    Init
    GivenBuildVersion '1.2.3-rc.1+build.300'
    GivenARepositoryWithItems 'my.file'
    GivenManifestProperties @{
        '_CustomMetadata' = @{
            'SomethingCustom' = 'Fancy custom metadata'
        }
    }
    WhenPackaging -WithPackageName 'AwesomePackageName' -WithDescription $null -Path 'my.file' -ErrorAction SilentlyContinue
    ThenTaskFails 'Property "Description" is mandatory'
}
