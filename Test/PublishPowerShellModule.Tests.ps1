Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$context = $null
$credentials = @{}
$failed = $false
$publishRoot = $null
$testModuleName = 'MyModule'
$repoToUnregister = $null

function Get-TestRepositoryFullPath
{
    param(
        [Parameter(Mandatory)]
        [String] $Name
    )

    return Join-Path -Path $testRoot -ChildPath $Name

}

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
        $At
    )

    if( -not $At )
    {
        $At = Get-TestRepositoryFullPath -Name $Named
    }

    if( -not ([IO.Path]::IsPathRooted($At)) )
    {
        $At = Join-Path -Path $script:testRoot -ChildPath $At
    }

    New-Item -Path $At -ItemType 'Directory' -Force | Out-Null
    $script:publishRoot = $At

    Register-PSRepository -Name $Named -PublishLocation $At -SourceLocation $At
    $script:repoToUnregister = $Named
}

function Init
{
    param(
    )

    $script:context = $null
    $script:credentials = @{ }
    $script:failed = $false
    $script:repoToUnregister = $null
    $script:publishRoot = $null
    $script:testRoot = New-WhiskeyTestRoot
}

function WhenPublishing
{
    [CmdletBinding()]
    param(
        [String] $ToRepo,

        [String] $RepoAt,

        [String] $ForManifestPath,

        [switch] $WithInvalidPath,

        [switch] $WithNonExistentPath,

        [switch] $WithoutPathParameter,

        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
        [String] $WithCredentialID,

        [switch] $WithNoPrereleasePropertyInManifest,

        [String] $WithPrerelease,

        [String] $WithApiKey
    )
    
    $version = '1.2.3'
    if( $WithPrerelease )
    {
        $version = '1.2.3-{0}' -f $WithPrerelease
    }

    $script:context = New-WhiskeyTestContext -ForBuildServer `
                                             -ForVersion $version `
                                             -ForBuildRoot $testRoot `
                                             -IncludePSModule @( 'PackageManagement', 'PowerShellGet' )
    
    $TaskParameter = @{ }

    if( $ToRepo )
    {
        $TaskParameter['RepositoryName'] = $ToRepo
    }

    if( $WithInvalidPath )
    {
        $TaskParameter.Add( 'Path', "$($testModuleName).ps1" )
        New-Item -Path $testRoot -ItemType 'file' -Name $TaskParameter['Path']
    }
    elseif( $WithNonExistentPath )
    {
        $TaskParameter.Add( 'Path', 'NopeISureDoNotExist.psd1' )
    }
    elseif( -not $WithoutPathParameter )
    {
        $TaskParameter.Add( 'Path', $testModuleName )
        New-Item -Path $testRoot -ItemType 'directory' -Name $testModuleName
        $module = Join-Path -Path $testRoot -ChildPath $testModuleName
        if( -not $ForManifestPath )
        {
            $prereleaseProperty = "Prerelease = '';"
            if( $WithNoPrereleasePropertyInManifest )
            {
                $prereleaseProperty = ''
            }

            New-item -Path $module -ItemType 'File' -Name "$($testModuleName).psm1"
            New-Item -Path $module -ItemType 'file' -Name "$($testModuleName).psd1" -Value @"
@{
    RootModule = '$($testModuleName).psm1';

    Description = '$($testModuleName)';

    Author = '$([Environment]::UserName)';

    # Version number of this module.
    ModuleVersion = '0.2.0';

    PrivateData = @{
        PSData = @{
            $($prereleaseProperty)
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

    $Global:Error.Clear()
    $script:failed = $False

    if( $RepoAt )
    {
        $TaskParameter['RepositoryLocation'] = $RepoAt
    }

    if( $WithCredentialID )
    {
        $TaskParameter['CredentialID'] = $WithCredentialID
    }

    if( $WithApiKey )
    {
        $TaskParameter['ApiKeyID'] = [Guid]::NewGuid().ToString()
        Add-WhiskeyApiKey -Context $context -ID $TaskParameter['ApiKeyID'] -Value $WithApiKey
    }

    foreach( $key in $credentials.Keys )
    {
        Add-WhiskeyCredential -Context $context -ID $key -Credential $credentials[$key]
    }

    if( $script:repoToUnregister )
    {
        Mock -CommandName 'Register-PSRepository' -ModuleName 'Whiskey'
    }

    Mock -CommandName 'Unregister-PSRepository' -ModuleName 'Whiskey'
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Parameter $TaskParameter -Name 'PublishPowerShellModule'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_ -ErrorAction $ErrorActionPreference
    }
}

function Reset
{
    Reset-WhiskeyTestPSModule
    Get-PSRepository | Where-Object 'Name' -Like 'Whiskey*' | Unregister-PSRepository
    if( $script:repoToUnregister )
    {
        Unregister-PSRepository -Name $script:repoToUnregister
    }
}
Reset

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
    Join-Path -Path $script:publishRoot -ChildPath '*.nupkg' | Should -Not -Exist
}

function ThenRepository
{
    param(
        [Parameter(Mandatory)]
        [String] $Named,

        [switch] $Exists,

        [switch] $NotExists,

        [switch] $NotRegistered,

        [switch] $NotUnregistered
    )

    if( $NotRegistered )
    {
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'Whiskey' -Times 0
    }

    if( $Exists )
    {
        Get-PSRepository |
            Where-Object 'Name' -EQ $Named |
            Where-Object 'PublishLocation' -EQ $script:publishRoot |
            Should -Not -BeNullOrEmpty
    }

    if( $NotExists )
    {
        Get-PSRepository |
            Where-Object 'Name' -EQ $Named |
            Should -BeNullOrEmpty
    }

    if( $NotUnregistered )
    {
        Assert-MockCalled -CommandName 'Unregister-PSRepository' -ModuleName 'Whiskey' -Times 0
    }
}

function ThenModulePublished
{
    param(
        $To = $script:context.OutputDirectory.FullName,
        $WithPrerelease = ''
    )
    
    if( -not [IO.Path]::IsPathRooted($To) )
    {
        $To = Join-Path -Path $script:testRoot -ChildPath $To
    }

    Join-Path -Path $To -ChildPath "$($testModuleName).*.*.*$($WithPrerelease).nupkg" | Should -Exist
}

function ThenManifest
{
    param(
        [String]$ManifestPath = (Join-Path -Path $testRoot -ChildPath "$($testModuleName)\$($testModuleName).psd1"),

        [String]$HasPrerelease
    )

    Test-ModuleManifest -Path $ManifestPath | Should -Not -BeNullOrEmpty
    # Test-ModuleManifest caches manifests if they have a RootModule property.
    Get-Content -Raw -Path $ManifestPath | Should -Match ([regex]::Escape("Prerelease = '$($HasPrerelease)'"))
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

    # PackageManagement and PowerShellGet leave handled errors in Global:Error so we need to filter those errors out.
    $Global:Error |
        Where-Object 'ScriptStackTrace' -NotMatch '\bPowerShellGet\b' -ErrorAction Ignore |
        Where-Object 'ScriptStackTrace' -NotMatch '\bPackageManagement\b' -ErrorAction Ignore
}

Describe 'PublishPowerShellModule.when publishing to repository that already exists' {
    AfterEach { Reset }
    It 'should publish the module wihtout registering the repository' {
        Init
        GivenRepository 'R1'
        WhenPublishing -ToRepo 'R1'
        ThenSucceeded
        ThenModulePublished -To 'R1'
        ThenRepository 'R1' -Exists -NotRegistered
    }
}

Describe 'PublishPowerShellModule.when publishing to repository that does not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenPublishing -ToRepo 'R2' -ErrorAction Silently
        ThenFailed 'a repository with that name doesn''t exist'
        ThenRepository 'R2' -NotExists -NotUnregistered
    }
}

Describe 'PublishPowerShellModule.when publishing prerelease module' {
    AfterEach { Reset }
    It 'should succeed' {
        Init
        WhenPublishing -WithPrerelease 'beta1'
        ThenSucceeded
        ThenModulePublished -WithPrerelease '-beta1'
        ThenManifest -HasPrerelease 'beta1'
    }
}

Describe 'PublishPowerShellModule.when publishing prerelease module but module manifest is missing Prerelease element' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenPublishing -WithPrerelease 'rc5' -WithNoPrereleasePropertyInManifest -ErrorAction SilentlyContinue
        ThenFailed 'missing a "Prerelease" property'
    }
}

Describe 'PublishPowerShellModule.when publishing with no repository name or repository location' {
    AfterEach { Reset }
    It 'should publish to build output directory' {
        Init
        WhenPublishing
        ThenSucceeded
        ThenRepository 'Whiskey*' -NotExists
        ThenModulePublished -To $context.OutputDirectory
    }
}

Describe 'PublishPowerShellModule.when given an API key' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        Mock -CommandName 'Publish-Module' `
             -ModuleName 'Whiskey' `
             -ParameterFilter { $NuGetApiKey -eq 'API6' } `
             -Verifiable
        WhenPublishing -WithApiKey 'API6'
        ThenSucceeded
        Assert-VerifiableMock
    }
}

