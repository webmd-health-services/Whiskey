
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

    It 'should write an error' {
        $Global:Error[0] | Should -Match $Message
    }
}

function ThenGlobalJson
{
    param(
        $ExpectedJson
    )

    $globalJsonPath = Join-Path -Path $globalJsonDirectory -ChildPath 'global.json'

    $globalJson = Get-Content -Path $globalJsonPath -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 100
    $ExpectedJson = $ExpectedJson | ConvertFrom-Json | ConvertTo-Json -Depth 100

    It 'should update global.json' {
        $globalJson | Should -Be $ExpectedJson
    }
}

function WhenSettingGlobalJson
{
    [CmdletBinding()]
    param()

    Set-WhiskeyDotNetGlobalJson -Directory $globalJsonDirectory -SDKVersion $sdkVersion
}

Describe 'Set-WhiskeyDotNetGlobalJson.when global.json root directory does not exist' {
    Init
    $script:globalJsonDirectory = 'a non existent directory'
    GivenSdkVersion '2.1.4'
    WhenSettingGlobalJson -ErrorAction SilentlyContinue
    ThenError 'does\ not\ exist\.'
}

Describe 'Set-WhiskeyDotNetGlobalJson.when global.json contains invalid JSON' {
    Init
    GivenExistingGlobalJson @"
    {
        "sdk": { "version": '1.0.0'
"@
    GivenSdkVersion '2.1.4'
    WhenSettingGlobalJson -ErrorAction SilentlyContinue
    ThenError 'contains\ invalid\ JSON.'
}

Describe 'Set-WhiskeyDotNetGlobalJson.when global.json does not exist' {
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

Describe 'Set-WhiskeyDotNetGlobalJson.when adding ''sdk'' property to existing global.json' {
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

Describe 'Set-WhiskeyDotNetGlobalJson.when adding ''version'' property to existing global.json' {
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

Describe 'Set-WhiskeyDotNetGlobalJson.when updating existing sdk version in global.json' {
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
