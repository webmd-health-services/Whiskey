
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

$powerShellModulesDirectoryName = 'PSModules'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

# Wrap private function so we can call it like it's public.
function Install-WhiskeyPowerShellModule
{
    [CmdletBinding()]
    param(
        $Name,
        $Version,
        $Path
    )

    $Global:Parameter = $PSBoundParameters
    try
    {
        InModuleScope 'Whiskey' { Install-WhiskeyPowerShellModule @Parameter } 
    }
    finally
    {
        Remove-Variable -Name 'Parameter' -Scope 'Global'
    }

}

function Invoke-PowershellInstall
{
    param(
        $ForModule,
        $Version,
        $ActualVersion
    )

    if( -not $ActualVersion )
    {
        $ActualVersion = $Version
    }

    $Global:Error.Clear()

    Push-Location -Path $TestDrive.FullName
    try
    {
        $result = Install-WhiskeyPowerShellModule -Name $ForModule -Version $Version
    }
    finally
    {
        Pop-Location
    }

    $moduleRootPath = Join-Path -Path $TestDrive.FullName -ChildPath ('PSModules\{0}' -f $ForModule)
    $result | Should -Not -BeNullOrEmpty
    $result | Should -Exist
    $result | Should -Be $moduleRootPath

    $errors = @()
    $module = Start-Job {
        Import-Module -Name $using:result -PassThru
    } | Wait-Job | Receive-Job -ErrorVariable 'errors'
    $errors | Should -BeNullOrEmpty
    $module.Version | Should -Be $ActualVersion
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and it''s already installed' {
    It 'should not write any erors' {
        $Global:Error.Clear()

        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2.0'
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2.0'

        $Global:Error | Should -BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and omitting patch number' {
    It 'should install at patch number 0' {
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2' -ActualVersion '0.2.0'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module omitting Version' {
    It 'should install the latest version' {
        $module = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyPowerShellModule' -Parameter @{ 'Name' = 'Zip' }
        Invoke-PowershellInstall -ForModule 'Zip' -Version '' -ActualVersion $module.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module using wildcard version' {
    It 'should resolve to the latest version that matches the wildcard' {
        $module = Invoke-WhiskeyPrivateCommand -Name 'Resolve-WhiskeyPowerShellModule' `
                                               -Parameter @{ 'Version' = '0.*'; 'Name' = 'Zip' }
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.*' -ActualVersion $module.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module' {
    It 'should install the module' {
        Invoke-PowershellInstall -ForModule 'Zip' -Version '0.2.0'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and the version doesn''t exist' {
    It 'should fail' {
        $Global:Error.Clear()
        $result = Install-WhiskeyPowerShellModule -Path $TestDrive.FullName -Name 'Pester' -Version '3.0.0' -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -Be 1
        $Global:Error[0] | Should -Match 'failed to find module'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when installing a PowerShell module and version parameter is empty' {
    It 'should fail' {
        $Global:Error.Clear()
        $result = Install-WhiskeyPowerShellModule -Path $TestDrive.FullName -Name 'Fubar' -Version '' -ErrorAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $Global:Error.Count | Should -Be 1
        $Global:Error[0] | Should -Match 'Failed to find module'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module is already installed' {
    It 'should install the new version' {
        Install-WhiskeyPowerShellModule -Path $TestDrive.FullName -Name 'Pester' -Version '4.0.6'
        $info = Get-ChildItem -Path $TestDrive.FullName -Filter 'Pester.psd1' -Recurse
        $manifest = Test-ModuleManifest -Path $info.FullName
        Start-Sleep -Milliseconds 333
        Install-WhiskeyPowerShellModule -Path $TestDrive.FullName -Name 'Pester' -Version '4.0.7'
        $newInfo = Get-ChildItem -Path $TestDrive.FullName -Filter 'Pester.psd1' -Recurse
        $newManifest = Test-ModuleManifest -Path $newInfo.FullName
        $newManifest.Version | Should -Be $manifest.Version
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module directory exists but is empty' {
    It 'should still install the module' {
        $moduleRootDir = Join-Path -Path $TestDrive.FullName -ChildPath ('{0}\Pester' -f $powerShellModulesDirectoryName)
        New-Item -Path $moduleRootDir -ItemType Directory | Write-Debug
        Invoke-PowershellInstall -ForModule 'Pester' -Version '4.4.0'
    }
}

Describe 'Install-WhiskeyPowerShellModule.when PowerShell module is missing files' {
    It 'should do something' {
        Install-WhiskeyPowerShellModule -Path $TestDrive.FullName -Name 'Pester' -Version '4.4.0'
        $moduleManifest = Join-Path -Path $TestDrive.FullName -ChildPath ('{0}\Pester\4.4.0\Pester.psd1' -f $powerShellModulesDirectoryName) -Resolve
        Remove-Item -Path $moduleManifest -Force
        Invoke-PowershellInstall -ForModule 'Pester' -Version '4.4.0'
    }
}

Remove-Item -Path 'function:Install-WhiskeyPowerShellModule'
