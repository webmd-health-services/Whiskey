
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Import-WhiskeyTestTaskModule

[Whiskey.Context]$context = $null
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

    New-Item -Path (Join-Path -Path $testRoot -ChildPath $Name) -ItemType 'File'
}

function Init
{
    $script:context = $null
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
        [hashtable]$WithParameter,

        [String]$TaskContextParameterName,

        [String]$TaskParameterParameterName
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

    if( $TaskContextParameterName )
    {
        $taskParameters[$TaskContextParameterName] | Should -BeOfType ([Whiskey.Context])
    }

    if( $TaskParameterParameterName )
    {
        $taskParameters[$TaskParameterParameterName] | Should -BeOfType ([hashtable])
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
        [String]$Named,

        [hashtable]$Parameter,

        [String]$BuildRoot
    )

    $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot
    $context.PipelineName = 'Build'
    $context.TaskName = $null
    $context.TaskIndex = 1

    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name $Named -Parameter $Parameter
    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }
}

Describe ('Get-TaskParameter.when task uses named parameters') {
    It ('should pass named parameters') {
        Init
        WhenRunningTask 'NamedParametersTask' -Parameter @{ 'Yolo' = 'Fizz' ; 'Fubar' = 'Snafu' } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Yolo' = 'Fizz' ; 'Fubar' = 'Snafu' }
    }
}

Describe ('Get-TaskParameter.when task uses named parameters but user doesn''t pass any') {
    It ('should not pass named parameters') {
        Init
        WhenRunningTask 'NamedParametersTask' -Parameter @{ } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameters @{ }
    }
}

Describe ('Get-TaskParameter.when using alternate names for context and parameters') {
    It 'should pass context and parameters to the task' {
        Init
        WhenRunningTask 'AlternateStandardParameterNamesTask' -Parameter @{ } 
        ThenPipelineSucceeded
        ThenTaskCalled -TaskContextParameterName 'Context' -TaskParameterParameterName 'Parameter'
    }
}

Describe ('Get-TaskParameter.when task parameter should come from a Whiskey variable') {
    It ('should pass the variable''s value to the parameter') {
        Init
        WhenRunningTask 'ParameterValueFromVariableTask' -Parameter @{ } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Environment' = $context.Environment }
    }
}

Describe ('Get-TaskParameter.when task parameter value uses a Whiskey variable member') {
    It 'should evaluate the member''s value' {
        Init
        WhenRunningTask 'ParameterValueFromVariablePropertyTask' -Parameter @{ } 
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Environment' = $Context.Environment.Length }
    }
}

Describe ('Get-TaskParameter.when passing typed parameters') {
    It ('should convert original values to boolean values') {
        Init
        WhenRunningTask 'NamedParametersTask' -Parameter @{ 'SwitchOne' = 'true' ; 'SwitchTwo' = 'false'; 'Bool' = 'true' ; 'Int' = '1' }
        ThenTaskCalled -WithParameter @{ 'SwitchOne' = $true ; 'SwitchTwo' = $false; 'Bool' = $true ; 'Int' = 1 }
    }
}

Describe ('Get-TaskParameter.when passing common parameters that map to preference values') {
    It ('should convert common parameters to preference values') {
        $origVerbose = $Global:VerbosePreference
        $origDebug = $Global:DebugPreference
        $origWhatIf = $Global:WhatIfPreference
        $originalInfo = $Global:InformationPreference
        Init
        $parameters = @{ 
            'Verbose' = 'true' ; 
            'Debug' = 'true'; 
            'WhatIf' = 'true'; 
            'InformationAction' = 'Continue';
            'ErrorAction' = 'Stop';
        }
        WhenRunningTask 'CapturesCommonPreferencesTask' -Parameter $parameters
        ThenTaskCalled -WithParameter @{ 
            'Verbose' = $true ; 
            'VerbosePreference' = 'Continue'
            'DebugPreference' = 'Continue'
            'WhatIf' = $true;
            'WhatIfPreference' = $true;
            'InformationAction' = 'Continue';
            'InformationPreference' = 'Continue';
            'ErrorAction' = 'Stop';
            'ErrorActionPreference' = 'Stop';
        }
        $Global:VerbosePreference | Should -Be $origVerbose
        $Global:DebugPreference | Should -Be $origDebug
        $Global:WhatIfPreference | Should -Be $origWhatIf
        $Global:InformationPreference | Should -Be $originalInfo
    }
}

