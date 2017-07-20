
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
}

function GivenANuGetPackage
{
    param(
        [string[]]
        $Path
    )

    $outputRoot = Join-Path -Path $TestDRive.FullName -ChildPath '.output'
    New-Item -Path $outputRoot -ItemType 'Directory' 

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

function WhenRunningNuGetPackTask
{
    [CmdletBinding()]
    param(
        [Switch]
        $ForProjectThatDoesNotExist,

        [Switch]
        $ForMultiplePackages,

        [string]
        $WithVersion,

        [Switch]
        $WithCleanSwitch
    )

    $script:context = [pscustomobject]@{
                                            OutputDirectory = (Join-Path -Path $TestDRive.FullName -ChildPath '.output');
                                            ConfigurationPath = (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
                                            BuildRoot = $TestDrive.FullName;
                                            Version = @{
                                                            SemVer1 = '1.2.3';
                                                        }
                                            TaskIndex = 1;
                                            TaskName = 'PublishNuGetPackage';
                                            ApiKeys = @{ }
                                        }        
    $taskParameter = @{ }

    if( $path )
    {
        $taskParameter['Path'] = $path
    }
                                            
    if( $apiKey )
    {
        $taskParameter['ApiKeyID'] = 'fubarsnafu'
        $context.ApiKeys['fubarsnafu'] = $apiKey
    }

    if( $nugetUri )
    {
        $taskParameter['Uri'] = $nugetUri
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
    if( $WithCleanSwitch )
    {
        $optionalParams['Clean'] = $True
    }
    $script:threwException = $false
    try
    {
        if( $WithVersion )
        {
            $Context.Version.SemVer1 = $WithVersion
        }
        if( $ForProjectThatDoesNotExist )
        {
            $taskParameter['Path'] = 'I\do\not\exist.csproj'
        }

        $Global:error.Clear()
        Publish-WhiskeyNuGetPackage -TaskContext $Context -TaskParameter $taskParameter @optionalParams | Out-Null 

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
    It('should not publish the package') {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -Times 0
    }
}

Describe 'Publish-WhiskeyNuGetPackage.when publishing a NuGet package' {
    InitTest
    GivenANuGetPackage 'Fubar.nupkg'
    WhenRunningNuGetPackTask
    ThenPackagePublished 'Fubar.nupkg'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyNuGetPackage.when creating multiple packages for publishing' {
    InitTest
    GivenANuGetPackage 'Fubar.nupkg','Snafu.nupkg'
    WhenRunningNugetPackTask -ForMultiplePackages
    ThenPackagePublished 'Fubar.nupkg'
    ThenPackagePublished 'Snafu.nupkg'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyNuGetPackage.when publishing fails' {
    InitTest
    GivenPackagePublishFails
    GivenANuGetPackage 'Fubar.nupkg'
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'failed to publish NuGet package'
    ThenPackagePublished 'Fubar.nupkg'
}

Describe 'Publish-WhiskeyNuGetPackage.when package already exists' {
    InitTest
    GivenPackageAlreadyPublished
    GivenANuGetPackage 'Fubar.nupkg'
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'already exists'
    ThenPackageNotPublished
}

Describe 'Publish-WhiskeyNuGetPackage.when creating WebRequest fails' {
    InitTest
    GivenTheCheckIfThePackageExistsFails
    GivenANuGetPackage 'Fubar.nupkg'
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'failure checking if'
    ThenPackageNotPublished
}

Describe 'Publish-WhiskeyNuGetPackage.when creating a NuGet package with Clean switch' {    
    InitTest
    GivenANuGetPackage 'Fubar.nupkg'
    WhenRunningNuGetPackTask -WithCleanSwitch
    ThenTaskSucceeds

    It 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }

    ThenPackageNotPublished
}

Describe 'Publish-WhiskeyNuGetPackage.when URI property is missing' {
    InitTest
    GivenANuGetPackage 'Fubar.nupkg'
    GivenNoUri
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotPublished
    ThenTaskThrowsAnException '\bURI\b.*\bmandatory\b'
}

Describe 'Publish-WhiskeyNuGetPackage.when ApiKeyID property is missing' {
    InitTest
    GivenANuGetPackage 'Fubar.nupkg'
    GivenNoApiKey
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotPublished
    ThenTaskThrowsAnException '\bApiKeyID\b.*\bmandatory\b'
}

Describe 'Publish-WhiskeyNuGetPackage.when publishing custom packages' {
    InitTest
    GivenANuGetPackage 'someotherdir\MyPack.nupkg'
    GivenPath '.output\someotherdir\MyPack.nupkg'
    WhenRunningNuGetPackTask
    ThenTaskSucceeds
    ThenPackagePublished 'someotherdir\MyPack.nupkg'
}