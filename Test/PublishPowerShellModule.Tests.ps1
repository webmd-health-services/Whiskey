Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$apikey = $null
$apikeyID = $null
$repositoryName = $null
$prerelease = $null
$context = $null
$credentials = @{ }

function GivenCredential
{
    param(
        [Parameter(Mandatory)]
        [pscredential]
        $Credential,

        [Parameter(Mandatory)]
        [string]
        $WithID
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

function GivenRepository
{
    param(
        $Named
    )

    $script:repositoryName = $Named
}

function Initialize-Test
{
    param(
    )

    $script:apikey = 'fubar:snauf'
    $script:apikeyID = 'PowerShellExampleCom'
    $script:repositoryName = $null
    $script:prerelease = $null
    $script:context = $null
    $script:credentials = @{ }
}

function Invoke-Publish
{
    [CmdletBinding()]
    param(
        [Switch]
        $withoutRegisteredRepo,

        [String]
        $ForRepositoryNamed,

        [string]
        $RepoAtUri,

        [String]
        $ForManifestPath,

        [Switch]
        $WithNoRepositoryName,

        [String]
        $ThatFailsWith,

        [Switch]
        $withNoProgetURI,

        [Switch]
        $WithInvalidPath,

        [Switch]
        $WithNonExistentPath,

        [Switch]
        $WithoutPathParameter,

        [string]
        $WithCredentialID
    )
    
    $version = '1.2.3'
    if( $prerelease )
    {
        $version = '1.2.3-{0}' -f $prerelease
    }

    $script:context = New-WhiskeyTestContext -ForBuildServer -ForVersion $version
    
    $TaskParameter = @{ }

    if( $ForRepositoryNamed )
    {
        $TaskParameter['RepositoryName'] = $ForRepositoryNamed;
    }

    if( $WithInvalidPath )
    {
        $TaskParameter.Add( 'Path', 'MyModule.ps1' )
        New-Item -Path $TestDrive.FullName -ItemType 'file' -Name 'MyModule.ps1'
    }
    elseif( $WithNonExistentPath )
    {
        $TaskParameter.Add( 'Path', 'MyModule.ps1' )
    }
    elseif( -not $WithoutPathParameter )
    {
        $TaskParameter.Add( 'Path', 'MyModule' )
        New-Item -Path $TestDrive.FullName -ItemType 'directory' -Name 'MyModule' 
        $module = Join-Path -Path $TestDrive.FullName -ChildPath 'MyModule'
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

    Mock -CommandName 'Get-PackageProvider' -ModuleName 'Whiskey'

    $repoName = $repositoryName
    Mock -CommandName 'Get-PSRepository' -ModuleName 'Whiskey' -MockWith { 
        param(
            $Name
        )
        #$DebugPreference = 'Continue'
        Write-Debug -Message ('Name  expected  {0}' -f $repoName)
        Write-Debug -Message ('      actual    {0}' -f $Name)
        return ($Name -eq $repoName) 
    }.GetNewClosure()

    Add-Type -AssemblyName System.Net.Http
    Mock -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' 
    Mock -CommandName 'Publish-Module' -ModuleName 'Whiskey'
    Mock -CommandName 'Get-PackageSource' -ModuleName 'PowerShellGet'  # Called by a dynamic parameter set on Register-PSRepository.
    
    $Global:Error.Clear()
    $failed = $False

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
        $failed = $True
        Write-Error -ErrorRecord $_
    }

    if( $ThatFailsWith )
    {
        It 'should throw an exception' {
            $failed | Should Be $True
        }
        It 'should exit with error' {
            $Global:Error | Should Match $ThatFailsWith
        }
    }
    else
    {
        It 'should not throw an exception'{
            $failed | Should Be $False
        }
        It 'should exit without error'{
            $Global:Error | Should BeNullOrEmpty
        }
    }
}

function ThenModuleNotPublished
{    
    It 'should not attempt to publish the module'{
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 0
    }
}

function Assert-ModuleNotPublished
{    
    It 'should not attempt to register the module'{
        Assert-MockCalled -CommandName 'Get-PSRepository' -ModuleName 'Whiskey' -Times 0
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 0
    }    
    It 'should not attempt to publish the module'{
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 0
    }
}

function ThenRepositoryChecked
{
    param(
        [Parameter(Mandatory)]
        [string]
        $Named
    )

    It ('should check that repository exists') {
        Assert-MockCalled -CommandName 'Get-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { 
            Write-Debug -Message ('Name  expected  {0}' -f $Named)
            Write-Debug -Message ('      actual    {0}' -f $Name)
            $Name -eq $Named 
        }
    }
}

function ThenRepositoryNotChecked
{
    It ('should not check that repository exists') {
        Assert-MockCalled -CommandName 'Get-PSRepository' -ModuleName 'Whiskey' -Times 0
    }
}

function ThenRepositoryNotRegistered
{
    param(
    )

    It ('should not register repository') {
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 0
    }
}

function ThenRepositoryRegistered
{
    param(
        [Parameter(Mandatory)]
        [string]
        $Named,

        [Parameter(Mandatory)]
        [string]
        $AtUri,

        [pscredential]
        $WithCredential
    )

    It ('should register the repository')  {
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Repository Name                 expected {0}' -f $Named)
            Write-Debug -Message ('                                actual   {0}' -f $Name)
            $Name -eq $Named
        }
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Source Location                 expected {0}' -f $AtUri)
            Write-Debug -Message ('                                actual   {0}' -f $SourceLocation)
            $AtUri -eq $SourceLocation
        }
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Publish Location                expected {0}' -f $AtUri)
            Write-Debug -Message ('                                actual   {0}' -f $PublishLocation)
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
    
}

