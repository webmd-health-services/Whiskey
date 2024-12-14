
function Install-WhiskeyTool
{
    <#
    .SYNOPSIS
    Downloads and installs tools needed by the Whiskey module.

    .DESCRIPTION
    The `Install-WhiskeyTool` function downloads and installs PowerShell modules or NuGet Packages needed by functions
    in the Whiskey module. PowerShell modules are installed to a `Modules` directory in your build directory. If
    PowerShell modules are already installed globally and are listed in the PSModulePath environment variable, they will
    not be re-installed. A `DirectoryInfo` object for the downloaded tool's directory is returned.

    `Install-WhiskeyTool` also installs tools that are needed by tasks. Tasks define the tools they need with a
    [Whiskey.RequiresTool()] attribute in the tasks function. Supported tools are 'Node', 'NodeModule', and 'DotNet'.

    Users of the `Whiskey` API typcially won't need to use this function. It is called by other `Whiskey` function so
    they have the tools they need.

    .EXAMPLE
    Install-WhiskeyTool -NugetPackageName 'NUnit.Runners' -version '2.6.4'

    Demonstrates how to install a specific version of a NuGet Package. In this case, NUnit Runners version 2.6.4 would
    be installed.
    #>
    [CmdletBinding()]
    param(
        # The attribute that defines what tool is necessary.
        [Parameter(Mandatory, ParameterSetName='FromAttribute')]
        [Whiskey.RequiresToolAttribute] $ToolInfo,

        # The task parameters for the currently running task.
        [Parameter(Mandatory, ParameterSetName='FromAttribute')]
        [hashtable] $TaskParameter,

        # Running in clean mode, so don't install the tool if it isn't installed.
        [Parameter(ParameterSetName='FromAttribute')]
        [switch] $InCleanMode,

        # The path to a directory where downloaded package files should be saved prior to installation.
        [Parameter(Mandatory, ParameterSetName='FromAttribute')]
        [Parameter(ParameterSetName='AtRuntime')]
        [String] $OutFileRootPath,

        [Parameter(ParameterSetName='AtRuntime')]
        [AllowEmptyString()]
        [String] $ProviderName,

        [Parameter(Mandatory, ParameterSetName='AtRuntime')]
        [String] $Name,

        # The name of the NuGet package to download.
        [Parameter(Mandatory, ParameterSetName='NuGet')]
        [String] $NuGetPackageName,

        [Parameter(ParameterSetName='NuGet')]
        [Parameter(ParameterSetName='AtRuntime')]
        [String] $Version,

        # The directory where you want the tools installed.
        [Parameter(Mandatory, ParameterSetName='FromAttribute')]
        [Parameter(Mandatory, ParameterSetName='AtRuntime')]
        [String] $InstallRoot,

        # The root directory where the tools should be downloaded. The default is your build directory.
        #
        # PowerShell modules are saved to `$DownloadRoot\Modules`.
        #
        # NuGet packages are saved to `$DownloadRoot\packages`.
        [Parameter(Mandatory, ParameterSetName='NuGet')]
        [String] $DownloadRoot
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Write-WhiskeyDebug '\Install-WhiskeyTool\' -Indent

    try
    {
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
                $msg = 'The "Install-WhiskeyTool" function''s "NuGetPackage" name parameter is obsolete. Use ' +
                    '[Whiskey.WhiskeyTool] attribute on your task instead.'
                Write-Warning -Message $msg

                Install-WhiskeyNuGetPackage -Name $NuGetPackageName -Version $Version -BuildRootPath $DownloadRoot
                return
            }

            if( $PSCmdlet.ParameterSetName -eq 'FromAttribute' )
            {
                $ProviderName = $ToolInfo.ProviderName
                $Name = $ToolInfo.Name
                $Version = $TaskParameter[$ToolInfo.VersionParameterName]
                if( -not $Version )
                {
                    $Version = $ToolInfo.Version
                }
            }

            if( -not $OutFileRootPath )
            {
                $OutFileRootPath = Join-Path -Path $InstallRoot -ChildPath '.output'
            }

            if( -not (Test-Path -Path $OutFileRootPath) )
            {
                New-Item -Path $OutFileRootPath -ItemType 'Directory' | Out-Null
            }

            if( $ToolInfo -is [Whiskey.RequiresPowerShellModuleAttribute] )
            {
                $module = Install-WhiskeyPowerShellModule -Name $Name `
                                                        -Version $Version `
                                                        -BuildRoot $InstallRoot `
                                                        -SkipImport:$ToolInfo.SkipImport `
                                                        -ErrorAction Stop

                if( $ToolInfo.ModuleInfoParameterName )
                {
                    $TaskParameter[$ToolInfo.ModuleInfoParameterName] = $module
                }

                return
            }

            $toolPath = $null
            switch( $ProviderName )
            {
                'NuGet'
                {
                    $toolPath = Install-WhiskeyNuGetPackage -Name $Name -Version $Version -BuildRootPath $InstallRoot
                }
                'NodeModule'
                {
                    $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $InstallRoot
                    if( -not $nodePath )
                    {
                        $msg = 'It looks like Node isn''t installed in your repository. Whiskey usually installs Node.js ' +
                            'for you into a .node directory. If this directory doesn''t exist, this is most likely a ' +
                            'task authoring error and the author of your task needs to add a `WhiskeyTool` attribute ' +
                            'declaring it has a dependency on Node.js. If the .node directory exists, the Node ' +
                            'package is most likely corrupt. Please delete it and re-run your build.'
                        Write-WhiskeyError -Message $msg -ErrorAction Stop
                        return
                    }
                    $toolPath = Install-WhiskeyNodeModule -Name $Name `
                                                        -BuildRootPath $InstallRoot `
                                                        -Version $Version `
                                                        -Global `
                                                        -InCleanMode:$InCleanMode `
                                                        -ErrorAction Stop
                }
                default
                {
                    switch( $Name )
                    {
                        'Node'
                        {
                            $toolPath = Install-WhiskeyNode -InstallRootPath $InstallRoot `
                                                            -Version $Version `
                                                            -InCleanMode:$InCleanMode `
                                                            -OutFileRootPath $OutFileRootPath
                        }
                        'DotNet'
                        {
                            $toolPath = Install-WhiskeyDotNetTool -InstallRoot $InstallRoot `
                                                                -WorkingDirectory (Get-Location).ProviderPath `
                                                                -Version $Version `
                                                                -ErrorAction Stop
                        }
                        default
                        {
                            throw "Unknown tool ""$($Name)"". The only supported tools are ""Node"" and ""DotNet""."
                        }
                    }
                }
            }

            if( $PSCmdlet.ParameterSetName -eq 'FromAttribute' -and $ToolInfo.PathParameterName )
            {
                $TaskParameter[$ToolInfo.PathParameterName] = $toolPath
            }

            return $toolPath
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
    finally
    {
        Write-WhiskeyDebug '/Install-WhiskeyTool/' -Outdent
    }
}
