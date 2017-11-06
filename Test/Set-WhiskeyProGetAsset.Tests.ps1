#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$apiKey = 'HKgaAKWjjgB9YRrTbTpHzw=='
$script:username = 'Admin'
$credential = New-Credential -UserName $username -Password $username
$script:taskParameter = @{ }
$script:taskParameter['uri'] = ('http://{0}:82/' -f $env:COMPUTERNAME)
$script:session = New-ProGetSession -Uri $TaskParameter['Uri'] -Credential $credential -ApiKey $apikey


function GivenContext
{
    $Script:Context = New-WhiskeyTestContext -ForBuildServer    
}
function GivenAsset {
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

    $feed = Test-ProGetFeed -Session $session -FeedName $directory -FeedType 'Asset'
    if( !$feed )
    {
        New-ProGetFeed -Session $session -FeedName $directory -FeedType 'Asset'
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
    $script:taskParameter['Name'] = $name
    $script:taskParameter['Directory'] = $directory
    $script:taskParameter['Path'] = (Join-Path -Path $TestDrive.FullName -ChildPath $FilePath)
    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $FilePath) -ItemType 'File' -Force
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
    $taskParameter['apiKey'] = $apiKey
    $taskParameter['proGetUsername'] = $username
    $taskParameter['proGetPassword'] = $username
    try{
        Invoke-WhiskeyTask -TaskContext $context -Parameter $taskParameter -Name 'SetProGetAsset' -ErrorAction SilentlyContinue
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
    It ('should not throw an error message') {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Set-WhiskeyProGetAsset.when Asset is uploaded correctly'{
    GivenContext
    GivenAsset -Name 'foo.txt' -directory 'bar' -FilePath 'foo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldExist -Name 'foo.txt' -directory 'bar'
    ThenTaskSucceeds
}

Describe 'Set-WhiskeyProGetAsset.when Asset does not exist'{
    GivenContext
    GivenAssetThatDoesntExist -Name 'fooboo.txt' -Directory 'bar' -FilePath 'fooboo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldNotExist -Name 'fooboo.txt' -directory 'bar'
    ThenTaskFails -ExpectedError 'Could Not find file named'
}

Describe 'Set-WhiskeyProGetAsset.when Asset Name parameter does not exist'{
    GivenContext
    GivenAssetThatDoesntExist -Directory 'bar' -FilePath 'fooboo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldNotExist -Name 'fooboo.txt' -directory 'bar'
    ThenTaskFails -ExpectedError 'Please add a valid Name to your whiskey.yml file'
}

Describe 'Set-WhiskeyProGetAsset.when Asset exists but proget directory does not exist'{
    GivenContext
    GivenAssetWithInvalidDirectory -Name 'foo.txt' -Directory 'foo' -FilePath 'foo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldNotExist -Name 'foo.txt' -directory 'foo' 
    ThenTaskFails -ExpectedError 'Asset Directory ''foo'' does not exist'
}

Describe 'Set-WhiskeyProGetAsset.when Asset already exists'{
    GivenContext
    GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'foo.txt'
    WhenAssetIsUploaded
    ThenAssetShouldExist -Name 'foo.txt' -directory 'bar'
    ThenTaskSucceeds
}

$assets = Get-ProGetAsset -Session $session -Directory 'bar'
foreach($asset in $assets)
{
    Remove-ProGetAsset -Session $session -Directory 'bar' -Name $asset.name
}
