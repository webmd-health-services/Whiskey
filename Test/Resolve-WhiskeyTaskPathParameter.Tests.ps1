#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Whiskey.Context]$context = $null
$global:taskCalled = $false
$global:taskParameters = $null
$fsCaseSensitive = $false

function GivenDirectory
{
    param(
        $Name
    )

    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Name) -ItemType 'Directory'
}

function GivenFile
{
    param(
        $Name
    )

    if( -not [IO.Path]::IsPathRooted($Name) )
    {
        $Name = Join-Path -Path $TestDrive.FullName -ChildPath $Name
    }
    New-Item -Path $Name -ItemType 'File' -Force
}

function Init
{
    $script:context = $null
    $global:taskCalled = $false
    $global:taskParameters = $null
    $script:fsCaseSensitive = -not (Test-Path -Path ($PSScriptRoot.ToUpperInvariant()))
}

function Remove-GlobalTestItem
{
    foreach( $path in @( 'function:Task', 'variable:taskCalled', 'variable:taskParameters' ) )
    {
        if( (Test-Path -Path $path) )
        {
            Remove-Item -Path $path
        }
    }
}

function ThenPipelineSucceeded
{
    $Global:Error | Should -BeNullOrEmpty
    $threwException | Should -BeFalse
}

function ThenTaskCalled
{
    param(
        [hashtable]
        $WithParameter
    )
    $taskCalled | should -BeTrue
    $taskParameters | Should -Not -BeNullOrEmpty

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
    $taskCalled | Should -BeFalse
    $taskParameters | Should -BeNullOrEmpty
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
        [string]
        $Name,

        [hashtable]
        $Parameter,

        [string]
        $BuildRoot
    )

    $optionalParams = @{}
    if( $BuildRoot )
    {
        $optionalParams['ForBuildRoot'] = $BuildRoot
    }
    $script:context = New-WhiskeyTestContext -ForDeveloper @optionalParams
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

Describe ('Resolve-WhiskeyTaskPathParameter.when path should be a file') {
    It ('should pass full path to file') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'abc.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path $context.BuildRoot -ChildPath 'abc.yml') }
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path should be a file but it''s a directory') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenDirectory 'abc.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should\ be\ to\ a\ file'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path should be a directory but it''s a file') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='Directory')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should\ be\ to\ a\ directory'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when all paths should be files but one is a directory') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml'
        GivenDirectory 'def.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '*.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should\ be\ to\ a\ file'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when an optional path that doesn''t exist should be a specific type') {
    It ('should pass nothing') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(PathType='File')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ }
        ThenTaskCalled -WithParameter @{ }
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is mandatory and missing') {
    It 'should fail' {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory)]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml' 
        WhenRunningTask 'Task' -Parameter @{ } -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'is\ mandatory'
        ThenTaskNotCalled
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is outside of build root and can be') {
    It ('should succeed') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',AllowNonexistent,AllowOutsideBuildRoot)]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '..\YOLO.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath '..\YOLO.yml'))  }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is outside of build root and should not be') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',AllowNonexistent)]
                [string]$Path
                
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '../YOLO.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'outside\ the\ build\ root'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path must exist and does') {
    It ('should pass full path to file') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'abc.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path $TestDrive.FullName -Childpath 'abc.yml' ) }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path must exist and does not') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'does\ not\ exist'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is absolute') {
    It ('should succeed') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,AllowNonexistent,PathType='File')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath 'abc.yml' )) }
        ThenTaskCalled -WithParameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath 'abc.yml' )) }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path doesn''t exist but has a wildcard') {
    It ('should work as expected') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,AllowNonexistent,PathType='File')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'packages\tool\*.yolo' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {            
            ThenThrewException -Pattern 'Illegal\ characters\ in\ path.'
        }
        else
        {
            ThenThrewException -Pattern 'did\ not\ resolve\ to\ anything.'
        }
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when path is outside build root') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,AllowNonexistent,PathType='File')]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask -Name 'Task' `
                        -Parameter @{ 'Path' = ('..\' + (Split-Path -Path $TestDrive.FullName -Leaf) + '!\abc.yml') } `
                        -BuildRoot ($TestDrive.FullName + '///') `
                        -ErrorAction SilentlyContinue
        ThenTaskNotCalled 
        ThenThrewException -Pattern 'outside\ the\ build\ root'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when multiple paths contain wildcards') {
    It ('should resolve wildcards to existing paths') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath()]
                [string[]]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml' 
        GivenFile 'xyz.yml' 
        GivenFile 'trolololo.txt'
        GivenFile 'yayaya.txt'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '*.yml', '*.txt' } 
        ThenPipelineSucceeded
        ThenTaskCalled
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
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string[]]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml'
        GivenFile 'xyz.yml'
        GivenFile 'hjk.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'abc.yml', 'xyz.yml', 'hjk.yml' } -ErrorAction SilentlyContinue
        ThenTaskCalled
        $taskParameters['Path'] | Should -HaveCount 3
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'abc.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'xyz.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'hjk.yml' -Resolve)   
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when a path uses different case to try to reach outside its build root') {
    It ('should fail on case-sensitive platforms and succeed on case-insensitive platforms') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(AllowNonexistent)]
                [string]$Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        $tempDir = $TestDrive.FullName | Split-Path -Parent
        $buildDirName = $TestDrive.FullName | Split-Path -Leaf
        $attackersBuildDirName = $buildDirName.ToUpper()
        $attackersBuildDir = Join-Path -Path $tempDir -ChildPath $attackersBuildDirName
        $attackersFile = Join-Path -Path $attackersBuildDir -ChildPath 'abc.yml'
        GivenFile $attackersFile
        $optionalParam = @{}
        if( $fsCaseSensitive )
        {
            $optionalParam['ErrorAction'] = 'SilentlyContinue'
        }
        WhenRunningTask 'Task' -Parameter @{ 'Path' = ('..\{0}\abc.yml' -f $attackersBuildDirName) } @optionalParam
        if( $fsCaseSensitive )
        {
            ThenTaskNotCalled 
            ThenThrewException -Pattern 'outside\ the\ build\ root'
        }
        else
        {
            ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path ($TestDrive.FullName) -ChildPath 'abc.yml')}
            ThenPipelineSucceeded
        }
    }
}