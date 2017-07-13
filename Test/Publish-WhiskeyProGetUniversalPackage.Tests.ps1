
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$progetUri = $null
$credentialID = $null
$credential = $null
$feedName = $null
$path = $null
$threwException = $false

function GivenNoPath
{
    $script:path = $null
}

function GivenPath
{
    param(
        $Path
    )

    $script:path = $Path
}

function GivenProGetIsAt
{
    param(
        $Uri
    )

    $script:progetUri = $Uri
}

function GivenCredential
{
    param(
        [Parameter(Mandatory=$true,Position=0)]
        $Credential,

        [Parameter(Mandatory=$true)]
        $WithID
    )

    $password = ConvertTo-SecureString -AsPlainText -Force -String $Credential
    $script:credential = New-Object 'Management.Automation.PsCredential' $Credential,$password
    $script:credentialID = $WithID
}

function GivenNoParameters
{
    $script:credentialID = $null
    $script:feedName = $null
    $script:path = $null
    $script:progetUri = $null
    $script:credential = $null
}

function GivenUniversalFeed
{
    param(
        $Named
    )

    $script:feedName = $Named
}

function GivenUpackFile
{
    param(
        $Name
    )

    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath ('.output\{0}' -f $Name)) -Force -ItemType 'File'
}

function ThenPackageNotPublished
{
    param(
        $FileName
    )

    It ('should not publish file ''.output\{0}''' -f $FileName) {
        Assert-MockCalled -CommandName 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -ParameterFilter { $PackagePath -eq (Join-Path -Path $TestDrive.FullName -ChildPath ('.output\{0}' -f $FileName)) } -Times 0
    }
}

function ThenPackagePublished
{
    param(
        $FileName
    )

    It ('should publish file ''.output\{0}''' -f $FileName) {
        Assert-MockCalled -CommandName 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -ParameterFilter { $PackagePath -eq (Join-Path -Path $TestDrive.FullName -ChildPath ('.output\{0}' -f $FileName)) }
    }
}

function ThenPackagePublishedAs
{
    param(
        $Credential
    )

    It ('should publish as ''{0}''' -f $Credential) {
        Assert-MockCalled -CommandName 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.Credential.UserName -eq $Credential }
        Assert-MockCalled -CommandName 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.Credential.GetNetworkCredential().Password -eq $Credential }
    }
}

function ThenPackagePublishedAt
{
    param(
        $Uri
    )

    It ('should publish to ''{0}''' -f $Uri) {
        Assert-MockCalled -CommandName 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Uri  expected  {0}' -f $Uri)
            Write-Debug -Message ('     actual    {0}' -f $Session.Uri)
            $session | Format-List | Out-String | Write-Debug
            $Session.Uri -eq $Uri
        }
    }
}

function ThenPackagePublishedToFeed
{
    param(
        $Named
    )

    It ('should publish to feed ''{0}''' -f $Named) {
        Assert-MockCalled -CommandName 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey' -ParameterFilter { $FeedName -eq $Named }
    }
}

function ThenTaskFailed
{
    param(
        $Pattern
    )

    It ('the task should throw an exception') {
        $threwException | Should -Be $true
    }

    It ('the exception should match /{0}/' -f $Pattern) {
        $Global:Error | Should -Match $Pattern
    }
}

function WhenPublishingPackage
{
    [CmdletBinding()]
    param(
    )

    $context = [pscustomobject]@{
                                    BuildRoot = $TestDrive.FullName;
                                    Credentials = @{ }
                                    OutputDirectory = (Join-Path -Path $TestDrive.FullName -ChildPath '.output')
                                    TaskIndex = 1;
                                    TaskName = 'PublishProGetUniversalPackage';
                                    ConfigurationPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml'
                                }
    $parameter = @{ }

    if( $credentialID )
    {
        $parameter['CredentialID'] = $credentialID
        if( $credential )
        {
            $context.Credentials[$credentialID] = $credential
        }
    }

    if( $progetUri )
    {
        $parameter['Uri'] = $progetUri
    }

    if( $feedName )
    {
        $parameter['FeedName'] = $feedName
    }

    if( $path )
    {
        $parameter['Path'] = $path
    }

    Mock -CommandName 'Publish-ProGetUniversalPackage' -ModuleName 'Whiskey'

    $script:threwException = $false
    try
    {
        $Global:Error.Clear()
        Publish-WhiskeyProGetUniversalPackage -TaskContext $context -TaskParameter $parameter
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'Publish-WhiskeyProGetUniversalPackage.when user publishes default files' {
    GivenUpackFile 'myfile1.upack'
    GivenUpackFile 'myfile2.upack'
    GivenProGetIsAt 'my uri'
    GivenCredential 'fubar' -WithID 'progetid'
    GivenUniversalFeed 'universalfeed'
    WhenPublishingPackage
    ThenPackagePublished 'myfile1.upack'
    ThenPackagePublished 'myfile2.upack'
    ThenPackagePublishedAt 'my uri'
    ThenPackagePublishedToFeed 'universalfeed'
    ThenPackagePublishedAs 'fubar'
}

Describe 'Publish-WhiskeyProGetUniversalPackage.when user specifies files to publish' {
    GivenUpackFile 'myfile1.upack'
    GivenUpackFile 'myfile2.upack'
    GivenProGetIsAt 'my uri'
    GivenCredential 'fubar' -WithID 'progetid'
    GivenUniversalFeed 'universalfeed'
    GivenPath '.output\myfile1.upack'
    WhenPublishingPackage
    ThenPackagePublished 'myfile1.upack'
    ThenPackageNotPublished 'myfile2.upack'
}

Describe 'Publish-WhiskeyProGetUniversalPackage.when CredentialID parameter is missing' {
    GivenNoParameters
    WhenPublishingPackage -ErrorAction SilentlyContinue
    ThenTaskFailed '\bCredentialID\b.*\bis\ a\ mandatory\b'
}

Describe 'Publish-WhiskeyProGetUniversalPackage.when Uri parameter is missing' {
    GivenNoParameters
    GivenCredential 'somecredential' -WithID 'fubar'
    WhenPublishingPackage -ErrorAction SilentlyContinue
    ThenTaskFailed '\bUri\b.*\bis\ a\ mandatory\b'
}

Describe 'Publish-WhiskeyProGetUniversalPackage.when FeedName parameter is missing' {
    GivenNoParameters
    GivenCredential 'somecredential' -WithID 'fubar'
    GivenProGetIsAt 'some uri'
    WhenPublishingPackage -ErrorAction SilentlyContinue
    ThenTaskFailed '\bFeedName\b.*\bis\ a\ mandatory\b'
}

Describe 'Publish-WhiskeyProGetUniversalPackage.when there is no upack files' {
    GivenProGetIsAt 'my uri'
    GivenCredential 'fubatr' -WithID 'id'
    GivenUniversalFeed 'universal'
    WhenPublishingPackage -ErrorAction SilentlyContinue
    ThenTaskFailed 'no packages'
}