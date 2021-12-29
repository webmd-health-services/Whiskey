
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$output = $null
$originalPath = $env:PATH
$globalDotNetDirectory = $null
$localDotNetDirectory = $null
$dotnetExeName = 'dotnet'
if( $IsWindows )
{
    $dotnetExeName = 'dotnet.exe'
}
$testRoot = $null

$latestSdkVersion = '5.0.209'
# The first in the major version line matching the latest SDK version.
$firstSdkVersion = '5.0.100'
$dotnetInstalled = $false

function Init
{
    $Global:Error.Clear()
    $script:output = $null
    $script:testRoot = New-WhiskeyTestRoot
    $script:globalDotNetDirectory = Join-Path $script:testRoot -ChildPath 'GlobalDotNetSDK'
    $script:localDotNetDirectory = Join-Path -Path $script:testRoot -ChildPath '.dotnet'
    $env:PATH = $originalPath
    $script:dotnetInstalled = $false
}

function GivenDotNetInstalled
{
    param(
        [Parameter(Mandatory)]
        [Version] $AtVersion
    )

    $installPath = $script:globalDotNetDirectory
    $script:dotnetInstalled = $true

    $dotNetExePath = Join-Path -Path $installPath -ChildPath $dotnetExeName
    New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

    $dotNetSdkPath = Join-Path -Path $installPath -ChildPath "sdk\$($AtVersion)\dotnet.dll"
    New-Item -Path $dotNetSdkPath -ItemType File -Force | Out-Null
}

function GivenDotNetNotInstalled
{
    $script:dotNetNotInstalled = $true
}

function ThenRestoreOriginalPathEnvironment
{
    $env:PATH = $originalPath
}

function ThenErrorIs
{
    param(
        $Message
    )

    $Global:Error | Select-Object -First 1 | Should -Match $Message
}

function ThenInstalledDotNet
{
    param(
        $ExpectedVersion
    )

    $sdkPath = Join-Path -Path $localDotNetDirectory -ChildPath ('sdk\{0}' -f $ExpectedVersion)

    $sdkPath | Should -Exist
    Get-ChildItem $sdkPath | Should -Not -BeNullOrEmpty
}

function ThenNotInstalledDotNetLocally
{
    param(
        $Version
    )

    $sdkPath = Join-Path -Path $localDotNetDirectory -ChildPath ('sdk\{0}' -f $Version)
    $sdkPath | Should -Not -Exist
}

function ThenReturnedPathToDotNet
{
    param(
        [switch] $Global
    )

    $output | Should -Not -BeNullOrEmpty
    $output | Should -HaveCount 1
    $output | Should -Exist
    if( $Global )
    {
        $output | Should -Be (Join-Path -Path $globalDotNetDirectory -ChildPath $dotnetExeName)
    }
    else
    {
        $output | Should -Be (Join-Path -Path $localDotNetDirectory -ChildPath $dotnetExeName)
    }
}

function ThenReturnedNothing
{
    $dotNetPath | Should -BeNullOrEmpty
}

function WhenInstallingDotNet
{
    [CmdletBinding()]
    param(
        $Version
    )

    $dotNetRoot = $script:globalDotNetDirectory
    $exeName = $script:dotNetExeName
    
    $mock = { Write-Error -Message 'Command not found.' -ErrorAction $ErrorActionPreference }
    if( $dotnetInstalled )
    {
        $mock = { 
            $cmd = [pscustomobject]@{ Source = (Join-Path -Path $dotNetRoot -ChildPath $exeName) }
            Write-Debug $cmd.Source
            return $cmd
        }.GetNewClosure()
    }
    Mock -CommandName 'Get-Command' -Module 'Whiskey' -ParameterFilter { $Name -eq 'dotnet' } -MockWith $mock

    $parameter = $PSBoundParameters
    $parameter['InstallRoot'] = $localDotNetDirectory
    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyDotNetSdk' -Parameter $parameter 
}

Describe "Install-WhiskeyDotNetSdk.when installing" {
    It "should install " {
        Init
        WhenInstallingDotNet $firstSdkVersion
        ThenInstalledDotNet $firstSdkVersion
        ThenReturnedPathToDotNet
    }

    Context "when installing newer version SDK alongside existing version" {
        It 'should install side by side' {
            WhenInstallingDotNet $latestSdkVersion
            ThenInstalledDotNet $firstSdkVersion
            ThenInstalledDotNet $latestSdkVersion
            ThenReturnedPathToDotNet
        }
    }
}

Describe 'Install-WhiskeyDotNetSdk.when SDK is installed globally' {
    It 'should not install locally' {
        Init
        GivenDotNetInstalled -AtVersion $latestSdkVersion
        WhenInstallingDotNet $latestSdkVersion
        ThenNotInstalledDotNetLocally $latestSdkVersion
        ThenReturnedPathToDotNet -Global
    }
}

Describe 'Install-WhiskeyDotNetSdk.when cannot find dotnet executable after install' {
    It 'should fail' {
        Init
        Mock -CommandName 'Join-Path' `
             -Module 'Whiskey' `
             -ParameterFilter {
                 $ChildPath -in @('dotnet', 'dotnet.exe') -and $Resolve -and $ErrorActionPreference -eq 'Ignore' } `
             -MockWith { Write-Error -Message "Path does not exist." -ErrorAction $ErrorActionPreference }
        WhenInstallingDotNet $latestSdkVersion -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorIs """$([regex]::Escape($dotnetExeName))"" command was not found"
    }
}

Describe 'Install-WhiskeyDotNetSdk.when installing SDK but desired SDK version was not found after install' {
    It 'should fail' {
        Init
        $installRoot = $script:InstallRoot
        $version = $latestSdkVersion
        Mock -CommandName 'Join-Path' `
             -Module 'Whiskey' `
             -ParameterFilter {
                 $ChildPath -eq "sdk\$($version)" -and $Resolve -and $ErrorActionPreference -eq 'Ignore' } `
             -MockWith { Write-Error -Message "Path does not exist." -ErrorAction $ErrorActionPreference }
        WhenInstallingDotNet $version -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorIs ([regex]::Escape(".NET SDK ""$($version)"" doesn't exist"))
    }
}
