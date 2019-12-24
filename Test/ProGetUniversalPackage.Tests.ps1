
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$defaultPackageName = 'WhiskeyTest'
$defaultDescription = 'A package created to test the New-WhiskeyProGetUniversalPackage function in the Whiskey module.'
$defaultVersion = '1.2.3'
$packageVersion = $null
$buildVersion = $null
$manifestProperties = $null

$threwException = $false
$context = $null
$expandPath = $null

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

function GivenBuildVersion
{
    param(
        [SemVersion.SemanticVersion]$Version
    )

    $script:buildVersion = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyVersionObject'
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
        [hashtable]$Content
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

    $script:testRoot = New-WhiskeyTestRoot
}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function ThenTaskFails
{
    Param(
        [String]$error
    )

    $Global:Error | Should -Match $error
}

function ThenTaskSucceeds
{
    $Global:Error | Should -BeNullOrEmpty
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
    $versionJson.Version | Should -BeOfType ([String])
    $versionJson.Version | Should -Be $Version
    $versionJson.PrereleaseMetadata | Should -BeOfType ([String])
    $versionJson.PrereleaseMetadata | Should -Be $PrereleaseMetadata
    $versionJson.BuildMetadata | Should -BeOfType ([String])
    $versionJson.BuildMetadata | Should -Be $BuildMetadata
    $versionJson.SemVer2 | Should -BeOfType ([String])
    $versionJson.SemVer2 | Should -Be $SemVer2
    $versionJson.SemVer1 | Should -BeOfType ([String])
    $versionJson.SemVer1 | Should -Be $SemVer1
    $versionJson.SemVer2NoBuildMetadata | Should -BeOfType ([String])
    $versionJson.SemVer2NoBuildMetadata | Should -Be $SemVer2NoBuildMetadata
}

