
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Set-WhiskeyDotNetGlobalJson.ps1' -Resolve)

$globalJsonDirectory = $null
$sdkVersion = $null

function Init
{
    $Global:Error.Clear()
    $script:globalJsonDirectory = $TestDrive.FullName
    $script:sdkVersion = $null
}

function GivenExistingGlobalJson
{
    param(
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $globalJsonDirectory -ChildPath 'global.json')
}

function GivenSdkVersion
{
    param(
        $Version
    )

    $script:sdkVersion = $Version
}

function ThenError
{
    param(
        $Message
    )

    $Global:Error[0] | Should -Match $Message
}

function ThenGlobalJson
{
    param(
        $ExpectedJson
    )

    $globalJsonPath = Join-Path -Path $globalJsonDirectory -ChildPath 'global.json'

    $globalJson = Get-Content -Path $globalJsonPath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 100
    $ExpectedJson = $ExpectedJson | ConvertFrom-Json | ConvertTo-Json -Depth 100

    $globalJson | Should -Be $ExpectedJson
}

function WhenSettingGlobalJson
{
    [CmdletBinding()]
    param()

    Set-WhiskeyDotNetGlobalJson -Directory $globalJsonDirectory -SdkVersion $sdkVersion
}

Describe 'Set-WhiskeyDotNetGlobalJson.when globalJson root directory does not exist' {
    It 'should fail' {
        Init
        $script:globalJsonDirectory = 'a non existent directory'
        GivenSdkVersion '2.1.4'
        WhenSettingGlobalJson -ErrorAction SilentlyContinue
        ThenError 'does\ not\ exist\.'
    }
}

Describe 'Set-WhiskeyDotNetGlobalJson.when globalJson contains invalid JSON' {
    It 'should fail' {
        Init
        GivenExistingGlobalJson @"
    {
        "sdk": { "version": '1.0.0'
"@
        GivenSdkVersion '2.1.4'
        WhenSettingGlobalJson -ErrorAction SilentlyContinue
        ThenError 'contains\ invalid\ JSON.'
    }
}

Describe 'Set-WhiskeyDotNetGlobalJson.when globalJson does not exist' {
    It 'should create it' {
        Init
        GivenSdkVersion '2.1.4'
        WhenSettingGlobalJson
        ThenGlobalJson @"
{
    "sdk": {
        "version": "2.1.4"
    }
}
"@
    }
}

Describe 'Set-WhiskeyDotNetGlobalJson.when adding sdk property is missing from globalJson' {
    It 'should add it' {
        Init
        GivenExistingGlobalJson @"
{
    "name": "app"
}
"@
        GivenSdkVersion '2.1.4'
        WhenSettingGlobalJson
        ThenGlobalJson @"
{
    "name": "app",
    "sdk": {
        "version": "2.1.4"
    }
}
"@
    }
}

Describe 'Set-WhiskeyDotNetGlobalJson.when version property is missing from globalJson' {
    It 'should add it' {
        Init
        GivenExistingGlobalJson @"
{
    "name": "app",
    "sdk": {
        "foo": "bar"
    }
}
"@
        GivenSdkVersion '2.1.4'
        WhenSettingGlobalJson
        ThenGlobalJson @"
{
    "name": "app",
    "sdk": {
        "foo": "bar",
        "version": "2.1.4"
    }
}
"@
    }
}

Describe 'Set-WhiskeyDotNetGlobalJson.when sdk version exists in globalJson' {
    It 'should update the sdk property' {
        Init
        GivenExistingGlobalJson @"
{
    "name": "app",
    "sdk": {
        "foo": "bar",
        "version": "1.0.0"
    }
}
"@
        GivenSdkVersion '2.1.4'
        WhenSettingGlobalJson
        ThenGlobalJson @"
{
    "name": "app",
    "sdk": {
        "foo": "bar",
        "version": "2.1.4"
    }
}
"@
    }
}
