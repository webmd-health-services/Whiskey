
function Invoke-WhsCINodeTask
{
    <#
    .SYNOPSIS
    Runs a Node build.
    
    .DESCRIPTION
    The `Invoke-WhsCINodeTask` function runs Node builds. It uses NPM's `run` command to run a list of targets. These targets are defined in your package.json file's `scripts` properties. If any task fails, the build will fail. This function checks if a task fails by looking at the exit code to `npm`. Any non-zero exit code is treated as a failure.

    This task also does the following as part of each Node build:

    * Runs `npm install` to install your dependencies.

    .EXAMPLE
    Invoke-WhsCINodeTask -WorkingDirectory 'C:\Projects\ui-cm' -NpmTarget 'build','test'

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
        $NpmTarget
    )

    Set-StrictMode -Version 'Latest'

    Push-Location -Path $WorkingDirectory
    try
    {
        npm install --production=false
        if( $LASTEXITCODE )
        {
            throw ('Node command `npm install` failed with exit code {0}.' -f $LASTEXITCODE)
        }

        npm run $NpmTarget
        if( $LASTEXITCODE )
        {
            throw ('Node command `npm run {0}` failed with exit code {1}.' -f ($NpmTarget -join ' '),$LASTEXITCODE)
        }
    }
    finally
    {
        Pop-Location
    }
}