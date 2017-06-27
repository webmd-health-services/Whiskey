
function Invoke-WhsCINodeAppPackageTask
{
    <#
    .SYNOPSIS
    Creates a Node-based application package and uploads it to ProGet.

    .DESCRIPTION
    The `NodeAppPackage` task creates a WHS application package for Node.js applications. It behaves exactly like, and accepts the same parameters as, the `AppPackage` task, with the following exceptions:
    
    * The `Include` parameter is optional. The `NodeAppPackage` task uses a default whitelist (which is shown below). If you do provide the `Include` parameter, your `Include` list is *added* to the default whitelist.
    * The `node_modules` directory is *always* incuded in your package as a third-party package, i.e. it is included in your package unfiltered.
    * The `Arc` platform is *excluded* from your package, since most of our Node.js applications don't need it. You can include `Arc` in  your package by setting the `IncludeArc` parameter to `true`.

    You *must* include paths to package with the `Path` parameter. Your application's `package.json` file is included by default.
    
    The default `Include` whitelist is:
    
      * *.css
      * *.dust
      * *.eot
      * *.gif
      * *.html
      * *.jpg
      * *.js
      * *.json
      * *.jsx
      * *.less
      * *.map
      * *.otf
      * *.png
      * *.scss
      * *.sh
      * *.svg
      * *.swf
      * *.ttf
      * *.txt
      * *.woff
      * *.woff2

    Please see the `AppPackage` task for additional documentation and examples.
    
    ## EXAMPLE 1
    
        BuildTasks:
        - NodeAppPackage:
            Name: Overlord
            Description: Node.js service that runs decoupled UI servers and proxy web requests between monolithic web app servers and decoupled web servers.
            IncludeArc: true
            SourceRoot: app
            Path:
            - config
            - lib
        
    This example demonstrates how the Overlord package is created. The package includes all files that match the default whitelist from the `app\config`, `app\lib` directories. All files that match the `app\*.js` and `app\*.json` wildcard patterns are also included. Because Overlord is a service, it needs the `Arc` platform so Overlord can be installed, so the `IncludeArc` parameter is set to `true`.

    ## EXAMPLE 2
    
        BuildTasks:
        - NodeAppPackage:
            Name: ui-cm-arc
            Description: The Condition Management user-interface (Arc integration fork).
            Path:
            - dist
            - src    
            Include:
            - "*.mov"
        
    This example demonstrates how to include extra files in your package that aren't included by the default whitelist. In addition to the default set of Node.js files, this package will also include and `*.mov` files.
    #>
    [Whiskey.Task("NodeAppPackage")]
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
        # * `Path` (Mandatory): the relative paths to the files/directories to include in the package. Paths should be relative to the whsbuild.yml file they were taken from.
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

    $whitelist = @( 
                        #'*.cert', # only found in Node Overlord
                        '*.css',
                        '*.dust',
                        '*.eot',
                        '*.gif',
                        # '*.gzip', # only found in ui-featuremanager: angular.min.js.gzip
                        '*.html',
                        '*.jpg',
                        '*.js',
                        #'*.jshintrc', # only found in ui-featuremanager
                        '*.json',
                        '*.jsx',
                        # '*.key', # only found in Overlord
                        '*.less',
                        '*.map',
                        # '*.md',  # Only readme.md and changelog.md files included in packages
                        '*.otf',
                        '*.png',
                        '*.scss',
                        '*.sh',
                        '*.svg',
                        '*.swf',
                        # '*.ts',  # Look like test files.
                        '*.ttf',
                        '*.txt',
                        '*.woff',
                        '*.woff2'
                  )
    $TaskParameter['Include'] += $whitelist
    $TaskParameter['ExcludeArc'] = -not $TaskParameter.ContainsKey('IncludeArc')
    $TaskParameter['ThirdPartyPath'] = Invoke-Command { 'node_modules' ; $TaskParameter['ThirdPartyPath'] } | Select-Object -Unique
    $TaskParameter['Path'] = Invoke-Command { $TaskParameter['Path'] ; 'package.json' } | Select-Object -Unique

    Invoke-WhsCIAppPackageTask -TaskContext $TaskContext -TaskParameter $TaskParameter
}