function Assert-NewWhiskeyProGetUniversalPackage
{
    [CmdletBinding()]
    param(
        [Object[]]$ForPath,

        [String[]]$ThatIncludes,

        [String[]]$ThatExcludes,

        [String]$Name = $defaultPackageName,

        [String]$Description = $defaultDescription,

        [String]$Version,

        [String[]]$HasRootItems,

        [String[]]$HasFiles,

        [String[]]$NotHasFiles,

        [String]$ShouldFailWithErrorMessage,

        [switch]$ShouldWriteNoErrors,

        [switch]$ShouldReturnNothing,

        [String[]]$HasThirdPartyRootItem,

        [Object[]]$WithThirdPartyRootItem,

        [String[]]$HasThirdPartyFile,

        [String]$FromSourceRoot,

        [String[]]$MissingRootItems,

        [switch]$WhenCleaning,

        [switch]$withInitialize
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

    $script:context = $taskContext = New-WhiskeyTestContext -ForBuildRoot (Join-Path -Path $testRoot -ChildPath 'Repo') `
                                                            -ForBuildServer `
                                                            -IncludePSModule 'ProGetAutomation'

    $semVer2 = [SemVersion.SemanticVersion]$Version
    $taskContext.Version.SemVer2 = $semVer2
    $taskContext.Version.Version = [Version]('{0}.{1}.{2}' -f $taskContext.Version.SemVer2.Major,$taskContext.Version.SemVer2.Minor,$taskContext.Version.SemVer2.Patch)
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
        $At | Should -BeNullOrEmpty
    }
    else
    {
        $At | Should -Exist
    }

    if( $ShouldWriteNoErrors )
    {
        ThenTaskSucceeds
    }

    if( $ShouldFailWithErrorMessage )
    {
        $threwException | Should -BeTrue

        ThenTaskFails $ShouldFailWithErrorMessage
    }
    else
    {
        $threwException | Should -BeFalse
    }

    $expandPath = Join-Path -Path $testRoot -ChildPath 'Expand'
    $packageContentsPath = Join-Path -Path $expandPath -ChildPath 'package'
    $packageName = '{0}.{1}.upack' -f $Name,($taskContext.Version.SemVer2NoBuildMetadata-replace '[\\/]','-')
    $outputRoot = $taskContext.OutputDirectory
    $packagePath = Join-Path -Path $outputRoot -ChildPath $packageName

    $packagePath | Should -Exist

    if( -not (Test-Path -Path $expandPath -PathType Container) )
    {
        New-Item -Path $expandPath -ItemType 'Directory' | Out-Null
    }
    [IO.Compression.ZipFile]::ExtractToDirectory($packagePath, $expandPath)

    $upackJsonPath = Join-Path -Path $expandPath -ChildPath 'upack.json'

    foreach( $itemName in $MissingRootItems )
    {
        Join-Path -Path $packageContentsPath -ChildPath $itemName | Should -Not -Exist
    }

    foreach( $itemName in $HasRootItems )
    {
        $dirPath = Join-Path -Path $packageContentsPath -ChildPath $itemName
        $dirpath | Should -Exist
        foreach( $fileName in $HasFiles )
        {
            Join-Path -Path $dirPath -ChildPath $fileName | Should -Exist
        }

        foreach( $fileName in $HasThirdPartyFile )
        {
            Join-Path -Path $dirPath -ChildPath $fileName | Should -Not -Exist
        }
    }

    $versionJsonPath = Join-Path -Path $packageContentsPath -ChildPath 'version.json'
    $versionJsonPath | Should -Exist

    $versionJson = Get-Content -Path $versionJsonPath -Raw | ConvertFrom-Json
    $versionJson.Version | Should -BeOfType ([String])
    $versionJson.Version | Should -Be $taskContext.Version.Version.ToString()
    $versionJson.PrereleaseMetadata | Should -BeOfType ([String])
    $versionJson.PrereleaseMetadata | Should -Be $taskContext.Version.SemVer2.Prerelease.ToString()
    $versionJson.BuildMetadata | Should -BeOfType ([String])
    $versionJson.BuildMetadata | Should -Be $taskContext.Version.SemVer2.Build.ToString()
    $versionJson.SemVer2 | Should -BeOfType ([String])
    $versionJson.SemVer2 | Should -Be $taskContext.Version.SemVer2.ToString()
    $versionJson.SemVer1 | Should -BeOfType ([String])
    $versionJson.SemVer1 | Should -Be $taskContext.Version.SemVer1.ToString()
    $versionJson.SemVer2NoBuildMetadata | Should -BeOfType ([String])
    $versionJson.SemVer2NoBuildMetadata | Should -Be $taskContext.Version.SemVer2NoBuildMetadata.ToString()

    if( $NotHasFiles )
    {
        foreach( $item in $NotHasFiles )
        {
            Get-ChildItem -Path $packageContentsPath -Filter $item -Recurse | Should -BeNullOrEmpty
        }
    }

    $upackJsonPath | Should -Exist

    foreach( $itemName in $HasThirdPartyRootItem )
    {
        $dirPath = Join-Path -Path $packageContentsPath -ChildPath $itemName
        $dirpath | Should -Exist

        foreach( $fileName in $HasThirdPartyFile )
        {
            Join-Path -Path $dirPath -ChildPath $fileName | Should -Exist
        }
    }

    $upackInfo = Get-Content -Raw -Path $upackJsonPath | ConvertFrom-Json
    $upackInfo | Should -Not -BeNullOrEmpty
    $upackInfo.Name | Should -Be $Name
    $upackInfo.title | Should -Be $Name
    $upackInfo.Version | Should -Be $taskContext.Version.SemVer2NoBuildMetadata.ToString()
    $upackInfo.Description | Should -Be $Description
}

