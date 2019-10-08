
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$username = 'testusername'
$credentialID = 'TestCredential'

function GivenContext
{
    $script:taskParameter = @{ }
    $script:taskParameter['Uri'] = 'TestURI'
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\ProGetAutomation' -Resolve)
    $script:session = New-ProGetSession -Uri $TaskParameter['Uri']
    $Global:globalTestSession = $session
    $Script:Context = New-WhiskeyTestContext -ForBuildServer `
                                             -ForTaskName 'PublishProGetAsset' `
                                             -ForBuildRoot $testRoot `
                                             -IncludePSModule 'ProGetAutomation'
    Mock -CommandName 'New-ProGetSession' -ModuleName 'Whiskey' -MockWith { return $globalTestSession }
    Mock -CommandName 'Set-ProGetAsset' -ModuleName 'Whiskey' -MockWith { return $true }
}

function GivenCredentials
{
    $password = ConvertTo-SecureString -AsPlainText -Force -String $username
    $script:credential = New-Object 'Management.Automation.PsCredential' $username,$password
    Add-WhiskeyCredential -Context $context -ID $credentialID -Credential $credential

    $taskParameter['CredentialID'] = $credentialID
}

function GivenAsset
{
    param(
        [string[]]
        $Name,
        [string]
        $directory,
        [string[]]
        $FilePath
    )
    $script:taskParameter['AssetPath'] = $name
    $script:taskParameter['AssetDirectory'] = $directory
    $script:taskParameter['Path'] = @()
    foreach($file in $FilePath){
        $script:taskParameter['Path'] += (Join-Path -Path $testRoot -ChildPath $file)
        New-Item -Path (Join-Path -Path $testRoot -ChildPath $file) -ItemType 'File' -Force
    }
}

function GivenAssetWithInvalidDirectory
{
    param(
        [string]
        $Name,
        [string]
        $directory,
        [string]
        $FilePath
    )
    # $script:taskParameter['Name'] = $name
    $script:taskParameter['AssetDirectory'] = $directory
    $script:taskParameter['Path'] = (Join-Path -Path $testRoot -ChildPath $FilePath)
    New-Item -Path (Join-Path -Path $testRoot -ChildPath $FilePath) -ItemType 'File' -Force
    Mock -CommandName 'Test-ProGetFeed' -ModuleName 'Whiskey' -MockWith { return $false }
}

function GivenAssetThatDoesntExist
{
    param(
        [string]
        $Name,
        [string]
        $directory,
        [string]
        $FilePath

    )
    $script:taskParameter['AssetPath'] = $name
    $script:taskParameter['AssetDirectory'] = $directory
    $script:taskParameter['Path'] = $testRoot,$FilePath -join '\'
}

function Init
{
    $script:testRoot = New-WhiskeyTestRoot
    Remove-Module -Name 'ProGetAutomation' -Force -ErrorAction Ignore
}

function Reset
{
    Reset-WhiskeyTestPSModule
}
function WhenAssetIsUploaded
{
    $Global:Error.Clear()
    $script:threwException = $false

    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'PublishProGetAsset' -ErrorAction SilentlyContinue
    }
    catch
    {
        $script:threwException = $true
    }
}

function ThenTaskFails 
{
    Param(
        [String]
        $ExpectedError
    )
    $Global:Error | Where-Object {$_ -match $ExpectedError } |  Should -Not -BeNullOrEmpty
}

function ThenAssetShouldExist
{
    param(
        [string[]]
        $AssetName
    )
    foreach( $file in $AssetName ){
        Assert-mockCalled -CommandName 'Set-ProGetAsset' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq $file }.getNewClosure()
    }
}

function ThenAssetShouldNotExist
{
    param(
        [string[]]
        $AssetName
    )
    foreach( $file in $AssetName ){
        Assert-mockCalled -CommandName 'Set-ProGetAsset' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $file } -Times 0
    }
}

function ThenTaskSucceeds 
{
    $Global:Error | Should -BeNullOrEmpty
}

Describe 'PublishProGetAsset.when Asset is uploaded' {
    AfterEach { Reset }
    It 'should upload the asset' {
        Init
        GivenContext
        GivenCredentials
        GivenAsset -Name 'foo.txt' -directory 'bar' -FilePath 'foo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldExist -AssetName 'foo.txt'
        ThenTaskSucceeds
    }
}

Describe 'PublishProGetAsset.when Asset is uploaded to a subdirectory' {
    AfterEach { Reset }
    It 'should upload into the sub-directory' {
        Init
        GivenContext
        GivenCredentials
        GivenAsset -Name 'boo/foo.txt' -directory 'bar' -FilePath 'foo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldExist -AssetName 'boo/foo.txt'
        ThenTaskSucceeds
    }
}

Describe 'PublishProGetAsset.when multiple Assets are uploaded'{
    AfterEach { Reset }
    It 'should upload all the assets' {
        Init
        GivenContext
        GivenCredentials
        GivenAsset -Name 'foo.txt','bar.txt' -directory 'bar' -FilePath 'foo.txt','bar.txt'
        WhenAssetIsUploaded
        ThenAssetShouldExist -AssetName 'foo.txt','bar.txt' 
        ThenTaskSucceeds
    }
}

Describe 'PublishProGetAsset.when Asset Name parameter does not exist'{
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenContext
        GivenCredentials
        GivenAsset -Directory 'bar' -FilePath 'fooboo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldNotExist -AssetName 'fooboo.txt'
        ThenTaskFails -ExpectedError 'There must be the same number of Path items as AssetPath Items. Each Asset must have both a Path and an AssetPath in the whiskey.yml file.'    
    }
}

Describe 'PublishProGetAsset.when there are less names than paths'{
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenContext
        GivenCredentials
        GivenAsset -name 'singlename' -Directory 'bar' -FilePath 'fooboo.txt','bar.txt'
        WhenAssetIsUploaded
        ThenAssetShouldNotExist -AssetName 'fooboo.txt','bar.txt'
        ThenTaskFails -ExpectedError 'There must be the same number of Path items as AssetPath Items. Each Asset must have both a Path and an AssetPath in the whiskey.yml file.'
    }
}

Describe 'PublishProGetAsset.when there are less paths than names'{
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenContext
        GivenCredentials
        GivenAsset -name 'multiple','names' -Directory 'bar' -FilePath 'fooboo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldNotExist -AssetName 'fooboo.txt'
        ThenTaskFails -ExpectedError 'There must be the same number of Path items as AssetPath Items. Each Asset must have both a Path and an AssetPath in the whiskey.yml file.'
    }
}

Describe 'PublishProGetAsset.when credentials are not given'{
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenContext
        GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'fooboo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldNotExist -AssetName 'foo.txt'
        ThenTaskFails -ExpectedError 'CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet'
    }
}

Describe 'PublishProGetAsset.when Asset already exists'{
    AfterEach { Reset }
    It 'should replace the asset' {
        Init
        GivenContext
        GivenCredentials
        GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'foo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldExist -AssetName 'foo.txt'
        ThenTaskSucceeds
    }
}
