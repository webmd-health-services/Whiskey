#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Import-WhiskeyTestTaskModule -Name 'Glob'

[Whiskey.Context]$context = $null
$fsCaseSensitive = $false
$testRoot = $null

# Don't let Carbon's alias interfere with our function.
if( (Test-Path -Path 'alias:Resolve-RelativePath') )
{
    Remove-Item -Path 'alias:Resolve-RelativePath'
}

function Resolve-RelativePath
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,Position=0)]
        [String[]]$Path
    )

    $outsideBuildRootIdentifier = '..{0}' -f [IO.Path]::DirectorySeparatorChar
    foreach( $item in $Path )
    {
        # Normalize separators
        $item = $item | Convert-WhiskeyPathDirectorySeparator

        if( $item.StartsWith($outsideBuildRootIdentifier) )
        {
            Write-Output $item
        } 
        else
        {
            Write-Output (Join-Path -Path '.' -ChildPath $item)
        }
    }
}

function GivenDirectory
{
    param(
        $Name
    )

    New-Item -Path (Join-Path -Path $testRoot -ChildPath $Name) -ItemType 'Directory'
}

function GivenFile
{
    param(
        [String[]]$Name,
        [Switch]$Hidden
    )

    foreach( $path in $Name )
    {
        if( -not [IO.Path]::IsPathRooted($path) )
        {
            $path = Join-Path -Path $testRoot -ChildPath $path
        }
        $item = New-Item -Path $path -Force
        if( $Hidden )
        {
            $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
        }
    }
}

function Init
{
    $script:context = $null
    $script:fsCaseSensitive = -not (Test-Path -Path ($PSScriptRoot.ToUpperInvariant()))
    $script:testRoot = New-WhiskeyTestRoot
    Clear-LastTaskBoundParameter
}

function Reset
{
    Reset-WhiskeyTestPSModule
}
function ThenPipelineSucceeded
{
    $Global:Error | Should -BeNullOrEmpty
    $threwException | Should -BeFalse
}

function ThenTaskCalled
{
    param(
        [hashtable]$WithParameter
    )

    $taskParameters = Get-LastTaskBoundParameter

    $null -eq $taskParameters | Should -BeFalse

    if( $WithParameter )
    {
        $taskParameters.Count | Should -Be $WithParameter.Count
        foreach( $key in $WithParameter.Keys )
        {
            ($taskParameters[$key] | Sort-Object) | Should -Be ($WithParameter[$key] | Sort-Object) -Because $key
        }
    }
}

function ThenTaskNotCalled
{
    $taskParameters = Get-LastTaskBoundParameter
    $null -eq $taskParameters | Should -BeTrue
}

function ThenThrewException
{
    param(
        $Pattern
    )

    $threwException | Should -BeTrue
    $Global:Error | Should -Match $Pattern
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [String]$Name,

        [hashtable]$Parameter,

        [String]$BuildRoot = $testRoot
    )

    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $BuildRoot -IncludePSModule 'Glob'
    $context.PipelineName = 'Build'
    $context.TaskIndex = 1

    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name $Name -Parameter $Parameter
    }
    catch
    {
        $script:threwException = $true
        Write-CaughtError $_
    }
}

Describe ('Resolve-WhiskeyTaskPath.when parameter is an optional path') {
    It 'should resolve the parameter to a relative path' {
        Init
        WhenRunningTask 'ValidateOptionalPathTask' -Parameter @{ 'Path' = 'whiskey.yml' } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath -Path 'whiskey.yml') }
    }
}

