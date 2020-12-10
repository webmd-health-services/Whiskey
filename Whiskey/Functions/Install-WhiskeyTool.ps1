
function Install-WhiskeyTool
{
    <#
    .SYNOPSIS
    Downloads and installs tools needed by the Whiskey module.

    .DESCRIPTION
    The `Install-WhiskeyTool` function downloads and installs PowerShell modules or NuGet Packages needed by functions in the Whiskey module. PowerShell modules are installed to a `Modules` directory in your build root. A `DirectoryInfo` object for the downloaded tool's directory is returned.

    `Install-WhiskeyTool` also installs tools that are needed by tasks. Tasks define the tools they need with a [Whiskey.RequiresTool()] attribute in the tasks function. Supported tools are 'Node', 'NodeModule', and 'DotNet'.

    Users of the `Whiskey` API typcially won't need to use this function. It is called by other `Whiskey` function so they have the tools they need.

    .EXAMPLE
    Install-WhiskeyTool -NugetPackageName 'NUnit.Runners' -version '2.6.4'

    Demonstrates how to install a specific version of a NuGet Package. In this case, NUnit Runners version 2.6.4 would be installed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ParameterSetName='Tool')]
        # The attribute that defines what tool is necessary.
        [Whiskey.RequiresToolAttribute]$ToolInfo,

        [Parameter(Mandatory,ParameterSetName='Tool')]
        # The directory where you want the tools installed.
        [String]$InstallRoot,

        [Parameter(Mandatory,ParameterSetName='Tool')]
        # The task parameters for the currently running task.
        [hashtable]$TaskParameter,

        [Parameter(ParameterSetName='Tool')]
        # Running in clean mode, so don't install the tool if it isn't installed.
        [switch]$InCleanMode,

        [Parameter(Mandatory,ParameterSetName='NuGet')]
        # The name of the NuGet package to download.
        [String]$NuGetPackageName,

        [Parameter(ParameterSetName='NuGet')]
        # The version of the package to download. Must be a three part number, i.e. it must have a MAJOR, MINOR, and BUILD number.
        [String]$Version,

        [Parameter(Mandatory,ParameterSetName='NuGet')]
        # The root directory where the tools should be downloaded. The default is your build root.
        #
        # PowerShell modules are saved to `$DownloadRoot\Modules`.
        #
        # NuGet packages are saved to `$DownloadRoot\packages`.
        [String]$DownloadRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $mutexName = $InstallRoot
    if( $DownloadRoot )
    {
        $mutexName = $DownloadRoot
    }
    # Back slashes in mutex names are reserved.
    $mutexName = $mutexName -replace '\\','/'
    $mutexName = $mutexName -replace '/','-'
    $startedWaitingAt = Get-Date
    $startedUsingAt = Get-Date
    Write-WhiskeyDebug -Message ('Creating mutex "{0}".' -f $mutexName)
    $installLock = New-Object 'Threading.Mutex' $false,$mutexName
    #$DebugPreference = 'Continue'
    Write-WhiskeyDebug -Message ('[{0:yyyy-MM-dd HH:mm:ss}]  Process "{1}" is waiting for mutex "{2}".' -f (Get-Date),$PID,$mutexName)

    try
    {
        try
        {
            [Void]$installLock.WaitOne()
        }
        catch [Threading.AbandonedMutexException]
        {
            Write-WhiskeyDebug -Message ('[{0:yyyy-MM-dd HH:mm:ss}]  Process "{1}" caught "{2}" exception waiting to acquire mutex "{3}": {4}.' -f (Get-Date),$PID,$_.Exception.GetType().FullName,$mutexName,$_)
            $Global:Error.RemoveAt(0)
        }

        $waitedFor = (Get-Date) - $startedWaitingAt
        Write-WhiskeyDebug -Message ('[{0:yyyy-MM-dd HH:mm:ss}]  Process "{1}" obtained mutex "{2}" in {3}.' -f (Get-Date),$PID,$mutexName,$waitedFor)
        #$DebugPreference = 'SilentlyContinue'
        $startedUsingAt = Get-Date

        if( $PSCmdlet.ParameterSetName -eq 'NuGet' )
        {
            if( -not $IsWindows )
            {
                Write-WhiskeyError -Message ('Unable to install NuGet-based package {0} {1}: NuGet.exe is only supported on Windows.' -f $NuGetPackageName,$Version) -ErrorAction Stop
                return
            }
            $packagesRoot = Join-Path -Path $DownloadRoot -ChildPath 'packages'
            $version = Resolve-WhiskeyNuGetPackageVersion -NuGetPackageName $NuGetPackageName -Version $Version -NugetPath $whiskeyNuGetExePath
            if( -not $Version )
            {
                return
            }

            $nuGetRootName = '{0}.{1}' -f $NuGetPackageName,$Version
            $nuGetRoot = Join-Path -Path $packagesRoot -ChildPath $nuGetRootName
            Set-Item -Path 'env:EnableNuGetPackageRestore' -Value 'true'
            if( -not (Test-Path -Path $nuGetRoot -PathType Container) )
            {
               & $whiskeyNuGetExePath install $NuGetPackageName -version $Version -outputdirectory $packagesRoot | Write-CommandOutput -Description ('nuget.exe install')
            }
            return $nuGetRoot
        }
        elseif( $PSCmdlet.ParameterSetName -eq 'Tool' )
        {
            $provider,$name = $ToolInfo.Name -split '::'
            if( -not $name )
            {
                $name = $provider
                $provider = ''
            }

            $version = $TaskParameter[$ToolInfo.VersionParameterName]
            if( -not $version )
            {
                $version = $ToolInfo.Version
            }

            if( $ToolInfo -is [Whiskey.RequiresPowerShellModuleAttribute] )
            {
                if(Test-WhiskeyPowerShellModule -Name $name -Version $version)
                {

                    $globalModules = Get-Module -Name $Name -ListAvailable -ErrorAction Ignore

                    foreach ($globalModule in $globalModules)
                    {
                        if($globalModule.Version -like $version)
                        {
                            $module = $globalModule.Path
                            break
                        } 
                    }

                    if(-not $ToolInfo.SkipImport)
                    {
                        Import-WhiskeyPowershellModule -Name $name -Version $version -InstalledGlobally
                    }
                }
                else 
                {
                    $module = Install-WhiskeyPowerShellModule -Name $name `
                                                            -Version $version `
                                                            -BuildRoot $InstallRoot `
                                                            -SkipImport:$ToolInfo.SkipImport `
                                                            -ErrorAction Stop
                }

                if( $ToolInfo.ModuleInfoParameterName )
                {
                    $TaskParameter[$ToolInfo.ModuleInfoParameterName] = $module
                }
                return
            }

            $toolPath = $null
            switch( $provider )
            {
                'NodeModule'
                {
                    $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $InstallRoot
                    if( -not $nodePath )
                    {
                        Write-WhiskeyError -Message ('It looks like Node isn''t installed in your repository. Whiskey usually installs Node for you into a .node directory. If this directory doesn''t exist, this is most likely a task authoring error and the author of your task needs to add a `WhiskeyTool` attribute declaring it has a dependency on Node. If the .node directory exists, the Node package is most likely corrupt. Please delete it and re-run your build.') -ErrorAction stop
                        return
                    }
                    $toolPath = Install-WhiskeyNodeModule -Name $name `
                                                          -BuildRootPath $InstallRoot `
                                                          -Version $version `
                                                          -Global `
                                                          -InCleanMode:$InCleanMode `
                                                          -ErrorAction Stop
                }
                default
                {
                    switch( $name )
                    {
                        'Node'
                        {
                            $toolPath = Install-WhiskeyNode -InstallRoot $InstallRoot -Version $version -InCleanMode:$InCleanMode
                        }
                        'DotNet'
                        {
                            $toolPath = Install-WhiskeyDotNetTool -InstallRoot $InstallRoot -WorkingDirectory (Get-Location).ProviderPath -Version $version -ErrorAction Stop
                        }
                        default
                        {
                            throw ('Unknown tool "{0}". The only supported tools are "Node" and "DotNet".' -f $name)
                        }
                    }
                }
            }

            if( $ToolInfo.PathParameterName )
            {
                $TaskParameter[$ToolInfo.PathParameterName] = $toolPath
            }
        }
    }
    finally
    {
        #$DebugPreference = 'Continue'
        $usedFor = (Get-Date) - $startedUsingAt
        Write-WhiskeyDebug -Message ('[{0:yyyy-MM-dd HH:mm:ss}]  Process "{1}" releasing mutex "{2}" after using it for {3}.' -f (Get-Date),$PID,$mutexName,$usedFor)
        $startedReleasingAt = Get-Date
        $installLock.ReleaseMutex();
        $installLock.Dispose()
        $installLock.Close()
        $installLock = $null
        $releasedDuration = (Get-Date) - $startedReleasingAt
        Write-WhiskeyDebug -Message ('[{0:yyyy-MM-dd HH:mm:ss}]  Process "{1}" released mutex "{2}" in {3}.' -f (Get-Date),$PID,$mutexName,$releasedDuration)
        #$DebugPreference = 'SilentlyContinue'
    }
}
