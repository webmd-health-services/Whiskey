
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testDirPath = $null
    $script:username = 'testusername'
    $script:credentialID = 'TestCredential'

    function GivenContext
    {
        $script:taskParameter = @{ }
        $script:taskParameter['Url'] = 'TestUrl'
        Import-WhiskeyTestModule -Name 'ProGetAutomation'
        $script:session = New-ProGetSession -Uri $TaskParameter['Url']
        $Global:globalTestSession = $session
        $Script:context = New-WhiskeyTestContext -ForBuildServer `
                                                -ForTaskName 'PublishProGetAsset' `
                                                -ForBuildRoot $script:testDirPath `
                                                -IncludePSModule 'ProGetAutomation'
        Mock -CommandName 'New-ProGetSession' -ModuleName 'Whiskey' -MockWith { return $globalTestSession }
        Mock -CommandName 'Set-ProGetAsset' -ModuleName 'Whiskey' -MockWith { return $true }
    }

    function GivenCredentials
    {
        $password = ConvertTo-SecureString -AsPlainText -Force -String $script:username
        $script:credential = New-Object 'Management.Automation.PsCredential' $script:username,$password
        Add-WhiskeyCredential -Context $context -ID $script:credentialID -Credential $credential

        $taskParameter['CredentialID'] = $script:credentialID
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
}

Describe 'PublishProGetAsset' {
    BeforeEach {
        $script:testDirPath = New-WhiskeyTestRoot
        Remove-Module -Name 'ProGetAutomation' -Force -ErrorAction Ignore
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }

    It 'uploads asset' {
        GivenContext
        GivenCredentials
        GivenAsset -Name 'foo.txt' -directory 'bar' -FilePath 'foo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldExist -AssetName 'foo.txt'
        ThenTaskSucceeds
    }

    It 'uploads asset to sub-folder' {
        GivenContext
        GivenCredentials
        GivenAsset -Name 'boo/foo.txt' -directory 'bar' -FilePath 'foo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldExist -AssetName 'boo/foo.txt'
        ThenTaskSucceeds
    }

    It 'uploads multiple assets' {
        GivenContext
        GivenCredentials
        GivenAsset -Name 'foo.txt','bar.txt' -directory 'bar' -FilePath 'foo.txt','bar.txt'
        WhenAssetIsUploaded
        ThenAssetShouldExist -AssetName 'foo.txt','bar.txt'
        ThenTaskSucceeds
    }

    It 'requires asset name' {
        GivenContext
        GivenCredentials
        GivenAsset -Directory 'bar' -FilePath 'fooboo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldNotExist -AssetName 'fooboo.txt'
        ThenTaskFails -ExpectedError 'There must be the same number of Path items as AssetPath Items. Each Asset must have both a Path and an AssetPath in the whiskey.yml file.'
    }

    It 'requires each path to have a name' {
        GivenContext
        GivenCredentials
        GivenAsset -name 'singlename' -Directory 'bar' -FilePath 'fooboo.txt','bar.txt'
        WhenAssetIsUploaded
        ThenAssetShouldNotExist -AssetName 'fooboo.txt','bar.txt'
        ThenTaskFails -ExpectedError 'There must be the same number of Path items as AssetPath Items. Each Asset must have both a Path and an AssetPath in the whiskey.yml file.'
    }

    It 'requires each name to have a path' {
        GivenContext
        GivenCredentials
        GivenAsset -name 'multiple','names' -Directory 'bar' -FilePath 'fooboo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldNotExist -AssetName 'fooboo.txt'
        ThenTaskFails -ExpectedError 'There must be the same number of Path items as AssetPath Items. Each Asset must have both a Path and an AssetPath in the whiskey.yml file.'
    }

    It 'requires credentials' {
        GivenContext
        GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'fooboo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldNotExist -AssetName 'foo.txt'
        ThenTaskFails -ExpectedError 'CredentialID is a mandatory property. It should be the ID of the credential to use when connecting to ProGet'
    }

    It 'replaces existing assets' {
        GivenContext
        GivenCredentials
        GivenAsset -Name 'foo.txt' -Directory 'bar' -FilePath 'foo.txt'
        WhenAssetIsUploaded
        ThenAssetShouldExist -AssetName 'foo.txt'
        ThenTaskSucceeds
    }
}
