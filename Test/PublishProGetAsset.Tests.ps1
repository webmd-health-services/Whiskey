
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    Remove-Module -Name 'ProGetAutomation' -Force
    Import-WhiskeyTestModule -Name 'ProGetAutomation'

    function GivenContext
    {
        $script:taskParameter['Url'] = 'TestUrl'
        $Script:context = New-WhiskeyTestContext -ForBuildServer `
                                                -ForTaskName 'PublishProGetAsset' `
                                                -ForBuildRoot $script:testDirPath `
                                                -IncludePSModule 'ProGetAutomation'
    }

    function GivenCredential
    {
        param(
            [String] $CredentialID
        )

        if ($CredentialID)
        {
            $script:credentialID = $CredentialID
        }

        $password = ConvertTo-SecureString -AsPlainText -Force -String $script:username
        $script:credential = New-Object 'Management.Automation.PsCredential' $script:username,$password
        $script:taskParameter['CredentialID'] = $script:credentialID
    }

    function GivenAsset
    {
        param(
            [String[]]$Name,
            [String]$directory,
            [String[]]$FilePath
        )
        $script:taskParameter['AssetPath'] = $name
        $script:taskParameter['AssetDirectory'] = $directory
        $script:taskParameter['Path'] = @()
        foreach($file in $FilePath){
            $script:taskParameter['Path'] += (Join-Path -Path $script:testDirPath -ChildPath $file)
            New-Item -Path (Join-Path -Path $script:testDirPath -ChildPath $file) -ItemType 'File' -Force
        }
    }

    function GivenAssetWithInvalidDirectory
    {
        param(
            [String]$Name,
            [String]$directory,
            [String]$FilePath
        )
        # $script:taskParameter['Name'] = $name
        $script:taskParameter['AssetDirectory'] = $directory
        $script:taskParameter['Path'] = (Join-Path -Path $script:testDirPath -ChildPath $FilePath)
        New-Item -Path (Join-Path -Path $script:testDirPath -ChildPath $FilePath) -ItemType 'File' -Force
        Mock -CommandName 'Test-ProGetFeed' -ModuleName 'Whiskey' -MockWith { return $false }
    }

    function GivenAssetThatDoesntExist
    {
        param(
            [String]$Name,
            [String]$directory,
            [String]$FilePath

        )
        $script:taskParameter['AssetPath'] = $name
        $script:taskParameter['AssetDirectory'] = $directory
        $script:taskParameter['Path'] = $script:testDirPath,$FilePath -join '\'
    }

    function ThenAssetContentType
    {
        param(
            [String] $ExpectedContentType
        )

        Should -Invoke -CommandName 'Set-ProGetAsset' -ModuleName 'Whiskey' -ParameterFilter {
            $ContentType | Should -Be $ExpectedContentType -Because 'it should set the ContentType'
            return $true
        }
    }

    function ThenTaskFailsWith
    {
        Param(
            [String]$ExpectedError
        )
        $Global:Error | Where-Object {$_ -match $ExpectedError } |  Should -Not -BeNullOrEmpty
    }

    function ThenAssetShouldExist
    {
        param(
            [String[]]$AssetName
        )

        foreach( $file in $AssetName )
        {
            Should -Invoke 'Set-ProGetAsset' -ModuleName 'Whiskey' -ParameterFilter {
                Write-Debug "Path  expected  ${file}"
                Write-Debug "      actual    ${Path}"
                $Path -eq $file
            }
        }
    }

    function ThenAssetShouldNotExist
    {
        param(
            [String[]]$AssetName
        )
        foreach( $file in $AssetName )
        {
            Should -Invoke 'Set-ProGetAsset' -ModuleName 'Whiskey' -Times 0 -ParameterFilter {
                Write-Debug "Path  expected  ${file}"
                Write-Debug "      actual    ${Path}"
                $Path -eq $file
                $Name -eq $file
            }
        }
    }

    function ThenTaskSucceeds
    {
        $Global:Error | Should -BeNullOrEmpty
    }

    function WhenPublishProGetAsset
    {
        [CmdletBinding()]
        param(
            [String] $WithYml
        )

        if ($WithYml)
        {
            $script:context = New-WhiskeyTestContext -ForYaml $WithYml -ForBuildServer -ForBuildRoot $script:testDirPath
            $script:taskParameter = $script:context.Configuration['Build'][0]['PublishProGetAsset']
        }

        Add-WhiskeyCredential -Context $script:context -ID $script:credentialID -Credential $script:credential

        $Global:Error.Clear()

        try
        {
            Invoke-WhiskeyTask -TaskContext $script:context -Parameter $script:taskParameter -Name 'PublishProGetAsset'
        }
        catch
        {
            Write-Error -ErrorRecord $_
        }
    }
}

Describe 'PublishProGetAsset' {
    BeforeEach {
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        Mock -CommandName 'New-ProGetSession' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Url = 'Mocked' } }
        Mock -CommandName 'Set-ProGetAsset' -ModuleName 'Whiskey'

        $script:testDirPath = New-WhiskeyTestRoot
        $script:username = 'testusername'
        $script:credentialID = 'TestCredential'
        $script:taskParameter = @{ }
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }

    It 'uploads asset' {
        GivenContext
        GivenCredential
        GivenAsset -Name 'foo.txt' -directory 'bar' -FilePath 'foo.txt'
        WhenPublishProGetAsset
        ThenAssetShouldExist -AssetName 'foo.txt'
        ThenTaskSucceeds
    }

    It 'uploads asset to sub-folder' {
        GivenContext
        GivenCredential
        GivenAsset -Name 'boo/foo.txt' -directory 'bar' -FilePath 'foo.txt'
        WhenPublishProGetAsset
        ThenAssetShouldExist -AssetName 'boo/foo.txt'
        ThenTaskSucceeds
    }

    It 'uploads multiple assets' {
        GivenContext
        GivenCredential
        GivenAsset -Name 'foo.txt','bar.txt' -directory 'bar' -FilePath 'foo.txt','bar.txt'
        WhenPublishProGetAsset
        ThenAssetShouldExist -AssetName 'foo.txt','bar.txt'
        ThenTaskSucceeds
    }

    It 'requires asset name' {
        GivenContext
        GivenCredential
        GivenAsset -Directory 'bar' -FilePath 'fooboo.txt'
        WhenPublishProGetAsset -ErrorAction SilentlyContinue
        ThenAssetShouldNotExist -AssetName 'fooboo.txt'
        ThenTaskFailsWith 'There must be the same number of "Path" items as "AssetPath" items.'
    }

    It 'requires each path to have a name' {
        GivenContext
        GivenCredential
        GivenAsset -name 'singlename' -Directory 'bar' -FilePath 'fooboo.txt','bar.txt'
        WhenPublishProGetAsset -ErrorAction SilentlyContinue
        ThenAssetShouldNotExist -AssetName 'fooboo.txt','bar.txt'
        ThenTaskFailsWith 'There must be the same number of "Path" items as "AssetPath" items.'
    }

    It 'requires each name to have a path' {
        GivenContext
        GivenCredential
        GivenAsset -name 'multiple','names' -Directory 'bar' -FilePath 'fooboo.txt'
        WhenPublishProGetAsset -ErrorAction SilentlyContinue
        ThenAssetShouldNotExist -AssetName 'fooboo.txt'
        ThenTaskFailsWith 'There must be the same number of "Path" items as "AssetPath" items.'
    }

    It 'requires credentials' {
        GivenContext
        GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'fooboo.txt'
        WhenPublishProGetAsset -ErrorAction SilentlyContinue
        ThenAssetShouldNotExist -AssetName 'foo.txt'
        ThenTaskFailsWith '"CredentialID" is a mandatory property.'
    }

    It 'replaces existing assets' {
        GivenContext
        GivenCredential
        GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'foo.txt'
        WhenPublishProGetAsset
        ThenAssetShouldExist -AssetName 'foo.txt'
        ThenTaskSucceeds
    }

    It 'sets asset content type when given ContentType property' {
        GivenCredential 'ProGetCredential'
        WhenPublishProGetAsset -WithYml @'
Build:
- PublishProGetAsset:
    Path:
    - file.txt
    AssetPath:
    - asset.txt
    AssetDirectory: Assets
    Url: http://proget.example.com
    CredentialID: ProGetCredential
    ContentType: application/json
'@
        ThenAssetShouldExist 'asset.txt'
        ThenAssetContentType 'application/json'
        ThenTaskSucceeds
    }

    It 'requires the Path property when its missing' {
        GivenCredential 'ProGetCredential'
        WhenPublishProGetAsset -WithYml @'
Build:
- PublishProGetAsset:
    AssetPath:
    - asset.txt
    AssetDirectory: Assets
    Url: http://proget.example.com
    CredentialID: ProGetCredential
'@ -ErrorAction SilentlyContinue
        ThenTaskFailsWith '"Path" is a mandatory property.'
    }

    It 'requires the AssetDirectory property when its missing' {
        GivenCredential 'ProGetCredential'
        WhenPublishProGetAsset -WithYml @'
Build:
- PublishProGetAsset:
    Path:
    - file.txt
    AssetPath:
    - asset.txt
    Url: http://proget.example.com
    CredentialID: ProGetCredential
'@ -ErrorAction SilentlyContinue
        ThenTaskFailsWith '"AssetDirectory" is a mandatory property.'
    }
}
