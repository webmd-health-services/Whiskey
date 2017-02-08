
function New-WhsCINodeAppPackage
{
    <#
    .SYNOPSIS
    Creates a Node-based application package and uploads it to ProGet.

    .DESCRIPTION
    The `New-WhsCINodeAppPackage` function creates a WHS application package for Node.js applications and uploads it to ProGet. It uses `New-WhsCIWhsAppPackage` to do the actual packaging and uploading to ProGet. Pass the path

    Pass the paths to package to the `Path` parameter. The `node_modules` directory is *always* included and is added to the package unfiltered.
    
    The `New-WhsCINodeAppPackage` function includes files that match the wildcards in this whitelist:

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

    To include additional files, pass wildcard patterns or filenames that match those files to the `Include` parameter.

    .EXAMPLE
    New-WhsCINodeAppPackage -RepositoryRoot 'C:\Projects\ui-cm' -Name 'ui-cm' -Description 'The Condition Management user interface.' -Version '2017.207.43+develop.deadbee' -Path 'dist','src'

    Demonstrates how to create a Node.js application package. In this example, a package will get created that includes the `dist` and `src` directories found in the `C:\Projects\ui-cm` directory. The package's name will be set to `ui-cm`. The package's description will be set to `The Condition Management user interface.`. The package's version will be set to `2017.207.43+develop.deadbee`.


    .EXAMPLE
    New-WhsCINodeAppPackage -RepositoryRoot 'C:\Projects\ui-cm' -Name 'ui-cm' -Description 'The Condition Management user interface.' -Version '2017.207.43+develop.deadbee' -Path 'dist','src' -Include '*.md'

    Demonstrates how to deploy files that aren't part of the default whitelist. In this example, files that match the `*.md` wildcard pattern will also be part of the package.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the root of the repository the application lives in.
        $RepositoryRoot,

        [Parameter(Mandatory=$true)]
        [string]
        # The name of the package being created.
        $Name,

        [Parameter(Mandatory=$true)]
        [string]
        # A description of the package.
        $Description,

        [Parameter(Mandatory=$true)]
        [SemVersion.SemanticVersion]
        # The package's version.
        $Version,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The filenames/directories to include in the package. Relative paths are resolved relative to the current directory. All files under these directories that match the standard whitelist and any additional filenames and wildcard patterns you pass to the `Include` parameter are included. The `node_modules` directory is *always* included, unfiltered, so you don't need to add it to this list.
        $Path,

        [string[]]
        # Filenames and wildcard patterns for files to include in the package that aren't part of the `New-WhsCINodeAppPackage` function's default whitelist. This help topic's Description section shows the default whitelist.
        $Include,

        [Parameter(Mandatory=$true,ParameterSetName='WithUpload')]
        [string]
        # The URI to the package's feed in ProGet. The package will be uploaded to this feed.
        $ProGetPackageUri,

        [Parameter(Mandatory=$true,ParameterSetName='WithUpload')]
        [pscredential]
        # The credential to use to upload the package to ProGet.
        $ProGetCredential,

        [Parameter(Mandatory=$true,ParameterSetName='WithUpload')]
        [object]
        # An object that represents the instance of BuildMaster to connect to.
        $BuildMasterSession,
        
        [string[]]
        # A list of files and/or directories to exclude. Wildcards supported. If any file or directory that would match a pattern in the `Include` list matches an item in this list, it is not included in the package.
        # 
        # `New-WhsCINodeAppPackage` will *always* exclude directories named:
        #
        # * .git
        # * .hg
        # * obj
        $Exclude,

        [string[]]
        # Paths to any third-party directories that should get included in the package. Third-party paths are copied as-is, warts and all. Nothing is excluded and the whitelist is ignored (i.e. the `Include` and `Exclude` parameters do not apply to any third-party paths). The `node_modules` directory is *always* included as a third-party item.
        $ThirdPartyPath        
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

    $PSBoundParameters['Include'] += $whitelist

    $PSBoundParameters['ThirdPartyPath'] = Invoke-Command { 'node_modules' ; $ThirdPartyPath } | Select-Object -Unique

    New-WhsCIAppPackage @PSBoundParameters
}