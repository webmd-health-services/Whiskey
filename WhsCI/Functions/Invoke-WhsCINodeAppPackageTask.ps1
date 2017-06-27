
function Invoke-WhsCINodeAppPackageTask
{
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
    $TaskParameter['Path'] = Invoke-Command { $TaskParameter['Path'] ; 'package.json' } | Select-Object -Unique

    Invoke-WhsCIAppPackageTask -TaskContext $TaskContext -TaskParameter $TaskParameter
}