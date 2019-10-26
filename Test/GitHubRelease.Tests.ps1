
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$apiKeys = @{ }
$failed = $false

function GivenApiKey
{
    param(
        $Name,
        $Value
    )

    $apiKeys[$Name] = $Value
}

function GivenAssets
{
    param(
        $Asset
    )

    $assetJson = ConvertTo-Json -InputObject $Asset
    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { 
             #$DebugPreference = 'Continue'
             Write-Debug ('Uri  {0}' -f $Uri)
             Write-Debug ('     */releases/*/assets')
             $result = $Uri -like '*/releases/*/assets' 
             Write-Debug ('     {0}' -f $result)
             return $result
            } `
         -MockWith ([scriptblock]::Create("'$assetJson' | ConvertFrom-Json"))
}

function GivenAssetUpdated
{
    param(
        [Parameter(Mandatory)]
        $To
    )

    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter ([scriptblock]::Create("`$Uri -like '$To'"))
}

function GivenAssetUploaded
{
    param(
        [Parameter(Mandatory)]
        $To
    )

    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter ([scriptblock]::Create("`$Uri -like '$To'"))
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

    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter ([scriptblock]::Create("`$Uri -like '*/releases' -and `$Method -eq 'POST'")) `
         -MockWith ([scriptblock]::create("'$ExpectedContent' | ConvertFrom-Json"))
}

function GivenReleaseDoesNotExist
{
    param(
        $Tag
    )

    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter ([scriptblock]::create("`$Uri -like '*/releases/tags/$Tag'")) `
         -MockWith { throw 'Not Found!' }
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
         -ParameterFilter ([scriptblock]::Create("`$Uri -like '*/releases*' -and `$Method -eq 'Patch'")) `
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
    $script:apiKeys = @{ }
}

function ThenAssetNotUploadedTo
{
    param(
        $Uri
    )

    It ('should not upload any assets') {
        $toUri = $Uri
        Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { 
            #$DebugPreference = 'Continue'
            Write-Debug ('Uri   expected  {0}' -f $toUri)
            Write-Debug ('      actual    {0}' -f $Uri)
            $Uri -eq [Uri]$toUri
        }
    }
}

function ThenError
{
    param(
        $Matches
    )

    It ('should write an error') {
        $Global:Error | Should -Match $Matches
    }
}

function ThenNoApiCalled
{
    It ('should not call the GitHub API') {
        Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -Times 0
    }
}

function ThenRequest
{
    param(
        [Parameter(Mandatory)]
        $Should,

        [Parameter(Mandatory)]
        $ToUri,

        [Microsoft.PowerShell.Commands.WebRequestMethod]$UsedMethod,

        $WithBody,

        $AsContentType,

        $WithFile
    )

    It ('should {0}' -f $Should) {
        if( $WithBody )
        {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { 
                #$DebugPreference = 'Continue'
                Write-Debug ('')
                Write-Debug ('Uri   expected  {0}' -f $ToUri)
                Write-Debug ('      actual    {0}' -f $Uri)
                $uriEqual = $Uri -eq [Uri]$ToUri
                Write-Debug ('                {0}' -f $uriEqual)
                Write-Debug ('Body  expected  {0}' -f $WithBody)
                Write-Debug ('      actual    {0}' -f $Body)
                $bodyEqual = $Body -eq $WithBody 
                $WithBody = $WithBody | ConvertFrom-Json
                $expectedProps = $WithBody | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty 'Name' | Sort-Object
                $actualProps = @()
                if( $Body )
                {
                    $Body = $Body | ConvertFrom-Json
                    $actualProps = $Body | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty 'Name' | Sort-Object
                }
                $bodyPropsEqual = ($expectedProps -join '|') -eq ($actualProps -join '|')
                Write-Debug ('                {0}' -f $bodyPropsEqual)
                
                $expectedValues = $expectedProps | ForEach-Object { $WithBody.$_ }
                $actualValues = $actualProps | ForEach-Object { $Body.$_ }
                $bodyValuesEqual = ($expectedValues -join '|') -eq ($actualValues -join '|')
                Write-Debug ('                {0}' -f $bodyValuesEqual)
                Write-Debug ('')
                $uriEqual -and $bodyPropsEqual -and $bodyValuesEqual
            }
        }

        if( $UsedMethod )
        {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { 
                #$DebugPreference = 'Continue'
                Write-Debug ('Uri     expected  {0}' -f $ToUri)
                Write-Debug ('        actual    {0}' -f $Uri)
                Write-Debug ('Method  expected  {0}' -f $UsedMethod)
                Write-Debug ('        actual    {0}' -f $Method)
                $Uri -eq [Uri]$ToUri -and $Method -eq $UsedMethod 
            }
        }

        if( $AsContentType )
        {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { 
                #$DebugPreference = 'Continue'
                Write-Debug ('Uri          expected  {0}' -f $ToUri)
                Write-Debug ('             actual    {0}' -f $Uri)
                Write-Debug ('ContentType  expected  {0}' -f $AsContentType)
                Write-Debug ('             actual    {0}' -f $ContentType)
                $Uri -eq [Uri]$ToUri -and $ContentType -eq $AsContentType 
            }
        }

        if( $WithFile )
        {
            Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -ParameterFilter { 
                #$DebugPreference = 'Continue'
                Write-Debug ('Uri     expected  {0}' -f $ToUri)
                Write-Debug ('        actual    {0}' -f $Uri)
                $WithFile = Join-Path -Path $TestDrive.FullName -ChildPath $WithFile
                Write-Debug ('InFile  expected  {0}' -f $WithFile)
                Write-Debug ('        actual    {0}' -f $InFile)
                $Uri -eq [Uri]$ToUri -and $InFile -eq $WithFile 
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
        [System.Net.ServicePointManager]::SecurityProtocol.HasFlag($HasFlag) | Should -BeTrue
    }
}

function ThenTaskFailed
{
    It ('should fail') {
        $failed | Should -BeTrue
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
        $parameter = $context.Configuration['Build'] | Where-Object { $_.ContainsKey('GitHubRelease') } | ForEach-Object { $_['GitHubRelease'] }
        if( $OnCommit )
        {
            $parameter['Commitish'] = $OnCommit
        }
        Invoke-WhiskeyTask -TaskContext $context -Name 'GitHubRelease' -Parameter $parameter

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
    - Path: Whiskey2.zip
      ContentType: fubar/snafu
'@
    GivenFile 'Whiskey.zip' 'WHISKEY_ZIP_FILE'
    GivenFile 'Whiskey2.zip' 'WHISKEY_ZIP_FILE'
    GivenReleaseDoesNotExist '0.0.0-rc.1'
    GivenReleaseCreated '
{
    "url": "https://example.com/releases/0",
    "upload_url": "https://api.github.com/webmd-health-services/Whiskey/releases/0/assets{?name,label}",
    "assets_url": "https://example.com/releases/0/assets"
}
'
    GivenAssets @( )
    GivenAssetUploaded -To 'https://api.github.com/webmd-health-services/Whiskey/releases/0/assets?*'
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
    ThenRequest -Should 'upload asset' `
                -ToUri 'https://api.github.com/webmd-health-services/Whiskey/releases/0/assets?name=Whiskey2.zip' `
                -UsedMethod Post `
                -AsContentType 'fubar/snafu' `
                -WithFile 'Whiskey2.zip'
}

Describe 'GitHubRelease.when the release and asset already exist' {
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
    - Path: Whiskey2.zip
      ContentType: fubar/snafu
'@
    GivenFile 'Whiskey.zip'
    GivenFile 'Whiskey2.zip'
    GivenReleaseExists '0.0.0-rc.1' '
{
    "url": "https://example.com/releases/0",
    "upload_url": "https://api.github.com/webmd-health-services/Whiskey/releases/0/assets{?name,label}",
    "assets_url": "https://example.com/releases/0/assets"
}
'
    GivenAssetUploaded -To 'https://example.com/releases/0/assets'
    GivenAssets @(
                    [pscustomobject]@{
                        url = 'https://example.com/asset/9'
                        name = 'Whiskey.zip'
                    },
                    [pscustomobject]@{
                        url = 'https://example.com/asset/10'
                        name = 'Whiskey2.zip'
                    }
                )
    GivenAssetUpdated -To 'https://example.com/asset/*'
    WhenRunningTask -OnCommit 'deadbee'
    ThenSecurityProtocol -HasFlag ([System.Net.SecurityProtocolType]::Tls12)
    ThenRequest -Should 'edit release' `
                -ToUri 'https://example.com/releases/0' `
                -UsedMethod Patch `
                -AsContentType 'application/json' `
                -WithBody @'
{
    "tag_name":  "0.0.0-rc.1",
    "target_commitish":  "deadbee"
}
'@
    ThenRequest -Should 'edit asset' `
                -ToUri 'https://example.com/asset/9' `
                -UsedMethod Patch `
                -WithBody @'
{
    "name":  "Whiskey.zip",
    "label":  "ZIP"
}
'@
    ThenRequest -Should 'edit asset' `
                -ToUri 'https://example.com/asset/10' `
                -UsedMethod Patch `
                -WithBody @'
{
    "name":  "Whiskey2.zip",
    "label":  ""
}
'@
}

Describe 'GitHubRelease.when using minimal required information' {
    Init
    GivenApiKey 'github.com' 'fubarsnafu'
    GivenWhiskeyYml @'
Build:
- GitHubRelease:
    ApiKeyID: github.com
    RepositoryName: webmd-health-services/Whiskey
    Tag: 0.0.0-rc.1
'@
    GivenReleaseDoesNotExist '0.0.0-rc.1'
    GivenReleaseCreated '
{
    "url": "https://example.com/releases/0",
    "upload_url": "https://api.github.com/webmd-health-services/Whiskey/releases/0/assets{?name,label}",
    "assets_url": "https://example.com/releases/0/assets"
}
'
    WhenRunningTask
    ThenSecurityProtocol -HasFlag ([System.Net.SecurityProtocolType]::Tls12)
    ThenRequest -Should 'create release' `
                -ToUri 'https://api.github.com/repos/webmd-health-services/Whiskey/releases' `
                -UsedMethod Post `
                -AsContentType 'application/json' `
                -WithBody @'
{
    "tag_name":  "0.0.0-rc.1"
}
'@
}

Describe 'GitHubRelease.when ApiKeyID property is missing' {
    Init
    GivenWhiskeyYml @'
Build:
- GitHubRelease:
    RepositoryName: webmd-health-services/Whiskey
    Tag: 0.0.0-rc.1
'@
    GivenReleaseDoesNotExist '0.0.0-rc.1'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenNoApiCalled
    ThenTaskFailed
    ThenError -Matches '"ApiKeyID"\ is\ mandatory'
}

Describe 'GitHubRelease.when RepositoryName property is missing' {
    Init
    GivenApiKey -Name 'github.com' -Value 'fubarsnafu'
    GivenWhiskeyYml @'
Build:
- GitHubRelease:
    ApiKeyID: github.com
    Tag: 0.0.0-rc.1
'@
    GivenReleaseDoesNotExist '0.0.0-rc.1'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenNoApiCalled
    ThenTaskFailed
    ThenError -Matches '"RepositoryName"\ is\ mandatory'
}

Describe 'GitHubRelease.when RepositoryName property is invalid' {
    foreach( $badRepoName in @( 'missingreponame', 'owner/repo/extrapath' ) )
    {
        Context $badRepoName {
            Init
            GivenApiKey -Name 'github.com' -Value 'fubarsnafu'
            GivenWhiskeyYml @"
Build:
- GitHubRelease:
    ApiKeyID: github.com
    RepositoryName: $badRepoName
    Tag: 0.0.0-rc.1
"@
            GivenReleaseDoesNotExist '0.0.0-rc.1'
            WhenRunningTask -ErrorAction SilentlyContinue
            ThenNoApiCalled
            ThenTaskFailed
            ThenError -Matches '"RepositoryName"\ is\ invalid'
        }
    }
}

Describe 'GitHubRelease.when Tag property is invalid' {
    Init
    GivenApiKey -Name 'github.com' -Value 'fubarsnafu'
    GivenWhiskeyYml @"
Build:
- GitHubRelease:
    ApiKeyID: github.com
    RepositoryName: owner/repo
"@
    Mock -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey'
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenNoApiCalled
    ThenTaskFailed
    ThenError -Matches '"Tag"\ is\ mandatory'
}

Describe 'GitHubRelease.when asset doesn''t exist' {
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
'@
    GivenReleaseDoesNotExist '0.0.0-rc.1'
    GivenReleaseCreated '
{
    "url": "https://example.com/releases/0",
    "upload_url": "https://api.github.com/webmd-health-services/Whiskey/releases/0/assets{?name,label}",
    "assets_url": "https://example.com/releases/0/assets"
}
'
    GivenAssets @( )
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenRequest -Should 'create release' `
                -ToUri 'https://api.github.com/repos/webmd-health-services/Whiskey/releases' `
                -UsedMethod Post `
                -AsContentType 'application/json' `
                -WithBody @'
{
    "tag_name":  "0.0.0-rc.1"
}
'@
    ThenAssetNotUploadedTo 'https://example.com/releases/0/assets'
    ThenTaskFailed
    ThenError -Matches 'Whiskey.zip"\ does\ not\ exist'
}


Describe 'GitHubRelease.when asset content type is missing' {
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
'@
    GivenFile 'Whiskey.zip' ''
    GivenReleaseDoesNotExist '0.0.0-rc.1'
    GivenReleaseCreated '
{
    "url": "https://example.com/releases/0",
    "upload_url": "https://api.github.com/webmd-health-services/Whiskey/releases/0/assets{?name,label}",
    "assets_url": "https://example.com/releases/0/assets"
}
'
    GivenAssets @( )
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenRequest -Should 'create release' `
                -ToUri 'https://api.github.com/repos/webmd-health-services/Whiskey/releases' `
                -UsedMethod Post `
                -AsContentType 'application/json' `
                -WithBody @'
{
    "tag_name":  "0.0.0-rc.1"
}
'@
    ThenAssetNotUploadedTo 'https://example.com/releases/0/assets'
    ThenTaskFailed
    ThenError -Matches '"ContentType"\ is\ mandatory'
}

