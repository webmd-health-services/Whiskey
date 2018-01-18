

#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$configuration = $null
$threwException = $false
$scope = $null

function GivenConfiguration
{
    param(
        $Configuration
    )

    $script:configuration = $Configuration
}

function GivenScope
{
    param(
        $Scope
    )

    $script:scope = $Scope
}

function Init
{
    $script:threwException = $false
    $script:configuration = $null
    $script:scope = $null
    $projectNpmrcPath = Join-Path -Path $TestDrive.FullName -ChildPath '.npmrc'
    if( (Test-Path -Path $projectNpmrcPath -PathType Leaf) )
    {
        Remove-Item -Path $projectNpmrcPath
    }
}

function ThenConfigNotSetAtProjectLevel
{
    It ('should not set project-level .npmrc') {
        Join-Path -Path $TestDrive.FullName -ChildPath '.npmrc' | Should -Not -Exist
    }
}

function ThenConfigNotSetAtProjectLevel
{
    It ('should not set config at the project level') {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $ArgumentList -notcontains '-userconfig' }
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $ArgumentList -notcontains '.npmrc' }
    }
}

function ThenConfigSetAtGlobalLevel
{
    It ('should set config in the user''s .npmrc file') {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $ArgumentList -contains '-g' }
    }
    ThenConfigNotSetAtProjectLevel
}

function ThenConfigSetAtUserLevel
{
    It ('should set config in the global .npmrc file') {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $ArgumentList -notcontains '-g' }
    }
    ThenConfigNotSetAtProjectLevel
}

function ThenNpmrcDoesNotExist
{
    It ('should set no configuration') {
        Join-Path -Path $TestDrive.FullName -ChildPath '.npmrc' | Should -Not -Exist
    }
}

function ThenNpmrcIs
{
    param(
        $ExpectedContent
    )

    It ('should set configuration') {
        GEt-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath '.npmrc') -Raw | Should -Be $ExpectedContent
    }
}

function ThenTaskFails
{
    param(
        $Message
    )

    It ('should throw an exception') {
        $threwException | Should -Be $true
        $Global:Error | Should -Match $Message
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
    )

    $Global:Error.Clear()

    $context = New-WhiskeyTestContext -ForDeveloper
    $parameter = @{ }
    if( $configuration )
    {
        $parameter['Configuration'] = $configuration
    }

    if( $scope )
    {
        $parameter['Scope'] = $scope
    }

    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name 'NpmConfig' -Parameter $parameter
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }
}

# All tests are in one Describe because it takes 15 seconds or so to setup Node. With one describe, we only pay that cost once instead of in every test.
Describe 'NpmConfig' {

    try
    {
        Install-Node

        Init
        GivenConfiguration @{ 'key1' = 'value1' ; 'key2' = 'value2' }
        WhenRunningTask
        ThenNpmrcIs @'
key1=value1
key2=value2

'@

        Init
        GivenScope 'Project'
        GivenConfiguration @{ 'key1' = 'value1' ; 'key2' = 'value2' }
        WhenRunningTask
        ThenNpmrcIs @'
key1=value1
key2=value2

'@

        Init
        WhenRunningTask
        ThenNpmrcDoesNotExist

        Init
        GivenConfiguration @{ }
        WhenRunningTask
        ThenNpmrcDoesNotExist

        Init
        GivenConfiguration 'string'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFails 'Configuration\ property\ is\ invalid'

        Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey'
        Init
        GivenConfiguration @{ 'key1' = 'value1' }
        GivenScope 'User'
        WhenRunningTask
        ThenConfigNotSetAtProjectLevel
        ThenConfigSetAtUserLevel

        Init
        GivenConfiguration @{ 'key1' = 'value1' }
        GivenScope 'Global'
        WhenRunningTask
        ThenConfigNotSetAtProjectLevel
        ThenConfigSetAtGlobalLevel

        Init
        GivenConfiguration @{ 'key1' = 'value1' }
        GivenScope 'Fubar'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFails 'Scope\ property\ ''Fubar''\ is\ invalid'
    }
    finally
    {
        Remove-Node
    }
}