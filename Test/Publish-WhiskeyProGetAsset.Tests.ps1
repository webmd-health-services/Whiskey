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
        [string]
        $Name,
        [string]
        $directory,
        [string]
        $FilePath
    )
    $script:taskParameter['Name'] = $name
    $script:taskParameter['Directory'] = $directory
    $script:taskParameter['Path'] = (Join-Path -Path $TestDrive.FullName -ChildPath $FilePath)
    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $FilePath) -ItemType 'File' -Force
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
    $script:taskParameter['Name'] = $name
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
    write-host $Global:Error
    It ('should fail with error message that matches ''{0}''' -f $ExpectedError) {
        $Global:Error | Where-Object {$_ -match $ExpectedError } |  Should -not -BeNullOrEmpty
    }
}

function ThenAssetShouldExist
{
    param(
        [string]
        $Name
    )
    it ('should contain the file {0}' -f $Name) {
        Get-ProGetAsset -session $session -Directory $TaskParameter['Directory'] | Where-Object { $_.name -match $name } | should -not -BeNullOrEmpty
    }
}

function ThenAssetShouldNotExist
{
    param(
        [string]
        $Name,
        [string]
        $directory
    )
    it ('should not contain the file {0}' -f $Name) {
        Get-ProGetAsset -session $session -Directory $directory| Where-Object { $_.name -match $name } | should -match '' 
    }
}

function ThenTaskSucceeds 
{
    write-host $Global:Error
    It ('should not throw an error message') {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Publish-WhiskeyProGetAsset.when Asset is uploaded correctly'{
    GivenContext
    GivenCredentials
    GivenAsset -Name 'foo.txt' -directory 'bar' -FilePath 'foo.txt'
    WhenAssetIsUploaded
    ThenTaskSucceeds
}
Describe 'Publish-WhiskeyProGetAsset.when Asset Name parameter does not exist'{
    GivenContext
    GivenCredentials
    GivenAssetThatDoesntExist -Directory 'bar' -FilePath 'fooboo.txt'
    WhenAssetIsUploaded
    ThenTaskFails -ExpectedError 'Please add a valid Name to your whiskey.yml file'
}

Describe 'Publish-WhiskeyProGetAsset.when credentials are not given'{
    GivenContext
    GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'fooboo.txt'
    WhenAssetIsUploaded
    ThenTaskFails -ExpectedError 'CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet'
}

Describe 'Publish-WhiskeyProGetAsset.when Asset already exists'{
    GivenContext
    GivenCredentials
    GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'foo.txt'
    WhenAssetIsUploaded
    ThenTaskSucceeds
}