Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$apikey = $null
$apikeyID = $null
$repositoryName = $null
$repositoryUri = $null
$prerelease = $null
$context = $null
$credentials = @{ }
$failed = $false
$publishError = $null
$registerError = $null

function GivenCredential
{
    param(
        [Parameter(Mandatory)]
        [pscredential]$Credential,

        [Parameter(Mandatory)]
        [String]$WithID
    )

    $credentials[$WithID] = $Credential
}

function GivenNoApiKey
{
    $script:apikey = $null
    $script:apikeyID = $null
}

function GivenPrerelease
{
    param(
        $Prerelease
    )

    $script:prerelease = $Prerelease
}

function GivenPublishingFails
{
    param(
        [Parameter(Mandatory)]
        [String]$WithError
    )

    $script:publishError = $WithError
}

function GivenRegisteringFails
{
    param(
        [Parameter(Mandatory)]
        [String]$WithError
    )

    $script:registerError = $WithError
}

function GivenRepository
{
    param(
        $Named,
        $Uri
    )

    $script:repositoryName = $Named
    $script:repositoryUri = $Uri
}

function Initialize-Test
{
    param(
    )

    $script:apikey = 'fubar:snauf'
    $script:apikeyID = 'PowerShellExampleCom'
    $script:repositoryName = $null
    $script:repositoryUri = $null
    $script:prerelease = $null
    $script:context = $null
    $script:credentials = @{ }
    $script:failed = $false
    $script:publishError = $null
    $script:registerError = $null

    $script:testRoot = New-WhiskeyTestRoot
}

