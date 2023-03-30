
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    $script:testRoot = $null
    $script:BuildPs1Path = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\build.ps1' -Resolve
    $script:testNum = 0

    function Remove-TestModule
    {
        Get-Module 'PowerShellGet','Whiskey','PackageManagement' | Remove-Module -Force -ErrorAction Ignore
    }

    Remove-TestModule

    $headers = @{ 'Content-Type' = 'application/json' }

    if ($env:GITHUB_BEARER_TOKEN)
    {
        $headers['Authorization'] = "Bearer $env:GITHUB_BEARER_TOKEN"
    }

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
    $releases =
        Invoke-RestMethod -Uri 'https://api.github.com/repos/webmd-health-services/Whiskey/releases' -Headers $headers |
        ForEach-Object { $_ }

    $script:latestRelease =
        $releases |
        Where-Object 'name' -NotLike '*-*' |
        Where-Object 'name' -NotLike '*+*' |
        Sort-Object -Property 'created_at' -Descending |
        Select-Object -First 1

    # TODO: remove once a version after 0.48.3 is published.
    if( ($script:latestRelease -as [version]) -le [version]'0.48.3' )
    {
        $net4Key = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Ignore
        $net462Release = 460798
        if( $net4Key -and $net4Key.Release -le $net462Release )
        {
            $msg = 'These tests require a version of Whiskey after 0.48.3 when the tests are running on .NET ' +
                "$($net4Key.Version) or earlier."
            Write-Warning $msg
            return
        }
    }

    function ThenModule
    {
        param(
            [Parameter(Mandatory)]
            [String[]]$Named,

            [switch]$Not,

            [Parameter(Mandatory)]
            [switch]$Loaded
        )

        if( $Not )
        {
            Get-Module -Name $Named | Should -BeNullOrEmpty
        }
        else
        {
            Get-Module -Name $Named | Should -Not -BeNullOrEmpty
        }
    }

    function ThenNoErrors
    {
        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenWhiskeyInstalled
    {
        $moduleDirName = $script:latestRelease.name -replace '(-.*)?(\+.*)?$',''
        $path = Join-Path -Path $script:testRoot -ChildPath "PSModules\Whiskey\${moduleDirName}\Whiskey.ps*1"
        $path | Should -Exist
        $path | Get-Item | Should -HaveCount 2
        $manifest = Test-ModuleManifest -Path ($path -replace '\.ps\*1','.psd1')
        Write-Verbose $manifest.PrivateData.PSData.Prerelease
        $manifest.PrivateData.PSData.Prerelease | Should -BeNullOrEmpty
        Join-Path -Path $script:testRoot -ChildPath 'whiskey.yml' | Should -Exist
    }

    function WhenBootstrapping
    {
        $Global:Error.Clear()

        Copy-Item -Path $script:BuildPs1Path -Destination $script:testRoot

        Mock -CommandName 'Invoke-WebRequest' -ParameterFilter {
            # Only mock out the first call. We just want to capture what parameters the function was called with.
            $nestedCount =
                Get-PSCallStack |
                Where-Object { $_.Command -like 'PesterMock_*' } |
                Measure-Object |
                Select-Object -ExpandProperty 'Count'
            return $nestedCount -eq 1
        } -MockWith {
            $parameters = @{}
            $cmdParameters = Get-Command 'Invoke-WebRequest' | Select-Object -Expand 'Parameters'
            foreach( $name in $cmdParameters.Keys )
            {
                $value = Get-Variable -Name $name -ValueOnly -ErrorAction Ignore
                if( $value )
                {
                    $parameters[$name] = $value
                }
            }
            $parameters | ConvertTo-Json | Write-Verbose
            $ProgressPreference = 'SilentlyContinue'
            Microsoft.PowerShell.Utility\Invoke-WebRequest @parameters }

        & (Join-Path -Path $script:testRoot -ChildPath 'build.ps1' -Resolve)
    }
}

Describe 'buildPs1' {
    BeforeEach {
        $Global:Error.Clear()
        $script:testRoot = Join-Path -Path $TestDrive -ChildPath $script:testNum
        New-Item -Path $script:testRoot -ItemType Directory
    }

    AfterEach {
        $script:testNum += 1
    }

    It 'should download latest non-prerelease version of Whiskey' {
        Copy-Item -Path $script:buildPs1Path -Destination $script:testRoot
        $testRoot = $script:testRoot
        # Do this in a background job so the version of Whiskey that could be loaded doesn't interfere with the
        # build.ps1 functionality and vice-versa.
        $job = Start-Job {
            $testRoot = $using:testRoot
            Set-Location $testRoot
            .\build.ps1
            Get-Module 'Whiskey'
        }
        $module = $job | Receive-Job -Wait -AutoRemoveJob
        ThenWhiskeyInstalled
        ThenNoErrors
        $module | Should -Not -BeNullOrEmpty
        $module.pstypenames | Should -Contain 'Deserialized.System.Management.Automation.PSModuleInfo'
        $module.Name | Should -Be 'Whiskey'
        $module.Version | Should -Be $script:latestRelease.name
    }

    It 'should bootstrap the latest version of the current major line' {
        $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Whiskey.psd1' -Resolve
        $manifest = Test-ModuleManifest -Path $manifestPath
        $defaultBootstrapVersion = ''
        foreach( $line in (Get-Content -Path $script:BuildPs1Path) )
        {
            if( $line -match 'whiskeyVersion = ''([^'']+)''' )
            {
                $defaultBootstrapVersion = $Matches[1]
                break
            }
        }

        $defaultBootstrapVersion |
            Should -Not `
                   -BeNullOrEmpty `
                   -Because 'this test must be able to find the version of Whiskey to pin to in build.ps1'
        $manifest.Version |
            Should -BeLike $Matches[1] -Because 'build.ps1 should be kept in sync with module''s major version number'
    }
}
