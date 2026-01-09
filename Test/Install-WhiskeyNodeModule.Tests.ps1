
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:name = $null
    $script:output = $null
    $script:version = $null
    $script:testRoot = $null

    function GivenNpmSucceedsButModuleNotInstalled
    {
        Mock -CommandName 'Invoke-WhiskeyNpmCommand' -Module 'Whiskey' -MockWith $SuccessCommandScriptBlock
    }

    function GivenName
    {
        param(
            $Module
        )
        $script:name = $Module
    }

    function GivenVersion
    {
        param(
            $Version
        )
        $script:version = $Version
    }

    function CreatePackageJson
    {
        $packageJsonPath = Join-Path -Path $script:testRoot -ChildPath 'package.json'

        @"
    {
        "name": "NPM-Test-App",
        "version": "0.0.1",
        "description": "test",
        "repository": "bitbucket:example/repo",
        "private": true,
        "license": "MIT"
    } 
"@ | Set-Content -Path $packageJsonPath -Force

    }

    function Reset
    {
    }

    function WhenInstallingNodeModule
    {
        [CmdletBinding()]
        param()
        
        CreatePackageJson

        $parameter = $PSBoundParameters

        if ($script:version)
        {
            $parameter['Version'] = $script:version
        }

        $parameter['Name'] = $script:name
        $parameter['BuildRootPath'] = $script:testRoot

        Push-Location $script:testRoot
        try
        {
            # Ignore STDERR because PowerShell on .NET Framework <= 4.6.2 converts command stderr to gross ErrorRecords
            # which causes our error checking assertions to fail.
            $script:output = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyNodeModule' `
                                                          -Parameter $parameter `
                                                          -ErrorAction $ErrorActionPreference `
                                                          2>$null
        }
        finally
        {
            Pop-Location    
        }
    }

    function ThenModule
    {
        param(
            [Parameter(Position=0)]
            [String]$Name,

            [Parameter(ParameterSetName='Exists')]
            [String]$Version,
            
            [Parameter(Mandatory,ParameterSetName='Exists')]
            [switch]$Exists,

            [Parameter(Mandatory,ParameterSetName='DoesNotExist')]
            [switch]$DoesNotExist
        )

        $modulePath = Resolve-WhiskeyNodeModulePath -Name $Name -BuildRootPath $script:testRoot

        if ($Exists)
        {
            $modulePath | Should -Exist

            if ($Version)
            {
                $moduleVersion = Get-Content -Path (Join-Path -Path $modulePath -ChildPath 'package.json') -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'Version'
                $moduleVersion | Should -Be $Version
            }
        }
        else
        {
            $modulePath | Should -Not -Exist
        }
    }

    function ThenNoErrorsWritten
    {
        $Global:Error -like 'error' | Should -BeNullOrEmpty
    }

    function ThenErrorMessage
    {
        param(
            $Message
        )

        $Global:Error | Where-Object { $_ -match $Message } | Should -Not -BeNullOrEmpty
    }

    function ThenReturnedPathForModule
    {
        param(
            $Module
        )

        $modulePath = Resolve-WhiskeyNodeModulePath -Name $Module -BuildRootPath $script:testRoot
        
        $script:output | Should -Be $modulePath
    }

    function ThenReturnedNothing
    {
        $script:output | Should -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyNodeModule.when given name' {
    BeforeEach {
        $Global:Error.Clear()
        $script:name = $null
        $script:output = $null
        $script:version = $null
        $script:testRoot = New-WhiskeyTestRoot
        Install-Node -BuildRoot $script:testRoot
    }

    # Starting with Node.js 24.x.x only supported on Windows 10 and Server 2016 or higher.
    $is2012R2 = $false
    if ((Test-Path -Path 'variable:IsWindows') -and $IsWindows -and ((Get-CimInstance Win32_OperatingSystem).Caption -like "*Windows Server 2012 R2*"))
    {
        $is2012R2 = $true
    }
    It 'should install the module' -Skip:$is2012R2 {
        GivenName 'wrappy'
        WhenInstallingNodeModule
        ThenModule 'wrappy' -Exists
        ThenReturnedPathForModule 'wrappy'
        ThenNoErrorsWritten
    }

    It 'should install specific module version' -Skip:$is2012R2 {
        GivenName 'wrappy'
        GivenVersion '1.0.2'
        WhenInstallingNodeModule
        ThenModule 'wrappy' -Version '1.0.2' -Exists
        ThenReturnedPathForModule 'wrappy'
        ThenNoErrorsWritten
    }

    It 'validates module' -Skip:$is2012R2 {
        GivenName 'nonexistentmodule'
        WhenInstallingNodeModule -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorMessage 'failed\ with\ exit\ code\ 1'
        $Global:Error | Where-Object { $_ -match 'NPM\ executed\ successfully' } | Should -BeNullOrEmpty
    }

    It 'validates module installs' {
        GivenName 'wrappy'
        GivenNpmSucceedsButModuleNotInstalled
        WhenInstallingNodeModule -ErrorAction SilentlyContinue
        ThenReturnedNothing
        ThenErrorMessage 'NPM executed successfully when attempting to install "wrappy" but the module was not found'
    }
}