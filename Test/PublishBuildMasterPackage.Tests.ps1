
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$mockPackage = [pscustomobject]@{ }
$mockRelease = [pscustomobject]@{ }
$mockDeploy = [pscustomobject]@{ }
$packageVersion = 'version'
$defaultApiKeyID = 'BuildMaster'
$defaultApiKey = 'fubarsnafu'
$defaultAppName = 'application'
$defaultReleaseId = 483
$packageVariable = @{ 'PackageVariable' = @{ 'One' = 'Two'; 'Three' = 'Four'; } }
$context = $null
$version = $null
$releaseName = $null
$appName = $null
$taskParameter = $null
$releaseId = $null
$apiKeyID = $null
$apiKey = $null
$uri = $null
$packageName = $null
$startAtStage = $null
$skipDeploy = $null

function GivenNoApiKey
{
    param(
        $ID,
        $ApiKey
    )

    $script:apiKeyID = $null
    $script:ApiKey = $null
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
    $script:releaseId = $null
}

function GivenNoUri
{
    $script:uri = $null
}

function GivenProperty
{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $Property
    )

    $script:taskParameter = $Property
}

function GivenPackageName
{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $Name
    )
    
    $script:packageName = $Name
}

function GivenStartAtStage
{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $Stage
    )
    
    $script:startAtStage = $Stage
}

function GivenSkipDeploy
{
    param(
    )
    
    $script:skipDeploy = 'true'
}

function Init
{
    $script:version = '9.8.3-rc.1+build.deadbee'
    $script:appName = $defaultAppName
    $script:releaseName = 'release'
    $script:uri = 'https://buildmaster.example.com'
    $script:apiKeyID = $defaultApiKeyID
    $script:apiKey = $defaultApiKey
    $script:releaseId = $defaultReleaseId
    $script:packageVariable = @{ 'PackageVariable' = @{ 'One' = 'Two'; 'Three' = 'Four'; } }
    $script:taskParameter = @{ }
    $script:packageName = $null
    $script:startAtStage = $null
    $script:skipDeploy = 'false'
    $script:testRoot = New-WhiskeyTestRoot
}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function WhenCreatingPackage
{
    [CmdletBinding()]
    param(
    )

    if( -not $taskParameter )
    {
        $taskParameter = @{ }
    }

    if( $appName )
    {
        $taskParameter['ApplicationName'] = $appName
    }

    if( $releaseName )
    {
        $taskParameter['ReleaseName'] = $releaseName
    }
    
    $script:context = New-WhiskeyTestContext -ForVersion $version `
                                             -ForTaskName 'PublishBuildMasterPackage' `
                                             -ForBuildServer `
                                             -ForBuildRoot $testRoot `
                                             -IncludePSModule 'BuildMasterAutomation'

    if( -not (Get-Module 'BuildMasterAutomation') )
    {
        Import-WhiskeyTestModule -Name 'BuildMasterAutomation'
    }

    if( $apiKeyID )
    {
        $taskParameter['ApiKeyID'] = $apiKeyID
        Add-WhiskeyApiKey -Context $context -ID $apiKeyID -Value $apiKey
    }
    
    if( $uri )
    {
        $taskParameter['Uri'] = $uri
    }
    
    if( $packageName )
    {
        $taskParameter['PackageName'] = $packageName
    }

    if( $startAtStage )
    {
        $taskParameter['StartAtStage'] = $startAtStage
    }

    if( $skipDeploy )
    {
        $taskParameter['SkipDeploy'] = $skipDeploy
    }
    
    $package = $mockPackage
    $deploy = $mockDeploy
    $release = [pscustomobject]@{ Application = $appName; Name = $releaseName; id = $releaseId  }

    if( $releaseId )
    {
        Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { return $release  }.GetNewClosure()
    }
    else
    {
        Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { }
    }
    Mock -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Release = $Release; PackageNumber = $PackageNumber; Variable = $Variable } }
    Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Package = $package } }

    $script:threwException = $false
    try
    {
        $Global:Error.Clear()
        Invoke-WhiskeyTask -TaskContext $context -Name 'PublishBuildMasterPackage' -Parameter $taskParameter
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

    Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $PackageNumber -eq $Name }
    Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $InRelease }
    Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $Release.id -eq $releaseId }
    Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Application -eq $ForApplication }
    Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
    Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
    Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
    Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
    
    foreach( $variableName in $WithVariables.Keys )
    {
        $variableValue = $WithVariables[$variableName]
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { 
            #$DebugPreference = 'Continue'
            Write-Debug ('Expected  {0}' -f $variableValue)
            Write-Debug ('Actual    {0}' -f $Variable[$variableName])
            $Variable.ContainsKey($variableName) -and $Variable[$variableName] -eq $variableValue
        }
    }

    Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
    Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $ErrorActionPreference -eq 'stop' }
}

