
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCiTest.ps1' -Resolve)

function GivenAnInstalledPowerShellModule
{
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell5')]
        [Switch]
        $LikePowerShell5,

        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell4')]
        [Switch]
        $LikePowerShell4,

        [Switch]
        $InDefaultDownloadDirectory,

        [Version]
        $WithVersion = '4.0.3',

        [String]
        $InstalledAt,

        [String]
        $WithName = 'Pester'
    )
    if( $InstalledAt )
    {
        $moduleRoot = $InstalledAt
    }
    else
    {
        $moduleRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'Modules'
    }
    if( $LikePowerShell4 )
    {        
        $Name = '{0}.{1}' -f $WithName, $WithVersion
    }
    elseif( $LikePowerShell5 )
    {
        $Name = '{0}\{1}' -f $WithName, $WithVersion 
    }
    $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $Name

    New-Item -Name $WithName -Path $moduleRoot -ItemType 'Directory' | Out-Null
}

function GivenAnInstalledNuGetPackage
{
    [CmdLetBinding()]
    param(
        [Switch]
        $InDefaultDownloadDirectory,

        [Version]
        $WithVersion,

        [String]
        $InstalledAt,

        [String]
        $WithName
    )

    $Name = '{0}.{1}' -f $Name, $Version
    
    if( -not $InstalledAt )
    {
        $InstalledAt = Join-Path -Path $TestDrive.FullName -ChildPath 'Packages'
        
    }
    New-Item -Name $Name -Path $InstalledAt -ItemType 'Directory' | Out-Null
}

function WhenUninstallingPowerShellModule
{
    [CmdletBinding()]
    param(

        [Switch]
        $FromDefaultDownloadDirectory,

        [Version]
        $WithVersion = '4.0.3',

        [String]
        $AtPath,

        [String]
        $WithName = 'Pester'
    )

    $optionalParams = @{ }
    if( -not $FromDefaultDownloadDirectory )
    {
        $downloadRoot = $TestDrive.FullName 
        $optionalParams['DownloadRoot'] = $downloadRoot
    }

    if ( $AtPath )
    {
        $optionalParams['Path'] = $AtPath
    }

    $Global:Error.Clear()
    Uninstall-WhsCITool -ModuleName $WithName -Version $WithVersion @optionalParams
}

function WhenUninstallingNuGetPackage
{
    [CmdletBinding()]
    param(
        [Version]
        $WithVersion = '2.6.4',

        [Switch]
        $FromDefaultDownloadDirectory,

        [String]
        $WithName = 'NUnit.Runners'
    )

    $optionalParams = @{ }
    if( -not $FromDefaultDownloadDirectory )
    {
        $downloadRoot = $TestDrive.FullName 
        $optionalParams['DownloadRoot'] = $downloadRoot
    }
    $Global:Error.Clear()
    Uninstall-WhsCITool -NuGetPackageName $WithName -Version $WithVersion @optionalParams
}

function ThenPowerShellModuleUninstalled
{
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell5')]
        [Switch]
        $LikePowerShell5,

        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell4')]
        [Switch]
        $LikePowerShell4,

        [version]
        $WithVersion = '4.0.3',

        [String]
        $WithName = 'Pester',

        [String]
        $From,

        [Switch]
        $FromDefaultDownloadDirectory
    )

    if( $LikePowerShell4 )
    {        
        $Name = '{0}.{1}' -f $WithName, $WithVersion
    }
    elseif( $LikePowerShell5 )
    {
        $Name = '{0}\{1}' -f $WithName, $WithVersion 
    }

    if( $From )
    {
        $uninstalledPath = $From
    }
    else
    {
        $path = Join-Path -Path $TestDrive.FullName -ChildPath 'Modules'
        $uninstalledPath = Join-Path -Path $path -ChildPath $Name
    }

    It 'should successfully uninstall the PowerShell Module' {
        $uninstalledPath | Should not Exist
    }

    if( $From -and -not $FromDefaultDownloadDirectory )
    {
        $errorMessage = 'You have supplied a Path and DownloadRoot parameter'
        It 'should warn about Path and DownloadRoot' {
            $Global:Error | should Match $errorMessage
        }       
    }
    else
    {
        It 'Should not write any errors' {
            $Global:Error | Should beNullOrEmpty
        }
    }
}

function ThenNuGetPackageUninstalled
{
    [CmdLetBinding()]
    param(
        [version]
        $WithVersion = '2.6.4',

        [String]
        $WithName = 'NUnit.Runners'
    )

    $Name = '{0}.{1}' -f $WithName, $Version
    $path = Join-Path -Path $TestDrive.FullName -ChildPath 'Packages'
    $uninstalledPath = Join-Path -Path $path -ChildPath $Name

    It 'should successfully uninstall the NuGet Package' {
        $uninstalledPath | Should not Exist
    }

    It 'Should not write any errors' {
        $Global:Error | Should beNullOrEmpty
    }
}

Describe 'Uninstall-WhsCITool.when given an NuGet Package' {
    GivenAnInstalledNuGetPackage
    WhenUninstallingNuGetPackage
    ThenNuGetPackageUnInstalled
}

Describe 'Uninstall-WhsCITool.when given a PowerShell Module under PowerShell 4' {
    GivenAnInstalledPowerShellModule -LikePowerShell4
    WhenUninstallingPowerShellModule
    ThenPowerShellModuleUninstalled -LikePowerShell4
}

Describe 'Uninstall-WhsCITool.when given a PowerShell Module under PowerShell 5' {
    GivenAnInstalledPowerShellModule -LikePowerShell5
    WhenUninstallingPowerShellModule
    ThenPowerShellModuleUninstalled -LikePowerShell5
}

Describe 'Uninstall-WhsCITool.when given a PowerShell Module with a specified path parameter' {
    $path = Join-Path -path $TestDrive.FullName -ChildPath 'FuBar'
    $modulePath = Join-Path -Path $path -ChildPath ( Join-Path -Path 'Pester' -ChildPath '4.0.3' ) 
    New-Item -Path $modulePath -ItemType 'Directory' -Force | Out-Null
    GivenAnInstalledPowerShellModule -InstalledAt $path -LikePowerShell5
    WhenUninstallingPowerShellModule -AtPath $path -ErrorAction SilentlyContinue
    ThenPowerShellModuleUninstalled -From $modulePath -LikePowerShell5
}

Describe 'Uninstall-WhsCITool.when uninstalling Powershell Module using default DownloadRoot' {
    $defaultDownloadRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI'
    Mock -CommandName 'Join-Path' `
         -ModuleName 'WhsCI' `
         -MockWith { return Join-Path -Path (Get-Item -Path 'TestDrive:').FullName -ChildPath $ChildPath } `
         -ParameterFilter { $Path -eq $defaultDownloadRoot }.GetNewClosure()

    GivenAnInstalledPowerShellModule -InDefaultDownloadDirectory -LikePowerShell5
    WhenUninstallingPowerShellModule -FromDefaultDownloadDirectory
    ThenPowerShellModuleUninstalled -FromDefaultDownloadDirectory -LikePowerShell5

    It 'should use LOCALAPPDATA for default install location' {
        Assert-MockCalled -CommandName 'Join-Path' -ModuleName 'WhsCI' -ParameterFilter { $Path -eq $defaultDownloadRoot }
    }
}