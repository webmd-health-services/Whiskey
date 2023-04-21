
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    Import-WhiskeyTestTaskModule

    [Whiskey.Context]$script:context = $null
    $script:testDirPath = $null

    function GivenDirectory
    {
        param(
            $Name
        )

        New-Item -Path (Join-Path -Path $script:testDirPath -ChildPath $Name) -ItemType 'Directory'
    }

    function GivenFile
    {
        param(
            $Name
        )

        New-Item -Path (Join-Path -Path $script:testDirPath -ChildPath $Name) -ItemType 'File'
    }

    function ThenPipelineSucceeded
    {
        $Global:Error | Should -BeNullOrEmpty
        $threwException | Should -BeFalse
    }

    function ThenTaskCalled
    {
        param(
            [hashtable] $WithParameter,

            [String] $TaskContextParameterName,

            [String] $TaskParameterParameterName
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
        [Diagnostics.CodeAnalysis.SuppressMessage('PSShouldProcess', '')]
        [CmdletBinding(SupportsShouldProcess)]
        param(
            [String]$Named,

            [hashtable]$Parameter,

            [String]$BuildRoot
        )

        $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $script:testDirPath
        $script:context.PipelineName = 'Build'
        $script:context.TaskIndex = 1

        $Global:Error.Clear()
        $script:threwException = $false
        try
        {
            Invoke-WhiskeyTask -TaskContext $script:context -Name $Named -Parameter $Parameter
        }
        catch
        {
            $script:threwException = $true
            Write-Error $_
        }
    }
}

Describe 'Get-TaskArgument' {
    BeforeEach {
        $script:context = $null
        $script:testDirPath = New-WhiskeyTestRoot
        Clear-LastTaskBoundParameter
    }

    It 'passes arguments using named parameters' {
        WhenRunningTask 'NamedParametersTask' -Parameter @{ 'Yolo' = 'Fizz' ; 'Fubar' = 'Snafu' }
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Yolo' = 'Fizz' ; 'Fubar' = 'Snafu' }
    }

    It 'handles missing argument for named parameter' {
        WhenRunningTask 'NamedParametersTask' -Parameter @{ }
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameters @{ }
    }

    It 'allows Context and Parameter as argument names for context and arguments' {
        WhenRunningTask 'AlternateStandardParameterNamesTask' -Parameter @{ }
        ThenPipelineSucceeded
        ThenTaskCalled -TaskContextParameterName 'Context' -TaskParameterParameterName 'Parameter'
    }

    It 'uses Whiskey variable as argument value' {
        WhenRunningTask 'ParameterValueFromVariableTask' -Parameter @{ }
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Environment' = $script:context.Environment }
    }

    It 'can use Whiskey variable member as argument value' {
        WhenRunningTask 'ParameterValueFromVariablePropertyTask' -Parameter @{ }
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Environment' = $script:context.Environment.Length }
    }

    It 'converts properties to bool, switch, and int argument' {
        WhenRunningTask 'NamedParametersTask' -Parameter @{ 'SwitchOne' = 'true' ; 'SwitchTwo' = 'false'; 'Bool' = 'true' ; 'Int' = '1' }
        ThenTaskCalled -WithParameter @{ 'SwitchOne' = $true ; 'SwitchTwo' = $false; 'Bool' = $true ; 'Int' = 1 }
    }

    It 'convert common arguments to preference values' {
        $origVerbose = $Global:VerbosePreference
        $origDebug = $Global:DebugPreference
        $origWhatIf = $Global:WhatIfPreference
        $originalInfo = $Global:InformationPreference
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

    It 'allows users to turn preferences off' {
        $origVerbose = $Global:VerbosePreference
        $origDebug = $Global:DebugPreference
        $origWhatIf = $Global:WhatIfPreference
        $originalInfo = $Global:InformationPreference
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

    It 'does not change global preferences' {
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

    It 'passes argument using parameter alias' {
        $one = [Guid]::NewGuid()
        $two = [Guid]::NewGuid()
        WhenRunningTask 'TaskWithParameterAliases' `
                        -Parameter @{ 'OldOne' = $one ; 'ReallyOldTwo' = $two } `
                        -WarningVariable 'warnings'
        ThenTaskCalled -WithParameter @{ 'One' = $one ; 'Two' = $two ; }
        $warnings | Should -HaveCount 2
        $warnings | Should -Match 'Property "(OldOne|ReallyOldTwo)" is deprecated.'
    }
}