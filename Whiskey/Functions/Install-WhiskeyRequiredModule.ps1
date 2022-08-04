
function Install-WhiskeyRequiredModule
{
    [CmdletBinding()]
    param(
        # The directory where package management modules should be installed.
        [Parameter(Mandatory)]
        [String] $PSModulesPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    function Wait
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, ValueFromPipeline)]
            [Object] $Job
        )

        process
        {
            if( (Get-Command -Name 'Receive-Job' -ParameterName 'AutoRemoveJob') )
            {
                $Job | Receive-Job -AutoRemoveJob -Wait
            }
            else
            {
                $Job | Wait-Job | Receive-Job
                $Job | Remove-Job
            }
        }
    }

    # PackageMangement first otherwise a version of PackageManagement gets automatically installed and loaded because
    # PackageManagement is a dependency of PowerShellGet. The version automatically installed may not be the version
    # you want.
    $requiredModules = @(
        [pscustomobject]@{
            Name = 'PackageManagement';
            MinimumVersion = $script:pkgMgmtMinVersion;
            MaximumVersion = $script:pkgMgmtMaxVersion;
        },
        [pscustomobject]@{
            Name = 'PowerShellGet';
            MinimumVersion = $script:psGetMinVersion;
            MaximumVersion = $script:psGetMaxVersion;
        }
    )

    Get-Module -Name ($requiredModules | Select-Object -ExpandProperty 'Name') -ListAvailable |
        Format-Table -Auto |
        Out-String |
        Write-WhiskeyDebug

    Write-WhiskeyDebug "[Install   Begin   ]  $(Get-Date)"
    & {
        foreach( $requiredModule in $requiredModules )
        {
            $installedModules =
                Get-Module -Name $requiredModule.Name -ListAvailable |
                Where-Object Version -ge $requiredModule.MinimumVersion |
                Where-Object Version -le $requiredModule.MaximumVersion
            if( $installedModules )
            {
                continue
            }

            if( -not (Test-Path -Path $PSModulesPath) )
            {
                New-Item -Path $PSModulesPath -ItemType 'Directory' | Out-Null
            }


            Start-Job {
                $name = $using:requiredModule.Name
                $version = $using:requiredModule.MaximumVersion
                $psModulesPath = $using:PSModulesPath
                Write-Debug "[Install           ]  [$($name)]  $(Get-Date)"
                Find-Module -Name $name -RequiredVersion $version |
                    Select-Object -First 1 |
                    ForEach-Object {
                        $msg = "Saving PowerShell module $($name) $($version) to " +
                               "$($psModulesPath | Resolve-Path -Relative)."
                        Write-Information $msg
                        $_ | Save-Module -Path $psModulesPath
                    }
            } | Write-Output
        }
    } | Wait


    Write-WhiskeyDebug "[Install   Complete]  $(Get-Date)"

    foreach( $requiredModule in $requiredModules )
    {
        $msg = "[Import]  $($requiredModule.Name)  $($requiredModule.MinimumVersion) <= " +
               "$($requiredModule.MaximumVersion)"
        Write-WhiskeyDebug $msg
        Import-Module -Name $requiredModule.Name `
                      -MinimumVersion $requiredModule.MinimumVersion `
                      -MaximumVersion $requiredModule.MaximumVersion `
                      -Global
    }

    if( (Test-Path -Path 'env:APPVEYOR') )
    {
        Get-Module -Name ($requiredModules | Select-Object -ExpandProperty 'Name') -ListAvailable |
            Format-Table -Auto
    }
}