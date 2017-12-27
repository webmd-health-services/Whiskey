
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\New-WhiskeySemanticVersion.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\ConvertTo-WhiskeySemanticVersion.ps1' -Resolve)

$developerMetadataObject = New-WhiskeyBuildMetadataObject
$buildServerMetadataObject = New-WhiskeyBuildMetadataObject
$buildServerMetadataObject.BuildNumber = '80'
$buildServerMetadataObject.ScmBranch = 'feature/fubar'
$buildServerMetadataObject.ScmCommitID = 'deadbeefdeadbeefdeadbeefdeadbeef'
$buildServerMetadataObject.BuildServerName = 'Jenkins'

$buildServerMetadataString = '80.feature-fubar.deadbee'
$developerMetadataString = '{0}.{1}' -f $env:USERNAME,$env:COMPUTERNAME

$buildServerVersion = $null
$developerVersion = $null
$inputVersion = $null
$path = $null
$prerelease = ''

function Init
{
    $Global:Error.Clear()
    $script:buildServerVersion = $null
    $script:developerVersion = $null
    $script:inputVersion = $null
    $script:path = $null
    $script:prerelease = ''
}

function GivenFile
{
    param(
        $Name,
        $Content
    )

    $filePath = Join-Path -Path $TestDrive.FullName -ChildPath $Name
    Set-Content -Path $filePath -Value $Content -Force
}

function GivenPath
{
    param(
        $Path
    )

    $script:path = Join-Path -Path $TestDrive.FullName -ChildPath $Path
}

function GivenPrerelease
{
    param(
        $Prerelease
    )

    $script:prerelease = $Prerelease
}

function GivenVersion
{
    param(
        $Version
    )

    $script:inputVersion = $Version
}

function WhenGettingSemanticVersion
{
    [CmdletBinding()]
    param()

    $inputParam = @{ 'Version' = $inputVersion }
    if ($path)
    {
        $inputParam = @{ 'Path' = $path }
    }

    $script:buildServerVersion = New-WhiskeySemanticVersion @inputParam -Prerelease $Prerelease -BuildMetadata $buildServerMetadataObject
    $script:developerVersion = New-WhiskeySemanticVersion @inputParam -Prerelease $Prerelease -BuildMetadata $developerMetadataObject
}

function ThenAddedBuildMetadataToSemanticVersionOf
{
    param(
        $Version
    )
    
    if ($prerelease)
    {
        $prerelease = '-{0}' -f $prerelease
    }

    $buildServerSemVer = $developerSemVer = $Version
    if ($Version -match '^\d{4}\.\d{4}$')
    {
        $buildServerSemVer = '{0}.{1}' -f $Version,$buildServerMetadataObject.BuildNumber
        $developerSemVer   = '{0}.{1}' -f $Version,$developerMetadataObject.BuildNumber
    }

    Context 'by build server' {
        $expectedVersion = '{0}{1}+{2}' -f $buildServerSemVer,$prerelease,$buildServerMetadataString

        It ('should convert to {0}' -f $expectedVersion) {
            $buildServerVersion.ToString() | Should -Be $expectedVersion
        }
    }

    Context 'by developer' {
        $expectedVersion = '{0}{1}+{2}' -f $developerSemVer,$prerelease,$developerMetadataString

        It ('should convert to {0}' -f $expectedVersion) {
            $developerVersion.ToString() | Should -Be $expectedVersion
        }
    }
}

function ThenReturnedNothing
{
    It 'should not return anything' {
        $buildServerVersion | Should -BeNullOrEmpty
        $developerVersion | Should -BeNullOrEmpty
    }
}

function ThenErrorMessage
{
    param(
        $Message
    )

    It ('should write error message matching /{0}/' -f $Message) {
        $Global:Error[0] | Should -Match $Message
    }
}

Describe 'New-WhiskeySemanticVersion.when passed ''3.2.1+build.info''' {
    Init
    GivenVersion '3.2.1+build.info'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '3.2.1'
}

Describe 'New-WhiskeySemanticVersion.when passed 2.0' {
    Init
    GivenVersion 2.0
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '2.0.0'
}

Describe 'New-WhiskeySemanticVersion.when passed 2.01' {
    Init
    GivenVersion 2.01
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '2.1.0'
}

