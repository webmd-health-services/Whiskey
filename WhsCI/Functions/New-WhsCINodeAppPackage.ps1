
function New-WhsCINodeAppPackage
{
    <#
    .SYNOPSIS
    Creates a Node-based application package and uploads it to ProGet.

    .DESCRIPTION
    The `New-WhsCINodeAppPackage` function creates a WHS application package for Node.js applications and uploads it to ProGet. It uses `New-WhsCIWhsAppPackage` to do the actual packaging and uploading to ProGet. Pass the context of the current build to the `TaskContext` parameter (use the `New-WhsCIContext` function to create contexts). Pass the task parameters in a hashtable via the `TaskParameter` parameter. Available parameters are:

     * `Path` (Mandatory): the relative paths to the files/directories to include in the package. Paths should be relative to the whsbuild.yml file they were taken from.
     * `Name` (Mandatory): the name of the package to create.
     * `Description` (Mandatory): a description of the package.
     * `Include`: a whitelist of wildcard patterns and filenames that should be included in the package. Only files under `Path` that match items an item in this list are included in the package.
     * `Exclude`: a list of wildcard patterns and filenames that should be excluded from the package.
     * `ThirdPartyPath`: a list of third-party directories/files that should be added to the package without being filtered by `Include` or `Exclude` lists.
    
    The `New-WhsCINodeAppPackage` function uses a default whitelist applicable to Node.js applications. Files that match the following wildcards will be included for you:

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

    Any values passed via the `Include` parameter are added to this list.

    .EXAMPLE
    New-WhsCINodeAppPackage -TaskContext $context -TaskParameter @{ Name = 'ui-cm'; Description = 'The Condition Management user interface.'; Path = 'dist','src'; }

    Demonstrates how to create a Node.js application package. In this example, a package will get created that includes the `dist` and `src` directories, found in the directory specified by the `TaskPathRoot` property on the `$context` object. The package's name will be set to `ui-cm`. The package's description will be set to `The Condition Management user interface.`. The package's version will be set to the value of the `Version` property of the context object.


    .EXAMPLE
    New-WhsCINodeAppPackage -TaskContext $context -TaskParameter @{ Name = 'ui-cm'; Description = 'The Condition Management user interface.'; Path = 'dist','src'; Include = '*.md' }

    Demonstrates how to deploy files that aren't part of the default whitelist. In this example, files that match the `*.md` wildcard pattern will also be part of the package.
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
        # * `Path` (Mandatory): the relative paths to the files/directories to include in the package. Paths should be relative to the whsbuild.yml file they were taken from.
        # * `Name` (Mandatory): the name of the package to create.
        # * `Description` (Mandatory): a description of the package.
        # * `Include`: a whitelist of wildcard patterns and filenames that should be included in the package. Only files under `Path` that match items an item in this list are included in the package.
        # * `Exclude`: a list of wildcard patterns and filenames that should be excluded from the package.
        # * `ThirdPartyPath`: a list of third-party directories/files that should be added to the package without being filtered by `Include` or `Exclude` lists.
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

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

    $TaskParameter['ThirdPartyPath'] = Invoke-Command { 'node_modules' ; $TaskParameter['ThirdPartyPath'] } | Select-Object -Unique

    New-WhsCIAppPackage -TaskContext $TaskContext -TaskParameter $TaskParameter
}