function Initialize-Test
{
    param(
        [String[]]$DirectoryName,

        [String[]]$FileName,

        [String[]]$RootFileName,

        [switch]$WhenUploadFails,

        [switch]$OnFeatureBranch,

        [switch]$OnMasterBranch,

        [switch]$OnReleaseBranch,

        [switch]$OnPermanentReleaseBranch,

        [switch]$OnDevelopBranch,

        [switch]$OnHotFixBranch,

        [switch]$OnBugFixBranch,

        [String]$SourceRoot
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
    $buildRoot = (Join-Path -Path $testRoot -ChildPath 'Repo')
    New-Item -Path $buildRoot -ItemType 'Directory' -Force -ErrorAction Ignore | Out-Null
    return $buildRoot
}

function GivenARepositoryWithItems
{
    param(
        [String[]]$Path,

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
}

function ThenPackageArchive
{
    param(
        [String]$PackageName,

        [String[]]$ContainsPath
    )

    $outputRoot = Join-Path -Path (Get-BuildRoot) -ChildPath '.output'
    $packagePath = Get-ChildItem -Path $outputRoot -Filter ('{0}.*.upack' -f $PackageName) | Select-Object -ExpandProperty 'FullName'

    [IO.Compression.ZipArchive]$packageArchive = [IO.Compression.ZipFile]::Open($packagePath, [IO.Compression.ZipArchiveMode]::Read)
    try
    {
        foreach ($path in $ContainsPath)
        {
            $path = $path -replace '[\\/]', [IO.Path]::DirectorySeparatorChar
            $packageArchive.Entries.FullName | Should -Contain $path
        }
    }
    finally
    {
        $packageArchive.Dispose()
    }
}

function ThenPackageShouldInclude
{
    param(
        $PackageName = $defaultPackageName,
        $PackageVersion = $defaultVersion,
        [Parameter(Position=0)]
        [String[]]$Path
    )

    $Path += @( 'version.json' )
    $packageRoot = Join-Path -Path $expandPath -ChildPath 'package'
    foreach( $item in $Path )
    {
        $expectedPath = Join-Path -Path $packageRoot -ChildPath $item
        $expectedPath | Should -Exist
    }
}

function ThenPackageShouldNotInclude
{
    param(
        [String[]]$Path
    )

    $packageRoot = Join-Path -Path $expandPath -ChildPath 'package'

    foreach( $item in $Path )
    {
        (Join-Path -Path $packageRoot -ChildPath $item) | Should -Not -Exist
    }
}

function ThenUpackMetadataIs
{
    param(
        [hashtable]$ExpectedContent
    )

    function Assert-HashTableEqual
    {
        param(
            [hashtable]$Reference,

            [hashtable]$Difference
        )

        # $DebugPreference = 'Continue'
        foreach ($key in $Reference.Keys)
        {
            Write-WhiskeyDebug -Context $context $key
            if ($key -notin $Difference.Keys)
            {
                Write-WhiskeyDebug -Context $context -Message ('Expected  {0},{1}' -f $key,($Difference.Keys -join ','))
                Write-WhiskeyDebug -Context $context -Message ('Actual    {0}' -f $Difference.Keys)
                return $false
            }
            elseif ($Reference[$key] | Get-Member -Name 'Keys')
            {
                if (-not ($Difference[$key] | Get-Member -Name 'Keys') -or (-not (Assert-HashTableEqual -Reference $Reference[$key] -Difference $Difference[$key])))
                {
                    Write-WhiskeyDebug -Context $context -Message ('Expected  {0}' -f $Reference[$key])
                    Write-WhiskeyDebug -Context $context -Message ('Actual    {0}' -f $Difference[$key])
                    return $false
                }
            }
            elseif (Compare-Object -ReferenceObject $Reference[$key] -DifferenceObject $Difference[$key])
            {
                Write-WhiskeyDebug -Context $context -Message ('Expected  {0}' -f $Reference[$key])
                Write-WhiskeyDebug -Context $context -Message ('Actual    {0}' -f $Difference[$key])
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

    Write-WhiskeyDebug -Context $context 'Expected'
    $ExpectedContent | ConvertTo-Json | Write-WhiskeyDebug -Context $context
    Write-WhiskeyDebug -Context $context 'Actual'
    $upackContent | ConvertTo-Json | Write-WhiskeyDebug -Context $context
    Assert-HashTableEqual -Reference $ExpectedContent -Difference $upackContent | Should -BeTrue
}

function ThenPackageShouldBeCompressed
{
    param(
        $PackageName = $defaultPackageName,
        $PackageVersion = $defaultVersion,
        [Parameter(Position=0)]
        [String[]]$Path,

        [int]$GreaterThan,

        [int]$LessThanOrEqualTo
    )

    $packageSize = Get-PackageSize -PackageName $PackageName -PackageVersion $PackageVersion
    #$DebugPreference = 'Continue'
    Write-WhiskeyDebug -Context $context -Message ('Package size: {0}' -f $packageSize)
    if( $GreaterThan )
    {
        $packageSize | Should -BeGreaterThan $GreaterThan
    }

    if( $LessThanOrEqualTo )
    {
        $packageSize | Should -Not -BeGreaterThan $LessThanOrEqualTo
    }

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
        [Object[]]$Paths,

        [Parameter(ParameterSetName='WithTaskParameter')]
        [Object[]]$WithWhitelist,

        [Parameter(ParameterSetName='WithTaskParameter')]
        [Object[]]$ThatExcludes,

        [Parameter(ParameterSetName='WithTaskParameter')]
        $FromSourceRoot,

        [Parameter(ParameterSetName='WithTaskParameter')]
        [Object[]]$WithThirdPartyPath,

        [Parameter(ParameterSetName='WithTaskParameter')]
        $WithVersion = $defaultVersion,

        [Parameter(ParameterSetName='WithTaskParameter')]
        $WithApplicationName,

        [Parameter(ParameterSetName='WithTaskParameter')]
        $CompressionLevel,

        [Parameter(ParameterSetName='WithTaskParameter')]
        [switch]$SkipExpand,

        [Parameter(Mandatory,ParameterSetName='WithYaml')]
        $WithYaml
    )

    if( $PSCmdlet.ParameterSetName -eq 'WithYaml' )
    {
        $script:context = $taskContext = New-WhiskeyTestContext -ForBuildRoot (Join-Path -Path $testRoot -ChildPath 'Repo') `
                                                                -ForBuildServer -ForYaml $WithYaml `
                                                                -IncludePSModule 'ProGetAutomation'

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

        $script:context = $taskContext = New-WhiskeyTestContext -ForBuildRoot (Join-Path -Path $testRoot -ChildPath 'Repo') `
                                                                -ForBuildServer -ForVersion $WithVersion `
                                                                -IncludePSModule 'ProGetAutomation'
                                                                
        if( $WithApplicationName )
        {
            $taskContext.ApplicationName = $WithApplicationName
        }
        if( $buildVersion )
        {
            $context.Version = $buildVersion
        }
    }

    $script:threwException = $false

    $Global:Error.Clear()

    try
    {
        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'ProGetUniversalPackage'
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }

    $packageInfo = Get-ChildItem -Path $taskContext.OutputDirectory -Filter '*.upack'

    if( -not $SkipExpand -and $packageInfo )
    {
        $script:expandPath = Join-Path -Path $taskContext.OutputDirectory -ChildPath 'extracted'
        $expandParent = $expandPath | Split-Path -Parent
        if( -not (Test-Path -Path $expandParent -PathType Container) )
        {
            New-item -Path $expandParent -ItemType 'Directory' | Out-Null
        }
        [IO.Compression.ZipFile]::ExtractToDirectory($packageInfo.FullName,$expandPath)
    }
}

Describe 'ProGetUniversalPackage.when packaging everything in a directory' {
    AfterEach { Reset }
    It 'should create the package' {
        Init
        $dirNames = @( 'dir1', 'dir1\sub' )
        $fileNames = @( 'html.html' )
        Initialize-Test -DirectoryName $dirNames `
                                        -FileName $fileNames

        Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                                -ThatIncludes '*.html' `
                                                -HasRootItems $dirNames `
                                                -HasFiles 'html.html'
    }
}

Describe 'ProGetUniversalPackage.when packaging root files' {
    AfterEach { Reset }
    It 'should package the root files' {
        Init
        $file = 'project.json'
        $thirdPartyFile = 'thirdparty.txt'
        Initialize-Test -RootFileName $file,$thirdPartyFile
        Assert-NewWhiskeyProGetUniversalPackage -ForPath $file `
                                                -WithThirdPartyRootItem $thirdPartyFile `
                                                -HasThirdPartyRootItem $thirdPartyFile `
                                                -HasRootItems $file
    }
}

Describe 'ProGetUniversalPackage.when packaging whitelisted files in a directory' {
    AfterEach { Reset }
    It 'should only package whitelisted files' {
        Init
        $dirNames = @( 'dir1', 'dir1\sub' )
        $fileNames = @( 'html.html', 'code.cs', 'style.css' )
        Initialize-Test -DirectoryName $dirNames -FileName $fileNames

        Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                                -ThatIncludes '*.html','*.css' `
                                                -HasRootItems $dirNames `
                                                -HasFiles 'html.html','style.css' `
                                                -NotHasFiles 'code.cs'
    }
}

Describe 'ProGetUniversalPackage.when packaging multiple directories' {
    AfterEach { Reset }
    It 'should package each directory' {
        Init
        $dirNames = @( 'dir1', 'dir1\sub', 'dir2' )
        $fileNames = @( 'html.html', 'code.cs' )
        Initialize-Test -DirectoryName $dirNames -FileName $fileNames

        Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1','dir2' `
                                                -ThatIncludes '*.html' `
                                                -HasRootItems $dirNames `
                                                -HasFiles 'html.html' `
                                                -NotHasFiles 'code.cs'
    }
}

Describe 'ProGetUniversalPackage.when whitelist includes items that need to be excluded' {
    AfterEach { Reset }
    It 'should exclude files that are in the whiteliset' {
        Init
        $dirNames = @( 'dir1', 'dir1\sub' )
        $fileNames = @( 'html.html', 'html2.html' )
        Initialize-Test -DirectoryName $dirNames -FileName $fileNames

        Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                                -ThatIncludes '*.html' `
                                                -ThatExcludes 'html2.html','sub' `
                                                -HasRootItems 'dir1' `
                                                -HasFiles 'html.html' `
                                                -NotHasFiles 'html2.html','sub'
    }
}

Describe 'ProGetUniversalPackage.when paths do not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init

        $Global:Error.Clear()

        Initialize-Test

        Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1','dir2' `
                                                -ThatIncludes '*' `
                                                -ShouldFailWithErrorMessage '(don''t|does not) exist' `
                                                -ErrorAction SilentlyContinue
    }
}

Describe 'ProGetUniversalPackage.when including third-party items' {
    AfterEach { Reset }
    It 'should not filter third-party items' {
        Init
        $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
        $fileNames = @( 'html.html', 'thirdparty.txt' )
        Initialize-Test -DirectoryName $dirNames -FileName $fileNames

        Assert-NewWhiskeyProGetUniversalPackage -ForPath 'dir1' `
                                                -ThatIncludes '*.html' `
                                                -ThatExcludes 'thirdparty.txt' `
                                                -HasRootItems 'dir1' `
                                                -HasFiles 'html.html' `
                                                -WithThirdPartyRootItem 'thirdparty','thirdpart2' `
                                                -HasThirdPartyRootItem 'thirdparty','thirdpart2' `
                                                -HasThirdPartyFile 'thirdparty.txt'
    }
}

foreach( $parameterName in @( 'Name', 'Description' ) )
{
    Describe ('ProGetUniversalPackage.when {0} property is omitted' -f $parameterName) {
        AfterEach { Reset }
        It 'should fail' {
            Init
            $parameter = @{
                            Name = 'Name';
                            Include = 'Include';
                            Description = 'Description';
                            Path = 'Path'
                        }
            $parameter.Remove($parameterName)

            $context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot -IncludePSModule 'ProGetAutomation'
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

            $threwException | Should -BeTrue
            $Global:Error | Should -Match ('\bProperty\ "{0}"\ is\ mandatory\b' -f $parameterName)
        }
    }
}

Describe 'ProGetUniversalPackage.when path to package does not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot -IncludePSModule 'ProGetAutomation'
        $Global:Error.Clear()

        { Invoke-WhiskeyTask -TaskContext $context -Parameter @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = 'fubar' } -Name 'ProGetUniversalPackage' } | Should -Throw

        $Global:Error | Should -Match '\bPath\b.*\bfubar\b.*\ does\ not\ exist'
    }
}

Describe 'ProGetUniversalPackage.when path to third-party item does not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot -IncludePSModule 'ProGetAutomation'

        $Global:Error.Clear()

        { Invoke-WhiskeyTask -TaskContext $context -Parameter @{ Name = 'fubar' ; Description = 'fubar'; Include = 'fubar'; Path = '.'; ThirdPartyPath = 'fubar' } -Name 'ProGetUniversalPackage' } | Should -Throw
        $Global:Error | Select-Object -First 1 | Should -Match '\bThirdPartyPath\b.*\bfubar\b.* does not exist' 
    }
}

Describe 'ProGetUniversalPackage.when application root is not the root of the repository' {
    AfterEach { Reset }
    It 'should use source root as package root' {
        Init
        $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
        $fileNames = @( 'html.html', 'thirdparty.txt' )
        Initialize-Test -DirectoryName $dirNames -FileName $fileNames -SourceRoot 'app'

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
}

Describe 'ProGetUniversalPackage.when custom application root does not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        $dirNames = @( 'dir1', 'thirdparty', 'thirdpart2' )
        $fileNames = @( 'html.html', 'thirdparty.txt' )
        Initialize-Test -DirectoryName $dirNames -FileName $fileNames
        $context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot -IncludePSModule 'ProGetAutomation'

        $Global:Error.Clear()

        $parameter = @{
                        Name = 'fubar' ;
                        Description = 'fubar';
                        Include = 'fubar';
                        Path = '.';
                        ThirdPartyPath = 'fubar'
                        SourceRoot = 'app';
                    }

        { Invoke-WhiskeyTask -TaskContext $context -Parameter $parameter -Name 'ProGetUniversalPackage' } | Should -Throw

        ThenTaskFails '\bapp\b.*\bdoes not exist'
    }
}

Describe 'ProGetUniversalPackage.when packaging given a full relative path' {
    AfterEach { Reset }
    It 'should package the file' {
        Init
        $file = 'project.json'
        $directory = 'relative'
        $path = ('{0}\{1}' -f ($directory, $file))

        Initialize-Test -DirectoryName $directory -FileName $file
        Assert-NewWhiskeyProGetUniversalPackage -ForPath $path -HasRootItems $path
    }
}

Describe 'ProGetUniversalPackage.when packaging given a full relative path to a file with override syntax' {
    AfterEach { Reset }
    It 'should customzie the item name in package' {
        Init
        $file = 'project.json'
        $directory = 'relative'
        $path = ('{0}\{1}' -f ($directory, $file))
        $forPath = @{ $path = $file }

        Initialize-Test -DirectoryName $directory -FileName $file
        Assert-NewWhiskeyProGetUniversalPackage -ForPath $forPath -HasRootItems $file
    }
}

Describe 'ProGetUniversalPackage.when packaging a directory with custom destination name' {
    AfterEach { Reset }
    It 'should customize directory name in package' {
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
}

Describe 'ProGetUniversalPackage.when including third-party items with override syntax' {
    AfterEach { Reset }
    It 'should customize third-party name in package`' {
        Init
        GivenARepositoryWithItems 'dir1\thirdparty.txt', 'app\thirdparty\none of your business', 'app\fourthparty\none of your business'
        # Ensures task handles either type of object so we can switch parsers easily.
        $thirdPartyDictionary = New-Object 'Collections.Generic.Dictionary[string,string]'
        $thirdPartyDictionary['app\fourthparty'] = 'fourthparty'
        WhenPackaging -Paths 'dir1' -WithWhitelist @('thirdparty.txt') -WithThirdPartyPath @{ 'app\thirdparty' = 'thirdparty' },$thirdPartyDictionary
        ThenTaskSucceeds
        ThenPackageShouldInclude 'dir1\thirdparty.txt', 'thirdparty\none of your business','fourthparty\none of your business'
    }
}

Describe 'ProGetUniversalPackage.when package is empty' {
    AfterEach { Reset }
    It 'should pass' {
        Init
        GivenARepositoryWIthItems 'file.txt'
        WhenPackaging -WithWhitelist "*.txt"
        ThenPackageShouldInclude
    }
}

Describe 'ProGetUniversalPackage.when path contains wildcards' {
    AfterEach { Reset }
    It 'should package items that match wildcard' {
        Init
        GivenARepositoryWIthItems 'one.ps1','two.ps1','three.ps1'
        WhenPackaging -Paths '*.ps1' -WithWhitelist '*.txt'
        ThenPackageShouldInclude 'one.ps1','two.ps1','three.ps1'
    }

}

Describe 'ProGetUniversalPackage.when packaging a directory' {
    AfterEach { Reset }
    It 'should package contents that match whitelist' {
        Init
        GivenARepositoryWIthItems 'dir1\subdir\file.txt'
        WhenPackaging -Paths 'dir1\subdir\' -WithWhitelist "*.txt"
        ThenPackageShouldInclude 'dir1\subdir\file.txt'
        ThenPackageShouldNotInclude ('dir1\{0}' -f $defaultPackageName)
    }
}

Describe 'ProGetUniversalPackage.when packaging a directory with a space' {
    AfterEach { Reset }
    It 'should pass' {
        Init
        GivenARepositoryWIthItems 'dir 1\sub dir\file.txt'
        WhenPackaging -Paths 'dir 1\sub dir' -WithWhitelist "*.txt"
        ThenPackageShouldInclude 'dir 1\sub dir\file.txt'
        ThenPackageShouldNotInclude ('dir 1\{0}' -f $defaultPackageName)
    }
}

Describe 'ProGetUniversalPackage.when packaging a directory with a space and trailing backslash' {
    AfterEach { Reset }
    It 'should pass' {
        Init
        GivenARepositoryWIthItems 'dir 1\sub dir\file.txt'
        WhenPackaging -Paths 'dir 1\sub dir\' -WithWhitelist "*.txt"
        ThenPackageShouldInclude 'dir 1\sub dir\file.txt'
        ThenPackageShouldNotInclude ('dir 1\{0}' -f $defaultPackageName)
    }
}

foreach( $compressionLevel in @( 9, 'Optimal' ) )
{
    Describe ('ProGetUniversalPackage.when compression level is {0}' -f $compressionLevel) {
        AfterEach { Reset }
        It 'should use compression level' {
            Init
            GivenARepositoryWIthItems 'one.ps1'
            WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1" -CompressionLevel $compressionLevel
            ThenPackageShouldBeCompressed 'one.ps1' -LessThanOrEqualTo 8500
        }
    }
}

foreach( $compressionLevel in @( 1, 'Fastest' ) )
{
    Describe ('ProGetUniversalPackage.when compression level is {0}' -f $compressionLevel) {
        AfterEach { Reset }
        It 'should use compression level' {
            Init
            GivenARepositoryWIthItems 'one.ps1'
            WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1" -CompressionLevel $compressionLevel
            ThenPackageShouldBeCompressed 'one.ps1' -GreaterThan 8500
        }
    }
}

Describe 'ProGetUniversalPackage.when compression level is not included' {
    AfterEach { Reset }
    It 'should use optimal compression' {
        Init
        GivenARepositoryWIthItems 'one.ps1'
        WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1"
        ThenPackageShouldBeCompressed 'one.ps1' -LessThanOrEqualTo 8500
    }
}

Describe 'ProGetUniversalPackage.when a bad compression level is included' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenARepositoryWIthItems 'one.ps1'
        WhenPackaging -Paths '*.ps1' -WithWhitelist "*.ps1" -CompressionLevel "this is no good" -ErrorAction SilentlyContinue
        ThenTaskFails 'not a valid compression level'
    }
}

Describe 'ProGetUniversalPackage.when package has empty directories' {
    AfterEach { Reset }
    It 'should not package empty directories' {
        Init
        GivenARepositoryWithItems 'root.ps1','dir1\one.ps1','dir1\emptyDir2\text.txt'
        GivenARepositoryWithItems 'dir1\emptyDir1' -ItemType 'Directory'
        WhenPackaging -Paths '.' -WithWhitelist '*.ps1' -ThatExcludes '.output'
        ThenPackageShouldInclude 'root.ps1','dir1\one.ps1'
        ThenPackageShouldNotInclude 'dir1\emptyDir1', 'dir1\emptyDir2'
    }
}

Describe 'ProGetUniversalPackage.when package has JSON files' {
    AfterEach { Reset }
    It 'should package the JSON files' {
        Init
        GivenARepositoryWIthItems 'my.json'
        WhenPackaging -Paths '.' -WithWhitelist '*.json' -ThatExcludes '.output'
        ThenPackageShouldInclude 'my.json','version.json'
    }
}

Describe 'New-WhiskeyProGetUniversalPackage.when package contains only third-party paths and only files' {
    AfterEach { Reset }
    It 'should package' {
        Init
        GivenARepositoryWithItems 'my.json','dir\yours.json', 'my.txt'
        WhenPackaging -WithThirdPartyPath 'dir' -Paths 'my.json'
        ThenPackageShouldInclude 'version.json','dir\yours.json', 'my.json'
        ThenPackageShouldNotInclude 'my.txt'
    }
}

Describe 'ProGetUniversalPackage.when package includes a directory but whitelist is empty' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging -Paths 'dir' -WithWhitelist @() -ErrorAction SilentlyContinue
        ThenTaskFails 'Property\ "Include"\ is\ mandatory\ because'
    }
}

