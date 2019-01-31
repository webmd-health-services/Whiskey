Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$feedUri = $null
$apikey = $null
$apikeyID = $null

function GivenNoApiKey
{
    $script:apikey = $null
    $script:apikeyID = $null
}

function GivenNoFeedUri
{
    $script:feedUri = $null
}

function Initialize-Test
{
    param(
    )

    $script:feedUri = 'https://powershell.example.com'
    $script:apikey = 'fubar:snauf'
    $script:apikeyID = 'PowerShellExampleCom'
}

function Invoke-Publish
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [Switch]
        $withoutRegisteredRepo,

        [String]
        $ForRepositoryName,

        [String]
        $ForFeedName,

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
        $WithoutPathParameter
    )
    
    

    if( -not $ForRepositoryName )
    {
        $ForRepositoryName = 'thisRepo'
    }
    if ( -not $ForFeedName )
    {
        $ForFeedName = 'thisFeed'
    }
    if( $WithNoRepositoryName )
    {
        $TaskParameter = @{ }
    }
    else
    {
        $TaskParameter = @{
                            RepositoryName = $ForRepositoryName;
                            FeedName = $ForFeedName;
        }
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
}
"@
        }
        else
        {
            $TaskParameter.Add( 'ModuleManifestPath', $ForManifestPath )
        }
    }

    if( -not $withNoProgetURI )
    {
        $publishLocation = $feedUri
    }

    Mock -CommandName 'Get-PackageProvider' -ModuleName 'Whiskey'

    if( $withoutRegisteredRepo )
    {
        Mock -CommandName 'Get-PSRepository' -ModuleName 'Whiskey' -MockWith { return $false }
    }
    else
    {
        Mock -CommandName 'Get-PSRepository' -ModuleName 'Whiskey' -MockWith { return $true }
    }

    Add-Type -AssemblyName System.Net.Http
    Mock -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -MockWith { return }
    Mock -CommandName 'Publish-Module' -ModuleName 'Whiskey' -MockWith { return }
    
    $Global:Error.Clear()
    $failed = $False

    if( $feedUri )
    {
        $TaskParameter['RepositoryUri'] = $feedUri
    }

    if( $apikeyID )
    {
        $TaskParameter['ApiKeyID'] = $apikeyID
        Add-WhiskeyApiKey -Context $TaskContext -ID $apikeyID -Value $apikey
    }
    
    try
    {
        Invoke-WhiskeyTask -TaskContext $TaskContext -Parameter $TaskParameter -Name 'PublishPowerShellModule'
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

function Assert-ModuleRegistered
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [String]
        $ExpectedRepositoryName,

        [String]
        $ExpectedFeedName,

        [switch]
        $WithNoRepositoryName
    )

    if( -not $ExpectedRepositoryName )
    {
        $ExpectedRepositoryName = 'thisRepo'
    }
    if ( -not $ExpectedFeedName )
    {
        $ExpectedFeedName = 'thisFeed'
    }
    
    It ('should register the Module')  {
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Repository Name                 expected {0}' -f $ExpectedRepositoryName)
            Write-Debug -Message ('                                actual   {0}' -f $Name)

            Write-Debug -Message ('Source Location                 expected {0}' -f $expectedPublishLocation)
            Write-Debug -Message ('                                actual   {0}' -f $SourceLocation)

            Write-Debug -Message ('Publish Location                expected {0}' -f $expectedPublishLocation)
            Write-Debug -Message ('                                actual   {0}' -f $PublishLocation)

            $Name -eq $ExpectedRepositoryName -and
            $SourceLocation -eq $feedUri -and
            $PublishLocation -eq $feedUri

        }
    }
    
}

function Assert-ModulePublished
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [String]
        $ExpectedRepositoryName = 'thisRepo',

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
    
    It ('should publish the Module')  {
        $expectedApiKey = $apikey
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Path Name                       expected {0}' -f $ExpectedPathName)
            Write-Debug -Message ('                                actual   {0}' -f $Path)

            Write-Debug -Message ('Repository Name                 expected {0}' -f $ExpectedRepositoryName)
            Write-Debug -Message ('                                actual   {0}' -f $Repository)

            Write-Debug -Message ('ApiKey                          expected {0}' -f $expectedApiKey)
            Write-Debug -Message ('                                actual   {0}' -f $NuGetApiKey)
            
            $Path -eq $ExpectedPathName -and
            $Repository -eq $ExpectedRepositoryName -and
            $NuGetApiKey -eq $expectedApiKey
        }
    }
}

function Assert-ManifestVersion
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [String]
        $manifestPath = (Join-Path -Path $TestDrive.FullName -ChildPath 'MyModule\MyModule.psd1')
    )
    $versionString = "'{0}.{1}.{2}'" -f ( $TaskContext.Version.SemVer2.Major, $TaskContext.Version.SemVer2.Minor, $TaskContext.Version.SemVer2.Patch )

    $matches = Select-String $versionString $manifestPath

    It ('should have a matching Manifest Version with the Context'){
        $matches | Should Not BeNullOrEmpty
    }
}

