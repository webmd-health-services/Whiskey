
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$mockPackage = [pscustomobject]@{ }
$mockRelease = [pscustomobject]@{ }
$mockDeploy = [pscustomobject]@{ }
$packageVersion = 'version'
$context = $null
$version = $null
$releaseName = $null
$appName = $null
$taskParameter = $null
$releaseId = 483
$apiKeyID = $null
$apiKey = $null

function GivenApiKey
{
    param(
        $ID,
        $ApiKey
    )

    $script:apiKeyID = $ID
    $script:ApiKey = $ApiKey
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
    $script:releaseName = $Name

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
    $releaseId = $script:releaseId
    Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Application = $Application; Name = $Name; id = $releaseId  } }.GetNewClosure()
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
    )

    $taskParameter['ApplicationName'] = $appName

    $script:context = New-WhiskeyTestContext -ForVersion $version -ForReleaseName $releaseName -ForTaskName 'PublishBuildMasterPackage' -ForBuildServer

    if( $apiKeyID )
    {
        Add-WhiskeyApiKey -Context $context -ID $apiKeyID -Value $apiKey
    }

    $package = $mockPackage
    $deploy = $mockDeploy
    Mock -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Release = $Release; PackageNumber = $PackageNumber; Variable = $Variable } }
    Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Package = $package } }

    $script:threwException = $false
    try
    {
        $Global:Error.Clear()
        Publish-WhiskeyBuildMasterPackage -TaskContext $context -TaskParameter $taskParameter
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
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $PackageNumber -eq $Name }
    }

    It ('should create package in release ''{0}''' -f $InRelease) {
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $InRelease }
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $Release.id -eq $releaseId }
    }

    It ('should create package in application ''{0}''' -f $ForApplication) {
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Application -eq $ForApplication }
    }

    It 'should publish package' {
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' 
    }

    It ('should create package at ''{0}''' -f $AtUri) {
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
    }

    It ('should create package with API key ''{0}''' -f $UsingApiKey) {
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
    }

    foreach( $variableName in $WithVariables.Keys )
    {
        $variableValue = $WithVariables[$variableName]
        It ('should create package variable ''{0}''' -f $variableName) {
            Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { 
                #$DebugPreference = 'Continue'
                Write-Debug ('Expected  {0}' -f $variableValue)
                Write-Debug ('Actual    {0}' -f $Variable[$variableName])
                $Variable.ContainsKey($variableName) -and $Variable[$variableName] -eq $variableValue
            }
        }
    }

    It ('should fail the build if BuildMaster calls fail') {
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $ErrorActionPreference -eq 'stop' }
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $ErrorActionPreference -eq 'stop' }
        
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
            Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -Times 0
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

Describe ('Publish-WhiskeyBuildMasterPackage.when customizing ReleaseName property') {
    GivenApiKey 'BuildMaster' 'fubarsnafu'
    GivenVersion '9.8.3-rc.1+build.deadbee'
    GivenApplicationName 'fubar'
    GivenRelease 'snafu' -ForApplication 'fubar'
    GivenProperty @{ 'ReleaseName' = 'hello' ; Uri = 'https://buildmaster.example.com'; 'ApiKeyID' = 'BuildMaster' }
    WhenCreatingPackage 
    ThenCreatedPackage '9.8.3' -InRelease 'hello' -ForApplication 'fubar' -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ }
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
