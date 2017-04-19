
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCiTest.ps1' -Resolve)

function Initialize-Test
{
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='PowerShell')]
        [Switch]
        $ForPowerShellModule,

        [Parameter(Mandatory=$true,ParameterSetName='NuGet')]
        [Switch]
        $ForNuGetPackage,

        [Parameter(Mandatory=$true,ParameterSetName='NuGet')]
        [Version]
        $Version,

        [String]
        $ForPath,

        [String]
        $Name
    )

    if( $PSCmdlet.ParameterSetName -eq 'PowerShell' )
    {
        $childPath = 'Modules'
    }
    elseif( $PSCmdlet.ParameterSetName -eq 'NuGet' )
    {
        $childPath = 'Packages'
        $Name = '{0}.{1}' -f $Name, $Version
    }

    if( -not $ForPath )
    {
        $ForPath = Join-Path -Path $TestDrive.FullName -ChildPath $childPath
        
    }
    New-Item -Name $Name -Path $ForPath -ItemType 'Directory' | Out-Null
}

function Invoke-NuGetUninstall
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        $Package,

        [Parameter(Mandatory=$true)]
        [version]
        $Version,

        [Switch]
        $UsingDefaultDownloadRoot
    )

    $downloadRootParam = @{ }
    if( -not $UsingDefaultDownloadRoot )
    {
        $downloadRootParam['DownloadRoot'] = $TestDrive.FullName
    }
    
    $Global:Error.Clear()
    Uninstall-WhsCITool @downloadRootParam -NuGetPackageName $Package -Version $Version

}

function Invoke-PowerShellUninstall
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$True)]
        $ForModule,
       
        [Switch]
        $UsingDefaultDownloadRoot,

        [String]
        $ForPath
    )

    $optionalParams = @{ }
    if( -not $UsingDefaultDownloadRoot )
    {
        $downloadRoot = $TestDrive.FullName 
        $optionalParams['DownloadRoot'] = $downloadRoot
    }
    if ( $ForPath )
    {
        $optionalParams['Path'] = $ForPath
    }

    $Global:Error.Clear()
    Uninstall-WhsCITool -ModuleName $ForModule @optionalParams
}

function Assert-Uninstall
{
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='PowerShell')]
        [Switch]
        $ForPowerShellModule,

        [Parameter(Mandatory=$true,ParameterSetName='NuGet')]
        [Switch]
        $ForNuGetPackage,

        [Parameter(Mandatory=$true,ParameterSetName='NuGet')]
        [version]
        $Version,

        [String]
        $Name,

        [String]
        $FromPath,

        [Switch]
        $UsingDefaultDownloadRoot
    )
    
    if( $PSCmdlet.ParameterSetName -eq 'PowerShell' )
    {
        $childPath = 'Modules'
    }
    elseif( $PSCmdlet.ParameterSetName -eq 'NuGet' )
    {
        $childPath = 'Packages'
        $Name = '{0}.{1}' -f $Name, $Version
    }

    if( $FromPath )
    {
        $uninstalledPath = $FromPath
    }
    else
    {
        $path = Join-Path -Path $TestDrive.FullName -ChildPath $childPath
        $uninstalledPath = Join-Path -Path $path -ChildPath $Name
    }

    It 'should successfully uninstall the WhsCI tool' {
        $uninstalledPath | Should not Exist
    }

    if( $PSCmdlet.ParameterSetName -eq 'PowerShell' -and $FromPath -and -not $UsingDefaultDownloadRoot )
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


Describe 'Uninstall-WhsCITool.when given an NuGet Package' {
    $packageName = 'NUnit.Runners'
    $version = '2.6.4'
    Initialize-Test -ForNuGetPackage -Name $packageName -Version $version
    Invoke-NuGetUninstall -Package $packageName -Version $version
    Assert-Uninstall -ForNuGetPackage -Name $packageName -Version $version
}

Describe 'Uninstall-WhsCITool.when given a PowerShell Module' {
    $moduleName = 'Pester'
    Initialize-Test -ForPowerShellModule -Name $moduleName
    Invoke-PowerShellUninstall -ForModule $moduleName 
    Assert-Uninstall -ForPowerShellModule -Name $moduleName
}

Describe 'Uninstall-WhsCITool.when given a PowerShell Module with a specified path parameter' {
    $moduleName = 'Pester'
    $path = $TestDrive.FullName
    $modulePath = Join-Path -Path $path -ChildPath $moduleName
    Initialize-Test -ForPowerShellModule -Name $moduleName -ForPath $modulePath
    Invoke-PowerShellUninstall -ForModule $moduleName -ForPath $path -ErrorAction SilentlyContinue
    Assert-Uninstall -ForPowerShellModule -Name $moduleName -FromPath $modulePath
}

Describe 'Uninstall-WhsCITool.when using default DownloadRoot' {
    $moduleName = 'Pester'
    $defaultDownloadRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI'
    Mock -CommandName 'Join-Path' `
         -ModuleName 'WhsCI' `
         -MockWith { return Join-Path -Path (Get-Item -Path 'TestDrive:').FullName -ChildPath $ChildPath } `
         -ParameterFilter { $Path -eq $defaultDownloadRoot }.GetNewClosure()

    Initialize-Test -ForPowerShellModule -Name $moduleName 
    Invoke-PowerShellUninstall -ForModule $moduleName -UsingDefaultDownloadRoot
    Assert-Uninstall -ForPowerShellModule -Name $moduleName -UsingDefaultDownloadRoot

    It 'should use LOCALAPPDATA for default install location' {
        Assert-MockCalled -CommandName 'Join-Path' -ModuleName 'WhsCI' -ParameterFilter { $Path -eq $defaultDownloadRoot }
    }
}