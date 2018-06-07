
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
$packageVersion = $null
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
    $script:packageVersion = $defaultVersion
    $script:version = $null
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

function GivenPackageVersion
{
    param(
        $PackageVersion
    )

    $script:packageVersion = $PackageVersion
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
        $Symbols,

        [Switch]
        $SkipUploadedCheck
    )

    $script:context = New-WhiskeyTestContext -ForVersion $packageVersion -ForBuildServer -IgnoreExistingOutputDirectory
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

    if( $version )
    {
        $taskParameter['Version'] = $version
    }

    if( $SkipUploadedCheck )
    {
        $taskParameter['SkipUploadedCheck'] = 'true'
    }

    Mock -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey'
    if( $packageExists )
    {
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey'
    }
    elseif( $publishFails )
    {
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith { 
            Write-Debug -Message 'http://httpstat.us/404'
            Invoke-WebRequest -Uri 'http://httpstat.us/404' -Headers @{ 'Accept' = 'text/html' }
        } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
    }
    elseif( $packageExistsCheckFails )
    {
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith { 
            Write-Debug -Message 'http://httpstat.us/500'
            Invoke-WebRequest -Uri 'http://httpstat.us/500' -Headers @{ 'Accept' = 'text/html' }
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
                Write-Debug -Message 'http://httpstat.us/404'
                Invoke-WebRequest -Uri 'http://httpstat.us/404' -Headers @{ 'Accept' = 'text/html' }
            }
            $global:counter = 0
            Write-Debug -Message 'http://httpstat.us/200'
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
        Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'NuGetPush' | Out-Null 

    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }

    Remove-Variable -Name 'counter' -Scope 'Global' -ErrorAction Ignore
}