Describe 'ProGetUniversalPackage.when package includes a directory but whitelist is missing' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging -Paths 'dir' -ErrorAction SilentlyContinue
        ThenTaskFails 'Property\ "Include"\ is\ mandatory\ because'
    }
}

Describe 'ProGetUniversalPackage.when package includes a file and there is no whitelist' {
    AfterEach { Reset }
    It 'should interpret files in include list as whitelisted' {
        Init
        GivenARepositoryWithItems 'dir\my.json', 'dir\yours.json'
        WhenPackaging -Paths 'dir\my.json'
        ThenPackageShouldInclude 'dir\my.json'
        ThenTaskSucceeds
        ThenPackageShouldNotInclude 'dir\yours.json'
    }
}

Describe 'ProGetUniversalPackage.when customizing package version' {
    AfterEach { Reset }
    It 'should package' {
        Init
        GivenBuildVersion '1.2.3-rc.1+build.300'
        GivenARepositoryWithItems 'my.file'
        GivenPackageVersion '5.8.2'
        WhenPackaging -Paths 'my.file'
        ThenPackageShouldInclude 'my.file','version.json'
        ThenUpackMetadataIs @{
            'name' = $defaultPackageName;
            'title' = $defaultPackageName;
            'description' = $defaultDescription;
            'version' = '5.8.2-rc.1';
        }
        ThenVersionIs -Version '5.8.2' `
                    -PrereleaseMetadata 'rc.1' `
                    -BuildMetadata 'build.300' `
                    -SemVer2 '5.8.2-rc.1+build.300' `
                    -SemVer1 '5.8.2-rc1' `
                    -SemVer2NoBuildMetadata '5.8.2-rc.1'
        ThenTaskSucceeds
    }
}

Describe 'ProGetUniversalPackage.when not customizing package version' {
    AfterEach { Reset }
    It 'should use build version' {
        Init
        GivenBuildVersion '1.2.3-rc.1+build.300'
        GivenARepositoryWithItems 'my.file'
        WhenPackaging -Paths 'my.file'
        ThenPackageShouldInclude 'my.file','version.json'
        ThenUpackMetadataIs @{
            'name' = $defaultPackageName;
            'title' = $defaultPackageName;
            'description' = $defaultDescription;
            'version' = $context.Version.SemVer2NoBuildMetadata.ToString();
        }
        ThenVersionIs -Version '1.2.3' `
                    -PrereleaseMetadata 'rc.1' `
                    -BuildMetadata 'build.300' `
                    -SemVer2 '1.2.3-rc.1+build.300' `
                    -SemVer1 '1.2.3-rc1' `
                    -SemVer2NoBuildMetadata '1.2.3-rc.1'
        ThenTaskSucceeds
    }
}

