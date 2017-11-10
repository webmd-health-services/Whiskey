#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$script:username = 'testusername'
$script:apikey = 'testapikey'
$script:apiKeyID = 'testApiid'
$script:credentialID = 'TestCredential'

function GivenContext
{
    $script:taskParameter = @{ }
    $script:taskParameter['uri'] = 'TestURI'
    $script:session = New-ProGetSession -Uri $TaskParameter['Uri']
    $Global:globalTestSession = $session
    $Script:Context = New-WhiskeyTestContext -ForBuildServer -forTaskname 'PublishProGetAsset'
    Mock -CommandName 'New-ProGetSession' -ModuleName 'Whiskey' -MockWith { return $globalTestSession }
    Mock -CommandName 'Set-ProGetAsset' -ModuleName 'Whiskey' -MockWith { return $true }
}

function GivenCredentials
{
    $password = ConvertTo-SecureString -AsPlainText -Force -String $username
    $script:credential = New-Object 'Management.Automation.PsCredential' $username,$password
    Add-WhiskeyCredential -Context $context -ID $credentialID -Credential $credential
    Add-WhiskeyApiKey -Context $context -ID $apiKeyID -value $apiKey 

    $taskParameter['CredentialID'] = $credentialID
    $taskParameter['ApiKeyID'] = $apiKeyID
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
    $script:taskParameter['Name'] = $name
    $script:taskParameter['Directory'] = $directory
    $script:taskParameter['Path'] = @()
    foreach($file in $FilePath){
        $script:taskParameter['Path'] += (Join-Path -Path $TestDrive.FullName -ChildPath $file)
        New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $file) -ItemType 'File' -Force
    }
}

function GivenAssetWithoutName
{
    param(
        [string]
        $directory,
        [string[]]
        $FilePath
    )
    $script:taskParameter['Directory'] = $directory
    $script:taskParameter['Path'] = @()
    foreach($file in $FilePath){
        $script:taskParameter['Path'] += (Join-Path -Path $TestDrive.FullName -ChildPath $file)
        New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $file) -ItemType 'File' -Force
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
    $script:taskParameter['Directory'] = $directory
    $script:taskParameter['Path'] = (Join-Path -Path $TestDrive.FullName -ChildPath $FilePath)
    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $FilePath) -ItemType 'File' -Force
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
    $script:taskParameter['Name'] = $name
    $script:taskParameter['Directory'] = $directory
    $script:taskParameter['Path'] = $TestDrive.FullName,$FilePath -join '\'
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
    It ('should fail with error message that matches ''{0}''' -f $ExpectedError) {
        $Global:Error | Where-Object {$_ -match $ExpectedError } |  Should -not -BeNullOrEmpty
    }
}

function ThenAssetShouldExist
{
    param(
        [string[]]
        $AssetName
    )
    foreach( $file in $AssetName ){
        it ('should contain the file {0}' -f $file) {
            Assert-mockCalled -CommandName 'Set-ProGetAsset' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $file }.getNewClosure()
        }
    }
}

function ThenAssetShouldNotExist
{
    param(
        [string[]]
        $AssetName
    )
    foreach( $file in $AssetName ){
        it ('should not contain the file {0}' -f $file) {
            Assert-mockCalled -CommandName 'Set-ProGetAsset' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $file } -Times 0
        }
    }
}

function ThenTaskSucceeds 
{
    It ('should not throw an error message') {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Publish-WhiskeyProGetAsset.when Asset is uploaded correctly'{
    GivenContext
    GivenCredentials
    GivenAsset -Name 'foo.txt' -directory 'bar' -FilePath 'foo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldExist -AssetName 'foo.txt'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyProGetAsset.when multiple Assets are uploaded correctly'{
    GivenContext
    GivenCredentials
    GivenAsset -Name 'foo.txt','bar.txt' -directory 'bar' -FilePath 'foo.txt','bar.txt'
    WhenAssetIsUploaded
    ThenAssetShouldExist -AssetName 'foo.txt','bar.txt' 
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyProGetAsset.when Asset Name parameter does not exist'{
    GivenContext
    GivenCredentials
    GivenAssetWithoutName -Directory 'bar' -FilePath 'fooboo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldExist -AssetName 'fooboo.txt'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyProGetAsset.when there are less names than paths'{
    GivenContext
    GivenCredentials
    GivenAssetWithoutName -name 'singlename' -Directory 'bar' -FilePath 'fooboo.txt','bar.txt'
    WhenAssetIsUploaded
    ThenAssetShouldExist -AssetName 'fooboo.txt','bar.txt'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyProGetAsset.when there are less paths than names'{
    GivenContext
    GivenCredentials
    GivenAssetWithoutName -name 'multiple','names' -Directory 'bar' -FilePath 'fooboo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldExist -AssetName 'fooboo.txt'
    ThenTaskSucceeds
}

Describe 'Publish-WhiskeyProGetAsset.when credentials are not given'{
    GivenContext
    GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'fooboo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldNotExist -AssetName 'foo.txt'
    ThenTaskFails -ExpectedError 'CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet'
}

Describe 'Publish-WhiskeyProGetAsset.when Asset already exists'{
    GivenContext
    GivenCredentials
    GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'foo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldExist -AssetName 'foo.txt'
    ThenTaskSucceeds
}