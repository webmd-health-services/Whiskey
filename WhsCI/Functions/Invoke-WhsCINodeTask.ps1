
function Invoke-WhsCINodeTask
{
    <#
    .SYNOPSIS
    Runs a Node build.
    
    .DESCRIPTION
    The `Invoke-WhsCINodeTask` function runs Node builds. It uses NPM's `run` command to run a list of NPM scripts. These scripts are defined in your package.json file's `scripts` properties. If any script fails, the build will fail. This function checks if a script fails by looking at the exit code to `npm`. Any non-zero exit code is treated as a failure.

    You are required to specify what version of Node you want in the engines field of your package.json file. (See https://docs.npmjs.com/files/package.json#engines for more information.) The version of Node is installed for you using NVM. 

    This task also does the following as part of each Node build:

    * Runs `npm install` to install your dependencies.

    .EXAMPLE
    Invoke-WhsCINodeTask -WorkingDirectory 'C:\Projects\ui-cm' -NpmScript 'build','test'

    Demonstrates how to run the `build` and `test` NPM targets in the `C:\Projects\ui-cm` directory. The function would run `npm run build test`.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the directory where the Node build should run.
        $WorkingDirectory,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The NPM commands to run as part of the build.
        $NpmScript
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $originalPath = $env:PATH

    Push-Location -Path $WorkingDirectory
    try
    {
        $packageJsonPath = Resolve-Path -Path 'package.json' | Select-Object -ExpandProperty 'ProviderPath'
        if( -not $packageJsonPath )
        {
            throw ('Package.json file ''{0}'' does not exist. This file is mandatory when using the Node build task.' -f (Join-Path -Path (Get-Location).ProviderPath -ChildPath 'package.json'))
        }

        $packageJson = Get-Content -Raw -Path $packageJsonPath | ConvertFrom-Json
        if( -not $packageJson )
        {
            throw ('Package.json file ''{0}'' contains invalid JSON. Please see previous errors for more information.' -f $packageJsonPath)
        }

        if( -not ($packageJson | Get-Member -Name 'engines') -or -not ($packageJson.engines | Get-Member -Name 'node') )
        {
            throw ('Node version is not defined or is missing from the package.json file ''{0}''. Please ensure the Node version to use is defined using the package.json''s engines field, e.g. `"engines": {{ node: "VERSION" }}`. See https://docs.npmjs.com/files/package.json#engines for more information.' -f $packageJsonPath)
            return
        }

        if( $packageJson.engines.node -notmatch '(\d+\.\d+\.\d+)' )
        {
            throw ('Node version ''{0}'' is invalid. The Node version must be a valid semantic version. Package.json file ''{1}'', engines field:{2}{3}' -f $packageJson.engines.node,$packageJsonPath,[Environment]::NewLine,($packageJson.engines | ConvertTo-Json -Depth 50))
        }

        $version = $Matches[1]
        $nodePath = Install-WhsCINodeJs -Version $version
        if( -not $nodePath )
        {
            throw ('Node version ''{0}'' failed to install. Please see previous errors for details.' -f $version)
        }

        $nodeRoot = $nodePath | Split-Path
        $npmPath = Join-Path -Path $nodeRoot -ChildPath 'node_modules\npm\bin\npm-cli.js' -Resolve
        if( -not $npmPath )
        {
            throw ('NPM didn''t get installed by NVM when installing Node {0}. Please use NVM to uninstall this version of Node.' -f $version)
        }

        Set-Item -Path 'env:PATH' -Value ('{0};{1}' -f $nodeRoot,$env:Path)

        $installNoColorArg = @()
        $runNoColorArgs = @()
        if( (Test-WhsCIRunByBuildServer) -or $Host.Name -ne 'ConsoleHost' )
        {
            $installNoColorArg = '--no-color'
            $runNoColorArgs = @( '--', '--no-color' )
        }

        & $nodePath $npmPath 'install' '--production=false' $installNoColorArg
        if( $LASTEXITCODE )
        {
            throw ('Node command `npm install` failed with exit code {0}.' -f $LASTEXITCODE)
        }

        foreach( $script in $npmScript )
        {
            & $nodePath $npmPath 'run' $script $runNoColorArgs
            if( $LASTEXITCODE )
            {
                throw ('Node command `npm run {0}` failed with exit code {1}.' -f $script,$LASTEXITCODE)
            }
        }
    }
    finally
    {
        Set-Item -Path 'env:PATH' -Value $originalPath

        Pop-Location
    }
}
