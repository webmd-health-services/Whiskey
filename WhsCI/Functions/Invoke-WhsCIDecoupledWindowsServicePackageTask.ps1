
function Invoke-WhsCIDecoupledWindowsServicePackageTask
{
    <#
    .SYNOPSIS
    Creates a Decoupled Windows Service package and uploads it to ProGet.

    .DESCRIPTION
    The `DecoupledWindowsServicePackage` task creates a WHS application package for Decoupled Windows applications. It behaves exactly like, and accepts the same parameters as, the `AppPackage` task, with the following exceptions:
    
    * The `Include` parameter is optional. The `DecoupledWindowsServicePackage` task automatically includes `.js` and `.json` files in the default whitelist. If you do provide the `Include` parameter, your `Include` list is *added* to the default whitelist.
    * Any `.js` or `.json` files in either your `resources/nad` or `resources/rabbitMQ` directories are *always* incuded in your package if they exist.

    You *must* include the `BinPath` parameter. This should point to the bin directory in the root of your package and is where the task will copy your files from. Your application's `services.json` file is included by default.
    
    The default `Include` whitelist is:
    
      * *.js
      * *.json

    Please see the `AppPackage` task for additional documentation and examples.
    
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context this task is operating in. Use `New-WhsCIContext` to create context objects.
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        # The parameters/configuration to use to run the task. Should be a hashtable that contains the following items:
        # 
        # * `Path` (Mandatory): the relative paths to any additional files/directories to include in the package. Paths should be relative to the whsbuild.yml file they were taken from.
        #                       Note: `resources/nad` and `resources/rabbitmq` are included by default and do not need to be explicitly added to the `Path` parameter.
        # * `BinPath` (Mandatory): the relative path to the `bin` directory containing the files to include in the package.
        # * `Name` (Mandatory): the name of the package to create.
        # * `Description` (Mandatory): a description of the package.
        # * `Include`: a whitelist of wildcard patterns and filenames that should be included in the package. Only files under `Path` that match items an item in this list are included in the package.
        # * `Exclude`: a list of wildcard patterns and filenames that should be excluded from the package.
        # * `ThirdPartyPath`: a list of third-party directories/files that should be added to the package without being filtered by `Include` or `Exclude` lists.
        $TaskParameter,

        [Switch]
        $Clean
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if ( $Clean )
    {
        return
    }

    if( -not $TaskParameter.ContainsKey('BinPath') )
    {
        Stop-WhsCITask -TaskContext $TaskContext -Message ('BinPath is mandatory.')
    }

    $whitelist = @( 
                        '*.js',
                        '*.json'
                  )
    $path = @(
        $TaskParameter.BinPath
    )

        $servicesPath = (Join-Path -Path $TaskContext.BuildRoot -ChildPath 'services.json')
    if( -not (Test-Path -Path $servicesPath -PathType Leaf ) )
    {
        $servicesPath = (Join-Path -Path $TaskContext.BuildRoot -childPath 'resources\services.json')
    }

    $nadPath = (Join-Path -Path $TaskContext.BuildRoot -childPath 'resources/nad')
    $rabbitMQPath = (Join-Path -Path $TaskContext.BuildRoot -childPath 'resources/rabbitmq')
    if( Test-Path -Path $servicesPath -PathType leaf )
    {
        $path += $servicesPath
    }
    if( Test-Path -Path $nadPath )
    {
        $path += $nadPath
    }
    if( Test-Path -Path $rabbitMQPath )
    {
        $path += $rabbitMQPath
    }

    $TaskParameter['Include'] += $whitelist
    $TaskParameter['Path'] = Invoke-Command { $TaskParameter['Path'] ; $path } | Select-Object -Unique

    Invoke-WhsCIAppPackageTask -TaskContext $TaskContext -TaskParameter $TaskParameter
}