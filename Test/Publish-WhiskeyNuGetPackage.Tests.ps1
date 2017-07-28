
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$projectName ='NUnit2PassingTest.csproj' 
$context = $null
$nugetUri = $null
$apiKey = $null
$defaultVersion = '1.2.3'
$packageExists = $false
$publishFails = $false
$packageExistsCheckFails = $false
$threwException = $false
$path = $null
$version = $null

function InitTest
{
    param(
    )

    $script:nugetUri = 'https://nuget.org'
    $script:apiKey = 'fubar:snafu'
    $script:packageExists = $false
    $script:publishFails = $false
    $script:packageExistsCheckFails = $false
    $script:path = $null
    $script:version = $defaultVersion
}

function GivenANuGetPackage
{
    param(
        [string[]]
        [ValidatePattern('\.\d+\.\d+\.\d+(-.*)?(\.symbols)?\.nupkg')]
        $Path
    )

    $outputRoot = Join-Path -Path $TestDRive.FullName -ChildPath '.output'
    New-Item -Path $outputRoot -ItemType 'Directory'  -ErrorAction Ignore

    foreach( $item in $Path )
    {
        New-Item -Path (Join-Path -Path $outputRoot -ChildPath $item) -ItemType 'File' -Force
    }
}

function GivenNoApiKey
{
    $script:apiKey = $null
}

function GivenNoUri
{
    $script:nugetUri = $null
}

function GivenPath
{
    param(
        $Path
    )

    $script:path = $Path
}

function GivenPackageAlreadyPublished
{
    $script:packageExists = $true
}

function GivenPackagePublishFails
{
    $script:publishFails = $true
}

function GivenTheCheckIfThePackageExistsFails
{
    $script:packageExistsCheckFails = $true
}

function GivenVersion
{
    param(
        $Version
    )

    $script:version = $Version
}

function WhenRunningNuGetPackTask
{
    [CmdletBinding()]
    param(
        [Switch]
        $ForProjectThatDoesNotExist,

        [Switch]
        $ForMultiplePackages,

        [Switch]
        $Symbols
    )

    $script:context = New-WhiskeyTestContext -ForVersion $version -ForTaskName 'PublishNuGetPackage' -ForBuildServer -IgnoreExistingOutputDirectory
    $taskParameter = @{ }

    if( $path )
    {
        $taskParameter['Path'] = $path
    }
                                            
    if( $apiKey )
    {
        $taskParameter['ApiKeyID'] = 'fubarsnafu'
        Add-WhiskeyApiKey -Context $context -ID 'fubarsnafu' -Value $apiKey
    }

    if( $nugetUri )
    {
        $taskParameter['Uri'] = $nugetUri
    }

    if( $Symbols )
    {
        $taskParameter['Symbols'] = $true
    }

    Mock -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey'
    if( $packageExists )
    {
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey'
    }
    elseif( $publishFails )
    {
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith { 
            Invoke-WebRequest -Uri 'http://httpstat.us/404'
        } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
    }
    elseif( $packageExistsCheckFails )
    {
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith { 
            Invoke-WebRequest -Uri 'http://httpstat.us/500'
        } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
    }
    else
    {
        $global:counter = 0
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith { 
            #$DebugPreference = 'Continue'
            Write-Debug $global:counter
            if($global:counter -eq 0)
            {
                $global:counter++    
                Write-Debug $global:counter
                Invoke-WebRequest -Uri 'http://httpstat.us/404'
            }
            $global:counter = 0
        } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
    }

    $optionalParams = @{ }
    $script:threwException = $false
    try
    {
        if( $ForProjectThatDoesNotExist )
        {
            $taskParameter['Path'] = 'I\do\not\exist.csproj'
        }

        $Global:error.Clear()
        Publish-WhiskeyNuGetPackage -TaskContext $Context -TaskParameter $taskParameter | Out-Null 

    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }

    Remove-Variable -Name 'counter' -Scope 'Global' -ErrorAction Ignore
}

function ThenTaskThrowsAnException
{
    param(
        $ExpectedErrorMessage
    )

    It 'should throw an exception' {
        $threwException | Should Be $true
    }

    It ('should throw an exception that matches /{0}/' -f $ExpectedErrorMessage) {
        $Global:Error | Should Not BeNullOrEmpty
        $lastError = $Global:Error[0]
        $lastError | Should -Match $ExpectedErrorMessage
    }
}

function ThenTaskSucceeds
{
    It 'should not throw an exception' {
        $threwException | Should Be $false
        $Global:Error | Should BeNullOrEmpty
    }
}

function ThenPackagePublished
{
    param(
        $Name,
        $Version,
        $Path,
        $Times = 1
    )

    foreach( $item in $Path )
    {
        It ('should publish package ''{0}''' -f $Path) {
            Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -ParameterFilter { 
                #$DebugPreference = 'Continue'
                $expectedPath = Join-Path -Path $TestDrive.FullName -ChildPath ('.output\{0}' -f $item)
                Write-Debug -Message ('Path  expected  {0}' -f $expectedPath)
                $Path | Where-Object { 
                                        Write-Debug -Message ('      actual    {0}' -f $_)
                                        $_ -eq $expectedPath 
                                     } 
           } 
        }

        It ('should check the correct URI for the package to exist') {
            $expectedUriWildcard = '*/{0}/{1}' -f $Name,$Version
            Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -ParameterFilter { 
                #$DebugPreference = 'Continue'
                Write-Debug -Message ('Uri   expected   {0}' -f $expectedUriWildcard)
                Write-Debug -Message ('      actual     {0}' -f $Uri)
                $Uri -like $expectedUriWildcard
             }.GetNewClosure()
        }
    }

    It ('should publish to {0}' -f $nugetUri) {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -ParameterFilter { $Uri -eq $nugetUri }
    }

    $expectedApiKey = $apiKey
    It ('should publish with API key ''{0}''' -f $apiKey) {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -ParameterFilter { $ApiKey -eq $expectedApiKey }
    }
}