Describe 'PublishPowerShellModule.when path parameter is not included' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenPublishing -WithoutPathParameter -ErrorAction SilentlyContinue
        ThenFailed -WithError '"Path\b.*\bis mandatory'
    }
}

Describe 'PublishPowerShellModule.when path does not exist' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenPublishing -WithNonExistentPath -ErrorAction SilentlyContinue
        ThenFailed -WithError 'does\ not\ exist'
    }
}

Describe 'PublishPowerShellModule.when path is not a directory' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenPublishing -WithInvalidPath  -ErrorAction SilentlyContinue
        ThenFailed -WithError 'should resolve to a directory'
    }
}

Describe 'PublishPowerShellModule.when module manifest is invalid' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        WhenPublishing -ForManifestPath 'fubar' -ErrorAction SilentlyContinue
        ThenFailed -WithError '"fubar"\ does\ not\ exist'
    }
}

Describe 'PublishPowerShellModule.when given repository by location and by name' {
    AfterEach { Reset }
    It 'should use repository registered by location' {
        Init
        GivenRepository -Named 'R7' -At 'R7'
        WhenPublishing -ToRepo 'R8' -RepoAt $script:publishRoot
        ThenSucceeded
        ThenRepository 'R8' -NotRegistered -NotExists
        ThenRepository 'R7' -NotRegistered -Exists
        ThenModulePublished -To 'R7'
    }
}
