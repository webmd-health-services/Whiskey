
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$apiKeys = @{ }

function GivenApiKey
{
    param(
        $Name,
        $Value
    )

    $apiKeys[$Name] = $Value
}

function GivenAssetUploaded
{
    Mock -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { $Uri -like '*/assets?*' }
}

function GivenFile
{
    param(
        $Path,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Path)
}

function GivenReleaseCreated
{
    param(
        $ExpectedContent
    )

    Mock -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' `
         -ParameterFilter ([scriptblock]::Create("`$Uri -like '*/releases' -and `$Method -eq 'POST'")) `
         -MockWith ([scriptblock]::create("'$ExpectedContent' | ConvertFrom-Json"))
}

function GivenReleaseDoesNotExist
{
    param(
        $Tag
    )

    Mock -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter ([scriptblock]::create("`$Uri -like '*/releases/tags/$Tag'"))
}

function GivenReleaseExists
{
    param(
        $Tag,
        $Release
    )

    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter ([scriptblock]::create("`$Uri -like '*/releases/tags/$Tag'")) `
         -MockWith ([scriptblock]::Create("'$Release' | ConvertFrom-Json"))
    Mock -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' `
         -ParameterFilter ([scriptblock]::Create("`$Uri -like '*/releases' -and `$Method -eq 'Patch'")) `
         -MockWith ([scriptblock]::create("'$Release' | ConvertFrom-Json"))
}

function GivenWhiskeyYml
{
    param(
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
}

function Init
{
    $apiKeys = @{ }
    $commit = $null
}

function ThenRequest
{
    param(
        [Parameter(Mandatory=$true)]
        $Should,

        [Parameter(Mandatory=$true)]
        $ToUri,

        [Microsoft.PowerShell.Commands.WebRequestMethod]
        $UsedMethod,

        $WithBody,

        $AsContentType,

        $WithFile
    )

    It ('should {0}' -f $Should) {
        if( $WithBody )
        {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { 
                $DebugPreference = 'Continue'
                Write-Debug ('Uri   expected  {0}' -f $ToUri)
                Write-Debug ('      actual    {0}' -f $Uri)
                Write-Debug ('Body  expected  {0}' -f $WithBody)
                Write-Debug ('      actual    {0}' -f $Body)
                $Uri -eq $ToUri -and $Body -eq $WithBody 
            }
        }

        if( $UsedMethod )
        {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { 
                $DebugPreference = 'Continue'
                Write-Debug ('Uri     expected  {0}' -f $ToUri)
                Write-Debug ('        actual    {0}' -f $Uri)
                Write-Debug ('Method  expected  {0}' -f $UsedMethod)
                Write-Debug ('        actual    {0}' -f $Method)
                $Uri -eq $ToUri -and $Method -eq $UsedMethod 
            }
        }

        if( $AsContentType )
        {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { 
                $DebugPreference = 'Continue'
                Write-Debug ('Uri          expected  {0}' -f $ToUri)
                Write-Debug ('             actual    {0}' -f $Uri)
                Write-Debug ('ContentType  expected  {0}' -f $AsContentType)
                Write-Debug ('             actual    {0}' -f $ContentType)
                $Uri -eq $ToUri -and $ContentType -eq $AsContentType 
            }
        }

        if( $WithFile )
        {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { 
                $DebugPreference = 'Continue'
                Write-Debug ('Uri     expected  {0}' -f $ToUri)
                Write-Debug ('        actual    {0}' -f $Uri)
                $WithFile = Join-Path -Path $TestDrive.FullName -ChildPath $WithFile
                Write-Debug ('InFile  expected  {0}' -f $WithFile)
                Write-Debug ('        actual    {0}' -f $InFile)
                $Uri -eq $ToUri -and $InFile -eq $WithFile 
            }
        }
    }
}

function ThenSecurityProtocol
{
    param(
        $HasFlag
    )

    It ('should enable Tls12'){
        [System.Net.ServicePointManager]::SecurityProtocol.HasFlag($HasFlag) | Should -Be $true
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        $OnCommit
    )

    $Global:Error.Clear()

    $script:failed = $false
    try
    {
        [Whiskey.Context]$context = New-WhiskeyTestContext -ForDeveloper -ConfigurationPath (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
        foreach( $key in $apiKeys.Keys )
        {
            Add-WhiskeyApiKey -Context $context -ID $key -Value $apiKeys[$key]
        }
        $context.BuildMetadata.ScmCommitID = $OnCommit
        $parameter = $context.Configuration['Build'] | Where-Object { $_.ContainsKey('GitHubRelease') } | ForEach-Object { $_['GitHubRelease'] }
        Invoke-WhiskeyTask -TaskContext $context -Name 'GitHubRelease' -Parameter $parameter
        $script:context = $context

        It ('should check if release exists') {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { $Uri -like ('*/releases/tags/{0}' -f $parameter['Tag']) }
        }
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $script:failed = $true
    }
}

Describe 'GitHubRelease.when the release doesn''t exist' {
    Init
    GivenApiKey 'github.com' 'fubarsnafu'
    GivenWhiskeyYml @'
Build:
- GitHubRelease:
    ApiKeyID: github.com
    RepositoryName: webmd-health-services/Whiskey
    Tag: 0.0.0-rc.1
    Name: My Release
    Description: Release Notes
    Assets:
    - Path: Whiskey.zip
      ContentType: fubar/snafu
      Name: ZIP
'@
    GivenFile 'Whiskey.zip' 'WHISKEY_ZIP_FILE'
    GivenReleaseDoesNotExist '0.0.0-rc.1'
    GivenReleaseCreated '
{
    "upload_url": "https://api.github.com/webmd-health-services/Whiskey/releases/0/assets{?name,label}"
}
'
    GivenAssetUploaded
    WhenRunningTask -OnCommit 'deadbee'
    ThenSecurityProtocol -HasFlag ([System.Net.SecurityProtocolType]::Tls12)
    ThenRequest -Should 'create release' `
                -ToUri 'https://api.github.com/repos/webmd-health-services/Whiskey/releases' `
                -UsedMethod Post `
                -AsContentType 'application/json' `
                -WithBody @'
{
    "target_commitish":  "deadbee",
    "body":  "Release Notes",
    "tag_name":  "0.0.0-rc.1",
    "name":  "My Release"
}
'@
    ThenRequest -Should 'upload asset' `
                -ToUri 'https://api.github.com/webmd-health-services/Whiskey/releases/0/assets?name=Whiskey.zip&label=ZIP' `
                -UsedMethod Post `
                -AsContentType 'fubar/snafu' `
                -WithFile 'Whiskey.zip'
}


Describe 'GitHubRelease.when the release exists' {
    Init
    GivenApiKey 'github.com' 'fubarsnafu'
    GivenWhiskeyYml @'
Build:
- GitHubRelease:
    ApiKeyID: github.com
    RepositoryName: webmd-health-services/Whiskey
    Tag: 0.0.0-rc.1
    Assets:
    - Path: Whiskey.zip
      ContentType: fubar/snafu
      Name: ZIP
'@
    GivenFile 'Whiskey.zip'
    GivenReleaseExists '0.0.0-rc.1' '
{
    "upload_url": "https://api.github.com/webmd-health-services/Whiskey/releases/0/assets{?name,label}"
}
'
    GivenAssetUploaded
    WhenRunningTask -OnCommit 'deadbee'
    ThenSecurityProtocol -HasFlag ([System.Net.SecurityProtocolType]::Tls12)
    ThenRequest -Should 'edit release' `
                -ToUri 'https://api.github.com/repos/webmd-health-services/Whiskey/releases' `
                -UsedMethod Patch `
                -AsContentType 'application/json' `
                -WithBody @'
{
    "tag_name":  "0.0.0-rc.1",
    "target_commitish":  "deadbee"
}
'@
    ThenRequest -Should 'upload asset' `
                -ToUri 'https://api.github.com/webmd-health-services/Whiskey/releases/0/assets?name=Whiskey.zip&label=ZIP' `
                -UsedMethod Post `
                -AsContentType 'fubar/snafu' `
                -WithFile 'Whiskey.zip'
}