function ThenPackageNotPublished
{
    param(
        $Path
    )

    $expectedPath = $Path
    It('should not publish the package') {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -Times 0 -ParameterFilter {
            #$DebugPreference = 'Continue'

            if( -not $expectedPath )
            {
                Write-Debug 'No Path'
                return $True
            }

            Write-Debug ('Path  expected  *\{0}' -f $expectedPath)
            Write-Debug ('      actual    {0}' -f $Path)
            return $Path -like ('*\{0}' -f $expectedPath)
        }
    }
}

Describe 'Publish-WhiskeyNuGetPackage.when publishing a NuGet package' {
    InitTest
    GivenVersion '1.2.3'
    GivenANuGetPackage 'Fubar.1.2.3.nupkg'
    WhenRunningNuGetPackTask
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -Version '1.2.3'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyNuGetPackage.when publishing a NuGet package with prerlease metadata' {
    InitTest
    GivenVersion '1.2.3-preleasee45'
    GivenANuGetPackage 'Fubar.1.2.3-preleasee45.nupkg'
    WhenRunningNuGetPackTask
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3-preleasee45.nupkg' -Version '1.2.3-preleasee45'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyNuGetPackage.when publishing a symbols NuGet package' {
    InitTest
    GivenVersion '1.2.3'
    GivenANuGetPackage 'Fubar.1.2.3.symbols.nupkg'
    GivenANuGetPackage 'Fubar.1.2.3.nupkg'
    WhenRunningNuGetPackTask -Symbols
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.symbols.nupkg' -Version '1.2.3'
    ThenPackageNotPublished -Path 'Fubar.1.2.3.nupkg'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyNuGetPackage.when creating multiple packages for publishing' {
    InitTest
    GivenVersion '3.4.5'
    GivenANuGetPackage 'Fubar.3.4.5.nupkg','Snafu.3.4.5.nupkg'
    WhenRunningNugetPackTask -ForMultiplePackages
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.3.4.5.nupkg' -Version '3.4.5'
    ThenPackagePublished -Name 'Snafu' -Path 'Snafu.3.4.5.nupkg' -Version '3.4.5'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyNuGetPackage.when publishing fails' {
    InitTest
    GivenVersion '9.0.1'
    GivenPackagePublishFails
    GivenANuGetPackage 'Fubar.9.0.1.nupkg'
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'failed to publish NuGet package'
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.9.0.1.nupkg' -Version '9.0.1'
}

Describe 'Publish-WhiskeyNuGetPackage.when package already exists' {
    InitTest
    GivenVersion '2.3.4'
    GivenPackageAlreadyPublished
    GivenANuGetPackage 'Fubar.2.3.4.nupkg'
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'already exists'
    ThenPackageNotPublished
}

Describe 'Publish-WhiskeyNuGetPackage.when creating WebRequest fails' {
    InitTest
    GivenVersion '5.6.7'
    GivenTheCheckIfThePackageExistsFails
    GivenANuGetPackage 'Fubar.5.6.7.nupkg'
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'failure checking if'
    ThenPackageNotPublished
}

Describe 'Publish-WhiskeyNuGetPackage.when URI property is missing' {
    InitTest
    GivenVersion '8.9.0'
    GivenANuGetPackage 'Fubar.8.9.0.nupkg'
    GivenNoUri
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotPublished
    ThenTaskThrowsAnException '\bURI\b.*\bmandatory\b'
}

Describe 'Publish-WhiskeyNuGetPackage.when ApiKeyID property is missing' {
    InitTest
    GivenVersion '1.2.3'
    GivenANuGetPackage 'Fubar.1.2.3.nupkg'
    GivenNoApiKey
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotPublished
    ThenTaskThrowsAnException '\bApiKeyID\b.*\bmandatory\b'
}

Describe 'Publish-WhiskeyNuGetPackage.when publishing custom packages' {
    InitTest
    GivenVersion '4.5.6'
    GivenANuGetPackage 'someotherdir\MyPack.4.5.6.nupkg'
    GivenPath '.output\someotherdir\MyPack.4.5.6.nupkg'
    WhenRunningNuGetPackTask
    ThenTaskSucceeds
    ThenPackagePublished -Name 'MyPack' -Path 'someotherdir\MyPack.4.5.6.nupkg' -Version '4.5.6'
}

Describe 'Publish-WhiskeyNuGetPackage.when there are only symbols packages' {
    InitTest
    GivenANuGetPackage 'Package.1.2.3.symbols.nupkg'
    WhenRunningNuGetPackTask
    ThenTaskSucceeds
    ThenPackageNotPublished
}