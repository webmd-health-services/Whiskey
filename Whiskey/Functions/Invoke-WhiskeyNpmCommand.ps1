
function Invoke-WhiskeyNpmCommand
{
    <#
    .SYNOPSIS
    Runs `npm` with given command and argument.
    
    .DESCRIPTION
    The `Invoke-WhiskeyNpmCommand` function runs `npm` commands in the current workding directory. Pass the path to the build root to the `BuildRootPath` parameter. The function will use the copy of Node and NPM installed in the `.node`  directory in the build root.

    Pass the name of the NPM command to run with the `Name` parameter. Pass any arguments to pass to the command with the `ArgumentList`.

    Task authors should add the `RequiresTool` attribute to their task functions to ensure that Whiskey installs Node and NPM, e.g.

        function MyTask
        {
            [Whiskey.Task('MyTask')]
            [Whiskey.RequiresTool('Node', 'NodePath')]
            param(
            )
        }

    .EXAMPLE
    Invoke-WhiskeyNpmCommand -Name 'install' -BuildRootPath $TaskParameter.BuildRoot -ForDeveloper:$Context.ByDeveloper

    Demonstrates how to run the `npm install` command from a task. 
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The NPM command to execute, e.g. `install`, `prune`, `run-script`, etc.
        $Name,
        
        [string[]]
        # An array of arguments to be given to the NPM command being executed.
        $ArgumentList,

        [Parameter(Mandatory=$true)]
        [string]
        $BuildRootPath,

        [switch]
        # NPM commands are being run on a developer computer.
        $ForDeveloper
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $BuildRootPath -ErrorAction Stop
    if( -not $nodePath )
    {
        return
    }

    $npmPath = Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $BuildRootPath -Global -ErrorAction Stop
    $npmPath = Join-Path -Path $npmPath -ChildPath 'bin\npm-cli.js'

    if( -not $npmPath -or -not (Test-Path -Path $npmPath -PathType Leaf) )
    {
        Write-Error -Message ('Whiskey failed to install NPM. Something pretty serious has gone wrong.')
        return
    }

    # Assign to new variables otherwise Invoke-Command can't find them.
    $commandName = $Name
    $commandArgs = & {
                        $ArgumentList
                        '--scripts-prepend-node-path=auto'
                        if( -not $ForDeveloper )
                        {
                            '--no-color'
                        }
                    }

    $npmCommandString = ('npm {0} {1}' -f $commandName,($commandArgs -join ' '))

    $originalPath = $env:PATH
    Set-Item -Path 'env:PATH' -Value ('{0}{1}{2}' -f (Split-Path -Path $nodePath -Parent),[IO.Path]::PathSeparator,$env:PATH)
    try
    {
        Write-Progress -Activity $npmCommandString
        Invoke-Command -ScriptBlock {
            # The ISE bails if processes write anything to STDERR. Node writes notices and warnings to
            # STDERR. We only want to stop a build if the command actually fails.
            $originalEap = $ErrorActionPreference
            if( $ErrorActionPreference -ne 'SilentlyContinue' -and $ErrorActionPreference -ne 'Ignore' )
            {
                $ErrorActionPreference = 'Continue'
            }
            try
            {
                Write-Verbose ('{0} {1} {2} {3}' -f $nodePath,$npmPath,$commandName,($commandArgs -join ' '))
                & $nodePath $npmPath $commandName $commandArgs
            }
            finally
            {
                Write-Verbose -Message ($LASTEXITCODE)
                $ErrorActionPreference = $originalEap
            }
        }
        if( $LASTEXITCODE -ne 0 )
        {
            Write-Error -Message ('NPM command "{0}" failed with exit code {1}. Please see previous output for more details.' -f $npmCommandString,$LASTEXITCODE)
        }
    }
    finally
    {
        Set-Item -Path 'env:PATH' -Value $originalPath
        Write-Progress -Activity $npmCommandString -Completed -PercentComplete 100
    }
}
