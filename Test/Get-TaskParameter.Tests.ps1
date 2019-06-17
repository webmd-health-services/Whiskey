
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

[Whiskey.Context]$context = $null
$global:taskCalled = $false
$global:taskParameters = $null

# The default DebugPreference when using the -Debug switch changed in PowerShell Core 6.2. 
# This function exists to get the default.
function Get-DefaultDebugPreference
{
    [CmdletBinding()]
    param(
    )
    return $DebugPreference
}
$defaultDebugPreference = Get-DefaultDebugPreference -Debug
Write-Verbose -Message ('Default DebugPreference: {0}' -f $defaultDebugPreference) -Verbose

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
        $Parameter
    )

    $script:context = New-WhiskeyTestContext -ForDeveloper
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

Describe ('Get-TaskParameter.when task uses named parameters') {
    It ('should pass named parameters') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                $Yolo,
                $Fubar
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Yolo' = 'Fizz' ; 'Fubar' = 'Snafu' } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Yolo' = 'Fizz' ; 'Fubar' = 'Snafu' }
    }
}

Describe ('Get-TaskParameter.when task uses named parameters but user doesn''t pass any') {
    It ('should not pass named parameters') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                $Yolo,
                $Fubar
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameters @{ }
    }
}

Describe ('Get-TaskParameter.when using alternate names for context and parameters') {
    It 'should pass context and parameters to the task' {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                $Context,
                $Parameter
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ } 
        ThenPipelineSucceeded
        ThenTaskCalled
        $taskParameters['Context'] | Should -BeOfType ([Whiskey.Context])
        $taskParameters['Parameter'] | Should -BeOfType ([hashtable])
    }
}

Describe ('Get-TaskParameter.when task parameter should come from a Whiskey variable') {
    It ('should pass the variable''s value to the parameter') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ParameterValueFromVariable('WHISKEY_ENVIRONMENT')]
                [string]
                $Environment
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Environment' = $context.Environment }
    }
}

Describe ('Get-TaskParameter.when task parameter value uses a Whiskey variable member') {
    It 'should evaluate the member''s value' {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ParameterValueFromVariable('WHISKEY_ENVIRONMENT.Length')]
                [string]
                $Environment
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Environment' = $Context.Environment.Length }
    }
}

Describe ('Get-TaskParameter.when parameter is an optional path') {
    It 'should resolve the parameter to a full path' {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath()]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'whiskey.yml' } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Path' = $context.ConfigurationPath.FullName }
    }
}

Describe ('Get-TaskParameter.when parameter is an optional path but it doesn''t exist') {
    It 'should return a full path' {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath()]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'somefile.txt' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'does\ not\ exist'
    }
}

Describe ('Get-TaskParameter.when parameter is a path with wildcards') {
    It 'should resolve path to actual paths' {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath()]
                [string[]]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml' 
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '*.yml' } 
        ThenPipelineSucceeded
        ThenTaskCalled
        $taskParameters['Path'] | Should -HaveCount 2
        $taskParameters['Path'] | Should -Contain (Join-Path -Path $Context.BuildRoot -ChildPath 'abc.yml')
        $taskParameters['Path'] | Should -Contain $context.ConfigurationPath.FullName
    }
}

Describe ('Get-TaskParameter.when parameter is a path that the user wants resolved with a wildcard but doesn''t exist') {
    It 'should fail' {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath()]
                [string[]]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml' 
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '*.fubar' } -ErrorAction SilentlyContinue
        ThenThrewException 'does\ not\ exist'
        ThenTaskNotCalled
    }
}

Describe ('Get-TaskParameter.when path parameter wants to be resolved but parameter type isn''t a string array') {
    It 'should fail' {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath()]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.txt' 
        GivenFile 'xyz.txt' 
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '*.txt' } -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'requires\ a\ single\ path'
        ThenTaskNotCalled
    }
}

Describe ('Get-TaskParameter.when path is mandatory and missing') {
    It 'should fail' {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory)]
                [string]
                $Path
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

Describe ('Get-TaskParameter.when path is mandatory and does not exist') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory)]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml' 
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'YOLO!' } -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'does\ not\ exist'
        ThenTaskNotCalled
    }
}

Describe ('Get-TaskParameter.when path should be a file') {
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
        ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path $context.BuildRoot -ChildPath 'abc.yml') }
    }
}

Describe ('Get-TaskParameter.when path should be a file but it''s a directory') {
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
        GivenDirectory 'abc.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'must\ be\ a\ file'
    }
}

Describe ('Get-TaskParameter.when path should be a directory but it''s a file') {
    It ('should fail') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(Mandatory,PathType='Directory')]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        GivenFile 'abc.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'must\ be\ a\ directory'
    }
}

Describe ('Get-TaskParameter.when all paths should be files but one is a directory') {
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
        GivenFile 'abc.yml'
        GivenDirectory 'def.yml'
        WhenRunningTask 'Task' -Parameter @{ 'Path' = '*.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'must\ be\ a\ file'
    }
}

Describe ('Get-TaskParameter.when an optional path that doesn''t exist should be a specific type') {
    It ('should pass nothing') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Whiskey.Tasks.ValidatePath(PathType='File')]
                [string]
                $Path
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ }
        ThenTaskCalled -WithParameter @{ }
    }
}

