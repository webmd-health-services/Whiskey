
function Invoke-WhiskeyNpmInstall
{
    [Whiskey.Task('NpmInstall',SupportsClean,Obsolete,ObsoleteMessage='The "NpmInstall" task is obsolete. It will be removed in a future version of Whiskey. Please use the "Npm" task instead.')]
    [Whiskey.RequiresTool('Node',PathParameterName='NodePath',VersionParameterName='NodeVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $workingDirectory = (Get-Location).ProviderPath

    if( -not $TaskParameter['Package'] )
    {
        if( $TaskContext.ShouldClean )
        {
            Write-WhiskeyDebug -Context $TaskContext -Message 'Removing project node_modules'
            Remove-WhiskeyFileSystemItem -Path 'node_modules' -ErrorAction Stop
        }
        else
        {
            Write-WhiskeyDebug -Context $TaskContext -Message 'Installing Node modules'
            Invoke-WhiskeyNpmCommand -Name 'install' -ArgumentList '--production=false' -BuildRootPath $TaskContext.BuildRoot -ForDeveloper:$TaskContext.ByDeveloper -ErrorAction Stop
        }
        Write-WhiskeyDebug -Context $TaskContext -Message 'COMPLETE'
    }
    else
    {
        $installGlobally = $false
        if( $TaskParameter.ContainsKey('Global') )
        {
            $installGlobally = $TaskParameter['Global'] | ConvertFrom-WhiskeyYamlScalar
        }

        foreach( $package in $TaskParameter['Package'] )
        {
            $packageVersion = ''
            if ($package | Get-Member -Name 'Keys')
            {
                $packageName = $package.Keys | Select-Object -First 1
                $packageVersion = $package[$packageName]
            }
            else
            {
                $packageName = $package
            }

            if( $TaskContext.ShouldClean )
            {
                if( $TaskParameter.ContainsKey('NodePath') -and (Test-Path -Path $TaskParameter['NodePath'] -PathType Leaf) )
                {
                    Write-WhiskeyDebug -Context $TaskContext -Message ('Uninstalling {0}' -f $packageName)
                    Uninstall-WhiskeyNodeModule -BuildRootPath $TaskContext.BuildRoot `
                                                -Name $packageName `
                                                -ForDeveloper:$TaskContext.ByDeveloper `
                                                -Global:$installGlobally `
                                                -ErrorAction Stop
                }
            }
            else
            {
                Write-WhiskeyDebug -Context $TaskContext -Message ('Installing {0}' -f $packageName)
                Install-WhiskeyNodeModule -BuildRootPath $TaskContext.BuildRoot `
                                          -Name $packageName `
                                          -Version $packageVersion `
                                          -ForDeveloper:$TaskContext.ByDeveloper `
                                          -Global:$installGlobally `
                                          -ErrorAction Stop
            }
            Write-WhiskeyDebug -Context $TaskContext -Message 'COMPLETE'
        }
    }
}
