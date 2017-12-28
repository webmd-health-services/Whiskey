
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function Invoke-PowershellInstall
{
    param(
        $ForModule,
        $Version,
        $ActualVersion,

        [Parameter(Mandatory=$true,ParameterSetName='ForRealsies')]
        [Switch]
        # Really do the install. Don't fake it out.
        $ForRealsies,

        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell5')]
        [Switch]
        $LikePowerShell5,

        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell4')]
        [Switch]
        $LikePowerShell4
    )

    if( -not $ActualVersion )
    {
        $ActualVersion = $Version
    }

    if( -not ($PSCmdlet.ParameterSetName -eq 'ForRealsies') )
    {
        $ForRealsies = $false
    }

    if( -not $ForRealsies )
    {
        if( $PSCmdlet.ParameterSetName -eq 'LikePowerShell5' ) 
        {
            $LikePowerShell4 = $false
        }
        if( $PSCmdlet.ParameterSetName -eq 'LikePowerShell4' ) 
        {
            $LikePowerShell5 = $false
        }

        Mock -CommandName 'Find-Module' -ModuleName 'Whiskey' -MockWith {
            return $module = @(
                                 [pscustomobject]@{
                                                Version = [Version]$Version                                            
                                            }
                                 [pscustomobject]@{
                                                Version = '0.1.1'
                                            }
                              )            
        }

        Mock -CommandName 'Save-Module' -ModuleName 'Whiskey' -MockWith {
            $moduleRoot = Join-Path -Path (Get-Item -Path 'TestDrive:').FullName -ChildPath 'Modules'
            if( $LikePowerShell4 )
            {
                $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $ForModule
            }
            elseif( $LikePowerShell5 )
            {
                $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $ForModule
                $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $ActualVersion
            }
            New-Item -Path $moduleRoot -ItemType 'Directory' | Out-Null
            $moduleManifestPath = Join-Path -Path $moduleRoot -ChildPath ('{0}.psd1' -f $ForModule)
            New-ModuleManifest -Path $moduleManifestPath -ModuleVersion $ActualVersion
        }.GetNewClosure()
    }

    $optionalParams = @{ }
    $Global:Error.Clear()
    $result = Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName $ForModule -Version $Version

    if( -not $ForRealsies )
    {
        It 'should download the module' {
            Assert-MockCalled -CommandName 'Save-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
                #$DebugPreference = 'Continue';
                Write-Debug -Message ('Name             expected  {0}' -f $ForModule)
                Write-Debug -Message ('                 actual    {0}' -f $Name)
                Write-Debug -Message ('RequiredVersion  expected  {0}' -f $ActualVersion)
                Write-Debug -Message ('                 actual    {0}' -f $RequiredVersion)
                $Name -eq $ForModule -and $RequiredVersion -eq $ActualVersion
            }
        }

        It 'should put the modules in $DownloadRoot\Modules' {
            Assert-MockCalled -CommandName 'Save-Module' -ModuleName 'Whiskey' -ParameterFilter {
                $Path -eq (Join-Path -Path $TestDrive.FullName -ChildPath 'Modules')
            }
        }
        return
    }

    Context 'the module' {
        It 'should exist' {
            $result | Should Exist
        }

        It 'should be importable' {
            $errors = @()
            Import-Module -Name $result -PassThru -ErrorVariable 'errors' | Remove-Module
            $errors | Should BeNullOrEmpty
        }

        It 'should put it in the right place' {
            $expectedRegex = 'Modules\\{0}$' -f [regex]::Escape($ForModule)
            $result | Should Match $expectedRegex
        }
    }
}

function Invoke-NuGetInstall 
{
    [CmdletBinding()]
    param(
        $Package,
        $Version,

        [switch]
        $invalidPackage
    )

    $result = Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -NugetPackageName $Package -Version $Version
    if( -not $invalidPackage)
    {
        Context 'the NuGet Package' {
            It 'should exist' {                    
                $result | Should -Exist
            }
            It 'should get installed into $DownloadRoot\packages' {
                $result | Should -BeLike ('{0}\packages\*' -f $TestDrive.FullName)
            }
        }        
    }
    else
    {
        Context 'the Invalid NuGet Package' {
            It 'should NOT exist' {                    
                $result | Should Not Exist
            }
            it 'should write errors' {
                $Global:Error | Should NOT BeNullOrEmpty
            }
        }
    }
}