Describe 'ProGetUniversalPackage.when Name property is in invalid format' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenBuildVersion '1.2.3-rc.1+build.300'
        GivenARepositoryWithItems 'my.file'
        WhenPackaging -WithPackageName 'this@is an invalid+name!' -Path 'my.file' -ErrorAction SilentlyContinue
        ThenTaskFails '"Name"\ property\ is invalid'
    }
}

Describe 'ProGetUniversalPackage.when given ManifestProperties' {
    AfterEach { Reset }
    It 'should add them to manifest' {
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
            'name' = 'NameTaskProperty'
            'description' = 'DescriptionTaskProperty'
            'title' = 'NameTaskProperty'
            'version' = '1.2.3-rc.1'
            '_CustomMetadata' = @{
                'SomethingCustom' = 'Fancy custom metadata'
            }
        }
        ThenTaskSucceeds
    }
}

Describe 'ProGetUniversalPackage.when given ManifestProperties that contain Name, Description, and Version task properties' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenBuildVersion '1.2.3-rc.1+build.300'
        GivenARepositoryWithItems 'my.file'
        GivenManifestProperties @{
            'name' = 'AwesomePackageName'
            'description' = 'CoolDescription'
            'version' = '0.0.0'
            '_CustomMetadata' = @{
                'SomethingCustom' = 'Fancy custom metadata'
            }
        }
        WhenPackaging -Path 'my.file' -ErrorAction SilentlyContinue
        ThenTaskFails 'This property cannot be manually defined in "ManifestProperties"'
    }
}

