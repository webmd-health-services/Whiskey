
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

# These tests intermittently fail. Turn on verbose and debug to maybe help locate the problem.
$DebugPreference = [Management.Automation.ActionPreference]::Continue
$VerbosePreference = [Management.Automation.ActionPreference]::Continue

$testRoot = $null
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

function Init
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

    $script:testRoot = New-WhiskeyTestRoot
}

function GivenANuGetPackage
{
    param(
        [ValidatePattern('\.\d+\.\d+\.\d+(-.*)?(\.symbols)?\.nupkg')]
        [String[]]$Path
    )

    $outputRoot = Join-Path -Path $testRoot -ChildPath '.output'
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
        [switch]$ForProjectThatDoesNotExist,

        [switch]$ForMultiplePackages,

        [switch]$Symbols,

        [switch]$SkipUploadedCheck
    )

    $script:context = New-WhiskeyTestContext -ForVersion $packageVersion `
                                             -ForBuildServer `
                                             -ForBuildRoot $testRoot `
                                             -IgnoreExistingOutputDirectory
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
            Write-WhiskeyDebug -Message 'http://httpstat.us/404'
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri 'http://httpstat.us/404' -Headers @{ 'Accept' = 'text/html' }
        } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
    }
    elseif( $packageExistsCheckFails )
    {
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith { 
            Write-WhiskeyDebug -Message 'http://httpstat.us/500'
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri 'http://httpstat.us/500' -Headers @{ 'Accept' = 'text/html' }
        } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
    }
    else
    {
        $global:counter = 0
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -MockWith { 
            #$DebugPreference = 'Continue'
            Write-WhiskeyDebug $global:counter
            if($global:counter -eq 0)
            {
                $global:counter++    
                Write-WhiskeyDebug $global:counter
                Write-WhiskeyDebug -Message 'http://httpstat.us/404'
                $ProgressPreference = 'SilentlyContinue'
                Invoke-WebRequest -Uri 'http://httpstat.us/404' -Headers @{ 'Accept' = 'text/html' }
            }
            $global:counter = 0
            Write-WhiskeyDebug -Message 'http://httpstat.us/200'
        } -ParameterFilter { $Uri -notlike 'http://httpstat.us/*' }
    }

    $script:threwException = $false
    try
    {
        if( $ForProjectThatDoesNotExist )
        {
            $taskParameter['Path'] = 'I\do\not\exist.csproj'
        }

        $Global:Error.Clear()
        Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'NuGetPush'

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
    
    Join-Path -Path $context.BuildRoot -ChildPath ('packages\{0}' -f $nugetVersion) | Should -Exist
}

function ThenTaskThrowsAnException
{
    param(
        $ExpectedErrorMessage
    )

    $Global:Error | Format-List * -Force | Out-String | Write-Verbose -Verbose
    
    $threwException | Should -BeTrue
    $Global:Error | Should -Not -BeNullOrEmpty
    $lastError = $Global:Error[0]
    $lastError | Should -Match $ExpectedErrorMessage
}

function ThenTaskSucceeds
{
    $Global:Error | Format-List * -Force | Out-String | Write-Verbose -Verbose

    $threwException | Should -BeFalse
    $Global:Error | Should -BeNullOrEmpty
}

function ThenPackagePublished
{
    param(
        $Name,
        $PackageVersion,
        $Path,
        $Times = 1
    )

    $Global:Error | Format-List * -Force | Out-String | Write-Verbose -Verbose
    foreach( $item in $Path )
    {
        $testRoot = $script:testRoot
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -ParameterFilter { 
            #$DebugPreference = 'Continue'
            $expectedPath = Join-Path -Path '.' -ChildPath ('.output\{0}' -f $item)
            Write-WhiskeyDebug -Message ('Path  expected  {0}' -f $expectedPath)
            $Path | Where-Object { 
                                    Write-WhiskeyDebug -Message ('      actual    {0}' -f $_)
                                    $_ -eq $expectedPath 
                                    } 
        }.GetNewClosure()

        $expectedUriWildcard = '*/{0}/{1}' -f $Name,$PackageVersion
        Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -ParameterFilter { 
            #$DebugPreference = 'Continue'
            Write-WhiskeyDebug -Message ('Uri   expected   {0}' -f $expectedUriWildcard)
            Write-WhiskeyDebug -Message ('      actual     {0}' -f $Uri)
            $Uri -like $expectedUriWildcard
            }.GetNewClosure()
    }

    Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -ParameterFilter { $Uri -eq $nugetUri }

    $expectedApiKey = $apiKey
    Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -ParameterFilter { $ApiKey -eq $expectedApiKey }
}

function ThenPackageNotPublished
{
    param(
        $Path
    )

    $expectedPath = $Path
    Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -Times 0 -ParameterFilter {
        #$DebugPreference = 'Continue'

        if( -not $expectedPath )
        {
            Write-WhiskeyDebug 'No Path'
            return $True
        }

        Write-WhiskeyDebug ('Path  expected  *\{0}' -f $expectedPath)
        Write-WhiskeyDebug ('      actual    {0}' -f $Path)
        return $Path -like ('*\{0}' -f $expectedPath)
    }
}

if( -not $IsWindows )
{
    Describe 'NuGetPush.when run on non-Windows platform' {
        It 'should fail' {
            Init
            GivenPackageVersion '1.2.3'
            GivenANuGetPackage 'Fubar.1.2.3.nupkg'
            WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
            ThenTaskThrowsAnException 'Windows\ platform'
        }
    }
    return
}

Describe 'NuGetPush.when publishing a NuGet package' {
    It 'should pass' {
        Init
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        WhenRunningNuGetPackTask
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -PackageVersion '1.2.3'
        ThenTaskSucceeds
    }
}

Describe 'NuGetPush.when publishing a NuGet package with prerelease metadata' {
    It 'should publish with prerelease metadata' {
        Init
        GivenPackageVersion '1.2.3-preleasee45'
        GivenANuGetPackage 'Fubar.1.2.3-preleasee45.nupkg'
        WhenRunningNuGetPackTask
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3-preleasee45.nupkg' -PackageVersion '1.2.3-preleasee45'
        ThenTaskSucceeds
    }
}

Describe 'NuGetPush.when publishing a symbols NuGet package' {
    It 'should publish with symbols' {
        Init
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.symbols.nupkg'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        WhenRunningNuGetPackTask -Symbols
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.symbols.nupkg' -PackageVersion '1.2.3'
        ThenPackageNotPublished -Path 'Fubar.1.2.3.nupkg'
        ThenTaskSucceeds
    }
}

Describe 'NuGetPush.when there are multiple packages' {
    It 'should publish all' {
        Init
        GivenPackageVersion '3.4.5'
        GivenANuGetPackage 'Fubar.3.4.5.nupkg','Snafu.3.4.5.nupkg'
        WhenRunningNugetPackTask -ForMultiplePackages
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.3.4.5.nupkg' -PackageVersion '3.4.5'
        ThenPackagePublished -Name 'Snafu' -Path 'Snafu.3.4.5.nupkg' -PackageVersion '3.4.5'
        ThenTaskSucceeds
    }
}

Describe 'NuGetPush.when publishing fails' {
    It 'should fail' {
        Init
        GivenPackageVersion '9.0.1'
        GivenPackagePublishFails
        GivenANuGetPackage 'Fubar.9.0.1.nupkg'
        WhenRunningNugetPackTask -ErrorAction SilentlyContinue
        ThenTaskThrowsAnException 'failed to publish NuGet package'
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.9.0.1.nupkg' -PackageVersion '9.0.1'
    }
}

Describe 'NuGetPush.when package already exists' {
    It 'should fail' {
        Init
        GivenPackageVersion '2.3.4'
        GivenPackageAlreadyPublished
        GivenANuGetPackage 'Fubar.2.3.4.nupkg'
        WhenRunningNugetPackTask -ErrorAction SilentlyContinue
        ThenTaskThrowsAnException 'already exists'
        ThenPackageNotPublished
    }
}

Describe 'NuGetPush.when creating WebRequest fails' {
    It 'should fail' {
        Init
        GivenPackageVersion '5.6.7'
        GivenTheCheckIfThePackageExistsFails
        GivenANuGetPackage 'Fubar.5.6.7.nupkg'
        WhenRunningNugetPackTask -ErrorAction SilentlyContinue
        ThenTaskThrowsAnException 'failure checking if'
        ThenPackageNotPublished
    }
}

Describe 'NuGetPush.when URI property is missing' {
    It 'should fail' {
        Init
        GivenPackageVersion '8.9.0'
        GivenANuGetPackage 'Fubar.8.9.0.nupkg'
        GivenNoUri
        WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
        ThenPackageNotPublished
        ThenTaskThrowsAnException '\bURI\b.*\bmandatory\b'
    }
}

Describe 'NuGetPush.when ApiKeyID property is missing' {
    It 'should fail' {
        Init
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        GivenNoApiKey
        WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
        ThenPackageNotPublished
        ThenTaskThrowsAnException '\bApiKeyID\b.*\bmandatory\b'
    }
}

Describe 'NuGetPush.when publishing custom packages' {
    It 'should pass' {
        Init
        GivenPackageVersion '4.5.6'
        GivenANuGetPackage 'someotherdir\MyPack.4.5.6.nupkg'
        GivenPath '.output\someotherdir\MyPack.4.5.6.nupkg'
        WhenRunningNuGetPackTask
        ThenTaskSucceeds
        ThenPackagePublished -Name 'MyPack' -Path 'someotherdir\MyPack.4.5.6.nupkg' -PackageVersion '4.5.6'
    }
}

Describe 'NuGetPush.when there are only symbols packages' {
    It 'should not publish anything' {
        Init
        GivenANuGetPackage 'Package.1.2.3.symbols.nupkg'
        WhenRunningNuGetPackTask
        ThenTaskSucceeds
        ThenPackageNotPublished
    }
}

Describe 'NuGetPush.when publishing a NuGet package using a specific version of NuGet' {
    It 'should use that version' {
        Init
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        GivenVersion '3.5.0'
        WhenRunningNuGetPackTask
        ThenSpecificNuGetVersionInstalled
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -PackageVersion '1.2.3'
        ThenTaskSucceeds
    }
}

Describe 'NuGetPush.when skipping publish check' {
    It 'should not check if publish succeeded' {
        Init
        GivenPackageVersion '1.2.3'
        GivenANuGetPackage 'Fubar.1.2.3.nupkg'
        GivenPackagePublishFails
        WhenRunningNuGetPackTask -SkipUploadedCheck
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.2.3.nupkg' -PackageVersion '1.2.3'
        ThenTaskSucceeds
        Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 1
    }
}

Describe 'NuGetPush.when publishing multiple packages at different version numbers' {
    It 'should publish' {
        Init
        GivenANuGetPackage 'Fubar.1.0.0.nupkg','Snafu.2.0.0.nupkg'
        WhenRunningNugetPackTask
        ThenPackagePublished -Name 'Fubar' -Path 'Fubar.1.0.0.nupkg' -PackageVersion '1.0.0'
        ThenPackagePublished -Name 'Snafu' -Path 'Snafu.2.0.0.nupkg' -PackageVersion '2.0.0'
        ThenTaskSucceeds
    }
}
