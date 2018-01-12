
function Invoke-WhiskeyNpmCommand
{
    <#
    .SYNOPSIS
    Runs `npm` with given command and argument.
    
    .DESCRIPTION
    The `Invoke-WhiskeyNpmCommand` function runs `npm` commands with given arguments in a Node.js project. The function will first call `Install-WhiskeyNodeJs` and `Get-WhiskeyNPMPath` to download and install the desired versions of Node.js and npm listed in the project's `package.json` `engines` field. Then `npm` will be invoked with the given `NpmCommand` and `Argument` in the `ApplicationRoot` directory. If `npm` returns a non-zero exit code this function will write an error indicating that the npm command failed.

    You must specify the `npm` command you would like to run with the `NpmCommand` parameter. Optionally, you may specify arguments for the `npm command` with the `Argument` parameter.

    The `ApplicationRoot` parameter must contain the path to the directory where the Node.js module's `package.json` can be found.

    .EXAMPLE
    Invoke-WhiskeyNpmCommand -NpmCommand 'install' -ApplicationRoot 'src\app' -RegistryUri 'http://registry.npmjs.org' -ForDeveloper

    Runs the `npm install' command without any arguments in the 'src\app' directory as a developer.

    .EXAMPLE
    Invoke-WhiskeyNpmCommand -NpmCommand 'run' -Argument 'test --silent' -ApplicationRoot 'src\app' -RegistryUri 'http://registry.npmjs.org'

    Executes `npm run test --silent` in the 'src\app' directory.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='NodePath')]
        [string]
        $NodePath,

        [Parameter(Mandatory=$true,ParameterSetName='NodePath')]
        [Parameter(Mandatory=$true,ParameterSetName='InvokeNpm')]
        [string]
        # The NPM command to execute.
        $NpmCommand,
        
        [Parameter(ParameterSetName='NodePath')]
        [Parameter(ParameterSetName='InvokeNpm')]
        [string[]]
        # An array of arguments to be given to the NPM command being executed.
        $Argument,

        [switch]
        # NPM commands are being run on a developer computer.
        $ForDeveloper
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $startedAt = Get-Date
    function Write-Timing
    {
        param(
            $Message
        )

        $now = Get-Date
        Write-Debug -Message ('[{0}]  [{1}]  {2}' -f $now,($now - $startedAt),$Message)
    }

    $nodeRoot = $NodePath | Split-Path
        
    Write-Timing -Message 'Resolving path to NPM.'
    $npmPath = Get-WhiskeyNPMPath -NodePath $nodePath
    Write-Timing -Message ('COMPLETE')
    
    if( -not $npmPath )
    {
        Write-Error -Message ('Could not locate version of NPM that is required for this package. Please see previous errors for details.')
        $Global:LASTEXITCODE = 3
        return
    }

    $originalPath = $env:PATH

    Set-Item -Path 'env:PATH' -Value ('{0};{1}' -f $nodeRoot,$env:Path)
    try
    {

        $defaultArguments = @('--scripts-prepend-node-path=auto')
        if( -not $ForDeveloper )
        {
            $defaultArguments += '--no-color'
        }

        $npmCommandString = ('npm {0} {1} {2}' -f $NpmCommand,($Argument -join ' '),($defaultArguments -join ' '))

        Write-Progress -Activity $npmCommandString
        Write-Verbose $npmCommandString
        Invoke-Command -NoNewScope -ScriptBlock {
            # The ISE bails if processes write anything to STDERR. Node writes notices and warnings to
            # STDERR. We only want to stop a build if the command actually fails.
            $ErrorActionPreference = 'Continue'
            & $nodePath $npmPath $NpmCommand $Argument $defaultArguments
        }
        if( $LASTEXITCODE -ne 0 )
        {
            Write-Error -Message ('NPM command ''{0}'' failed with exit code {1}. Please see previous output for more details.' -f $npmCommandString,$LASTEXITCODE)
        }
    }
    finally
    {
        Set-Item -Path 'env:PATH' -Value $originalPath
        Write-Progress -Activity $npmCommandString -Completed -PercentComplete 100
    }
}
