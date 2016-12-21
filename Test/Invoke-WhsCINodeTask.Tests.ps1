
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$originalNodeEnv = $env:NODE_ENV

function Assert-SuccessfulBuild
{
    foreach( $taskName in @( 'build', 'test' ) )
    {
        It ('should run the {0} task' -f $taskName) {
            (Join-Path -Path $TEstDRive.Fullname -ChildPath $taskName) | Should Exist
        }
    }
}

function Initialize-NodeProject
{
    param(
        [string[]]
        $DevDependency
    )

    if( -not $DevDependency )
    {
        $DevDependency = @(
                            '"jit-grunt": "^0.10.0"',
                            '"grunt": "^1.0.1"',
                            '"grunt-cli": "^1.2.0"'
                          )
    }
    $packageJsonPath = Join-Path -Path $TEstDRive.FullName -ChildPath 'package.json'
    @"
{
    "private": true,
    "scripts": {
        "build": "grunt build",
        "test": "grunt test",
        "fail": "grunt fail"
    },

    "devDependencies": {
        $( $DevDependency -join "," )
    }
}

"@ | Set-Content -Path $packageJsonPath

    $gruntfilePath = Join-Path -Path $TestDrive.FullName -ChildPath 'Gruntfile.js'
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
}
'@ | Set-Content -Path $gruntfilePath

}

function Invoke-FailingBuild
{
    param(
        [string]
        $ThatFailsWithMessage
    )

    $failed = $false
    $failure = $null
    try
    {
        Invoke-WhsCINodeTask -WorkingDirectory $TestDrive.FullName -NpmTarget 'fail','build','test'
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
}

Describe 'Invoke-WhsCINodeTask.when run by a developer' {
    Initialize-NodeProject
    Invoke-WhsCINodeTask -WorkingDirectory $TestDrive.FullName -NpmTarget 'build','test'
    Assert-SuccessfulBuild
}

Describe 'Invoke-WhsCINodeTask.when a build task fails' {
    Initialize-NodeProject
    Invoke-FailingBuild -ThatFailsWithMessage 'npm\ run\b.*\bfailed'
}

Describe 'Invoke-WhsCINodeTask.when a install fails' {
    Initialize-NodeProject -DevDependency '"whs-idonotexist": "^1.0.0"'
    Invoke-FailingBuild -ThatFailsWithMessage 'npm\ install\b.*failed'   
}

Describe 'Invoke-WhsCINodeTask.when NODE_ENV is set to production' {
    $env:NODE_ENV = 'production'
    Initialize-NodeProject
    Invoke-WhsCINodeTask -WorkingDirectory $TestDrive.FullName -NpmTarget 'build','test'
    Assert-SuccessfulBuild
}

if( $originalNodeEnv )
{
    $env:NODE_ENV = $originalNodeEnv
}