function ThenPackageDeployed
{
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $AtUri,

        [Parameter(Mandatory=$true)]
        [string]
        $UsingApiKey,
        
        [string]
        $AtStage
    )
    
    if( $AtStage )
    {    
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Stage -eq $AtStage }
    }
    else
    {
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Stage -eq '' }
    }

    Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
    Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
    Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $ErrorActionPreference -eq 'stop' }
}

function ThenPackageNotDeployed
{
    param(
    )
    
    Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -Times 0
}

function ThenPackageNotCreated
{
    [CmdletBinding()]
    param(
    )

    process
    {
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -Times 0

        ThenPackageNotDeployed
    }
}

function ThenTaskFails
{
    param(
        $Pattern
    )

    $threwException | Should -BeTrue
    $Global:Error | Should -Match $Pattern
}

Describe 'PublishBuildMasterPackage.when called' {
    AfterEach { Reset }
    It 'should publish package' {
        Init
        GivenProperty $packageVariable
        WhenCreatingPackage
        ThenCreatedPackage '9.8.3' -InRelease 'release' -ForApplication 'application' -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenPackageDeployed -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu'
    }
}

Describe 'PublishBuildMasterPackage.when creating package with defined name' {
    AfterEach { Reset }
    It 'should publish that package' {
        $packageNameOverride = 'PackageABCD'
        Init
        GivenPackageName $packageNameOverride
        GivenProperty $packageVariable
        WhenCreatingPackage
        ThenCreatedPackage $packageNameOverride -InRelease 'release' -ForApplication 'application' -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenPackageDeployed -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu'
    }
}

Describe 'PublishBuildMasterPackage.when deploying release package to specific stage' {
    AfterEach { Reset }
    It 'should deploy to that stage' {
        $releaseStage = 'Test'
        Init
        GivenStartAtStage $releaseStage
        GivenProperty $packageVariable
        WhenCreatingPackage
        ThenCreatedPackage '9.8.3' -InRelease 'release' -ForApplication 'application' -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenPackageDeployed -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -AtStage $releaseStage
    }
}

Describe 'PublishBuildMasterPackage.when creating package without starting deployment' {
    AfterEach { Reset }
    It 'should not start the deployment' {
        Init
        GivenSkipDeploy
        GivenProperty $packageVariable
        WhenCreatingPackage
        ThenCreatedPackage '9.8.3' -InRelease 'release' -ForApplication 'application' -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenPackageNotDeployed
    }
}

Describe 'PublishBuildMasterPackage.when no application or release in BuildMaster' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenNoRelease 'release' -ForApplication 'application'
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails 'unable\ to\ create\ and\ deploy\ a\ release\ package'
    }
}

Describe ('PublishBuildMasterPackage.when ApplicationName property is missing') {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenNoApplicationName
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails ('\bApplicationName\b.*\bmandatory\b')
    }
}

Describe ('PublishBuildMasterPackage.when ReleaseName property is missing') {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenNoReleaseName
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails ('\bReleaseName\b.*\bmandatory\b')
    }
}

Describe ('PublishBuildMasterPackage.when Uri property is missing') {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenNoUri
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails ('\bUri\b.*\bmandatory\b')
    }
}

Describe ('PublishBuildMasterPackage.when ApiKeyID property is missing') {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenNoApiKey
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails ('\bApiKeyID\b.*\bmandatory\b')
    }
}