function Invoke-Publish
{
    [CmdletBinding()]
    param(
        [switch]$withoutRegisteredRepo,

        [String]$ForRepositoryNamed,

        [String]$RepoAtUri,

        [String]$ForManifestPath,

        [switch]$WithNoRepositoryName,

        [switch]$withNoProgetURI,

        [switch]$WithInvalidPath,

        [switch]$WithNonExistentPath,

        [switch]$WithoutPathParameter,

        [String]$WithCredentialID
    )
    
    $version = '1.2.3'
    if( $prerelease )
    {
        $version = '1.2.3-{0}' -f $prerelease
    }

    $script:context = New-WhiskeyTestContext -ForBuildServer `
                                             -ForVersion $version `
                                             -ForBuildRoot $testRoot `
                                             -IncludePSModule @( 'PackageManagement', 'PowerShellGet' )
    
    $TaskParameter = @{ }

    if( $ForRepositoryNamed )
    {
        $TaskParameter['RepositoryName'] = $ForRepositoryNamed;
    }

    if( $WithInvalidPath )
    {
        $TaskParameter.Add( 'Path', 'MyModule.ps1' )
        New-Item -Path $testRoot -ItemType 'file' -Name 'MyModule.ps1'
    }
    elseif( $WithNonExistentPath )
    {
        $TaskParameter.Add( 'Path', 'MyModule.ps1' )
    }
    elseif( -not $WithoutPathParameter )
    {
        $TaskParameter.Add( 'Path', 'MyModule' )
        New-Item -Path $testRoot -ItemType 'directory' -Name 'MyModule' 
        $module = Join-Path -Path $testRoot -ChildPath 'MyModule'
        if( -not $ForManifestPath )
        {            
            New-Item -Path $module -ItemType 'file' -Name 'MyModule.psd1' -Value @"
@{
    # Version number of this module.
    ModuleVersion = '0.2.0'

    PrivateData = @{
        PSData = @{
            Prerelease = '';
        }
    }
    
}
"@
        }
        else
        {
            $TaskParameter.Add( 'ModuleManifestPath', $ForManifestPath )
        }
    }

    Import-WhiskeyTestModule -Name 'PackageManagement','PowerShellGet'
    Mock -CommandName 'Get-PackageProvider' -ModuleName 'Whiskey'

    $repoName = $script:repositoryName
    $repoUri = $script:repositoryUri

    Mock -CommandName 'Get-PSRepository' -ModuleName 'Whiskey' -MockWith {
        return [pscustomobject]@{
            'Name' = $repoName;
            'SourceLocation' = $repoUri;
        }
    }.GetNewClosure()

    Add-Type -AssemblyName System.Net.Http

    $mock = { }
    if( $publishError )
    {
        $message = $publishError
        $mock = { 
                    [CmdletBinding()]
                    param(
                        $NuGetApiKey,
                        $Repository,
                        $Path,
                        [switch]$Force
                    ) 
                    Write-Error -Message $message
                }.GetNewClosure()
    }
    Mock -CommandName 'Publish-Module' -ModuleName 'Whiskey' -MockWith $mock

    $mock = { }
    if( $registerError )
    {
        $message = $registerError
        $mock = { 
                    [CmdletBinding()]
                    param(
                        $InstallationPolicy,
                        $SourceLocation,
                        $PackageManagementProvider,
                        $Name,
                        $PublishLocation
                    ) 
                    Write-Error -Message $message
                }.GetNewClosure()
    }
    Mock -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -MockWith $mock
    
    $Global:Error.Clear()
    $script:failed = $False

    if( $RepoAtUri )
    {
        $TaskParameter['RepositoryUri'] = $RepoAtUri
    }

    if( $WithCredentialID )
    {
        $TaskParameter['CredentialID'] = $WithCredentialID
    }

    if( $apikeyID )
    {
        $TaskParameter['ApiKeyID'] = $apikeyID
        Add-WhiskeyApiKey -Context $context -ID $apikeyID -Value $apikey
    }

    foreach( $key in $credentials.Keys )
    {
        Add-WhiskeyCredential -Context $context -ID $key -Credential $credentials[$key]
    }
    
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Parameter $TaskParameter -Name 'PublishPowerShellModule'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function Reset
{
    Reset-WhiskeyTestPSModule
}

function ThenFailed
{
    param(
        [Parameter(Mandatory)]
        $WithError
    )

    $script:failed | Should -BeTrue
    Get-Error | Should -Match $WithError
}

function ThenModuleNotPublished
{    
    Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 0
}

function ThenRepositoryChecked
{
    Assert-MockCalled -CommandName 'Get-PSRepository' -ModuleName 'Whiskey' -Times 1
}

function ThenRepositoryNotChecked
{
    Assert-MockCalled -CommandName 'Get-PSRepository' -ModuleName 'Whiskey' -Times 0
}

function ThenRepositoryNotRegistered
{
    Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 0
}

function ThenRepositoryRegistered
{
    param(
        [Parameter(Mandatory)]
        [String]$Named,

        [Parameter(Mandatory)]
        [String]$AtUri,

        [pscredential]$WithCredential
    )

    Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
        #$DebugPreference = 'Continue'
        Write-WhiskeyDebug -Message ('Repository Name                 expected {0}' -f $Named)
        Write-WhiskeyDebug -Message ('                                actual   {0}' -f $Name)
        $Name -eq $Named
    }
    Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
        #$DebugPreference = 'Continue'
        Write-WhiskeyDebug -Message ('Source Location                 expected {0}' -f $AtUri)
        Write-WhiskeyDebug -Message ('                                actual   {0}' -f $SourceLocation)
        $AtUri -eq $SourceLocation
    }
    Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
        #$DebugPreference = 'Continue'
        Write-WhiskeyDebug -Message ('Publish Location                expected {0}' -f $AtUri)
        Write-WhiskeyDebug -Message ('                                actual   {0}' -f $PublishLocation)
        $AtUri -eq $PublishLocation
    }
    Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $InstallationPolicy -eq 'Trusted' }
    Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $PackageManagementPRovider -eq 'NuGet' }

    if( $WithCredential )
    {
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Credential.UserName -eq $WithCredential.UserName }
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Credential.GetNetworkCredential().Password -eq $WithCredential.GetNetworkCredential().Password }
    }
}

function ThenModulePublished
{
    param(
        [Parameter(Mandatory)]
        [String]$ToRepositoryNamed,

        [String]$ExpectedPathName = (Join-Path -Path '.' -ChildPath 'MyModule'),

        [switch]$WithNoRepositoryName
    )
    
    Assert-MockCalled -CommandName 'Get-PackageProvider' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq 'NuGet' }
    Assert-MockCalled -CommandName 'Get-PackageProvider' -ModuleName 'Whiskey' -ParameterFilter { $ForceBootstrap }
    $expectedApiKey = $apikey
    Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
        #$DebugPreference = 'Continue'
        Write-WhiskeyDebug -Message ('Path Name                       expected {0}' -f $ExpectedPathName)
        Write-WhiskeyDebug -Message ('                                actual   {0}' -f $Path)
        
        $Path -eq $ExpectedPathName
    }
    Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
        #$DebugPreference = 'Continue'
        Write-WhiskeyDebug -Message ('Repository Name                 expected {0}' -f $ToRepositoryNamed)
        Write-WhiskeyDebug -Message ('                                actual   {0}' -f $Repository)
        $Repository -eq $ToRepositoryNamed
    }
    Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
        #$DebugPreference = 'Continue'
        Write-WhiskeyDebug -Message ('ApiKey                          expected {0}' -f $expectedApiKey)
        Write-WhiskeyDebug -Message ('                                actual   {0}' -f $NuGetApiKey)
        $NuGetApiKey -eq $expectedApiKey
    }
    Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Force }
}

function ThenManifest
{
    param(
        [String]$ManifestPath = (Join-Path -Path $testRoot -ChildPath 'MyModule\MyModule.psd1'),

        [String]$AtVersion,

        [String]$HasPrerelease
    )

    if( -not $AtVersion )
    {
        $AtVersion = '{0}.{1}.{2}' -f $context.Version.SemVer2.Major, $context.Version.SemVer2.Minor, $context.Version.SemVer2.Patch
    }

    $manifest = Test-ModuleManifest -Path $ManifestPath

    $manifest.Version | Should -Be $AtVersion
    if( $HasPrerelease )
    {
        $manifest.PrivateData.PSData.Prerelease | Should -Be $HasPrerelease
    }
    else
    {
        $manifest.PrivateData.PSData.Prerelease | Should -BeNullOrEmpty
    }
}

function ThenSucceeded
{
    $script:failed | Should -BeFalse
    Get-Error | Should -BeNullOrEmpty
}

function Get-Error
{
    [CmdletBinding()]
    param(
    )

    $Global:Error |
        Where-Object {
            if( -not $_.TargetObject -or -not $_.ScriptStackTrace )
            {
                return $true
            }

            # These errors are internal and can be ignored.
            $fromGetPackageSource = $_.TargetObject.ToString() -eq 'Microsoft.PowerShell.PackageManagement.Cmdlets.GetPackageSource'
            $fromResolvingDynamicParams = $_.ScriptStackTrace -match '\bGet-DynamicParameters\b'
            return -not ( $fromGetPackageSource -and $fromResolvingDynamicParams )
        }
}

Describe 'PublishPowerShellModule.when publishing new module' {
    AfterEach { Reset }
    It 'should publish the module' {
        Initialize-Test
        GivenRepository 'FubarSnafu'
        Invoke-Publish -ForRepositoryNamed 'FubarSnafu'
        ThenSucceeded
        ThenRepositoryChecked
        ThenRepositoryNotRegistered
        ThenModulePublished -ToRepositoryNamed 'FubarSnafu'
    }
}

Describe 'PublishPowerShellModule.when publishing prerelease module' {
    AfterEach { Reset }
    It 'should succeed' {
        Initialize-Test
        GivenRepository 'SomeRepo'
        GivenPrerelease 'beta1'
        Invoke-Publish -ForRepositoryNamed 'SomeRepo'
        ThenSucceeded
        ThenRepositoryChecked
        ThenRepositoryNotRegistered
        ThenModulePublished -ToRepositoryNamed 'SomeRepo'
        ThenManifest -HasPrerelease 'beta1'
    }
}

Describe 'PublishPowerShellModule.when publishing with no repository name' {
    AfterEach { Reset }
    It 'should fail' {
        Initialize-Test
        Invoke-Publish -ErrorAction SilentlyContinue
        ThenFailed -WithError 'Property\ "RepositoryName"\ is mandatory'
        ThenRepositoryNotChecked
        ThenRepositoryNotRegistered
        ThenModuleNotPublished
    }
}

Describe 'PublishPowerShellModule.when publishing fails' {
    AfterEach { Reset }
    It 'should fail' {
        Initialize-Test
        GivenRepository 'FubarSnafu'
        GivenPublishingFails -WithError 'something went wrong!'
        Invoke-Publish -ForRepositoryNamed 'FubarSnafu' -ErrorAction SilentlyContinue
        ThenFailed -WithError 'something\ went\ wrong\!'
    }
}

Describe 'PublishPowerShellModule.when publishing to a new repository' {
    AfterEach { Reset }
    It 'should succeed' {
        Initialize-Test
        Invoke-Publish -ForRepositoryName 'ANewRepo' -RepoAtUri 'https://example.com' 
        ThenRepositoryChecked
        ThenRepositoryRegistered 'ANewRepo' -AtUri 'https://example.com/'
        ThenModulePublished -ToRepositoryNamed 'ANewRepo'
        ThenSucceeded
    }
}

Describe 'PublishPowerShellModule.when publishing to a new repository that requires a credential' {
    AfterEach { Reset }
    It 'should succeed' {
        Initialize-Test
        $cred = New-Object 'pscredential' ('fubar',(ConvertTo-SecureString -String 'snafu' -AsPlainText -Force))
        GivenCredential $cred -WithID 'somecred'
        Invoke-Publish -ForRepositoryName 'ANewRepo' -RepoAtUri 'https://example.com' -WithCredentialID 'somecred'
        ThenSucceeded
        ThenRepositoryChecked
        ThenRepositoryRegistered 'ANewRepo' -AtUri 'https://example.com/' -WithCredential $cred
        ThenModulePublished -ToRepositoryNamed 'ANewRepo'
    }
}

Describe 'PublishPowerShellModule.when publishing to a new repository but its URI is not given' {
    AfterEach { Reset }
    It 'should fail' {
        Initialize-Test 
        Invoke-Publish -ForRepositoryNamed 'Fubar' -ErrorAction SilentlyContinue
        ThenFailed -WithError 'Property\ "RepositoryUri"\ is\ mandatory'
        ThenRepositoryChecked
        ThenRepositoryNotRegistered
        ThenModuleNotPublished
    }
}

Describe 'PublishPowerShellModule.when registering a repository fails' {
    AfterEach { Reset }
    It 'should fail' {
        Initialize-Test
        GivenRegisteringFails -WithError 'something went wrong!'
        Invoke-Publish -ForRepositoryNamed 'FubarSnafu' -RepoAtUri 'https://example.com' -ErrorAction SilentlyContinue
        ThenFailed -WithError 'something\ went\ wrong\!'
    }
}

Describe 'PublishPowerShellModule.when no API key' {
    AfterEach { Reset }
    It 'should fail' {
        Initialize-Test
        GivenNoApiKey
        GivenRepository 'Fubar'
        Invoke-Publish -ForRepositoryNamed 'Fubar'  -ErrorAction SilentlyContinue
        ThenFailed -WithError 'Property\ "ApiKeyID"\ is\ mandatory'
        ThenRepositoryNotChecked
        ThenRepositoryNotRegistered
        ThenModuleNotPublished
    }
}

Describe 'PublishPowerShellModule.when path parameter is not included' {
    AfterEach { Reset }
    It 'should fail' {
        Initialize-Test
        GivenRepository 'Fubar'
        Invoke-Publish -ForRepositoryNamed 'Fubar' -WithoutPathParameter -ErrorAction SilentlyContinue
        ThenFailed -WithError '"Path\b.*\bis mandatory'
        ThenRepositoryNotChecked
        ThenRepositoryNotRegistered
        ThenModuleNotPublished
    }
}

Describe 'PublishPowerShellModule.when non-existent path parameter' {
    AfterEach { Reset }
    It 'should fail' {
        Initialize-Test
        GivenRepository 'Fubar'
        Invoke-Publish -ForRepositoryNamed 'Fubar' -WithNonExistentPath -ErrorAction SilentlyContinue
        ThenFailed -WithError 'does\ not\ exist'
        ThenModuleNotPublished
    }
}

Describe 'PublishPowerShellModule.when non-directory path parameter' {
    AfterEach { Reset }
    It 'should fail' {
        Initialize-Test
        GivenRepository 'Fubar'
        Invoke-Publish -ForRepositoryNamed 'Fubar' -WithInvalidPath  -ErrorAction SilentlyContinue
        ThenFailed -WithError 'should resolve to a directory'
        ThenModuleNotPublished
    }
}

Describe 'PublishPowerShellModule.when invalid manifest' {
    AfterEach { Reset }
    It 'should fail' {
        Initialize-Test
        GivenRepository 'Fubar'
        Invoke-Publish -ForRepositoryNamed 'Fubar' -withoutRegisteredRepo -ForManifestPath 'fubar' -ErrorAction SilentlyContinue
        ThenFailed -WithError 'path\ "fubar"\ either\ does\ not\ exist'
        ThenModuleNotPublished
    }
}

Describe 'PublishPowerShellModule.when registering an existing PSRepository under a different name' {
    AfterEach { Reset }
    It 'should use already registered PSRepository' {
        Initialize-Test
        GivenRepository -Named 'FirstRepo' -Uri 'https://example.com'
        Invoke-Publish -ForRepositoryNamed 'ImposterRepo' -RepoAtUri 'https://example.com'
        ThenSucceeded
        ThenRepositoryNotRegistered
        ThenRepositoryChecked
        ThenModulePublished -ToRepositoryNamed 'FirstRepo'
    }
}

Describe 'PublishPowerShellModule.when re-registering an existing PSRepository under the same name' {
    AfterEach { Reset }
    It 'should succeed' {
        Initialize-Test
        GivenRepository -Named 'FirstRepo' -Uri 'https://example.com'
        Invoke-Publish -ForRepositoryNamed 'FirstRepo' -RepoAtUri 'https://example.com'
        ThenSucceeded
        ThenRepositoryChecked
        ThenRepositoryNotRegistered
        ThenModulePublished -ToRepositoryNamed 'FirstRepo'
    }
}
