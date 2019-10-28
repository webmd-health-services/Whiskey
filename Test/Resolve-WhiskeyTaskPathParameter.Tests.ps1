#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Import-WhiskeyTestTaskModule

[Whiskey.Context]$context = $null
$fsCaseSensitive = $false
$testRoot = $null

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
        $Name
    )

    if( -not [IO.Path]::IsPathRooted($Name) )
    {
        $Name = Join-Path -Path $testRoot -ChildPath $Name
    }
    New-Item -Path $Name -ItemType 'File' -Force
}

function Init
{
    $script:context = $null
    $script:fsCaseSensitive = -not (Test-Path -Path ($PSScriptRoot.ToUpperInvariant()))
    $script:testRoot = New-WhiskeyTestRoot
    Clear-LastTaskBoundParameter
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
            $taskParameters[$key] | Should -Be $WithParameter[$key] -Because $key
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
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [String]$Name,

        [hashtable]$Parameter,

        [String]$BuildRoot = $testRoot
    )

    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $BuildRoot
    $context.PipelineName = 'Build'
    $context.TaskName = $null
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
        Write-Error $_
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when parameter is an optional path') {
    It 'should resolve the parameter to a full path' {
        Init
        WhenRunningTask 'ValidateOptionalPathTask' -Parameter @{ 'Path' = 'whiskey.yml' } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Path' = $context.ConfigurationPath.FullName }
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when parameter is an optional path but it doesn''t exist') {
    It 'should return a full path' {
        Init
        WhenRunningTask 'ValidateOptionalPathTask' -Parameter @{ 'Path' = 'somefile.txt' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'does\ not\ exist'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when parameter is a path with wildcards') {
    It 'should resolve path to actual paths' {
        Init
        GivenFile 'abc.yml' 
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.yml' } 
        ThenPipelineSucceeded
        ThenTaskCalled
        $taskParameters = Get-LastTaskBoundParameter
        $taskParameters['Path'] | Should -HaveCount 2
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'abc.yml')
        $taskParameters['Path'] | Should -Contain $context.ConfigurationPath.FullName
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when parameter is a path that the user wants resolved with a wildcard but doesn''t exist') {
    It 'should fail' {
        Init
        GivenFile 'abc.yml' 
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.fubar' } -ErrorAction SilentlyContinue
        ThenThrewException 'does\ not\ exist'
        ThenTaskNotCalled
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path parameter wants to be resolved but parameter type isn''t a string array') {
    It 'should fail' {
        Init
        GivenFile 'abc.txt' 
        GivenFile 'xyz.txt' 
        WhenRunningTask 'ValidateOptionalPathTask' -Parameter @{ 'Path' = '*.txt' } -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'requires\ a\ single\ path'
        ThenTaskNotCalled
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path should be a file') {
    It ('should pass full path to file') {
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path $context.BuildRoot -ChildPath 'abc.yml') }
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path should be a file but it''s a directory') {
    It ('should fail') {
        Init
        GivenDirectory 'abc.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should\ be\ to\ a\ file'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path should be a directory but it''s a file') {
    It ('should fail') {
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryDirectoryTask' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should\ be\ to\ a\ directory'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when all paths should be files but one is a directory') {
    It ('should fail') {
        Init
        GivenFile 'abc.yml'
        GivenDirectory 'def.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = '*.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should\ be\ to\ a\ file'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when an optional path that doesn''t exist should be a specific type') {
    It ('should pass nothing') {
        Init
        WhenRunningTask 'ValidateOptionalFileTask' -Parameter @{ }
        ThenTaskCalled -WithParameter @{ }
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is mandatory and missing') {
    It 'should fail' {
        Init
        GivenFile 'abc.yml' 
        WhenRunningTask 'ValidateMandatoryPathTask' -Parameter @{ } -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'is\ mandatory'
        ThenTaskNotCalled
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is outside of build root and can be') {
    It ('should succeed') {
        Init
        WhenRunningTask 'ValidateMandatoryNonexistentOutsideBuildRootFileTask' -Parameter @{ 'Path' = '..\YOLO.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $testRoot -Childpath '..\YOLO.yml'))  }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is outside of build root and should not be') {
    It ('should fail') {
        Init
        WhenRunningTask 'ValidateMandatoryNonexistentFileTask' -Parameter @{ 'Path' = '../YOLO.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'outside\ the\ build\ root'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path must exist and does') {
    It ('should pass full path to file') {
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path $testRoot -Childpath 'abc.yml' ) }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path must exist and does not') {
    It ('should fail') {
        Init
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'does\ not\ exist'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is absolute') {
    It ('should succeed') {
        Init
        WhenRunningTask 'ValidateMandatoryNonexistentFileTask' -Parameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $testRoot -Childpath 'abc.yml' )) }
        ThenTaskCalled -WithParameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $testRoot -Childpath 'abc.yml' )) }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path doesn''t exist but has a wildcard') {
    It ('shouldn''t pass anything') {
        Init
        WhenRunningTask 'ValidateMandatoryNonexistentFileTask' -Parameter @{ 'Path' = 'packages\tool\*.yolo' } -ErrorAction SilentlyContinue
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {            
            ThenTaskNotCalled
            ThenThrewException -Pattern 'Illegal\ characters\ in\ path.'
        }
        else
        {
            ThenTaskCalled -WithParameter @{ 'Path' = '' }
            ThenPipelineSucceeded
        }
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is outside build root') {
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

Describe ('Resolve-WhiskeyTaskPathParameter.when multiple paths contain wildcards') {
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
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'abc.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'xyz.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'trolololo.txt' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'yayaya.txt' -Resolve)
        $taskParameters['Path'] | Should -Contain $context.ConfigurationPath.FullName
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when given multipe paths') {
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
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'abc.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'xyz.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'hjk.yml' -Resolve)   
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when a path uses different case to try to reach outside its build root') {
    It ('should fail on case-sensitive platforms and succeed on case-insensitive platforms') {
        Init
        $tempDir = $testRoot | Split-Path -Parent
        $buildDirName = $testRoot | Split-Path -Leaf
        $attackersBuildDirName = $buildDirName.ToUpper()
        $attackersBuildDir = Join-Path -Path $tempDir -ChildPath $attackersBuildDirName
        $attackersFile = Join-Path -Path $attackersBuildDir -ChildPath 'abc.yml'
        GivenFile $attackersFile
        $optionalParam = @{}
        if( $fsCaseSensitive )
        {
            $optionalParam['ErrorAction'] = 'SilentlyContinue'
        }
        WhenRunningTask 'ValidateOptionalNonexistentPathTask' -Parameter @{ 'Path' = ('..\{0}\abc.yml' -f $attackersBuildDirName) } @optionalParam
        if( $fsCaseSensitive )
        {
            ThenTaskNotCalled 
            ThenThrewException -Pattern 'outside\ the\ build\ root'
        }
        else
        {
            ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path $testRoot -ChildPath 'abc.yml')}
            ThenPipelineSucceeded
        }
    }
}
