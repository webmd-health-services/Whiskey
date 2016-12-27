
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$originalNodeEnv = $env:NODE_ENV

function Assert-SuccessfulBuild
{
    param(
        $ThatRanIn,
        [string[]]
        $ThatRan = @( 'build', 'test' )
    )

    foreach( $taskName in $ThatRan )
    {
        It ('should run the {0} task' -f $taskName) {
            (Join-Path -Path $ThatRanIn -ChildPath $taskName) | Should Exist
        }
    }
}

function Initialize-NodeProject
{
    param(
        [string[]]
        $DevDependency,

        [switch]
        $WithNoNodeEngine,

        [string]
        $UsingNodeVersion = '^4.4.7'
    )

    $empty = Join-Path -Path $env:Temp -ChildPath ([IO.Path]::GetRandomFileName())
    New-Item -Path $empty -ItemType 'Directory' | Out-Null
    $workingDir = Join-Path -Path $env:Temp -ChildPath 'z'
    try
    {
        while( (Test-Path -Path $workingDir -PathType Container) )
        {
            Write-Verbose -Message 'Removing working directory...'
            Start-Sleep -Milliseconds 100
            robocopy $empty $workingDir /MIR | Write-Verbose
            Remove-Item -Path $workingDir -Recurse -Force
        }
    }
    finally
    {
        Remove-Item -Path $empty -Recurse
    }
    New-Item -Path $workingDir -ItemType 'Directory' | Out-Null

    if( -not $DevDependency )
    {
        $DevDependency = @(
                            '"jit-grunt": "^0.10.0"',
                            '"grunt": "^1.0.1"',
                            '"grunt-cli": "^1.2.0"'
                          )
    }

    $nodeEngine = @"
    "engines": {
        "node": "$($UsingNodeVersion)"
    },
"@
    if( $WithNoNodeEngine )
    {
        $nodeEngine = ''
    }
    $packageJsonPath = Join-Path -Path $workingDir -ChildPath 'package.json'

    @"
{
    $($nodeEngine)
    "private": true,
    "scripts": {
        "envars": "grunt envars",
        "build": "grunt build",
        "test": "grunt test",
        "fail": "grunt fail"
    },

    "devDependencies": {
        $( $DevDependency -join "," )
    }
}
"@ | Set-Content -Path $packageJsonPath

    $gruntfilePath = Join-Path -Path $workingDir -ChildPath 'Gruntfile.js'
    @'
'use strict';
module.exports = function(grunt) {
    require('jit-grunt')(grunt);

    grunt.registerTask('build', '', function(){
        grunt.file.write('build', '');
    });

    grunt.registerTask('test', '', function(){
        grunt.file.write('test', '');
    });

    grunt.registerTask('fail', '', function(){
        grunt.fail.fatal('I failed!');
    });

    grunt.registerTask('envars', '', function(){
        grunt.file.write('envars', '');
        if( ('NODE_PATH' in process.env) )
        {
            grunt.fail.fatal(('NODE_PATH exists and is set to ' + process.env['NODE_PATH']));
        }
    });
}
'@ | Set-Content -Path $gruntfilePath

    return $workingDir
}

function Invoke-FailingBuild
{
    [CmdletBinding()]
    param(
        [string]
        $InDirectory,

        [string]
        $ThatFailsWithMessage,

        [string[]]
        $NpmScript = @( 'fail', 'build', 'test' )
    )

    $failed = $false
    $failure = $null
    try
    {
        Invoke-WhsCINodeTask -WorkingDirectory $InDirectory -NpmScript $NpmScript
    }
    catch
    {
        $failed = $true
        $failure = $_
    }

    It 'should throw an exception' {
        $failed | Should Be $True
        $failure | Should Not BeNullOrEmpty
        $failure | Should Match $ThatFailsWithMessage
    }

    foreach( $script in $NpmScript )
    {
        It ('should not run ''{0}'' NPM script' -f $script) {
            Join-Path -Path $InDirectory -ChildPath $script | Should Not Exist
        }
    }
}

Describe 'Invoke-WhsCINodeTask.when run by a developer' {
    $workingDir = Initialize-NodeProject
    Invoke-WhsCINodeTask -WorkingDirectory $workingDir -NpmScript 'build','test'
    Assert-SuccessfulBuild -ThatRanIn $workingDir
}

Describe 'Invoke-WhsCINodeTask.when a build task fails' {
    $workingDir = Initialize-NodeProject
    Invoke-FailingBuild -InDirectory $workingDir -ThatFailsWithMessage 'npm\ run\b.*\bfailed'
}

Describe 'Invoke-WhsCINodeTask.when a install fails' {
    $workingDir = Initialize-NodeProject -DevDependency '"whs-idonotexist": "^1.0.0"'
    Invoke-FailingBuild -InDirectory $workingDir -ThatFailsWithMessage 'npm\ install\b.*failed'   
}

Describe 'Invoke-WhsCINodeTask.when NODE_ENV is set to production' {
    $env:NODE_ENV = 'production'
    $workingDir = Initialize-NodeProject
    Invoke-WhsCINodeTask -WorkingDirectory $workingDir -NpmScript 'build','test'
    Assert-SuccessfulBuild -ThatRanIn $workingDir
}

Describe 'Invoke-WhsCINodeTask.when node engine is missing' {
    $workingDir = Initialize-NodeProject -WithNoNodeEngine
    Invoke-FailingBuild -InDirectory $workingDir -ThatFailsWithMessage 'Node version is not defined or is missing' -NpmScript @( 'build' )
}

Describe 'Invoke-WhsCINodeTask.when node version is invalid' {
    $workingDir = Initialize-NodeProject -UsingNodeVersion "fubarsnafu"
    Invoke-FailingBuild -InDirectory $workingDir -ThatFailsWithMessage 'Node version ''fubarsnafu'' is invalid' -NpmScript @( 'build' )
}

Describe 'Invoke-WhsCINodeTask.when node version does not exist' {
    $workingDir = Initialize-NodeProject -UsingNodeVersion "438.4393.329"
    Invoke-FailingBuild -InDirectory $workingDir -ThatFailsWithMessage 'version ''.*'' failed to install' -NpmScript @( 'build' ) -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCiNodeTask.when NODE_PATH is defined' {
    $originalNodePath = $null
    $removeNodePath = $true
    if( (Test-Path -Path 'env:NODE_PATH') )
    {
        $originalNodePath = $env:NODE_PATH
        $removeNodePath = $false
    }
    else
    {
        Set-Item -Path 'env:NODE_PATH' -Value 'fubarsnafu'
    }

    $expectedNodePath = $env:NODE_PATH

    try
    {
        $workingDir = Initialize-NodeProject
        Invoke-WhsCINodeTask -WorkingDirectory $workingDir -NpmScript 'envars' | Write-Verbose
        Assert-SuccessfulBuild -ThatRanIn $workingDir -ThatRan 'envars'

        It 'should put original NODE_PATH back' {
            $env:NODE_PATH | Should Be $expectedNodePath
        }
    }
    finally
    {
        if( $removeNodePath )
        {
            Remove-Item -Path 'env:NODE_PATH'
        }
        else
        {
            Set-Item -Path 'env:NODE_PATH' -Value $originalNodePath
        }
    }
}

if( $originalNodeEnv )
{
    $env:NODE_ENV = $originalNodeEnv
}
