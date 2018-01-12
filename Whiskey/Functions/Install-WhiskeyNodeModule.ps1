
function Install-WhiskeyNodeModule
{
    <#
    .SYNOPSIS
    Installs Node.js modules
    
    .DESCRIPTION
    The `Install-WhiskeyNodeModule` function installs Node.js modules to the `node_modules` directory located in the given `ApplicationRoot` parameter and returns the path to the installed module.
    
    The function will use `Invoke-WhiskeyNpmCommand` to execute `npm install` with the given module `Name` to install the Node module.
    
    If `Invoke-WhiskeyNpmCommand` returns a non-zero exit code an error will be written and the function will return nothing. If NPM executes successfully but the module to be installed cannot be found then an error will be written and nothing will be returned.
    
    .EXAMPLE
    Install-WhiskeyNodeModule -Name 'rimraf' -Version '^2.0.0' -ApplicationRoot 'C:\build\app' -RegistryUri 'http://registry.npmjs.org'

    This example will install the Node module `rimraf` at the latest `2.x.x` version in the `node_modules` directory located in `C:\build\app`.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The name of the module to install.
        $Name,

        [string]
        # The version of the module to install.
        $Version,

        [Parameter(Mandatory=$true)]
        [string]
        # The root directory of the target Node.js application. This directory will contain the application's `package.json` config file and will be where Node modules are installed.
        $ApplicationRoot,

        [Parameter(Mandatory=$true,ParameterSetName='Legacy')]
        # The URI to the registry from which Node modules should be downloaded.
        $RegistryUri,

        [switch]
        # Node modules are being installed on a developer computer.
        $ForDeveloper,

        [Parameter(Mandatory=$true,ParameterSetName='New')]
        [string]
        # The path to the node executable.
        $NodePath,

        [Switch]
        # Whether or not to install the module globally.
        $Global
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $npmArgument = & {
                        if( $Version )
                        {
                            ('{0}@{1}' -f $Name,$Version)
                        }
                        else
                        {
                            $Name
                        }
                        if( $Global )
                        {
                            '-g'
                        }
                    }

    $nodeRoot = $ApplicationRoot
    if( $Global )
    {
        $nodeRoot = $NodePath | Split-Path
    }

    $modulePath = Join-Path -Path $nodeRoot -ChildPath ('node_modules\{0}' -f $Name)
    if( (Test-Path -Path $modulePath -PathType Container) )
    {
        return $modulePath
    }  

    Invoke-WhiskeyNpmCommand -NodePath $NodePath -NpmCommand 'install' -Argument $npmArgument -ApplicationRoot $ApplicationRoot | Write-Verbose

    #cat 'package-lock.json' -Raw | Write-Host

    if ($Global:LASTEXITCODE -ne 0)
    {
        Write-Error -Message ('Failed to install Node module ''{0}''. See previous errors for more details.' -f $npmArgument)
        return
    }


    if (-not (Test-Path -Path $modulePath -PathType Container))
    {
        Write-Error -Message ('NPM executed successfully when attempting to install ''{0}'' but the module was not found at ''{1}''' -f $npmArgument,$modulePath)
        return
    }

    return $modulePath
}