Describe ('Resolve-WhiskeyTaskPath.when parameter is an optional path but it doesn''t exist') {
    It 'should return relative path' {
        Init
        WhenRunningTask 'ValidateOptionalPathTask' -Parameter @{ 'Path' = 'somefile.txt' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'does\ not\ exist'
    }
}

Describe ('Resolve-WhiskeyTaskPath.when parameter is a path with wildcards') {
    It 'should resolve path to actual paths' {
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.yml' } 
        ThenPipelineSucceeded
        ThenTaskCalled
        $taskParameters = Get-LastTaskBoundParameter
        $taskParameters['Path'] | Should -HaveCount 2
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'abc.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'whiskey.yml')
    }
}

Describe ('Resolve-WhiskeyTaskPath.when parameter is a hidden path') {
    It 'should resolve path to actual paths' {
        Init
        GivenFile '.hidden.yml' -Hidden
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.yml' } 
        ThenPipelineSucceeded
        $expectedPaths = @(
            (Resolve-RelativePath '.hidden.yml')
            (Resolve-RelativePath 'whiskey.yml')
        )
        ThenTaskCalled -WithParameter @{ 'Path' = $expectedPaths }
    }
}

Describe ('Resolve-WhiskeyTaskPath.when parameter is a path that the user wants resolved with a wildcard but doesn''t exist') {
    It 'should fail' {
        Init
        GivenFile 'abc.yml' 
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.fubar' } -ErrorAction SilentlyContinue
        ThenThrewException 'does\ not\ exist'
        ThenTaskNotCalled
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path parameter wants to be resolved but parameter type isn''t a string array') {
    It 'should fail' {
        Init
        GivenFile 'abc.txt' 
        GivenFile 'xyz.txt' 
        WhenRunningTask 'ValidateOptionalPathTask' -Parameter @{ 'Path' = '*.txt' } -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'requires\ a\ single\ path'
        ThenTaskNotCalled
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path should be a file') {
    It ('should pass full path to file') {
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'abc.yml') }
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path should be a file but it''s a directory') {
    It ('should fail') {
        Init
        GivenDirectory 'abc.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should resolve to a file'
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path should be a directory but it''s a file') {
    It ('should fail') {
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryDirectoryTask' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should resolve to a directory'
    }
}

Describe ('Resolve-WhiskeyTaskPath.when all paths should be files but one is a directory') {
    It ('should fail') {
        Init
        GivenFile 'abc.yml'
        GivenDirectory 'def.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = '*.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should resolve to a file'
    }
}

Describe ('Resolve-WhiskeyTaskPath.when an optional path that doesn''t exist should be a specific type') {
    It ('should pass nothing') {
        Init
        WhenRunningTask 'ValidateOptionalFileTask' -Parameter @{ }
        ThenTaskCalled -WithParameter @{ }
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path is mandatory and missing') {
    It 'should fail' {
        Init
        GivenFile 'abc.yml' 
        WhenRunningTask 'ValidateMandatoryPathTask' -Parameter @{ } -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'is\ mandatory'
        ThenTaskNotCalled
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path is outside of build root and can be') {
    It ('should succeed') {
        Init
        WhenRunningTask 'ValidateMandatoryNonexistentOutsideBuildRootFileTask' -Parameter @{ 'Path' = '..\YOLO.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path '..' -ChildPath 'YOLO.yml') }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path is outside of build root and should not be') {
    It ('should fail') {
        Init
        WhenRunningTask 'ValidateMandatoryNonexistentFileTask' -Parameter @{ 'Path' = '../YOLO.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'outside\ the\ build\ root'
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path must exist and does') {
    It ('should pass relative path to file') {
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'abc.yml') }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path must exist and does not') {
    It ('should fail') {
        Init
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'does\ not\ exist'
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path is absolute') {
    It ('should succeed') {
        Init
        WhenRunningTask 'ValidateMandatoryNonexistentFileTask' -Parameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $testRoot -Childpath 'abc.yml' )) }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'abc.yml') }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path doesn''t exist but has a wildcard') {
    It ('shouldn''t pass anything') {
        Init
        WhenRunningTask 'ValidateMandatoryNonexistentFileTask' -Parameter @{ 'Path' = 'packages\tool\*.yolo' } -ErrorAction SilentlyContinue
        ThenTaskCalled -WithParameter @{ 'Path' = '' }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPath.when path is outside build root') {
    It ('should fail') {
        Init
        WhenRunningTask -Name 'ValidateMandatoryNonexistentFileTask' `
                        -Parameter @{ 'Path' = ('..\' + (Split-Path -Path $testRoot -Leaf) + '!\abc.yml') } `
                        -BuildRoot ($testRoot + '///') `
                        -ErrorAction SilentlyContinue
        ThenTaskNotCalled 
        ThenThrewException -Pattern 'outside\ the\ build\ root'
    }
}

Describe ('Resolve-WhiskeyTaskPath.when multiple paths contain wildcards') {
    It ('should resolve wildcards to existing paths') {
        Init
        GivenFile 'abc.yml' 
        GivenFile 'xyz.yml' 
        GivenFile 'trolololo.txt'
        GivenFile 'yayaya.txt'
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.yml', '*.txt' } 
        ThenPipelineSucceeded
        ThenTaskCalled
        $taskParameters = Get-LastTaskBoundParameter
        $taskParameters | Should -Not -BeNullOrEmpty
        $taskParameters['Path'] | Should -HaveCount 5
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'abc.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'xyz.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'trolololo.txt')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'yayaya.txt')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'whiskey.yml')
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPath.when given multipe paths') {
    It ('should succeed') {
        Init
        GivenFile 'abc.yml'
        GivenFile 'xyz.yml'
        GivenFile 'hjk.yml'
        WhenRunningTask 'ValidateMandatoryFilesTask' -Parameter @{ 'Path' = 'abc.yml', 'xyz.yml', 'hjk.yml' } -ErrorAction SilentlyContinue
        ThenTaskCalled
        $taskParameters = Get-LastTaskBoundParameter
        $taskParameters | Should -Not -BeNullOrEmpty
        $taskParameters['Path'] | Should -HaveCount 3
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'abc.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'xyz.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'hjk.yml')
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPath.when a path uses different case to try to reach outside its build root') {
    It ('should fail on case-sensitive platforms and succeed on case-insensitive platforms') {
        Init
        # Make sure we're in a directory that has letters.
        $buildRoot = Join-Path -Path $testRoot -ChildPath 'fubar'
        $tempDir = $buildRoot | Split-Path -Parent
        $buildDirName = $buildRoot | Split-Path -Leaf
        $attackersBuildDirName = $buildDirName.ToUpper()
        $attackersBuildDir = Join-Path -Path $tempDir -ChildPath $attackersBuildDirName
        $attackersFile = Join-Path -Path $attackersBuildDir -ChildPath 'abc.yml'
        GivenFile $attackersFile
        $optionalParam = @{}
        if( $fsCaseSensitive )
        {
            $optionalParam['ErrorAction'] = 'SilentlyContinue'
        }
        WhenRunningTask 'ValidateOptionalNonexistentPathTask' `
                        -Parameter @{ 'Path' = ('..\{0}\abc.yml' -f $attackersBuildDirName) } `
                        @optionalParam `
                        -BuildRoot $buildRoot
        if( $fsCaseSensitive )
        {
            ThenTaskNotCalled 
            ThenThrewException -Pattern 'outside\ the\ build\ root'
        }
        else
        {
            ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'abc.yml') }
            ThenPipelineSucceeded
        }
    }
}

Describe 'Resolve-WhiskeyTaskPath.when working directory isn''t build root and using a non-existent relative path inside the build root' {
    It 'should allow the path' {
        Init
        GivenDirectory 'subdir'
        WhenRunningTask 'ValidateOptionalNonExistentPathTask' -Parameter @{ 'Path' = '..\NewFile.txt'; 'WorkingDirectory' = 'subdir' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath '..\Newfile.txt') }
    }
}

Describe 'Resolve-WhiskeyTaskPathParamter.when file should get created' {
    It 'should create the item' {
        Init
        # We use a directory since `New-Item` defaults to creating files.
        WhenRunningTask 'CreateMissingFileTask' -Parameter @{ 'Path' = 'dir\One.txt','Two.txt' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'dir\One.txt','Two.txt') }
        Join-Path -Path $testRoot -ChildPath 'dir\One.txt' | Should -Exist
        Join-Path -Path $testRoot -ChildPath 'Two.txt' | Should -Exist
    }
}

Describe 'Resolve-WhiskeyTaskPathParamter.when directory should get created' {
    It 'should create the item' {
        Init
        # We use a directory since `New-Item` defaults to creating files.
        WhenRunningTask 'CreateMissingDirectoryTask' -Parameter @{ 'Path' = 'One','Two' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'One','Two') }
        Join-Path -Path $testRoot -ChildPath 'One' | Should -Exist
        Join-Path -Path $testRoot -ChildPath 'Two' | Should -Exist
    }
}

Describe 'Resolve-WhiskeyTaskPath.when item should get created but path type not given' {
    It 'should fail' {
        Init
        WhenRunningTask 'CreateMissingItemwithPathTypeMissingTask' -Parameter @{ 'Path' = 'One.txt' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'add a PathType property'
    }
}

Describe 'Resolve-WhiskeyTaskPath.when path is current directory' {
    It 'should pass' {
        Init
        WhenRunningTask 'ValidateMandatoryDirectoryTask' -Parameter @{ 'Path' = '.' }
        ThenTaskCalled -WithParameter @{ 'Path' = ('.{0}' -f [IO.Path]::DirectorySeparatorChar) }
    }
}

Describe 'Resolve-WhiskeyTaskPath.when path does not exist and some paths use wildcards and others do not' {
    It 'should normalize directory separators' {
        Init
        WhenRunningTask 'ValidateMandatoryNonexistentFilesTask' -Parameter @{ 'Path' = @( 'file.txt','*.json','anotherfile.txt') }
        $expectedPaths = & {
            Resolve-RelativePath 'file.txt'
            Resolve-RelativePath 'anotherfile.txt'
        }
        ThenTaskCalled -WithParameter @{ 'Path' = $expectedPaths }
    }
}

Describe 'Resolve-WhiskeyTaskPath.when path does not exist and user is using directory separator from another OS' {
    It 'should normalize directory separators' {
        if( [IO.Path]::DirectorySeparatorChar -eq '\' )
        {
            $separator = '/'
        }
        else
        {
            $separator = '\'
        }
        Init
        $paths = @(
            ((Join-Path -Path $testRoot -ChildPath 'some\custom\path.zip') -replace ([regex]::Escape([IO.Path]::DirectorySeparatorChar)),$separator),
            ('some{0}other{0}path.zip' -f $separator)
            # Make sure on Windows, separator gets switched to backslash.
            'another{0}path.txt' -f [IO.Path]::AltDirectorySeparatorChar
        )
        WhenRunningTask 'ValidateMandatoryNonexistentFilesTask' -Parameter @{ 'Path' = $paths }
        $expectedPaths = & {
            Resolve-RelativePath ('some{0}custom{0}path.zip' -f [IO.Path]::DirectorySeparatorChar)
            Resolve-RelativePath ('some{0}other{0}path.zip' -f [IO.Path]::DirectorySeparatorChar)
            Resolve-RelativePath ('another{0}path.txt' -f [IO.Path]::DirectorySeparatorChar)
        }
        ThenTaskCalled -WithParameter @{ 'Path' = $expectedPaths }
    }
}

Describe 'Resolve-WhiskeyTaskPath.when using glob syntax' {
    AfterEach { Reset }
    It 'should return files matching globs' {
        Init
        GivenFile 'absolute','abc.yml', 'cdf.yml', 'root.txt','root.txt.orig', 'dir\file.txt', 'dir\whiskey.yml', 'dir1\file.txt.orig', 'dir2\dir3\anotherfile.txt', 'dir2\dir3\anotherfile.txt.fubar'
        # These files test that we search hidden places
        GivenFile '.hidden.yml' -Hidden
        GivenDirectory '.hidden' -Hidden
        GivenFile '.hidden\config.txt'
        # These files test that we're doing a case-senstive search on Linux.
        GivenFile 'uppercase.TXT'

        WhenRunningTask 'ValidatePathWithGlobTask' -Parameter @{ 
            'Path' = @( '*.yml', '**\*.txt', '**\*.txt.*', (Join-Path -Path $testRoot -ChildPath 'absolute')); 
            'Exclude' = @( 'PSModules\**', '**\*.orig', 'whiskey.yml' ) }
        $expectedPaths = & {
            Resolve-RelativePath 'absolute'
            Resolve-RelativePath 'abc.yml'
            Resolve-RelativePath 'cdf.yml'
            Resolve-RelativePath 'root.txt'
            Resolve-RelativePath 'dir\file.txt'
            Resolve-RelativePath 'dir2\dir3\anotherfile.txt'
            Resolve-RelativePath 'dir2\dir3\anotherfile.txt.fubar'
            Resolve-RelativePath '.hidden.yml'
            Resolve-RelativePath '.hidden\config.txt'
            
            # If we're not on a case-sensitive file sytem, make sure results use the correct case sensitivity.
            if( (Test-Path -Path $testRoot.ToUpperInvariant()) )
            {
                Resolve-RelativePath 'uppercase.TXT'
            }
        }
        ThenTaskCalled -WithParameter @{ 'Path' = $expectedPaths }
    }
}

Describe 'Resolve-WhiskeyTaskPath.when task uses glob syntax but path property only accepts a single path' {
    AfterEach { Reset }
    It 'should fail' {
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateSinglePathWithGlobTask' -Parameter @{ 'Path' = '**/*.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'use glob.*type is not.*task authoring error'
    }
}

if( -not (Get-ChildItem -Path ([IO.Path]::DirectorySeparatorChar) -File) )
{
    Write-Warning -Message ('Unable to test if globbing works from the root directory.')
}
else
{
    # Whiskey detects the case-sensitivity of the file system and calls Find-GlobFile with matching case-sensitivity.
    # This detection needs to handle when resolving paths from the root directory.
    Describe 'Resolve-WhiskeyTaskPath.when globbing in the root directory' {
        AfterEach { 
            Reset
            if( -not $IsWindows )
            {
                sudo chmod o-w /
            }
        }
        It 'should correctly detect case-sensitivity' {
            Init
            if( -not $IsWindows )
            {
                sudo chmod o+w /
            }
            $rootPath = 
                Resolve-Path -Path ([IO.Path]::DirectorySeparatorChar) | 
                Select-Object -ExpandProperty 'ProviderPath'
            Initialize-WhiskeyTestPSModule -BuildRoot $rootPath -Name 'Glob'
            Push-Location $rootPath
            try
            {
                $paths = 
                    Get-ChildItem -Path $rootPath -File |
                    Split-Path -Leaf 

                $changedCasePaths = 
                    $paths |
                    ForEach-Object {
                        Write-Output ($_.ToUpperInvariant())
                    }

                $exclude = 
                    Get-ChildItem -Path $rootPath -Directory -Force |
                        ForEach-Object { '**\{0}\**' -f $_.Name }

                $context = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $testRoot
                $context.BuildRoot = $rootPath
                $resolvedPaths =
                    $changedCasePaths |
                    Resolve-WhiskeyTaskPath -TaskContext $context -UseGlob -PropertyName 'Path' -Exclude $exclude -ErrorAction Ignore
                $expectedPaths = & {
                    foreach( $changedCasePath in $changedCasePaths )
                    {
                        $fullPath = Join-Path -Path $rootPath -ChildPath $changedCasePath
                        # Case-insensitive ?
                        if( (Test-Path -Path $fullPath) )
                        {
                            Write-Output (Resolve-RelativePath -Path $changedCasePath)
                        }
                    }
                }
                
                $expectedPaths = $expectedPaths | Where-Object {$_ -ne ".\DOCKERFILE.WINDOWS"}
                $resolvedPaths | Sort-Object | Should -Be ($expectedPaths | Sort-Object)
            }
            finally
            {
                Pop-Location
            }
        } 
    }
}