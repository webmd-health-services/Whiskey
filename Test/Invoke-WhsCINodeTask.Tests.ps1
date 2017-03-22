
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$originalNodeEnv = $env:NODE_ENV
$startedWithNodeEnv = (Test-Path -Path 'env:NODE_ENV')

$defaultPackageName = 'fubarsnafu'

function Invoke-SuccessfulBuild
{
    [CmdletBinding()]
    param(
        [object]
        $WithContext,
        [string]
        $InWorkingDirectory,
        [string[]]
        $ThatRuns,
        [string]
        $ForVersion = '4.4.7',
        [Switch]
        $ByDeveloper,
        [Switch]
        $ByBuildServer
    )

    if( -not $ByDeveloper -and -not $ByBuildServer )
    {
        throw ('You must provide either the ByDeveloper or ByBuildServer switch when calling Assert-SuccessfulBuild.')
    }

    $taskParameter = @{ }

    if( $ThatRuns )
    {
        $taskParameter['NpmScripts'] = $ThatRuns
    }
    
    if( $InWorkingDirectory )
    {
        $taskParameter['WorkingDirectory'] = $InWorkingDirectory
        $InWorkingDirectory = Join-Path -Path $WithContext.BuildRoot -ChildPath $InWorkingDirectory
    }
    else
    {
        $InWorkingDirectory = $WithContext.BuildRoot
    }

    Invoke-WhsCINodeTask -TaskContext $WithContext -TaskParameter $taskParameter

    foreach( $taskName in $ThatRuns )
    {
        It ('should run the {0} task' -f $taskName) {
            (Join-Path -Path $InWorkingDirectory -ChildPath $taskName) | Should Exist
        }
    }

    $versionRoot = Join-Path -Path $env:APPDATA -ChildPath ('nvm\v{0}' -f $ForVersion)
    It ('should prepend path to Node version to path environment variable') {
        Assert-MockCalled -CommandName 'Set-Item' -ModuleName 'WhsCI' -Times 1 -ParameterFilter {
            $Path -eq 'env:Path' -and $Value -like ('{0};*' -f $versionRoot)
        }
    }

    It ('should remove Node version path from path environment variable') {
        Assert-MockCalled -CommandName 'Set-Item' -ModuleName 'WhsCI' -Times 1 -ParameterFilter {
            $Path -eq 'env:Path' -and $Value -notlike ('*{0}*' -f $versionRoot)
        }
    }

    $licensePath = Join-Path -Path $WithContext.OutputDirectory -ChildPath ('node-license-checker-report.json' -f $defaultPackageName)

    Context 'the licenses report' {
        It 'should exist' {
            $licensePath | Should Exist
        }

        $json = Get-Content -Raw -Path $licensePath | ConvertFrom-Json
        It 'should be parsable JSON' {
            $json | Should Not BeNullOrEmpty
        }

        It 'should be transformed from license-checker''s format' {
            $json | Select-Object -ExpandProperty 'name' | Should Not BeNullOrEmpty
            $json | Select-Object -ExpandProperty 'licenses' | Should Not BeNullOrEmpty
        }
    }

    $devDependencyPaths = Join-Path -Path $InWorkingDirectory -ChildPath 'package.json' | 
                            ForEach-Object { Get-Content -Raw -Path $_ } | 
                            ConvertFrom-Json |
                            Select-Object -ExpandProperty 'devDependencies' |
                            Get-Member -MemberType NoteProperty |
                            Select-Object -ExpandProperty 'Name' |
                            ForEach-Object { Join-Path -Path $InWorkingDirectory -ChildPath ('node_modules\{0}' -f $_)  }
    if( $ByBuildServer )
    {
        It 'should prune dev dependencies' {
            $devDependencyPaths | Should Not Exist
        }
    }
    
    if( $ByDeveloper )
    {
        It 'should not prune dev dependencies' {
            $devDependencyPaths | Should Exist
        }
    }
}