function ThenModulePublished
{
    param(
        [Parameter(Mandatory)]
        [string]
        $ToRepositoryNamed,

        [String]
        $ExpectedPathName = (Join-Path -Path $TestDrive.FullName -ChildPath 'MyModule'),

        [switch]
        $WithNoRepositoryName
    )
    
    $WhiskeyBinPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin' -Resolve
    It ('should bootstrap NuGet provider') {
        Assert-MockCalled -CommandName 'Get-PackageProvider' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq 'NuGet' }
        Assert-MockCalled -CommandName 'Get-PackageProvider' -ModuleName 'Whiskey' -ParameterFilter { $ForceBootstrap }
    }
    
    It ('should publish the module')  {
        $expectedApiKey = $apikey
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Path Name                       expected {0}' -f $ExpectedPathName)
            Write-Debug -Message ('                                actual   {0}' -f $Path)
            
            $Path -eq $ExpectedPathName
        }
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Repository Name                 expected {0}' -f $ToRepositoryNamed)
            Write-Debug -Message ('                                actual   {0}' -f $Repository)
            $Repository -eq $ToRepositoryNamed
        }
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('ApiKey                          expected {0}' -f $expectedApiKey)
            Write-Debug -Message ('                                actual   {0}' -f $NuGetApiKey)
            $NuGetApiKey -eq $expectedApiKey
        }
    }
}

