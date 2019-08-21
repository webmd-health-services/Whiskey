#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Resolve-WhiskeyTaskPathParameter.ps1' -Resolve)

[Whiskey.Context]$context = $null
$global:taskCalled = $false
$global:taskParameters = $null

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

    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Name) -ItemType 'File'
}

function Init
{
    $script:context = $null
    $global:taskCalled = $false
    $global:taskParameters = $null
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

Describe ('Resolve-WhiskeyTaskPathParameter.when relative path is outside of buildroot and can be') {
    It ('should succeed') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',MustExist=$false,AllowOutsideBuildRoot)]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '..\YOLO.yml' } -ErrorAction SilentlyContinue
        ThenTaskCalled -WithParameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath '..\YOLO.yml'))  }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when absolute path is outside of buildroot and can be') {
    It ('should succeed') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',MustExist=$false,AllowOutsideBuildRoot,AllowAbsolute)]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath '../YOLO.yml')) } -ErrorAction SilentlyContinue
        ThenTaskCalled -WithParameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath '../YOLO.yml'))  }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when relative path is outside of buildroot and should not be') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',MustExist=$false,AllowOutsideBuildRoot=$false)]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '../YOLO.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'outside\ of\ the\ build\ root'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when absolute path is outside of buildroot and should not be') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',MustExist=$false,AllowOutsideBuildRoot=$false,AllowAbsolute)]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath '../YOLO.yml' )) } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'outside\ of\ the\ build\ root'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when given relative path that must exist and does') {
    It ('should pass full path to file') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string]
                $Path
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

Describe ('Resolve-WhiskeyTaskPathParameter.when given absolute path that must exist and does') {
    It ('should pass full path to file') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',AllowAbsolute)]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath 'abc.yml' )) }
        ThenTaskCalled -WithParameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath 'abc.yml' )) }
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when given relative path that must exist and does not') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string]
                $Path
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

Describe ('Resolve-WhiskeyTaskPathParameter.when given absolute path that must exist and does not') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',AllowAbsolute)]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $TestDrive.FullName -Childpath 'abc.yml' )) } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'does\ not\ exist'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when given path that can be absolute and is') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,MustExist=$false,PathType='File',AllowAbsolute)]
                [string]
                $Path
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

Describe ('Resolve-WhiskeyTaskPathParameter.when given path doesn''t exist but has a wildcard') {
    It ('should work as expected') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,MustExist=$false,PathType='File')]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'packages\tool\*.yolo' } -ErrorAction SilentlyContinue
        if ($PSVersionTable.PSVersion.Major -lt 6)
        {            
            ThenTaskNotCalled
            ThenThrewException -Pattern 'Illegal\ characters\ in\ path.'
        }
        else
        {
            ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path $TestDrive.FullName -ChildPath 'packages\tool\*.yolo') }
            ThenPipelineSucceeded
        }
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when absolute path does not start with the correct BuildRoot') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,MustExist=$false,AllowAbsolute,PathType='File')]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask -Name 'Task' `
                        -Parameter @{ 'Path' = (Join-Path -Path ($TestDrive.FullName + '!\') -ChildPath 'abc.yml') } `
                        -BuildRoot ($TestDrive.FullName + '///') `
                        -ErrorAction SilentlyContinue
        ThenTaskNotCalled 
        ThenThrewException -Pattern 'outside\ of\ the\ build\ root'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when relative path does not start with the correct BuildRoot') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,MustExist=$false,PathType='File')]
                [string]
                $Path
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
        ThenThrewException -Pattern 'outside\ of\ the\ build\ root'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when given path that contains wildcards and "../"') {
    It ('should resolve wildcards to paths outside BuildRoot') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(AllowOutsideBuildRoot)]
                [string[]]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml' 
        GivenFile 'xyz.yml' 
        GivenFile 'hjk.yml' 
        GivenDirectory 'buildroot'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '../*.yml' } -BuildRoot (Join-Path -Path $TestDrive.FullName -ChildPath 'buildroot')
        ThenPipelineSucceeded
        ThenTaskCalled
        $taskParameters['Path'] | Should -HaveCount 3
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $TestDrive.FullName -ChildPath 'abc.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $TestDrive.FullName -ChildPath 'xyz.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $TestDrive.FullName -ChildPath 'hjk.yml' -Resolve)
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when given multiple paths that contains wildcards') {
    It ('should resolve wildcards to paths') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(AllowOutsideBuildRoot)]
                [string[]]
                $Path
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

Describe ('Resolve-WhiskeyTaskPathParameter.when given multipe paths as parameters') {
    It ('should succeed') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string[]]
                $Path
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

Describe ('Resolve-WhiskeyTaskPathParameter.when given multipe paths as parameters, where some do not exist and should') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string[]]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml'
        GivenFile 'xyz.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'abc.yml', 'xyz.yml', 'hjk.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'does\ not\ exist'
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when given multiple paths as parameters, where some are absolute and can be') {
    It ('should succeed') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',AllowAbsolute)]
                [string[]]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml'
        GivenFile 'xyz.yml'
        GivenFile 'hjk.yml'
        WhenRunningTask 'Task' -Parameter @{
            'Path'=
                (Join-Path -Path $TestDrive.FullName -ChildPath 'abc.yml' -Resolve),
                (Join-Path -Path $TestDrive.FullName -ChildPath 'xyz.yml' -Resolve),
                (Join-Path -Path $TestDrive.FullName -ChildPath 'hjk.yml' -Resolve)
        } -ErrorAction SilentlyContinue
        ThenTaskCalled
        $taskParameters['Path'] | Should -HaveCount 3
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'abc.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'xyz.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'hjk.yml' -Resolve) 
        ThenPipelineSucceeded
    }
}

Describe ('Resolve-WhiskeyTaskPathParameter.when given multiple paths as parameters, where some are outside buildroot and can be') {
    It ('should succeed') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',AllowOutsideBuildRoot)]
                [string[]]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenDirectory 'buildroot'
        GivenFile 'buildroot/abc.yml'
        GivenFile 'buildroot/xyz.yml'
        GivenFile 'hjk.yml'
        WhenRunningTask 'Task' `
                        -Parameter @{ 'Path'= 'abc.yml', 'xyz.yml', '../hjk.yml' } `
                        -BuildRoot (Join-Path -Path $TestDrive.FullName -ChildPath 'buildroot')
        ThenTaskCalled
        $taskParameters['Path'] | Should -HaveCount 3
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'abc.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'xyz.yml' -Resolve)
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath '../hjk.yml' -Resolve) 
        ThenPipelineSucceeded
    }
 }

Describe ('Resolve-WhiskeyTaskPathParameter.when given multipe paths as parameters where some outside buildroot, and should not be') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
                [string[]]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenDirectory 'buildroot'
        GivenFile 'buildroot\abc.yml'
        GivenFile 'buildroot\xyz.yml'
        GivenFile 'hjk.yml'
        WhenRunningTask 'Task' `
                        -Parameter @{ 'Path' = 'abc.yml', 'xyz.yml', '../hjk.yml' } `
                        -BuildRoot (Join-Path -Path $TestDrive.FullName -ChildPath 'buildroot') `
                        -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'outside\ of\ the\ build\ root'
    }
}

Remove-Item -Path 'function:Resolve-WhiskeyTaskPathParameter'