function Initialize-NodeProject
{
    param(
        [string[]]
        $DevDependency,

        [string[]]
        $Dependency,
        
        [string]
        $UsingNodeVersion = '^4.4.7',

        [Switch]
        $WithNoName,

        [Switch]
        $ByDeveloper,

        [Switch]
        $ByBuildServer,

        [string]
        $InSubDirectory
    )

    if( $ByDeveloper )
    {
        Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -MockWith { return $true } -ParameterFilter { $Path -eq 'env:NVM_HOME' }
        Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = (Join-Path -Path $env:APPDATA -ChildPath 'nvm') } } -ParameterFilter { $Path -eq 'env:NVM_HOME' }
        $mock = { return $false }
        Set-Item -Path 'env:NODE_ENV' -Value 'developer'
    }
    else
    {
        $mock = { return $true }
        Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -MockWith { return $false } -ParameterFilter { $Path -eq 'env:HOME' }
        Set-Item -Path 'env:NODE_ENV' -Value 'production'
    }

    Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith $mock

    $version = [SemVersion.SemanticVersion]'5.4.3-rc.5+build'
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return $version }.GetNewClosure()

    $empty = Join-Path -Path $env:Temp -ChildPath ([IO.Path]::GetRandomFileName())
    New-Item -Path $empty -ItemType 'Directory' | Out-Null
    $buildRoot = Join-Path -Path $env:Temp -ChildPath 'z'
    $workingDir = $buildRoot
    if( $InSubDirectory )
    {
        $workingDir = Join-Path -Path $buildRoot -ChildPath $InSubDirectory
    }

    try
    {
        while( (Test-Path -Path $buildRoot -PathType Container) )
        {
            Write-Verbose -Message 'Removing working directory...'
            Start-Sleep -Milliseconds 100
            robocopy $empty $buildRoot /MIR | Write-Verbose
            Remove-Item -Path $buildRoot -Recurse -Force
        }
    }
    finally
    {
        Remove-Item -Path $empty -Recurse
    }
    New-Item -Path $buildRoot -ItemType 'Directory' | Out-Null
    New-Item -Path $workingDir -ItemType 'Directory' -Force -ErrorAction Ignore | Out-Null

    Mock -CommandName 'Set-Item' -ModuleName 'WhsCI' -Verifiable

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
    $packageJsonPath = Join-Path -Path $workingDir -ChildPath 'package.json'
    $name = '"name": "{0}",' -f $defaultPackageName
    if( $WithNoName )
    {
        $name = ''
    }

    @"
{
    $($name)
    $($nodeEngine)
    "private": true,
    "scripts": {
        "build": "grunt build",
        "test": "grunt test",
        "fail": "grunt fail"
    },

    "dependencies": {
        $( $Dependency -join ',' )
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
}
'@ | Set-Content -Path $gruntfilePath

    $byWhoArg = @{  }
    if( $ByBuildServer )
    {
        $byWhoArg['ForBuildServer'] = $true
    }
    if( $ByDeveloper )
    {
        $byWhoArg['ForDeveloper'] = $true
    }

    return New-WhsCITestContext -ForBuildRoot $buildRoot -ForTaskName 'Node' -ForVersion $version @byWhoArg -UseActualProGet
}

function Invoke-FailingBuild
{
    [CmdletBinding()]
    param(
        [object]
        $WithContext,

        [string]
        $ThatFailsWithMessage,

        [string[]]
        $NpmScript = @( 'fail', 'build', 'test' ),

        [Switch]
        $WhoseScriptsPass,

        [string]
        $InWorkingDirectory
    )

    $failed = $false
    $failure = $null
    $taskParameter = @{ NpmScripts = $NpmScript }
    if( $InWorkingDirectory )
    {
        $taskParameter['WorkingDirectory'] = $InWorkingDirectory
    }

    try
    {
        Invoke-WhsCINodeTask -TaskContext $WithContext -TaskParameter $taskParameter
    }
    catch
    {
        $failed = $true
        $failure = $_
        Write-Error -ErrorRecord $_
    }

    It 'should throw an exception' {
        $failed | Should Be $True
        $failure | Should Not BeNullOrEmpty
        $failure | Should Match $ThatFailsWithMessage
    }

    foreach( $script in $NpmScript )
    {
        if( $WhoseScriptsPass )
        {
            It ('should run ''{0}'' NPM script' -f $script) {
                Join-Path -Path $WithContext.BuildRoot -ChildPath $script | Should Exist
            }
        }
        else
        {
            It ('should not run ''{0}'' NPM script' -f $script) {
                Join-Path -Path $WithContext.BuildRoot -ChildPath $script | Should Not Exist
            }
        }
    }
}