Describe ('Get-TaskParameter.when turning off preference values') {
    It ('should convert common parameters to preference values') {
        $origVerbose = $Global:VerbosePreference
        $origDebug = $Global:DebugPreference
        $origWhatIf = $Global:WhatIfPreference
        $originalInfo = $Global:InformationPreference
        Init
        $parameters = @{ 
            'Verbose' = 'false' ;
            'Debug' = 'false';
            'WhatIf' = 'false';
            'InformationAction' = 'Ignore'
            'ErrorAction' = 'Ignore'
        }
        WhenRunningTask -Named 'CapturesCommonPreferencesTask' `
                        -Parameter $parameters `
                        -Verbose `
                        -Debug `
                        -WhatIf `
                        -InformationAction Continue `
                        -ErrorAction Continue
        ThenTaskCalled -WithParameter @{ 
            'Verbose' = $false ; 
            'VerbosePreference' = 'SilentlyContinue'
            'Debug' = $false;
            'DebugPreference' = 'SilentlyContinue';
            'WhatIf' = $false;
            'WhatIfPreference' = $false;
            'InformationAction' = 'Ignore';
            'InformationPreference' = 'Ignore';
            'ErrorAction' = 'Ignore';
            'ErrorActionPreference' = 'Ignore';
        }
        $Global:VerbosePreference | Should -Be $origVerbose
        $Global:DebugPreference | Should -Be $origDebug
        $Global:WhatIfPreference | Should -Be $origWhatIf
        $Global:InformationPreference | Should -Be $originalInfo
    }
}

Describe ('Get-TaskParameter.when turning off global preference values') {
    It ('should convert common parameters to preference values') {
        $origVerbose = $Global:VerbosePreference
        $origDebug = $Global:DebugPreference
        $origWhatIf = $Global:WhatIfPreference
        $originalInfo = $Global:InformationPreference
        $originalError = $Global:ErrorActionPreference
        try
        {
            $Global:VerbosePreference = 'Continue'
            $Global:DebugPreference = 'Continue'
            $Global:WhatIfPreference = $false
            $Global:InformationPreference = 'Continue'
            $Global:ErrorActionPreference = 'Continue'

            Init
            $parameters = @{ 
                'Verbose' = 'false' ;
                'Debug' = 'false';
                'WhatIf' = 'true';
                'InformationAction' = 'Ignore';
                'ErrorAction' = 'Ignore';
            }
            WhenRunningTask 'CapturesCommonPreferencesTask' -Parameter $parameters
            ThenTaskCalled -WithParameter @{ 
                                                'Verbose' = $false;
                                                'VerbosePreference' = 'SilentlyContinue';
                                                'Debug' = $false;
                                                'DebugPreference' = 'SilentlyContinue';
                                                'WhatIf' = $true;
                                                'WhatIfPreference' = $true;
                                                'InformationAction' = 'Ignore';
                                                'InformationPreference' = 'Ignore';
                                                'ErrorAction' = 'Ignore';
                                                'ErrorActionPreference' = 'Ignore';
                                            }
            $Global:VerbosePreference | Should -Be 'Continue'
            $Global:DebugPreference | Should -Be 'Continue'
            $Global:WhatIfPreference | Should -BeFalse
            $Global:InformationPreference | Should -Be 'Continue'
            $Global:ErrorActionPreference | Should -Be 'Continue'
        }
        finally
        {
            $Global:VerbosePreference = $origVerbose
            $Global:DebugPreference = $origDebug
            $Global:WhatIfPreference = $origWhatIf
            $Global:InformationPreference = $originalInfo
            $Global:ErrorActionPreference = $originalError
        }
    }
}

Describe 'Get-TaskParameter.when using property alias' {
    It 'should write a warning and pass the value' {
        Init
        $one = [Guid]::NewGuid()
        $two = [Guid]::NewGuid()
        WhenRunningTask 'TaskWithParameterAliases' -Parameter @{ 'OldOne' = $one ; 'ReallyOldTwo' = $two } -WarningVariable 'warnings'
        ThenTaskCalled -WithParameter @{ 'One' = $one ; 'Two' = $two ; }
        $warnings | Should -HaveCount 2
        $warnings | Should -Match 'Property "(OldOne|ReallyOldTwo)" is deprecated.'
    }
}
