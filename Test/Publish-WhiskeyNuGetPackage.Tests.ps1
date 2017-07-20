
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

function InitTest
{
    param(
    )

    $script:nugetUri = 'https://nuget.org'
    $script:apiKey = 'fubar:snafu'
    $script:packageExists = $false
    $script:publishFails = $false
    $script:packageExistsCheckFails = $false
}

function GivenABuiltLibrary
{
    param(
        [Switch]
        $ThatDoesNotExist,

        [Switch]
        $InReleaseMode,

        [string]
        $WithVersion = $defaultVersion
    )

    $projectRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest'
    robocopy $projectRoot $TestDrive.FullName '/MIR' '/R:0'

    # Make sure output directory gets created by the task
    $buildConfig = 'Debug'
    if( $InReleaseMode )
    {
        $buildConfig = 'Release'
    }

    #New-WhiskeyTestContext -ForBuildRoot $TestDrive.FullName -ForTaskName 'NuGetPack' -ForDeveloper | Format-List | Out-String | Write-Verbose -Verbose
        
    $script:context = [pscustomobject]@{
                                            Version = [pscustomobject]@{
                                                                            SemVer1 = $WithVersion;
                                                                       }
                                            OutputDirectory = (Join-Path -Path $TestDRive.FullName -ChildPath '.output');
                                            BuildConfiguration = $buildConfig;
                                            ConfigurationPath = (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
                                            BuildRoot = $TestDrive.FullName;
                                            TaskIndex = 1;
                                            TaskName = 'PublishNuGetLibrary';
                                            ApiKeys = @{ }
                                        }
    New-Item -Path $context.OutputDirectory -ItemType 'Directory' 
    
    Get-ChildItem -Path $context.OutputDirectory | Remove-Item -Recurse -Force
    if( $WithVersion )
    {
        $Context.Version.SemVer1 = $WithVersion
    }

    $Global:Error.Clear()
    $project = Join-Path -Path $TestDrive.FullName -ChildPath $projectName -Resolve
    
    $propertyArg = @{}
    if( $InReleaseMode )
    {
        $propertyArg['Property'] = 'Configuration=Release'
    }

    Get-ChildItem -Path $TestDrive.FullName -File '*.sln' | ForEach-Object { & (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\bin\NuGet.exe' -Resolve) restore $_.FullName }# $project
    Invoke-WhiskeyMSBuild -Path $project -Target 'build' @propertyArg | Write-Verbose
}

function GivenNoApiKey
{
    $script:apiKey = $null
}

function GivenNoUri
{
    $script:nugetUri = $null
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

    process 
    {        
        $Global:Error.Clear()        
        if( $ForMultiplePackages )
        {
            $taskParameter = @{
                            Path = @(
                                        $projectName,
                                        $projectName
                                    )
                          }
        }
        else 
        {
            $taskParameter = @{
                            Path = @(
                                        $projectName
                                    )
                          }
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

function ThenPackageCreated
{
    param(
        [string]
        $WithVersion
    )

    if( $WithVersion )
    {
        $Context.Version.SemVer1 = $WithVersion
    }

    It ('should create NuGet package') {
        $packagePath = Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.nupkg' -f $Context.Version.SemVer1)
        $packagePath | Should Exist
    }

    It ('should create NuGet symbols package') {
        $packagePath = Join-Path -Path $Context.OutputDirectory -ChildPath ('NUnit2PassingTest.{0}.symbols.nupkg' -f $Context.Version.SemVer1)
        $packagePath | Should Exist
    }
 }

 function ThenPackagePublished
 {
    param(
        $Times = 1
    )

    It ('should publish {0} packages' -f $Times) {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNuGetPush' -ModuleName 'Whiskey' -Times ($Times * 2) 
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

function ThenPackageNotCreated
{
    It 'should not create any .nupkg files' {
        (Join-Path -Path $context.OutputDirectory -ChildPath '*.nupkg') | Should Not Exist
    }
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating a NuGet package with an invalid project' {
    InitTest
    GivenABuiltLibrary
    WhenRunningNuGetPackTask -ForProjectThatDoesNotExist -ErrorAction SilentlyContinue
    ThenPackageNotCreated
    ThenTaskThrowsAnException 'does not exist'
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating a NuGet package' {
    InitTest
    GivenABuiltLibrary
    WhenRunningNuGetPackTask
    ThenPackageCreated
    ThenPackagePublished
    ThenTaskSucceeds
}

Describe 'Invoke-PublishNuGetLibraryTask.when passed a version' {
    InitTest
    $version = '4.5.6-rc1'
    GivenABuiltLibrary -WithVersion $version
    WhenRunningNugetPackTask
    ThenPackageCreated -WithVersion $version
    ThenPackagePublished
    ThenTaskSucceeds
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating a package built in release mode' {
    InitTest
    GivenABuiltLibrary -InReleaseMode
    WhenRunningNugetPackTask
    ThenPackageCreated
    ThenPackagePublished
    ThenTaskSucceeds
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating multiple packages for publishing' {
    InitTest
    GivenABuiltLibrary
    WhenRunningNugetPackTask -ForMultiplePackages
    ThenPackageCreated
    ThenPackagePublished -Times 2
    ThenTaskSucceeds
}

Describe 'Invoke-PublishNuGetLibraryTask.when publishing fails' {
    InitTest
    GivenPackagePublishFails
    GivenABuiltLibrary
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'failed to publish NuGet package'
    ThenPackageCreated
    ThenPackagePublished
}

Describe 'Invoke-PublishNuGetLibraryTask.when package already exists' {
    InitTest
    GivenPackageAlreadyPublished
    GivenABuiltLibrary
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'already exists'
    ThenPackageNotPublished
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating WebRequest fails' {
    InitTest
    GivenTheCheckIfThePackageExistsFails
    GivenABuiltLibrary
    WhenRunningNugetPackTask -ErrorAction SilentlyContinue
    ThenTaskThrowsAnException 'failure checking if'
    ThenPackageNotPublished
}

Describe 'Invoke-PublishNuGetLibraryTask.when creating a NuGet package with Clean switch' {    
    InitTest
    GivenABuiltLibrary
    WhenRunningNuGetPackTask -WithCleanSwitch
    ThenTaskSucceeds

    It 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }

    ThenPackageNotCreated
    ThenPackageNotPublished
}

Describe 'Invoke-PublishNuGetLibraryTask.when URI property is missing' {
    InitTest
    GivenABuiltLibrary
    GivenNoUri
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotCreated
    ThenTaskThrowsAnException '\bURI\b.*\bmandatory\b'
}

Describe 'Invoke-PublishNuGetLibraryTask.when ApiKeyID property is missing' {
    InitTest
    GivenABuiltLibrary
    GivenNoApiKey
    WhenRunningNuGetPackTask -ErrorAction SilentlyContinue
    ThenPackageNotCreated
    ThenTaskThrowsAnException '\bApiKeyID\b.*\bmandatory\b'
}