function ThenManifest
{
    param(
        [string]
        $manifestPath = (Join-Path -Path $TestDrive.FullName -ChildPath 'MyModule\MyModule.psd1'),

        [string]
        $AtVersion,

        [string]
        $HasPrerelease
    )

    if( -not $AtVersion )
    {
        $AtVersion = '{0}.{1}.{2}' -f $context.Version.SemVer2.Major, $context.Version.SemVer2.Minor, $context.Version.SemVer2.Patch
    }

    $manifest = Test-ModuleManifest -Path $manifestPath

    It ('should have a matching Manifest Version with the Context'){
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
}

Describe 'PublishPowerShellModule.when publishing new module' {
    Initialize-Test
    GivenRepository 'FubarSnafu'
    Invoke-Publish -ForRepositoryNamed 'FubarSnafu'
    ThenRepositoryChecked 'FubarSnafu' 
    ThenRepositoryNotRegistered
    ThenModulePublished -ToRepositoryNamed 'FubarSnafu'
}

Describe 'PublishPowerShellModule.when publishing prerelease module' {
    Initialize-Test
    GivenRepository 'SomeRepo'
    GivenPrerelease 'beta1'
    Invoke-Publish -ForRepositoryNamed 'SomeRepo'
    ThenRepositoryChecked 'SomeRepo'
    ThenRepositoryNotRegistered
    ThenModulePublished -ToRepositoryNamed 'SomeRepo'
    ThenManifest -HasPrerelease 'beta1'
}

Describe 'PublishPowerShellModule.when publishing with no repository name' {
    Initialize-Test
    Invoke-Publish -ThatFailsWith 'Property\ "RepositoryName"\ is mandatory' -ErrorAction SilentlyContinue
    ThenRepositoryNotChecked
    ThenRepositoryNotRegistered
    ThenModuleNotPublished
}

Describe 'PublishPowerShellModule.when publishing to a new repository' {
    Initialize-Test
    Invoke-Publish -ForRepositoryName 'ANewRepo' -RepoAtUri 'https://example.com' 
    ThenRepositoryChecked 'ANewRepo'
    ThenRepositoryRegistered 'ANewRepo' -AtUri 'https://example.com/'
    ThenModulePublished -ToRepositoryNamed 'ANewRepo'
}

Describe 'PublishPowerShellModule.when publishing to a new repository that requires a credential' {
    Initialize-Test
    $cred = New-Object 'pscredential' ('fubar',(ConvertTo-SecureString -String 'snafu' -AsPlainText -Force))
    GivenCredential $cred -WithID 'somecred'
    Invoke-Publish -ForRepositoryName 'ANewRepo' -RepoAtUri 'https://example.com' -WithCredentialID 'somecred'
    ThenRepositoryChecked 'ANewRepo'
    ThenRepositoryRegistered 'ANewRepo' -AtUri 'https://example.com/' -WithCredential $cred
    ThenModulePublished -ToRepositoryNamed 'ANewRepo'
}

Describe 'PublishPowerShellModule.when publishing to a new repository but its URI is not given' {
    Initialize-Test 
    Invoke-Publish -ForRepositoryNamed 'Fubar' -ThatFailsWith 'Property\ "RepositoryUri"\ is\ mandatory' -ErrorAction SilentlyContinue
    ThenRepositoryChecked 'Fubar'
    ThenRepositoryNotRegistered
    ThenModuleNotPublished
}

Describe 'PublishPowerShellModule.when no API key' {
    Initialize-Test
    GivenNoApiKey
    GivenRepository 'Fubar'
    Invoke-Publish -ForRepositoryNamed 'Fubar' -ThatFailsWith 'Property\ "ApiKeyID"\ is\ mandatory' -ErrorAction SilentlyContinue
    ThenRepositoryNotChecked
    ThenRepositoryNotRegistered
    ThenModuleNotPublished
}

Describe 'PublishPowerShellModule.when path parameter is not included' {
    Initialize-Test
    GivenRepository 'Fubar'
    Invoke-Publish -ForRepositoryNamed 'Fubar' -WithoutPathParameter -ThatFailsWith 'Property "Path" is mandatory' -ErrorAction SilentlyContinue
    ThenRepositoryNotChecked
    ThenRepositoryNotRegistered
    ThenModuleNotPublished
}

Describe 'PublishPowerShellModule.when non-existent path parameter' {
    Initialize-Test
    GivenRepository 'Fubar'
    Invoke-Publish -ForRepositoryNamed 'Fubar' -WithNonExistentPath -ThatFailsWith 'does\ not\ exist' -ErrorAction SilentlyContinue
    ThenModuleNotPublished
}

Describe 'PublishPowerShellModule.when non-directory path parameter' {
    Initialize-Test
    GivenRepository 'Fubar'
    Invoke-Publish -ForRepositoryNamed 'Fubar' -WithInvalidPath -ThatFailsWith 'path to the root directory of a PowerShell module' -ErrorAction SilentlyContinue
    ThenModuleNotPublished
}

Describe 'PublishPowerShellModule.when invalid manifest' {
    Initialize-Test
    GivenRepository 'Fubar'
    Invoke-Publish -ForRepositoryNamed 'Fubar' -withoutRegisteredRepo -ForManifestPath 'fubar' -ThatFailsWith 'path\ "fubar"\ either\ does\ not\ exist' -ErrorAction SilentlyContinue
    ThenModuleNotPublished
}
