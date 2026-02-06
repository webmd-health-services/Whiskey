
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'


BeforeDiscovery {
    $script:disableHttpErrorHandlingTests = $true
    $script:httpStatusBaseUrl = 'https://tools-httpstatus.pickup-services.com'

    try
    {
        Invoke-WebRequest -Uri "${script:httpStatusBaseUrl}/200" -UseBasicParsing
        $script:disableHttpErrorHandlingTests = $false
    }
    catch
    {

    }

    if (-not (Test-Path -Path 'variable:IsWindows'))
    {
        $script:IsWindows = $true
        $script:IsLinux = $script:IsMacOS = $false
    }

}

BeforeAll {
    Set-StrictMode -Version 'Latest'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey' -Resolve) -Verbose:$false

    $script:result = ''
    $script:testNum = 0
    $script:testDirPath = ''
    $script:nodeVersions = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' | ForEach-Object { $_ }

    $script:latestLtsVersion =
        $script:nodeVersions |
        Where-Object 'lts' -NE $false |
        Select-Object -First 1 |
        Select-Object -ExpandProperty 'version'

    $script:pkgPlatform = 'win'
    $script:pkgFileExtension = 'zip'
    if ($IsLinux)
    {
        $script:pkgPlatform = 'linux'
        $script:pkgFileExtension = 'tar.xz'
    }
    elseif ($IsMacOS)
    {
        $script:pkgPlatform = 'darwin'
        $script:pkgFileExtension = 'tar.gz'
    }

    $script:defaultPkgFileName = "node-${script:latestLtsVersion}-${script:pkgPlatform}-x64.${script:pkgFileExtension}"

    function GivenFile
    {
        param(
            $Named
        )

        New-Item -Path (Join-Path -Path $script:testDirPath -ChildPath $Named) -ItemType File
    }

    function ThenError
    {
        [CmdletBinding()]
        param(
            [int] $AtIndex,
            [String] $MatchesRegex
        )

        $errToCheck = $Global:Error
        if ($PSBoundParameters.ContainsKey('AtIndex'))
        {
            $errToCheck = $Global:Error[$AtIndex]
        }
        $errToCheck | Should -Match $MatchesRegex
    }

    function ThenPackage
    {
        param(
            [String] $Named,
            [switch] $Not,
            [switch] $Saved
        )


        $expectedPath = Join-Path -Path $script:testDirPath -ChildPath $Named
        $expectedPath | Should -Not:$Not -Exist

        if (-not $Not)
        {
            Get-Item -Path $expectedPath | Select-Object -ExpandProperty 'Length' | Should -BeGreaterThan 0
        }
    }

    function ThenReturned
    {
        param(
            [Object] $Path
        )

        if ($Path)
        {
            $Path = Join-Path -Path $script:testDirPath -ChildPath $Path
        }

        if ($null -eq $Path)
        {
            $script:result | Should -BeNullOrEmpty
        }
        else
        {
            $script:result | Should -Be $Path
        }
    }

    function WhenSavingNodeJsPackage
    {
        [CmdletBinding()]
        param(
            [hashtable] $WithArgs = @{}
        )

        $WithArgs['OutputDirectoryPath'] = $script:testDirPath
        $WithArgs['ErrorAction'] = $ErrorActionPreference

        $script:result = InModuleScope -ModuleName 'Whiskey' -ScriptBlock {
            param(
                [hashtable] $SaveArgs
            )
            Save-NodeJsPackage @SaveArgs
        } -Parameters @{ SaveArgs = $WithArgs }
    }
}

Describe 'Save-NodeJsPackage' {
    BeforeEach {
        $script:testDirPath = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:testDirPath -ItemType 'Directory'
        $Global:Error.Clear()
    }

    It 'downloads Node.js package' {
        WhenSavingNodeJsPackage -WithArgs @{ Version = $script:latestLtsVersion }
        ThenPackage $script:defaultPkgFileName -Saved
        ThenReturned $script:defaultPkgFileName
    }

    It 'downloads custom CPU architecture' {
        WhenSavingNodeJsPackage -WithArgs @{ Version = $script:latestLtsVersion; Cpu = 'arm64' }
        $pkgName = "node-${script:latestLtsVersion}-${script:pkgPlatform}-arm64.${script:pkgFileExtension}"
        ThenPackage $pkgName -Saved
        ThenReturned $pkgName
    }

    It 'handles download failure' -Skip:$disableHttpErrorHandlingTests {
        $http500Url = "${httpStatusBaseUrl}/500"
        $pkgFileName = $script:defaultPkgFileName
        Mock -CommandName 'Invoke-WebRequest' `
             -ModuleName 'Whiskey' `
             -ParameterFilter { $Uri -like "*/${pkgFileName}" } `
             -MockWith { Invoke-WebRequest -Uri $http500Url }
        WhenSavingNodeJsPackage -WithArgs @{ Version = $script:latestLtsVersion } -ErrorAction SilentlyContinue
        ThenPackage $pkgFileName -Not -Saved
        ThenReturned $null
        ThenError 0 -Matches 'failed to download'
    }

    It 'redownloads package' {
        GivenFile $script:defaultPkgFileName
        WhenSavingNodeJsPackage -WithArgs @{ Version = $script:latestLtsVersion }
        ThenPackage $script:defaultPkgFileName -Saved
        ThenReturned $script:defaultPkgFileName
    }

    It 'caches package' {
        $pkgFileName = $script:defaultPkgFileName
        WhenSavingNodeJsPackage -WithArgs @{ Version = $script:latestLtsVersion }
        ThenPackage $pkgFileName -Saved
        ThenReturned $pkgFileName
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -ParameterFilter { $Uri -like "*/${pkgFileName}" }
        $script:result = $null
        WhenSavingNodeJsPackage -WithArgs @{ Version = $script:latestLtsVersion }
        Should -Not -Invoke 'Invoke-WebRequest' -ModuleName 'Whiskey'
        ThenReturned $pkgFileName
    }

    It 'validates downloaded package' {
        $mockHash = Get-FileHash -Path $PSCommandPath
        Mock 'Get-FileHash' -ModuleName 'Whiskey' -MockWith { $mockHash }
        WhenSavingNodeJsPackage -WithArgs @{ Version = $script:latestLtsVersion }
        ThenPackage $script:defaultPkgFileName -Not -Saved
        ThenReturned $null
        ThenError -Matches 'sha256 checksum.*doesn''t match'
    }
}