Describe 'Install-WhiskeyTool.when given a NuGet Package' {
    Invoke-NuGetInstall -package 'NUnit.Runners' -version '2.6.4'
}

Describe 'Install-WhiskeyTool.when NuGet Pack is bad' {
    Invoke-NuGetInstall -package 'BadPackage' -version '1.0.1' -invalidPackage -ErrorAction silentlyContinue
}

Describe 'Install-WhiskeyTool.when NuGet pack Version is bad' {
    Invoke-NugetInstall -package 'Nunit.Runners' -version '0.0.0' -invalidPackage -ErrorAction silentlyContinue
}

Describe 'Install-WhiskeyTool.when given a NuGet Package with an empty version string' {
    Invoke-NuGetInstall -package 'NUnit.Runners' -version ''
}

Describe 'Install-WhiskeyTool.when installing an already installed NuGet package' {
    
    $Global:Error.Clear()

    Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'
    Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'

    it 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyTool.when run by developer/build server' {
    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.15.0' -ForRealsies
}

Describe 'Install-WhiskeyTool.when installing an already installed module' {
    $Global:Error.Clear()

    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.15.0' -ForRealsies
    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.15.0' -ForRealsies

    it 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyTool.when omitting BUILD number' {
    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.15' -ActualVersion '0.15.0' -ForRealsies
}

Describe 'Install-WhiskeyTool.when omitting Version' {
    $actualVersion = Resolve-WhiskeyPowerShellModuleVersion -Version '' -ModuleName 'Blade'
    Invoke-PowershellInstall -ForModule 'Blade' -Version '' -ActualVersion $actualVersion -ForRealsies
}

Describe 'Install-WhiskeyTool.when using wildcard version' {
    $actualVersion = Resolve-WhiskeyPowerShellModuleVersion -Version '0.*' -ModuleName 'Blade'
    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.*' -ActualVersion $actualVersion -ForRealsies
}

Describe 'Install-WhiskeyTool.when installing a module under PowerShell 4' {
    Invoke-PowershellInstall -ForModule 'Fubar' -Version '1.3.3' -LikePowerShell4
}

Describe 'Install-WhiskeyTool.when installing a module under PowerShell 5' {
    Invoke-PowershellInstall -ForModule 'Fubar' -Version '1.3.3' -LikePowerShell5
}

Describe 'Install-WhiskeyTool.when version of module doesn''t exist' {
    $Global:Error.Clear()

    $result = Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName 'Pester' -Version '3.0.0' -ErrorAction SilentlyContinue
    
    It 'shouldn''t return anything' {
        $result | Should BeNullOrEmpty
    }

    It 'should write an error' {
        $Global:Error[0] | Should Match 'failed to download Pester 3\.0\.0'
    }
}

Describe 'Install-WhiskeyTool.for non-existent module when version parameter is empty' {
    $Global:Error.Clear()

    $result = Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName 'Fubar' -Version '' -ErrorAction SilentlyContinue
    
    It 'shouldn''t return anything' {
        $result | Should BeNullOrEmpty
    }

    It 'should write an error' {
        $Global:Error.Count | Should Be 1
        $Global:Error[0] | Should Match 'Unable to find any versions'
    }
}

Describe 'Install-WhiskeyTool.when set EnableNuGetPackageRestore' {
    Mock -CommandName 'Set-Item' -ModuleName 'Whiskey'
    Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -NugetPackageName 'NUnit.Runners' -version '2.6.4'
    It 'should enable NuGet package restore' {
        Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Path -eq 'env:EnableNuGetPackageRestore'}
        Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Value -eq 'true'}
    }
}

Describe 'Install-WhiskeyTool.when PowerShell module is already installed' {
    Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName 'Pester' -Version '4.0.6'
    $info = Get-ChildItem -Path $TestDrive.FullName -Filter 'Pester.psd1' -Recurse
    $manifest = Test-ModuleManifest -Path $info.FullName
    Start-Sleep -Milliseconds 333
    Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName 'Pester' -Version '4.0.7'
    $newInfo = Get-ChildItem -Path $TestDrive.FullName -Filter 'Pester.psd1' -Recurse
    $newManifest = Test-ModuleManifest -Path $newInfo.FullName
    It 'should not redownload module' {
        $newManifest.Version | Should -Be $manifest.Version
    }
}