Describe 'Publish-WhiskeyPowerShellModule.when publishing new module.'{
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    Invoke-Publish -WithoutRegisteredRepo -TaskContext $context
    Assert-ModuleRegistered -TaskContext $context
    Assert-ModulePublished -TaskContext $context
}

Describe 'Publish-WhiskeyPowerShellModule.when publishing with no repository name'{
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    Invoke-Publish -WithoutRegisteredRepo -WithNoRepositoryName -TaskContext $context -ThatFailsWith 'Property\ "RepositoryName"\ is mandatory' -ErrorAction SilentlyContinue
    Assert-ModuleNotPublished
}

Describe 'Publish-WhiskeyPowerShellModule.when publishing previously published module.'{
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    Invoke-Publish -TaskContext $context
    Assert-ModulePublished -TaskContext $context
}

Describe 'Publish-WhiskeyPowerShellModule.when publishing new module with custom repository name.'{
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    $repository = 'fubarepo'
    Invoke-Publish -WithoutRegisteredRepo -ForRepositoryName $repository -TaskContext $context
    Assert-ModuleRegistered -TaskContext $context -ExpectedRepositoryName $repository
    Assert-ModulePublished -TaskContext $context -ExpectedRepositoryName $repository
}

Describe 'Publish-WhiskeyPowerShellModule.when publishing new module with custom feed name.'{
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    $feed = 'snafeed'
    Invoke-Publish -WithoutRegisteredRepo -ForFeedName $feed -TaskContext $context
    Assert-ModuleRegistered -TaskContext $context -ExpectedFeedName $feed 
    Assert-ModulePublished -TaskContext $context 
}

Describe 'Publish-WhiskeyPowerShellModule.when no feed URI' {
    Initialize-Test
    GivenNoFeedUri
    $context = New-WhiskeyTestContext -ForBuildServer
    $errorMatch = '\bRepositoryUri\b.*\bmandatory\b'
    
    Invoke-Publish -withoutRegisteredRepo -withNoProgetURI -TaskContext $context -ThatFailsWith $errorMatch -ErrorAction SilentlyContinue
    Assert-ModuleNotPublished
}

Describe 'Publish-WhiskeyPowerShellModule.when no API key' {
    Initialize-Test
    GivenNoApiKey
    $context = New-WhiskeyTestContext -ForBuildServer
    $errorMatch = '\bApiKeyID\b.*\bmandatory\b'
    
    Invoke-Publish -withoutRegisteredRepo -withNoProgetURI -TaskContext $context -ThatFailsWith $errorMatch -ErrorAction SilentlyContinue
    Assert-ModuleNotPublished
}

Describe 'Publish-WhiskeyPowerShellModule.when Path Parameter is not included' {
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    $errorMatch = 'Property "Path" is mandatory'

    Invoke-Publish -WithoutPathParameter -TaskContext $context -ThatFailsWith $errorMatch -ErrorAction SilentlyContinue
    Assert-ModuleNotPublished
}

Describe 'Publish-WhiskeyPowerShellModule.when non-existent path parameter' {
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    $errorMatch = 'does not exist'

    Invoke-Publish -WithNonExistentPath -TaskContext $context -ThatFailsWith $errorMatch -ErrorAction SilentlyContinue
    Assert-ModuleNotPublished
}

Describe 'Publish-WhiskeyPowerShellModule.when non-directory path parameter' {
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    $errorMatch = 'path to the root directory of a PowerShell module'

    Invoke-Publish -WithInvalidPath -TaskContext $context -ThatFailsWith $errorMatch -ErrorAction SilentlyContinue
    Assert-ModuleNotPublished
}

Describe 'Publish-WhiskeyPowerShellModule.when reversion manifest with custom manifestPath and authentic manifest file' {
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    $existingManifestPath = (Join-Path -path (Split-Path $PSScriptRoot -Parent ) -ChildPath 'Whiskey\Whiskey.psd1')
    New-Item -Name 'Manifest' -Path $TestDrive.FullName -ItemType 'Directory'
    $manifestPath = (Join-Path -Path $TestDrive.FullName -ChildPath 'Manifest\manifest.psd1')
    Copy-Item $existingManifestPath $manifestPath
    
    Invoke-Publish -withoutRegisteredRepo -TaskContext $context -ForManifestPath $manifestPath
    Assert-ModuleRegistered -TaskContext $context
    Assert-ModulePublished -TaskContext $context
    Assert-ManifestVersion -TaskContext $context -manifestPath $manifestPath
}

Describe 'Publish-WhiskeyPowerShellModule.when reversion manifest without custom manifestPath' {
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    Invoke-Publish -withoutRegisteredRepo -TaskContext $context
    Assert-ModuleRegistered -TaskContext $context
    Assert-ModulePublished -TaskContext $context
    Assert-ManifestVersion -TaskContext $context
}

Describe 'Publish-WhiskeyPowerShellModule.when invalid manifestPath' {
    Initialize-Test
    $context = New-WhiskeyTestContext -ForBuildServer
    $manifestPath = 'fubar'
    $errorMatch = 'Module Manifest Path'

    Invoke-Publish -withoutRegisteredRepo -TaskContext $context -ForManifestPath $manifestPath -ThatFailsWith $errorMatch -ErrorAction SilentlyContinue
    Assert-ModuleNotPublished
}