Describe 'New-WhiskeySemanticVersion.when passed 2.001' {
    Init
    GivenVersion 2.01
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '2.1.0'
}

Describe 'New-WhiskeySemanticVersion.when passed 3' {
    Init
    GivenVersion 3
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '3.0.0'
}

Describe 'New-WhiskeySemanticVersion.when not passed a Version' {
    Init
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf (Get-Date).ToString('yyyy.MMdd')
}

Describe 'New-WhiskeySemanticVersion.when passed ''5.6.7-rc.3''' {
    Init
    GivenVersion '5.6.7-rc.3'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '5.6.7-rc.3'
}

Describe 'New-WhiskeySemanticVersion.when passed ''1''' {
    Init
    GivenVersion '1'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '1.0.0'
}

Describe 'New-WhiskeySemanticVersion.when passed ''1.32''' {
    Init
    GivenVersion '1.32'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '1.32.0'
}

Describe 'New-WhiskeySemanticVersion.when passed ''1.32.4''' {
    Init
    GivenVersion '1.32.4'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '1.32.4'
}

Describe 'New-WhiskeySemanticVersion.when passed ''1.0130''' {
    Init
    GivenVersion '1.0130'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '1.130.0'
}

Describe 'New-WhiskeySemanticVersion.when passed ''1.5.6'' and Prerelease ''rc.4''' {
    Init
    GivenVersion '1.5.6'
    GivenPrerelease 'rc.4'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '1.5.6'
}

Describe 'New-WhiskeySemanticVersion.when passed only Prerelease ''rc.4''' {
    Init
    GivenPrerelease 'rc.4'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf (Get-Date).ToString('yyyy.MMdd')
}

Describe 'New-WhiskeySemanticVersion.when given invalid Path' {
    Init
    GivenPath 'package.json'
    WhenGettingSemanticVersion -ErrorAction SilentlyContinue
    ThenReturnedNothing
    ThenErrorMessage 'does not exist.'
}

Describe 'New-WhiskeySemanticVersion.when given Path to a package.json with missing ''version'' key' {
    Init
    GivenFile 'package.json' @'
    {
        "name": "test-app"
    }
'@
    GivenPath 'package.json'
    WhenGettingSemanticVersion -ErrorAction SilentlyContinue
    ThenReturnedNothing
    ThenErrorMessage 'Unable to get the version to build from the Node.js package.json file'
}

Describe 'New-WhiskeySemanticVersion.when given Path to a ''package.json''' {
    Init
    GivenFile 'package.json' @'
    {
        "name": "test-app",
        "version": "0.0.1"
    }
'@
    GivenPath 'package.json'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '0.0.1'
}

Describe 'New-WhiskeySemanticVersion.when given Path to a ''package.json'' and Prerelease ''rc.4''' {
    Init
    GivenFile 'package.json' @'
    {
        "name": "test-app",
        "version": "0.0.1"
    }
'@
    GivenPath 'package.json'
    GivenPrerelease 'rc.4'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '0.0.1'
}

Describe 'New-WhiskeySemanticVersion.when given Path to a PowerShell module manifest with missing ''ModuleVersion'' key' {
    Init
    GivenFile 'module.psd1' @'
    @{
        Description = 'A PowerShell module'
    }
'@
    GivenPath 'module.psd1'
    WhenGettingSemanticVersion -ErrorAction SilentlyContinue
    ThenReturnedNothing
    ThenErrorMessage 'Unable to get the version to build from the PowerShell module manifest file'
}

Describe 'New-WhiskeySemanticVersion.when given Path to a PowerShell module manifest' {
    Init
    GivenFile 'module.psd1' @'
    @{
        Description = 'A PowerShell module'
        ModuleVersion = '0.0.1'
    }
'@
    GivenPath 'module.psd1'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '0.0.1'
}

Describe 'New-WhiskeySemanticVersion.when given Path to a PowerShell module manifest and Prerelease ''rc.4''' {
    Init
    GivenFile 'module.psd1' @'
    @{
        Description = 'A PowerShell module'
        ModuleVersion = '0.0.1'
    }
'@
    GivenPath 'module.psd1'
    GivenPrerelease 'rc.4'
    WhenGettingSemanticVersion
    ThenAddedBuildMetadataToSemanticVersionOf '0.0.1'
}
