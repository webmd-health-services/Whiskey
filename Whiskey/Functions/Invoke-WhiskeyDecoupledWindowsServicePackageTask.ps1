
function Invoke-WhiskeyDecoupledWindowsServicePackageTask
{
    [Whiskey.Task("DecoupledWindowsServicePackage")]
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
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
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('The property BinPath is mandatory. It should be the path (relative to your whsbuild.yml file) to your service''s bin directory. This is usually where your compiled output goes.')
    }

    $whitelist = @( 
                        '*.js',
                        '*.json',
                        '*.config',
                        '*.dll',
                        '*.exe',
                        '*.xml'
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

    Invoke-WhiskeyAppPackageTask -TaskContext $TaskContext -TaskParameter $TaskParameter
}