Describe ('Get-TaskParameter.when passing typed parameters') {
    It ('should convert original values to boolean values') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            param(
                [Switch]
                $SwitchOne,
                [Switch]
                $SwitchTwo,
                [Switch]
                $SwitchThree,
                [bool]
                $Bool,
                [int]
                $Int,
                [bool]
                $NoBool,
                [int]
                $NoInt
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
        }
        Init
        WhenRunningTask 'Task' -Parameter @{ 'SwitchOne' = 'true' ; 'SwitchTwo' = 'false'; 'Bool' = 'true' ; 'Int' = '1' }
        ThenTaskCalled -WithParameter @{ 'SwitchOne' = $true ; 'SwitchTwo' = $false; 'Bool' = $true ; 'Int' = 1 }
    }
}

Describe ('Get-TaskParameter.when passing common parameters that map to preference values') {
    It ('should convert common parameters to preference values') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            [CmdletBinding(SupportsShouldProcess)]
            param(
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
            foreach( $prefName in @( 'VerbosePreference', 'WhatIfPreference', 'DebugPreference' ) )
            {
                $global:taskParameters[$prefName] = Get-Variable -Name $prefName -ValueOnly
            }
        }
        $origVerbose = $Global:VerbosePreference
        $origDebug = $Global:DebugPreference
        $origWhatIf = $Global:WhatIfPreference
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Verbose' = 'true' ; 'Debug' = 'true'; 'WhatIf' = 'true' }
        ThenTaskCalled -WithParameter @{ 
                                            'Verbose' = $true ; 
                                            'VerbosePreference' = 'Continue'
                                            'Debug' = $true;
                                            'DebugPreference' = $defaultDebugPreference;
                                            'WhatIf' = $true;
                                            'WhatIfPreference' = $true;
                                        }
        $Global:VerbosePreference | Should -Be $origVerbose
        $Global:DebugPreference | Should -Be $origDebug
        $Global:WhatIfPreference | Should -Be $origWhatIf
    }
}

Describe ('Get-TaskParameter.when turning off preference values') {
    It ('should convert common parameters to preference values') {
        function global:Task
        {
            [Whiskey.Task('Task')]
            [CmdletBinding(SupportsShouldProcess)]
            param(
            )
            $global:taskCalled = $true
            $global:taskParameters = $PSBoundParameters
            foreach( $prefName in @( 'VerbosePreference', 'WhatIfPreference', 'DebugPreference' ) )
            {
                $global:taskParameters[$prefName] = Get-Variable -Name $prefName -ValueOnly
            }
        }
        $origVerbose = $Global:VerbosePreference
        $origDebug = $Global:DebugPreference
        $origWhatIf = $Global:WhatIfPreference
        Init
        WhenRunningTask 'Task' -Parameter @{ 'Verbose' = 'false' ; 'Debug' = 'false'; 'WhatIf' = 'false' } -Verbose -Debug -WhatIf
        ThenTaskCalled -WithParameter @{ 
                                            'Verbose' = $false ; 
                                            'VerbosePreference' = 'SilentlyContinue'
                                            'Debug' = $false;
                                            'DebugPreference' = 'SilentlyContinue';
                                            'WhatIf' = $false;
                                            'WhatIfPreference' = $false;
                                        }
        $Global:VerbosePreference | Should -Be $origVerbose
        $Global:DebugPreference | Should -Be $origDebug
        $Global:WhatIfPreference | Should -Be $origWhatIf
    }
}

Describe ('Get-TaskParameter.when turning off global preference values') {
    It ('should convert common parameters to preference values') {
        $origVerbose = $Global:VerbosePreference
        $origDebug = $Global:DebugPreference
        $origWhatIf = $Global:WhatIfPreference
        try
        {
            function global:Task
            {
                [Whiskey.Task('Task')]
                [CmdletBinding(SupportsShouldProcess)]
                param(
                )
                $global:taskCalled = $true
                $global:taskParameters = $PSBoundParameters
                foreach( $prefName in @( 'VerbosePreference', 'WhatIfPreference', 'DebugPreference' ) )
                {
                    $global:taskParameters[$prefName] = Get-Variable -Name $prefName -ValueOnly
                }
            }
            $Global:VerbosePreference = 'Continue'
            $Global:DebugPreference = 'Continue'
            $Global:WhatIfPreference = $true
            Init
            WhenRunningTask 'Task' -Parameter @{ 'Verbose' = 'false' ; 'Debug' = 'false'; 'WhatIf' = 'false' }
            ThenTaskCalled -WithParameter @{ 
                                                'Verbose' = $false;
                                                'VerbosePreference' = 'SilentlyContinue';
                                                'Debug' = $false;
                                                'DebugPreference' = 'SilentlyContinue';
                                                'WhatIf' = $false;
                                                'WhatIfPreference' = $false;
                                            }
            $Global:VerbosePreference | Should -Be 'Continue'
            $Global:DebugPreference | Should -Be 'Continue'
            $Global:WhatIfPreference | Should -BeTrue
        }
        finally
        {
            $Global:VerbosePreference = $origVerbose
            $Global:DebugPreference = $origDebug
            $Global:WhatIfPreference = $origWhatIf
        }
    }
}

Remove-GlobalTestItem