function ThenSpecificNuGetVersionInstalled
{
    $nugetVersion = 'NuGet.CommandLine.{0}' -f $version
    
    It ('should install ''{0}''' -f $nugetVersion) {
        Join-Path -Path $context.BuildRoot -ChildPath ('packages\{0}' -f $nugetVersion) | Should -Exist
    }
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
        $PackageVersion,
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
            $expectedUriWildcard = '*/{0}/{1}' -f $Name,$PackageVersion
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

Describe 'NuGetPush.when publishing a NuGet package' {
    InitTest
    GivenPackageVersion '1.2.3'
    GivenANuGetPackage 'Fubar.1.2.3.nupkg'
    WhenRunningNuGetPackTask
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -PackageVersion '1.2.3'
    ThenTaskSucceeds
}

Describe 'NuGetPush.when publishing a NuGet package with prerlease metadata' {
    InitTest
    GivenPackageVersion '1.2.3-preleasee45'
    GivenANuGetPackage 'Fubar.1.2.3-preleasee45.nupkg'
    WhenRunningNuGetPackTask
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3-preleasee45.nupkg' -PackageVersion '1.2.3-preleasee45'
    ThenTaskSucceeds
}

Describe 'NuGetPush.when publishing a symbols NuGet package' {
    InitTest
    GivenPackageVersion '1.2.3'
    GivenANuGetPackage 'Fubar.1.2.3.symbols.nupkg'
    GivenANuGetPackage 'Fubar.1.2.3.nupkg'
    WhenRunningNuGetPackTask -Symbols
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.symbols.nupkg' -PackageVersion '1.2.3'
    ThenPackageNotPublished -Path 'Fubar.1.2.3.nupkg'
    ThenTaskSucceeds
}

Describe 'NuGetPush.when creating multiple packages for publishing' {
    InitTest
    GivenPackageVersion '3.4.5'
    GivenANuGetPackage 'Fubar.3.4.5.nupkg','Snafu.3.4.5.nupkg'
    WhenRunningNugetPackTask -ForMultiplePackages
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.3.4.5.nupkg' -PackageVersion '3.4.5'
    ThenPackagePublished -Name 'Snafu' -Path 'Snafu.3.4.5.nupkg' -PackageVersion '3.4.5'
    ThenTaskSucceeds
}

Describe 'NuGetPush.when publishing fails' {
    InitTest
    GivenPackageVersion '9.0.1'
    GivenPackagePublishFails
    GivenANuGetPackage 'Fubar.9.0.1.nupkg'
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'failed to publish NuGet package'
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.9.0.1.nupkg' -PackageVersion '9.0.1'
}

Describe 'NuGetPush.when package already exists' {
    InitTest
    GivenPackageVersion '2.3.4'
    GivenPackageAlreadyPublished
    GivenANuGetPackage 'Fubar.2.3.4.nupkg'
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'already exists'
    ThenPackageNotPublished
}

Describe 'NuGetPush.when creating WebRequest fails' {
    InitTest
    GivenPackageVersion '5.6.7'
    GivenTheCheckIfThePackageExistsFails
    GivenANuGetPackage 'Fubar.5.6.7.nupkg'
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'failure checking if'
    ThenPackageNotPublished
}

Describe 'NuGetPush.when URI property is missing' {
    InitTest
    GivenPackageVersion '8.9.0'
    GivenANuGetPackage 'Fubar.8.9.0.nupkg'
    GivenNoUri
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotPublished
    ThenTaskThrowsAnException '\bURI\b.*\bmandatory\b'
}

Describe 'NuGetPush.when ApiKeyID property is missing' {
    InitTest
    GivenPackageVersion '1.2.3'
    GivenANuGetPackage 'Fubar.1.2.3.nupkg'
    GivenNoApiKey
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotPublished
    ThenTaskThrowsAnException '\bApiKeyID\b.*\bmandatory\b'
}

Describe 'NuGetPush.when publishing custom packages' {
    InitTest
    GivenPackageVersion '4.5.6'
    GivenANuGetPackage 'someotherdir\MyPack.4.5.6.nupkg'
    GivenPath '.output\someotherdir\MyPack.4.5.6.nupkg'
    WhenRunningNuGetPackTask
    ThenTaskSucceeds
    ThenPackagePublished -Name 'MyPack' -Path 'someotherdir\MyPack.4.5.6.nupkg' -PackageVersion '4.5.6'
}

Describe 'NuGetPush.when there are only symbols packages' {
    InitTest
    GivenANuGetPackage 'Package.1.2.3.symbols.nupkg'
    WhenRunningNuGetPackTask
    ThenTaskSucceeds
    ThenPackageNotPublished
}

Describe 'NuGetPush.when publishing a NuGet package using a specific version of NuGet' {
    InitTest
    GivenPackageVersion '1.2.3'
    GivenANuGetPackage 'Fubar.1.2.3.nupkg'
    GivenVersion '3.5.0'
    WhenRunningNuGetPackTask
    ThenSpecificNuGetVersionInstalled
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -PackageVersion '1.2.3'
    ThenTaskSucceeds
}

Describe 'NuGetPush.when skipping publish check' {
    InitTest
    GivenPackageVersion '1.2.3'
    GivenANuGetPackage 'Fubar.1.2.3.nupkg'
    GivenPackagePublishFails
    WhenRunningNuGetPackTask -SkipUploadedCheck
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -PackageVersion '1.2.3'
    ThenTaskSucceeds
    It ('should call Invoke-WebRequest once') {
        Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 1
    }
}

Describe 'NuGetPush.when publishing multiple packages at different version numbers' {
    InitTest
    GivenANuGetPackage 'Fubar.1.0.0.nupkg','Snafu.2.0.0.nupkg'
    WhenRunningNugetPackTask
    ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.0.0.nupkg' -PackageVersion '1.0.0'
    ThenPackagePublished -Name 'Snafu' -Path 'Snafu.2.0.0.nupkg' -PackageVersion '2.0.0'
    ThenTaskSucceeds
}