Describe 'ProGetUniversalPackage.when missing required properties' {
    AfterEach { Reset }
    It 'should fail' {
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
}

Describe 'ProGetUniversalPackage.when ProGetAutomation function writes an error when packaging a file' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        Import-WhiskeyTestModule -Name 'ProGetAutomation'
        Mock -CommandName 'Add-ProGetUniversalPackageFile' -ModuleName 'Whiskey' -MockWith { Write-Error -Message 'Failed to add file to package' }
        GivenARepositoryWithItems 'my.file'
        WhenPackaging -Paths 'my.file' -ErrorAction SilentlyContinue
        ThenTaskFails 'Failed\ to\ add\ file\ to\ package'
    }
}

Describe 'ProGetUniversalPackage.when using the "." syntax to package a directory into the root of the package' {
    AfterEach { Reset }
    It 'should put item in root of package' {
        Init
        GivenARepositoryWithItems 'dir1\dir2\file.txt'
        WhenPackaging -WithYaml @"
Build:
- ProGetUniversalPackage:
    Name: TestPackage
    Version: 1.2.3
    Description: Test package
    Path:
    - dir1\dir2: .
    Include:
    - "*.txt"
"@
        ThenTaskSucceeds
        ThenPackageArchive 'TestPackage' -ContainsPath 'package\file.txt'
    }
}
