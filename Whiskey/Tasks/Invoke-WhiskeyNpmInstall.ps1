
function Invoke-WhiskeyNpmInstall
{
    <#
    .SYNOPSIS
    Installs Node.js packages.

    .DESCRIPTION
    The `NpmInstall` task will use NPM's `install` command to install Node.js packages. By default, the task will run `npm install` to install all packages listed in your `package.json` file's `dependency` and `devDependency` properties. 
    
    You can install a specific package with the `Package` property. It should be a list of package names. You can specify a specific version of the module with this syntax:

        BuildTasks:
        - NpmInstall:
            Package:
            - rimraf: ^2.0.0

    In this example, the latest 2.x version of the `rimraf` module would be installed.

    This task will install the latest LTS version of Node into a `.node` directory (in the same directory as your whiskey.yml file). To use a specific version, set the `engines.node` property in your package.json file to the version you want. (See https://docs.npmjs.com/files/package.json#engines for more information.)

    You may additionally specify a version of NPM to use in the `engines.npm` field of your package.json file. The version of NPM will be upgraded to that version. Downgrading to a version older than the one that ships with your version of Node is not supported.

    # Properties

    * `Package`: a list of NPM packages to install. List items can simply be package names, `rimraf`, or package names with semantic version numbers that NPM understands, e.g. `rimraf: ^2.0.0`. When using the `Package` property the task will only install the given packages and not the ones listed in the `package.json` file.
    * `WorkingDirectory`: the directory where the `package.json` exists. Defaults to the directory where the build's `whiskey.yml` file was found. Must be relative to the `whiskey.yml` file.

    # Examples

    ## Example 1

        BuildTasks:
        - NpmInstall

    This example will install all the Node packages listed in the `package.json` file to the `BUILD_ROOT\node_modules` directory.

    ## Example 2

        BuildTasks:
        - NpmInstall:
            Package:
            - gulp

    This example will install the Node package `gulp` to the `BUILD_ROOT\node_modules` directory.

    ## Example 3

        BuildTasks:
        - NpmInstall:
            WorkingDirectory: app
            Package:
            - gulp
            - rimraf: ^2.0.0

    This example will install the Node packages `gulp` and the latest 2.x.x version of `rimraf` to the `BUILD_ROOT\app\node_modules` directory.
    #>
    [Whiskey.Task('NpmInstall')]
    [Whiskey.RequiresTool('Node', 'NodePath')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
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

    $workingDirectory = (Get-Location).ProviderPath

    $nodePath = $TaskParameter['NodePath']
    if( -not $nodePath -or -not (Test-Path -Path $nodePath -PathType Leaf) )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Whiskey didn''t install Node. Something pretty serious has gone wrong.')
    }

    if( -not $TaskParameter['Package'] )
    {
        Write-Timing -Message 'Installing Node modules'
        Invoke-WhiskeyNpmCommand -NodePath $nodePath -NpmCommand 'install' -Argument '--production=false' -ApplicationRoot $workingDirectory -ForDeveloper:$TaskContext.ByDeveloper -ErrorAction Stop
        Write-Timing -Message 'COMPLETE'
    }
    else
    {
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

            Write-Timing -Message ('Installing {0}' -f $packageName)
            Install-WhiskeyNodeModule -NodePath $nodePath -ApplicationRoot $workingDirectory -Name $packageName -Version $packageVersion -ForDeveloper:$TaskContext.ByDeveloper -ErrorAction Stop
            Write-Timing -Message 'COMPLETE'
        }
    }
}
