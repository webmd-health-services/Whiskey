
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCiTest.ps1' -Resolve)

function Invoke-Powershell-Install
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
        $LikePowerShell4,

        [Switch]
        $UsingDefaultDownloadRoot
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

        Mock -CommandName 'Save-Module' -ModuleName 'WhsCI' -MockWith {
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

    $downloadRootParam = @{ }
    if( -not $UsingDefaultDownloadRoot )
    {
        $downloadRootParam['DownloadRoot'] = $TestDrive.FullName
    }

    $result = Install-WhsCITool @downloadRootParam -ModuleName $ForModule -Version $Version

    if( -not $ForRealsies )
    {
        It 'should download the module' {
            Assert-MockCalled -CommandName 'Save-Module' -ModuleName 'WhsCI' -Times 1 -ParameterFilter {
                #$DebugPreference = 'Continue';
                Write-Debug -Message ('Name             expected  {0}' -f $ForModule)
                Write-Debug -Message ('                 actual    {0}' -f $Name)
                Write-Debug -Message ('RequiredVersion  expected  {0}' -f $ActualVersion)
                Write-Debug -Message ('                 actual    {0}' -f $RequiredVersion)
                $Name -eq $ForModule -and $RequiredVersion -eq $ActualVersion
            }
        }
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
            if( $LikePowerShell4 -or ($ForRealsies -and $PSVersionTable.PSVersion -lt [version]'5.0'))
            {
                $expectedRegex = 'Modules\\{0}\.{1}\\{0}\.psd1$' -f [regex]::Escape($ForModule),[regex]::Escape($ActualVersion)
            }
            else
            {
                $expectedRegex = 'Modules\\{0}\\{1}\\{0}\.psd1$' -f [regex]::Escape($ForModule),[regex]::Escape($ActualVersion)
            }
            $result | Should Match $expectedRegex
        }
    }
}

function Invoke-NuGetInstall {
    [CmdletBinding()]
    param(
        $Package,
        $Version,

        [Switch]
        $UsingDefaultDownloadRoot,

        [switch]
        $invalidPackage
    )

    $downloadRootParam = @{ }
    if( -not $UsingDefaultDownloadRoot )
    {
        $downloadRootParam['DownloadRoot'] = $TestDrive.FullName
    }
    $Global:Error.Clear()
    $result = Install-WhsCITool @downloadRootParam -NugetPackageName $Package -Version $Version
    if( -not $invalidPackage){
        Context 'the Vaild NuGet Package' {
            It 'should exist' {                    
                $result | Should Exist
            }
            It 'should put it in the right place' {
                $expectedRegex = 'Packages\\{0}\.{1}' -f [regex]::Escape($Package),[regex]::Escape($Version)
                
                $result | Should Match $expectedRegex
            }
        }        
    }
    else{
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

Describe 'Install-WhsCITool.when given a NuGet Package' {
    Invoke-NuGetInstall -package 'NUnit.Runners' -version '2.6.4'
}

Describe 'Install-WhsCITool.when NuGet Pack is bad' {
    Invoke-NuGetInstall -package 'BadPackage' -version '1.0.1' -invalidPackage -ErrorAction SilentlyContinue
}

Describe 'Install-WhsCITool.when NuGet pack Version is bad' {
    Invoke-NugetInstall -package 'Nunit.Runners' -version '0.0.0' -invalidPackage -ErrorAction SilentlyContinue
}

Describe 'Install-WhsCITool.when installing an already installed NuGet package' {
    
    $Global:Error.Clear()

    Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'
    Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'

    it 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Install-WhsCITool.when run by developer/build server' {
    Invoke-Powershell-Install -ForModule 'Blade' -Version '0.15.0' -ForRealsies
}

Describe 'Install-WhsCITool.when installing an already installed module' {
    $Global:Error.Clear()

    Invoke-Powershell-Install -ForModule 'Blade' -Version '0.15.0' -ForRealsies
    Invoke-Powershell-Install -ForModule 'Blade' -Version '0.15.0' -ForRealsies

    it 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Install-WhsCITool.when omitting BUILD number' {
    Invoke-Powershell-Install -ForModule 'Blade' -Version '0.15' -ActualVersion '0.15.0' -ForRealsies
}

Describe 'Install-WhsCITool.when installing a module under PowerShell 4' {
    Invoke-Powershell-Install -ForModule 'Fubar' -Version '1.3.3' -LikePowerShell4
}

Describe 'Install-WhsCITool.when installing a module under PowerShell 5' {
    Invoke-Powershell-Install -ForModule 'Fubar' -Version '1.3.3' -LikePowerShell5
}

Describe 'Install-WhsCITool.when using default DownloadRoot' {
    $defaultDownloadRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI'
    Mock -CommandName 'Join-Path' `
         -ModuleName 'WhsCI' `
         -MockWith { return Join-Path -Path (Get-Item -Path 'TestDrive:').FullName -ChildPath $ChildPath } `
         -ParameterFilter { $Path -eq $defaultDownloadRoot }.GetNewClosure()

    Invoke-Powershell-Install -ForModule 'Snafu' -Version '3939.9393' -ActualVersion '3939.9393.0' -LikePowerShell4 -UsingDefaultDownloadRoot

    It 'should use LOCALAPPDATA for default install location' {
        Assert-MockCalled -CommandName 'Join-Path' -ModuleName 'WhsCI' -ParameterFilter { $Path -eq $defaultDownloadRoot }
    }
}

Describe 'Install-WhsCITool.when version doesn''t exist' {
    $Global:Error.Clear()

    $pesterRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI\Modules\Pester'
    '.3.0.0','\3.0.0' | 
        ForEach-Object { '{0}{1}' -f $pesterRoot,$_ } | 
        Where-Object { Test-Path -Path $_ -PathType Container } |
        Remove-Item -Recurse -Force 

    $result = Install-WhsCITool -ModuleName 'Pester' -Version '3.0.0' -ErrorAction SilentlyContinue
    
    It 'shouldn''t return anything' {
        $result | Should BeNullOrEmpty
    }

    It 'should write an error' {
        $Global:Error.Count | Should Be 2
        $Global:Error[0] | Should Match 'failed to download'
    }
}