Describe 'Invoke-WhsCINodeTask.when run by a developer' {
    $context = Initialize-NodeProject -ByDeveloper
    Invoke-SuccessfulBuild -WithContext $context -ByDeveloper -ThatRuns 'build','test'
}

Describe 'Invoke-WhsCINodeTask.when run by build server' {
    $context = Initialize-NodeProject -ByBuildServer
    Invoke-SuccessfulBuild -WithContext $context -ByBuildServer -ThatRuns 'build','test'
}

Describe 'Invoke-WhsCINodeTask.when a build task fails' {
    $context = Initialize-NodeProject -ByDeveloper
    Invoke-FailingBuild -WithContext $context -ThatFailsWithMessage 'npm\ run\b.*\bfailed' -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCINodeTask.when a install fails' {
    $context = Initialize-NodeProject -DevDependency '"whs-idonotexist": "^1.0.0"' -ByDeveloper
    Invoke-FailingBuild -WithContext $context -ThatFailsWithMessage 'npm\ install\b.*failed' -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCINodeTask.when NODE_ENV is set to production' {
    $env:NODE_ENV = 'production'
    $context = Initialize-NodeProject -ByBuildServer 
    Invoke-SuccessfulBuild -WithContext $context -ByBuildServer -ThatRuns 'build','test'
}

Describe 'Invoke-WhsCINodeTask.when module has security vulnerability' {
    $context = Initialize-NodeProject -Dependency @( '"minimatch": "3.0.0"' ) -ByDeveloper
    Invoke-FailingBuild -WithContext $context -ThatFailsWithMessage 'found the following security vulnerabilities' -NpmScript @( 'build' ) -WhoseScriptsPass -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCINodeTask.when packageJson has no name' {
    $context = Initialize-NodeProject -WithNoName -ByDeveloper
    Invoke-FailingBuild -WithContext $context -ThatFailsWithMessage 'name is missing or doesn''t have a value' -NpmScript @( 'build' )  -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCINodeTask.when user forgets to add any NpmScripts' {
    $context = Initialize-NodeProject -ByDeveloper
    Invoke-SuccessfulBuild -WithContext $context -ByDeveloper -WarningVariable 'warnings'
    It 'should warn that there were no NPM scripts' {
        $warnings | Should Match ([regex]::Escape('Element ''NpmScripts'' is missing or empty'))
    }
}

Describe 'Invoke-WhsCINodeTask.when app is not in the root of the repository' {
    $context = Initialize-NodeProject -ByDeveloper -InSubDirectory 's'
    Invoke-SuccessfulBuild -WithContext $context -ByDeveloper -InWorkingDirectory 's' -ThatRuns 'build','test'
}

Describe 'Invoke-WhsCINodeTask.when working directory does not exist' {
    $context = Initialize-NodeProject -ByDeveloper 
    $Global:Error.Clear()
    Invoke-FailingBuild -WithContext $context -ThatFailsWithMessage 'WorkingDirectory\[0\] .* does not exist' -NpmScript @( 'build' ) -InWorkingDirectory 'idonotexist' -ErrorAction SilentlyContinue
    It 'should write one error' {
        $Global:Error.Count | Should Be 1
    }
}

if( $startedWithNodeEnv )
{
    $env:NODE_ENV = $originalNodeEnv
}
elseif( (Test-Path -Path 'env:NODE_ENV') )
{
    Remove-Item -Path 'env:NODE_ENV'
}