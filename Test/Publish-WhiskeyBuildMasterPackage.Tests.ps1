
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$mockPackage = [pscustomobject]@{ }
$mockRelease = [pscustomobject]@{ }
$mockDeploy = [pscustomobject]@{ }
$packageVersion = 'version'
$context = $null
$version = $null
$releaseName = $null
$appName = $null
$apiKeys = @{ }
$taskParameter = $null

function New-Context
{
}

function GivenApiKey
{
    param(
        $ID,
        $ApiKey
    )

    $script:apiKeys = @{ $ID = $ApiKey }
}

function GivenApplicationName
{
    param(
        $Name
    )

    $script:appName = $Name
}

function GivenNoApplicationName
{
    $script:appName = $null
}

function GivenNoReleaseName
{
    $script:releaseName = $null
}

function GivenNoRelease
{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]
        $Name,
        [Parameter(Mandatory=$true)]
        [string]
        $ForApplication
    )

    $script:appName = $ForApplication
    $script:releaseName = $releaseName

    Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { }
}

function GivenProperty
{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $Property
    )

    $script:taskParameter = $Property
}

function GivenRelease
{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]
        $Name,
        [Parameter(Mandatory=$true)]
        [string]
        $ForApplication
    )

    $script:appName = $ForApplication
    $script:releaseName = $Name
    Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Application = $Application; Name = $Name } }
}

function GivenVersion
{
    param(
        $Version
    )

    $script:version = $Version
}

function WhenCreatingPackage
{
    [CmdletBinding()]
    param(
        [Switch]
        $InCleanMode
    )

    $taskParameter['ApplicationName'] = $appName
    $taskParameter['ReleaseName'] = $releaseName

    $context = [pscustomobject]@{
                                    ApiKeys = $apiKeys;
                                    Version = [pscustomobject]@{
                                                                    'SemVer2' = [SemVersion.SemanticVersion]$version
                                                                }
                                    ConfigurationPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml';
                                    TaskIndex = 0;
                                    TaskName = 'PublishBuildMasterPackage';
                                    }

    $package = $mockPackage
    $deploy = $mockDeploy
    Mock -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Release = $Release; PackageNumber = $PackageNumber; Variable = $Variable } }
    Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Package = $package } }

    $script:threwException = $false
    try
    {
        $Global:Error.Clear()
        $cleanParam = @{ }
        if( $InCleanMode )
        {
            $cleanParam['Clean'] = $true
        }
        Publish-WhiskeyBuildMasterPackage -TaskContext $context -TaskParameter $taskParameter @cleanParam
    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }
}

function ThenCreatedPackage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string]
        $Name,

        [Parameter(Mandatory=$true)]
        [string]
        $InRelease,

        [Parameter(Mandatory=$true)]
        [string]
        $ForApplication,

        [Parameter(Mandatory=$true)]
        [string]
        $AtUri,

        [Parameter(Mandatory=$true)]
        [string]
        $UsingApiKey,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $WithVariables
    )

    It ('should create package ''{0}''' -f $Name) {
        Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $PackageNumber -eq $Name }
    }

    It ('should create package in release ''{0}''' -f $InRelease) {
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $InRelease }
        Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Release -eq $InRelease }
    }

    It ('should create package in application ''{0}''' -f $ForApplication) {
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Application -eq $ForApplication }
    }

    It 'should publish package' {
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' 
    }

    It ('should create package at ''{0}''' -f $AtUri) {
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
        Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
    }

    It ('should create package with API key ''{0}''' -f $UsingApiKey) {
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
        Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
    }

    foreach( $variableName in $WithVariables.Keys )
    {
        $variableValue = $WithVariables[$variableName]
        It ('should create package variable ''{0}''' -f $variableName) {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { 
                #$DebugPreference = 'Continue'
                Write-Debug ('Expected  {0}' -f $variableValue)
                Write-Debug ('Actual    {0}' -f $Variable[$variableName])
                $Variable.ContainsKey($variableName) -and $Variable[$variableName] -eq $variableValue
            }
        }
    }
}

function ThenPackageNotCreated
{
    [CmdletBinding()]
    param(
    )

    process
    {
        It 'should not create release package' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -Times 0
        }
        It 'should not start deploy' {
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -Times 0
        }
    }
}

function ThenTaskFails
{
    param(
        $Pattern
    )

    It 'should throw an exception' {
        $threwException | Should -Be $true
    }

    It 'should write an errors' {
        $Global:Error | Should -Match $Pattern
    }
}

Describe 'Publish-WhiskeyBuildMasterPackage.when called' {
    GivenApiKey 'BuildMaster' 'fubarsnafu'
    GivenVersion '9.8.3-rc.1+build.deadbee'
    GivenRelease 'release' -ForApplication 'application'
    GivenProperty @{
                        'Uri' = 'https://buildmaster.example.com';
                        'ApiKeyID' = 'BuildMaster';
                        'PackageVariables' = @{
                                                    'One' = 'Two';
                                                    'Three' = 'Four';
                                              }
                   }
    WhenCreatingPackage
    ThenCreatedPackage '9.8.3' -InRelease 'release' -ForApplication 'application' -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
}

Describe 'Publish-WhiskeyBuildMasterPackage.when no application or release in BuildMaster' {
    GivenNoRelease 'release' -ForApplication 'application'
    WhenCreatingPackage -ErrorAction SilentlyContinue
    ThenPackageNotCreated
    ThenTaskFails 'unable\ to\ create\ and\ deploy\ a\ release\ package'
}

Describe ('Publish-WhiskeyBuildMasterPackage.when ApplicationName property is missing') {
    GivenNoApplicationName
    WhenCreatingPackage -ErrorAction SilentlyContinue
    ThenTaskFails ('\bApplicationName\b.*\bmandatory\b')
}

Describe ('Publish-WhiskeyBuildMasterPackage.when ReleaseName property is missing') {
    GivenApplicationName 'fubar'
    GivenNoReleaseName
    WhenCreatingPackage -ErrorAction SilentlyContinue
    ThenTaskFails ('\bReleaseName\b.*\bmandatory\b')
}

Describe ('Publish-WhiskeyBuildMasterPackage.when Uri property is missing') {
    GivenRelease 'release' -ForApplication 'fubar'
    GivenProperty @{ }
    WhenCreatingPackage -ErrorAction SilentlyContinue
    ThenTaskFails ('\bUri\b.*\bmandatory\b')
}

Describe ('Publish-WhiskeyBuildMasterPackage.when ApiKeyID property is missing') {
    GivenRelease 'release' -ForApplication 'fubar'
    GivenProperty @{ 'Uri' = 'https://buildmaster.example.com' }
    WhenCreatingPackage -ErrorAction SilentlyContinue
    ThenTaskFails ('\bApiKeyID\b.*\bmandatory\b')
}

Describe ('Publish-WhiskeyBuildMasterPackage.when run in clean mode') {
    GivenNoApplicationName
    GivenNoReleaseName
    GivenProperty @{ }
    WhenCreatingPackage -InCleanMode
    ThenPackageNotCreated
    It 'should not throw an exception' {
        $threwException | Should -Be $false
    }
}