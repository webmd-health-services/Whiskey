& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$originalPath = $env:Path
$testRoot = $null
$globalDotNetDirectory = $null
$output = $null
$dotNetExeName = 'dotnet'
if ( $IsWindows )
{
    $dotNetExeName = 'dotnet.exe'
}
function Init
{
    $Global:Error.Clear()
    $script:testRoot = New-WhiskeyTestRoot
    $script:globalDotNetDirectory = Join-Path $script:testRoot -ChildPath 'GlobalDotNetSDK'
    $env:Path = $originalPath
    $script:output = $null
}

function GivenDotNetInstalled
{
    param(
        [Parameter(Mandatory)]
        [Version[]] $AtVersion
    )

    $installPath = $script:globalDotNetDirectory
    $dotNetExePath = Join-Path -Path $installPath -ChildPath $dotnetExeName
    New-Item -Path $dotNetExePath -ItemType File -Force | Out-Null

    $sdkPaths = 
        $AtVersion |
        ForEach-Object { Join-Path -Path $installPath -ChildPath "sdk\$($_)\dotnet.dll"}
    
    New-Item -Path $sdkPaths -ItemType File -Force | Out-Null
}

function WhenResolvingVersions
{
    $dotNetRoot = $script:globalDotNetDirectory
    $exeName = $script:dotNetExeName
    $mock = { [pscustomobject]@{ Source = (Join-Path -Path $dotNetRoot -ChildPath $exeName) } }.GetNewClosure()
    Mock -CommandName 'Get-Command' -Module 'Whiskey' -ParameterFilter { $Name -eq 'dotnet' } -MockWith $mock
    $script:output = Invoke-WhiskeyPrivateCommand -Name 'Get-InstalledDotNetSdk'
}

function ThenResolvedVersion
{
    param(
        [Parameter(Mandatory)]
        [Version[]] $ExpectedVersion
    )

    $ExpectedVersion |
        ForEach-Object {
            $_ | Should -BeIn $output
        }
}

Describe 'Get-InstalledDotNetSdk.when .NET SDK has one installed version' {
    it 'Resolved that version' {
        Init
        GivenDotNetInstalled '1.1.100'
        WhenResolvingVersions
        ThenResolvedVersion '1.1.100'
    }
}

Describe 'Get-InstalledDotNetSdk.when .NET SDK has multiple installed versions' {
    It 'resolves all versions' {
        Init
        GivenDotNetInstalled '1.1.140', '2.1.202', '2.1.525'
        WhenResolvingVersions
        ThenResolvedVersion '1.1.140', '2.1.202', '2.1.525'
    }
}

Describe 'Get-InstalledDotNetSdk.when .NET SDK has no installed versions' {
    It 'should return nothing and throw no errors' {
        Init
        WhenResolvingVersions
        $script:output | Should -BeNullOrEmpty
    }
}