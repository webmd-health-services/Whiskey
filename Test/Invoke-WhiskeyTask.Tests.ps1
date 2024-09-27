
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    Import-WhiskeyTestTaskModule

    $script:testRoot = $null
    $script:runByDeveloper = $false
    $script:runByBuildServer = $false
    [Whiskey.Context] $script:context = $null
    $script:output = $null
    $script:taskDefaults = @{ }
    $script:scmBranch = $null
    $script:taskProperties = @{ }
    $script:taskRun = $false
    $script:variables = @{ }
    $script:enablePlugins = $null
    $script:taskNameForPlugin = $null
    $script:taskRunCount = 0
    $script:tasks = Get-WhiskeyTask -Force

    function Global:Invoke-PreTaskPlugin
    {
        param(
            [Parameter(Mandatory)]
            [Object]$TaskContext,

            [Parameter(Mandatory)]
            [String]$TaskName,

            [Parameter(Mandatory)]
            [hashtable]$TaskParameter
        )

    }

    function Global:Invoke-PostTaskPlugin
    {
        param(
            [Parameter(Mandatory)]
            [Object]$TaskContext,

            [Parameter(Mandatory)]
            [String]$TaskName,

            [Parameter(Mandatory)]
            [hashtable]$TaskParameter
        )
    }

    function Get-TaskCommandName
    {
        param(
            [Parameter(Mandatory)]
            [String]$Name
        )

        $script:tasks | Where-Object { $_.Name -eq $Name } | Select-Object -ExpandProperty 'CommandName'
    }

    function GivenEnvironmentVariable
    {
        param(
            $Name
        )

        Set-Item -Path ('env:{0}' -f $Name) -Value 'somevalue'
    }

    function GivenFile
    {
        param(
            $Name
        )

        New-Item -Path (Join-Path -Path $script:testRoot -ChildPath $Name)
    }

    function GivenMockedTask
    {
        [CmdletBinding(DefaultParameterSetName='ByTaskName')]
        param(
            [Parameter(Mandatory,ParameterSetName='ByTaskName',Position=0)]
            [String]$TaskName,

            [Parameter(Mandatory,ParameterSetName='ByCommandName')]
            [String]$CommandName,

            [scriptblock]$MockedWith
        )

        if( -not $CommandName )
        {
            $CommandName = Get-TaskCommandName -Name $TaskName
        }

        $optionalParams = @{ }
        if( $MockedWith )
        {
            $optionalParams['MockWith'] = $MockedWith
        }

        Mock -CommandName $CommandName -ModuleName 'Whiskey' @optionalParams
    }

    function GivenRunByBuildServer
    {
        $script:runByDeveloper = $false
        $script:runByBuildServer = $true
    }

    function GivenRunByDeveloper
    {
        $script:runByDeveloper = $true
        $script:runByBuildServer = $false
    }

    function GivenPlugins
    {
        param(
            [String]$ForSpecificTask
        )

        $script:enablePlugins = $true

        if( $ForSpecificTask )
        {
            $script:taskNameForPlugin = $ForSpecificTask
        }
    }

    function GivenDefaults
    {
        param(
            [hashtable]$Default,

            [String]$ForTask
        )

        $script:taskDefaults[$ForTask] = $Default
    }

    function GivenScmBranch
    {
        param(
            [String]$Branch
        )
        $script:scmBranch = $Branch
    }

    function GivenVariable
    {
        param(
            $Name,
            $Value
        )

        $script:variables[$Name] = $Value
    }

    function GivenWorkingDirectory
    {
        param(
            [String]$Directory
        )

        $wd = Join-Path -Path $script:testRoot -ChildPath $Directory
        [IO.Directory]::CreateDirectory($wd)
    }

    function ThenPipelineFailed
    {
        $threwException | Should -BeTrue
    }

    function ThenPipelineSucceeded
    {
        $Global:Error | Should -BeNullOrEmpty
        $threwException | Should -BeFalse
    }

    function ThenNoOutput
    {
        $script:output | Should -BeNullOrEmpty
    }

    function ThenPluginsRan
    {
        param(
            $ForTaskNamed,

            $WithParameter,

            [int]$Times = 1
        )

        foreach( $pluginName in @( 'Invoke-PreTaskPlugin', 'Invoke-PostTaskPlugin' ) )
        {
            if( $Times -eq 0 )
            {
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times 0 -ParameterFilter { $TaskName -eq $ForTaskNamed }
            }
            else
            {
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times $Times -ParameterFilter { $null -ne $TaskContext }
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times $Times -ParameterFilter {
                    #$DebugPreference = 'Continue'
                    Write-WhiskeyDebug -Message ('TaskName  expected  {0}' -f $ForTaskNamed)
                    Write-WhiskeyDebug -Message ('          actual    {0}' -f $TaskName)
                    $TaskName -eq $ForTaskNamed
                }
                Write-WhiskeyDebug -Message $pluginName
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times $Times -ParameterFilter {
                    $TaskParameter.Count | Should -Be $WithParameter.Count -Because 'should pass parameters to plugin'
                    foreach( $key in $WithParameter.Keys )
                    {
                        $TaskParameter[$key] | Should -Be $WithParameter[$key] -Because 'should pass parameter values to plugin'
                    }
                    return $true
                }
            }

            Unregister-WhiskeyEvent -Context $script:context -CommandName $pluginName -Event AfterTask
            Unregister-WhiskeyEvent -Context $script:context -CommandName $pluginName -Event AfterTask -TaskName $ForTaskNamed
            Unregister-WhiskeyEvent -Context $script:context -CommandName $pluginName -Event BeforeTask
            Unregister-WhiskeyEvent -Context $script:context -CommandName $pluginName -Event BeforeTask -TaskName $ForTaskNamed
        }
    }

    function ThenTaskNotRun
    {
        [CmdletBinding(DefaultParameterSetName='ByTaskName')]
        param(
            [Parameter(Mandatory,ParameterSetName='ByTaskName',Position=0)]
            [String]$TaskName,

            [Parameter(Mandatory,ParameterSetName='ByCommandName')]
            [String]$CommandName
        )

        if( -not $CommandName )
        {
            $CommandName = Get-TaskCommandName -Name $TaskName
        }

        Assert-MockCalled -CommandName $CommandName -ModuleName 'Whiskey' -Times 0
    }

    function ThenTaskRan
    {
        [CmdletBinding(DefaultParameterSetName='ByTaskName')]
        param(
            [Parameter(Mandatory, ParameterSetName='ByTaskName', Position=0)]
            [String] $Named,

            [Parameter(Mandatory, ParameterSetName='ByCommandName')]
            [String] $CommandNamed,

            [hashtable] $WithParameter = @{},

            [hashtable] $WithArgument = @{},

            [int] $Times = 1,

            [String] $InWorkingDirectory,

            [String[]] $WithoutParameter
        )

        if( -not $CommandNamed )
        {
            $CommandNamed = Get-TaskCommandName -Name $Named
        }

        Assert-MockCalled -CommandName $CommandNamed -ModuleName 'Whiskey' -Times $Times -Exactly -ParameterFilter {
            $PSBoundParameters | ConvertTo-Json | Write-WhiskeyDebug
            function Assert-Hashtable
            {
                param(
                    $Actual,
                    $Expected
                )

                $Actual.Count | Should -Be ($Expected.Count)
                foreach( $key in $Expected.Keys )
                {
                    if( $Expected[$key] -is [hashtable] )
                    {
                        $Actual[$key] | Should -BeOfType ([hashtable])
                        Assert-Hashtable $Actual[$key] $Expected[$key]
                    }
                    else
                    {
                        $Actual[$key] | Should -Be $Expected[$key]
                    }
                }
            }
            Assert-Hashtable -Expected $WithParameter -Actual $TaskParameter
            return $true
        }

        Assert-MockCalled -CommandName $CommandNamed -ModuleName 'Whiskey' -Times $Times -Exactly -ParameterFilter {
            foreach ($argName in $WithArgument.Keys)
            {
                Get-Variable -Name $argName -ValueOnly -ErrorAction Ignore |
                    Should -Be $WithArgument[$argName] -Because "should pass ${argName} value"
            }
            return $true
        }

        if( $InWorkingDirectory )
        {
            $wd = Join-Path -Path $script:testRoot -ChildPath $InWorkingDirectory

            Join-Path -Path $wd -ChildPath 'wd' | Should -Exist -Because 'should have run in this directory'
        }

        if( $WithoutParameter )
        {
            Assert-MockCalled -CommandName $CommandNamed -ModuleName 'Whiskey' -ParameterFilter {
                foreach( $name in $ParameterName )
                {
                    $TaskParameter[$name] | Should -BeNullOrEmpty -Because 'should not pass this property to task'
                }
                return $true
            }
        }
    }

    function ThenTempDirectoryCreated
    {
        param(
            $TaskName
        )

        $expectedTempPath = Join-Path -Path $script:context.OutputDirectory -ChildPath ('Temp.{0}.' -f $TaskName)
        $expectedTempPathRegex = '^{0}[a-z0-9]{{8}}\.[a-z0-9]{{3}}$' -f [regex]::escape($expectedTempPath)
        Assert-MockCalled -CommandName 'New-Item' -ModuleName 'Whiskey' -ParameterFilter {
            #$DebugPreference = 'Continue'
            $PSBoundParameters | ConvertTo-Json | Out-String | Write-WhiskeyDebug
            if( $Path -notmatch $expectedTempPathRegex )
            {
                Write-WhiskeyDebug ('Path  expected  {0}' -f $expectedTempPathRegex)
                return $false
            }
            $Force | Should -BeTrue -Because 'should force the creation of temporary directory'
            $ItemType | Should -Be 'Directory' -Because 'should create temporary *directory*'
            return $true
        }
    }

    function ThenTempDirectoryRemoved
    {
        param(
            $TaskName
        )

        $expectedTempPath = Join-Path -Path $script:context.OutputDirectory -ChildPath ('Temp.{0}.*' -f $TaskName)
        $expectedTempPath | Should -Not -Exist
        $script:context.Temp | Should -Not -Exist
    }

    function ThenThrewException
    {
        param(
            $Pattern
        )

        $threwException | Should -BeTrue
        $Global:Error | Should -Match $Pattern
    }

    function ThenToolInstalled
    {
        param(
            $ToolName,
            $Parameter
        )

        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter {
            #$DebugPreference = 'Continue'
            $ToolInfo.Name | Should -Be $ToolName -Because 'should install the right tool'
            $PesterBoundParameters['ErrorAction'] | Should -Be 'Stop' -Because 'should fail the build if install fails'
            $expectedInstallRoot = $script:testRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)
            Write-WhiskeyDebug -Message ('InstallRoot  expected  {0}' -f $expectedInstallRoot)
            Write-WhiskeyDebug -Message ('             actual    {0}' -f $InstallRoot)
            return $InstallRoot -eq $expectedInstallRoot -and
                $OutFileRootPath -eq (Join-Path -Path $expectedInstallRoot -ChildPath '.output')
        }
    }

    function ThenToolNotCleaned
    {
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -Times 0
    }

    function ThenToolPathPassedToTask
    {
        param(
            $ParameterName,
            $Path
        )

        $script:taskProperties.ContainsKey($ParameterName) | Should -BeTrue
    }

    function ThenToolUninstalled
    {
        param(
            $ToolName
        )

        $taskContext = $script:context
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $ToolInfo.Name -eq $ToolName }
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { [Object]::ReferenceEquals($Context,$taskContext) }
    }

    function WhenRunningMockedTask
    {
        [CmdletBinding()]
        param(
            [String]$Named,
            [hashtable]$Parameter = @{},
            [String]$InRunMode,
            [switch]$ThatMarksWorkingDirectory
        )

        $optionalParams = @{}
        if( $ThatMarksWorkingDirectory )
        {
            $optionalParams['MockedWith'] = {
                '' | Set-Content -Path 'wd'
            }
        }

        GivenMockedTask $Named @optionalParams

        $PSBoundParameters.Remove('ThatMarksWorkingDirectory')

        WhenRunningTask @PSBoundParameters
    }

    function WhenRunningTask
    {
        [CmdletBinding()]
        param(
            [String]$Named,
            [hashtable]$Parameter = @{},
            [String]$InRunMode
        )

        $byItDepends = @{ 'ForDeveloper' = $true }
        if( $script:runByBuildServer )
        {
            $byItDepends = @{ 'ForBuildServer' = $true }
        }

        $script:context = New-WhiskeyTestContext @byItDepends -ForBuildRoot $script:testRoot
        $script:context.PipelineName = 'Build';
        $script:context.TaskIndex = 1;
        foreach( $key in $script:taskDefaults.Keys )
        {
            $script:context.TaskDefaults.Add($key,$script:taskDefaults[$key])
        }

        if( $InRunMode )
        {
            $script:context.RunMode = $InRunMode
        }

        if( $script:scmBranch )
        {
            $script:context.BuildMetadata.ScmBranch = $script:scmBranch
        }

        if( $script:enablePlugins )
        {
            $taskNameParam = @{}
            if( $script:taskNameForPlugin )
            {
                $taskNameParam['TaskName'] = $script:taskNameForPlugin
            }

            Register-WhiskeyEvent -Context $script:context -CommandName 'Invoke-PostTaskPlugin' -Event AfterTask @taskNameParam
            Mock -CommandName 'Invoke-PostTaskPlugin' -ModuleName 'Whiskey'
            Register-WhiskeyEvent -Context $script:context -CommandName 'Invoke-PreTaskPlugin' -Event BeforeTask @taskNameParam
            Mock -CommandName 'Invoke-PreTaskPlugin' -ModuleName 'Whiskey'
        }

        Mock -CommandName 'New-Item' -ModuleName 'Whiskey' -MockWith { [IO.Directory]::CreateDirectory($Path) }

        foreach( $variableName in $script:variables.Keys )
        {
            Add-WhiskeyVariable -Context $script:context -Name $variableName -Value $script:variables[$variableName]
        }

        $Global:Error.Clear()
        $script:threwException = $false
        try
        {
            $script:output = Invoke-WhiskeyTask -TaskContext $script:context `
                                                -Name $Named `
                                                -Parameter $Parameter `
                                                4>&1 `
                                                5>&1
            Write-Verbose '# BEGIN TASK OUTPUT' #-Verbose
            $script:output | Write-Verbose #-Verbose
            Write-Verbose '# END   TASK OUTPUT' #-Verbose
        }
        catch
        {
            Write-CaughtError $_
            $script:threwException = $true
        }
    }
}

AfterAll {
    Remove-Module -Name 'WhiskeyTestTasks' -Force -ErrorAction Ignore
}

Describe 'Invoke-WhiskeyTask' {
    BeforeEach {
        $script:taskDefaults = @{ }
        $script:output = $null
        $script:scmBranch = $null
        $script:taskProperties = @{ }
        $script:taskRun = $false
        $script:variables = @{ }
        $script:enablePlugins = $null
        $script:taskNameForPlugin = $null
        $script:taskRunCount = 0
        $script:testRoot = New-WhiskeyTestRoot
    }

    AfterEach {
        Remove-Node -BuildRoot $script:testRoot
        if (Test-Path -Path 'env:fubar')
        {
            Remove-Item -Path 'env:fubar'
        }
    }

    AfterAll {
        Remove-Item -Path 'function:\Invoke-PreTaskPlugin'
        Remove-Item -Path 'function:\Invoke-PostTaskPlugin'
    }

    It 'should fail builds' {
        WhenRunningTask 'FailingTask' -ErrorAction SilentlyContinue
        ThenPipelineFailed
        ThenThrewException 'Failed!'
        ThenTempDirectoryCreated 'FailingTask'
        ThenTempDirectoryRemoved 'FailingTask'
    }

    It 'should run the event handlers' {
        GivenPlugins
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ Path = 'somefile.ps1' }
        ThenPipelineSucceeded
        ThenPluginsRan -ForTaskNamed 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' }
        ThenTempDirectoryCreated 'NoOpTask.OnBeforeTask'
        ThenTempDirectoryCreated 'NoOpTask'
        ThenTempDirectoryCreated 'NoOpTask.OnAfterTask'
        ThenTempDirectoryRemoved 'NoOpTask.OnBeforeTask'
        ThenTempDirectoryRemoved 'NoOpTask'
        ThenTempDirectoryRemoved 'NoOpTask.OnAfterTask'
    }

    It 'should run task-specific events' {
        GivenPlugins -ForSpecificTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ Path = 'somefile.ps1' }
        ThenPipelineSucceeded
        ThenPluginsRan -ForTaskNamed 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' }
    }

    $tasks = @(
        @{ Name = 'NamedParametersTask' ; Style = 'CamelCase' },
        @{ Name = 'named_parameters_task' ; Style = 'snake_case' ; }
    )
    It 'runs task with <Style> name' -ForEach $tasks {
        GivenMockedTask 'NamedParametersTask'
        WhenRunningTask $Name
        ThenPipelineSucceeded
        ThenTaskRan 'NamedParametersTask' -WithParameter @{}
    }

    $testCases = @(
        @{
            Style = 'CamelCase';
            Properties = @{
                'NameOne' = 'enoeman';
                'NameTwo' = 'owtman';
            };
            Arguments = @{
                'NameOne' = 'enoeman';
                'NameTwo' = 'owtman';
            };
            Parameters = @{
                'NameOne' = 'enoeman';
                'NameTwo' = 'owtman';
            };
        },
        @{
            Style = 'snake_case';
            Properties = @{
                'name_one' = 'enoeman';
                'name_two' = 'owtman';
            };
            Arguments = @{
                'NameOne' = 'enoeman';
                'NameTwo' = 'owtman';
            };
            Parameters = @{
                'NameOne' = 'enoeman';
                'NameTwo' = 'owtman';
                'name_one' = 'enoeman';
                'name_two' = 'owtman';
            }
        }
    )
    It 'runs task with <Style> property names' -ForEach $testCases {
        WhenRunningMockedTask 'NamedAndTaskParameter' -Parameter $Properties
        ThenPipelineSucceeded
        ThenTaskRan 'NamedAndTaskParameter' -WithArgument $Arguments -WithParameter $Parameters
    }

    It 'should apply those task defaults' {
        $defaults = @{ 'Fubar' = @{ 'Snfau' = 'value1' ; 'Key2' = 'value1' }; 'Key3' = 'Value3' }
        GivenDefaults $defaults -ForTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask'
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter $defaults
    }

    It 'should not not apply task defaults' {
        $defaults = @{ 'Fubar' = @{ 'Snfau' = 'value1' ; 'Key2' = 'value1' }; 'Key3' = 'Value3' }
        GivenDefaults $defaults -ForTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Fubar' = @{ 'Snfau' = 'myvalue' } ; 'NotADefault' = 'NotADefault' }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Fubar' = @{ 'Snfau' = 'myvalue'; 'Key2' = 'value1' }; 'Key3' = 'Value3'; 'NotADefault' = 'NotADefault' }
    }

    It 'should replace variables with values' {
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = '$(MachineName)'; }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = [Environment]::MachineName; }
        ThenNoOutput
    }

    It 'should not run task in clean mode' {
        WhenRunningMockedTask 'BuildOnlyTask' -InRunMode 'Clean'
        ThenTaskNotRun 'BuildOnlyTask'
    }

    It 'should run task in clean mode' {
        WhenRunningMockedTask 'SupportsCleanTask' -InRunMode 'Clean'
        ThenTaskRan 'SupportsCleanTask'
    }

    It 'should not run task in initialize mode' {
        WhenRunningMockedTask 'BuildOnlyTask' -InRunMode 'Initialize'
        ThenTaskNotRun 'BuildOnlyTask'
    }

    It 'should run task in initialize mode' {
        WhenRunningMockedTask 'SupportsInitializeTask' -InRunMode 'Initialize'
        ThenTaskRan 'SupportsInitializeTask'
    }

    It 'should install task tool' {
        Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        WhenRunningTask 'RequiresNodeTask'
        ThenPipelineSucceeded
        ThenToolInstalled 'Node'
        ThenToolNotCleaned
    }

    It 'should install the tool during initialize mode' {
        Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        WhenRunningTask 'RequiresNodeFailingTask' -InRunMode 'Initialize'
        ThenToolInstalled 'Node'
        ThenToolNotCleaned
        ThenPipelineSucceeded
    }

    It 'should remove tool when cleaning' {
        Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        WhenRunningTask 'RequiresNodeTask' -InRunMode 'Clean'
        ThenToolUninstalled 'Node'
        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $InCleanMode -eq $true }
    }

    It 'should should not download tool when cleaning' {
        Install-Node -BuildRoot $script:testRoot
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey'
        WhenRunningTask 'RequiresNodeTask' -InRunMode 'Clean'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 0
    }

    It 'should allow tasks to call other tasks' {
        GivenMockedTask 'NoOpTask'
        WhenRunningTask 'WrapsNoOpTask' -Parameter @{ 'Path' = 'script.ps1' }
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'script.ps1' }
        ThenTempDirectoryCreated 'WrapsNoOpTask'
        ThenTempDirectoryCreated 'NoOpTask'
        ThenTempDirectoryRemoved 'WrapsNoOpTask'
        ThenTempDirectoryRemoved 'NoOpTask'
        ThenPipelineSucceeded
    }

    It 'should run or not run Windows-only task' {
        WhenRunningMockedTask 'WindowsOnlyTask' -ErrorAction SilentlyContinue
        if( $IsWindows )
        {
            ThenTaskRan 'WindowsOnlyTask'
        }
        else
        {
            ThenTaskNotRun 'WindowsOnlyTask'
            ThenThrewException -Pattern 'only\ supported\ on\ the\ Windows\ platform'
        }
    }

    It 'should run or not run Linux-only task' {
        WhenRunningMockedTask 'LinuxOnlyTask' -ErrorAction SilentlyContinue
        if( $IsLinux )
        {
            ThenTaskRan 'LinuxOnlyTask'
        }
        else
        {
            ThenTaskNotRun 'LinuxOnlyTask'
            ThenThrewException -Pattern 'only\ supported\ on\ the\ Linux\ platform'
        }
    }

    It 'should run or not run macOS-only task' {
        WhenRunningMockedTask 'MacOSOnlyTask' -ErrorAction SilentlyContinue
        if( $IsMacOS )
        {
            ThenTaskRan 'MacOSOnlyTask'
        }
        else
        {
            ThenTaskNotRun 'MacOSOnlyTask'
            ThenThrewException -Pattern 'only\ supported\ on\ the\ MacOS\ platform'
        }
    }

    It 'should run or not run Windows and Linux-only task' {
        WhenRunningMockedTask 'WindowsAndLinuxTask' -ErrorAction SilentlyContinue
        if( $IsMacOS )
        {
            ThenTaskNotRun 'WindowsAndLinuxTask'
            ThenThrewException -Pattern 'only\ supported\ on\ the\ Windows, Linux\ platform'
        }
        else
        {
            ThenTaskRan 'WindowsAndLinuxTask'
        }
    }

    It 'should run task using its alias' {
        GivenMockedTask 'AliasedTask'
        WhenRunningTask 'OldAliasedTaskName'
        WhenRunningTask 'AnotherOldAliasedTaskName'
        ThenTaskRan 'AliasedTask' -Times 2
    }

    It 'should write warning for obsolete task' {
        GivenMockedTask 'ObsoleteAliasTask'
        WhenRunningTask 'OldObsoleteAliasTaskName' -WarningVariable 'warnings'
        $warnings | Should -Not -BeNullOrEmpty
        $warnings | Should -Match 'is\ an\ alias'
        ThenTaskRan -CommandNamed 'ObsoleteAliasTask'
    }

    It 'should validate task aliases are unique' {
        GivenMockedTask 'DuplicateAliasTask1'
        GivenMockedTask 'DuplicateAliasTask2'
        WhenRunningTask 'DuplicateAliasTask' -Parameter @{} -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'Found\ \d+\ tasks\ with\ alias'
        ThenTaskNotRun -CommandName 'DuplicateAliasTask1'
        ThenTaskNotRun -CommandName 'DuplicateAliasTask2'
    }

    It 'should validate task names are unique' {
        GivenMockedTask -CommandName 'DuplicateTask1'
        GivenMockedTask -CommandName 'DuplicateTask2'
        WhenRunningTask 'DuplicateTask' -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'Found\ \d+\ tasks\ named'
        ThenTaskNotRun -CommandName 'DuplicateTask1'
        ThenTaskNotRun -CommandName 'DuplicateTask2'
    }

    It 'should warn that a task is obsolete' {
        WhenRunningMockedTask 'ObsoleteTask' -WarningVariable 'warnings'
        $warnings | Should -Match 'is\ obsolete'
        ThenTaskRan 'ObsoleteTask'
    }

    It 'should use custom obsolete warning message' {
        WhenRunningTask 'ObsoleteWithCustomMessageTask' -WarningVariable 'warnings'
        $warnings | Should -Match 'Use\ the\ NonObsoleteTask\ instead\.'
        $warnings | Should -Not -Match 'is\ obsolete'
    }

    $notOnWindows = (Test-Path -Path 'variable:IsWindows') -and -not $IsWindows
    It 'runs commands' -Skip:$notOnWindows {
        WhenRunningTask "cmd /C echo Hello, World! > helloworld.txt"
        ThenPipelineSucceeded
        $outputFilePath = Join-Path -Path $script:testRoot -ChildPath 'helloworld.txt'
        $outputFilePath | Should -Exist
        Get-Content -Path $outputFilePath | Should -Be 'Hello, World! '
    }

    It 'runs commands with default properties' -Skip:$notOnWindows {
        WhenRunningTask 'Exec' -Parameter @{ '' = "cmd /C echo Hello, World 2! > helloworld2.txt" }
        ThenPipelineSucceeded
        $outputFilePath = Join-Path -Path $script:testRoot -ChildPath 'helloworld2.txt'
        $outputFilePath | Should -Exist
        Get-Content -Path $outputFilePath | Should -Be 'Hello, World 2! '
    }

    Context 'common properties' {
        function New-Matrix
        {
            param(
                [String] $Vector1Name,

                [String[]] $Vector1,

                [String] $Vector2Name,

                [String[]] $Vector2
            )

            foreach ($one in $Vector1)
            {
                foreach ($two in $Vector2)
                {
                    @{ $Vector1Name = $one ; $Vector2Name = $two ; } | Write-Output
                }
            }
        }

        $onlyByNames = @('OnlyBy', '.OnlyBy', '.only_by')
        $exceptByNames = @('ExceptBy', '.ExceptBy', '.except_by')

        $onlyOnBranchNames = @('OnlyOnBranch', '.OnlyOnBranch', '.only_on_branch')
        $exceptOnBranchNames = @('ExceptOnBranch', '.ExceptOnBranch', '.except_on_branch')

        $wdNames = @('WorkingDirectory', '.WorkingDirectory', '.working_directory')

        $exceptDuringNames = @('ExceptDuring', '.ExceptDuring', '.except_during')
        $onlyDuringNames = @('OnlyDuring', '.OnlyDuring', '.only_during')
        $duringMatrix = New-Matrix -Vector1Name 'ExceptDuring' -Vector1 $exceptDuringNames `
                                   -Vector2Name 'OnlyDuring'   -Vector2 $onlyDuringNames

        $onlyOnPlatformNames = @('OnlyOnPlatform', '.OnlyOnPlatform', '.only_on_platform')
        $exceptOnPlatformNames = @('ExceptOnPlatform', '.ExceptOnPlatform', '.except_on_platform')

        Context 'by conditions' {
            Context 'only by condition' {
                Context 'using <_> property name' -ForEach $onlyByNames {
                    It 'runs Developer task' -ForEach $_ {
                        GivenRunByBuildServer
                        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; $_ = 'Developer' }
                        ThenPipelineSucceeded
                        ThenTaskNotRun 'NoOpTask'
                    }

                    It 'does not run Developer task' -ForEach $_ {
                        GivenRunByDeveloper
                        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; $_ = 'Developer' }
                        ThenPipelineSucceeded
                        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter $_
                    }

                    It 'runs <_> BuildServer task' -ForEach $_ {
                        GivenRunByBuildServer
                        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; $_ = 'BuildServer' }
                        ThenPipelineSucceeded
                        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter $_
                    }

                    It 'does not run <_> BuildServer task' -ForEach $_ {
                        GivenRunByDeveloper
                        WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'BuildServer' }
                        ThenPipelineSucceeded
                        ThenTaskNotRun 'NoOpTask'
                    }
                }
            }

            Context 'except by condition' {
                Context 'using <_> property name' -ForEach $exceptByNames {
                    It 'runs BuildServer task' -ForEach $_ {
                        GivenRunByBuildServer
                        WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'BuildServer' }
                        ThenPipelineSucceeded
                        ThenTaskNotRun 'NoOpTask'
                    }

                    It 'runs BuildServer task' -ForEach $_ {
                        GivenRunByDeveloper
                        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; $_ = 'BuildServer' }
                        ThenPipelineSucceeded
                        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' }
                    }
                }
            }

            It 'validates <_> value' -ForEach ($onlyByNames + $exceptByNames) {
                GivenRunByDeveloper
                WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'Somebody' } -ErrorAction SilentlyContinue
                ThenThrewException 'invalid value'
                ThenTaskNotRun 'NoOpTask'
            }

            $byMatrix =
                New-Matrix -Vector1Name 'OnlyBy' -Vector1 $onlyByNames -Vector2Name 'ExceptBy' -Vector2 $exceptByNames
            It 'prohibits both <OnlyBy> and <ExceptBy> properties' -ForEach $byMatrix {
                GivenRunByDeveloper
                GivenScmBranch 'develop'
                WhenRunningMockedTask 'NoOpTask' `
                                    -Parameter @{ $OnlyBy = 'Developer'; $ExceptBy = 'Developer' } `
                                    -ErrorAction SilentlyContinue
                ThenThrewException 'except_?by"\ and\ "\.only_?by'
                ThenTaskNotRun 'NoOpTask'
            }
        }

        Context 'scm branch conditions' {
            Context 'only on branch condition' {
                Context 'using <_> property' -ForEach $onlyOnBranchNames {
                    It 'runs task' -ForEach $_ {
                        GivenRunByDeveloper
                        GivenScmBranch 'develop'
                        WhenRunningMockedTask 'NoOpTask' `
                                            -Parameter @{ 'Path' = 'somefile.ps1'; $_ = 'develop' } `
                                            -ErrorAction SilentlyContinue
                        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter $_
                    }

                    It 'supports wildcard branch names' -ForEach $_ {
                        GivenRunByDeveloper
                        GivenScmBranch 'develop'
                        WhenRunningMockedTask 'NoOpTask' `
                                            -Parameter @{ 'Path' = 'somefile.ps1'; $_ = @( 'master', 'dev*' ) } `
                                            -ErrorAction SilentlyContinue
                        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter $_
                    }

                    It 'does not run task' -ForEach $_ {
                        GivenRunByDeveloper
                        GivenScmBranch 'develop'
                        WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'notDevelop' } -ErrorAction SilentlyContinue
                        ThenTaskNotRun 'NoOpTask'
                    }

                    It 'uses value from defaults task' -ForEach $_ {
                        GivenDefaults @{ $_ = 'Snafu' } -ForTask 'NoOpTask'
                        GivenScmBranch 'Snafu'
                        WhenRunningMockedTask 'NoOpTask'
                        ThenTaskRan 'NoOpTask'
                    }
                }
            }

            Context 'except on branch condition' {
                Context 'using <_> property' -ForEach $exceptOnBranchNames {
                    It 'does not run task' -ForEach $_ {
                        GivenRunByDeveloper
                        GivenScmBranch 'develop'
                        WhenRunningMockedTask 'NoOpTask' `
                                            -Parameter @{ 'Path' = 'somefile.ps1'; $_ = 'develop' } `
                                            -ErrorAction SilentlyContinue
                        ThenTaskNotRun 'NoOpTask'
                    }

                    It 'supports wildcards in branch names' -ForEach $_ {
                        GivenRunByDeveloper
                        GivenScmBranch 'develop'
                        WhenRunningMockedTask 'NoOpTask' `
                                            -Parameter @{ $_ = @( 'master', 'dev*' ) } `
                                            -ErrorAction SilentlyContinue
                        ThenTaskNotRun 'NoOpTask'
                    }

                    It 'runs task' -ForEach $_ {
                        GivenRunByDeveloper
                        GivenScmBranch 'develop'
                        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; $_ = 'notDevelop' }
                        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter $_
                    }
                }
            }

            $branchMatrix = New-Matrix -Vector1Name 'ExceptOnBranch' -Vector1 $exceptOnBranchNames `
                                       -Vector2Name 'OnlyOnBranch'   -Vector2 $onlyOnBranchNames
            It 'prohibits <ExceptOnBranch> and <OnlyOnBranch> properties' -ForEach $branchMatrix {
                GivenRunByDeveloper
                GivenScmBranch 'develop'
                WhenRunningMockedTask 'NoOpTask' `
                                    -Parameter @{ $ExceptOnBranch = 'develop'; $OnlyOnBranch = 'develop' } `
                                    -ErrorAction SilentlyContinue
                ThenThrewException ('except_?on_?branch"\ and\ "\.?only_?on_?branch')
                ThenTaskNotRun 'NoOpTask'
            }
        }

        Context 'working directory' {
            Context 'using <_> property name' -ForEach $wdNames {
                It 'runs task in a working directory' -ForEach $_ {
                    GivenRunByDeveloper
                    GivenWorkingDirectory '.output'
                    WhenRunningMockedTask -Named 'NoOpTask' `
                                        -Parameter @{ 'Path' = 'somefile.ps1'; $_ = '.output' } `
                                        -ThatMarksWorkingDirectory
                    ThenTaskRan -Named 'NoOpTask' `
                                -WithParameter @{ 'Path' = 'somefile.ps1' } `
                                -WithoutParameter $_ `
                                -InWorkingDirectory '.output'
                }

                It 'always installs tool in the build root' -ForEach $_ {
                    GivenRunByDeveloper
                    GivenWorkingDirectory '.output'
                    $script:testRoot = $script:testRoot
                    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -MockWith {
                            #$DebugPreference = 'Continue'
                            $currentPath = (Get-Location).ProviderPath
                            Write-WhiskeyDebug ('Current  Path   {0}' -f $currentPath)
                            Write-WhiskeyDebug ('Expected Path   {0}' -f $script:testRoot)
                            if( $currentPath -ne $script:testRoot )
                            {
                                throw 'tool installation didn''t happen in the build root'
                            }
                        }
                    $parameter = @{ $_ = '.output' }
                    WhenRunningTask 'RequiresNodeTask' -Parameter $parameter
                    ThenToolInstalled 'Node'
                    ThenPipelineSucceeded
                }

                It 'should clean in custom working directory' -ForEach $_ {
                    GivenRunByDeveloper
                    GivenWorkingDirectory '.output'
                    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
                    $script:testRoot = $script:testRoot
                    Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -MockWith {
                            #$DebugPreference = 'Continue'
                            $currentPath = (Get-Location).ProviderPath
                            $expectedPath = Join-Path -Path $script:testRoot -ChildPath '.output'
                            Write-WhiskeyDebug ('Current  Path   {0}' -f $currentPath)
                            Write-WhiskeyDebug ('Expected Path   {0}' -f $expectedPath)
                            if( $currentPath -ne $expectedPath )
                            {
                                throw 'tool uninstallation didn''t happen in the task''s working directory'
                            }
                        }
                    WhenRunningTask 'RequiresNodeTask' -Parameter @{ $_ = '.output' } -InRunMode 'Clean'
                    ThenPipelineSucceeded
                    ThenToolUninstalled 'Node'
                }
            }

            It 'validates directory exists' {
                GivenRunByDeveloper
                WhenRunningMockedTask 'NoOpTask' `
                                    -Parameter @{ '.working_directory' = 'Invalid/Directory' } `
                                    -ErrorAction SilentlyContinue
                ThenThrewException '\bInvalid(\\|/)Directory\b.+does not exist'
                ThenTaskNotRun 'NoOpTask'
            }
        }

        Context 'run mode conditions' {
            $modeNames = @('Clean', 'Initialize', 'Build')
            $modeExceptDuringMatrix =
                New-Matrix -Vector1Name 'RunMode' -Vector1 $modenames -Vector2Name 'ExceptDuring' -Vector2 $exceptDuringNames
            It 'does not run <RunMode> task with except during property <ExceptDuring>' -ForEach $modeExceptDuringMatrix {
                $TaskParameter = @{ $ExceptDuring = $RunMode }
                WhenRunningMockedTask 'SupportsCleanAndInitializeTask' -Parameter $TaskParameter
                WhenRunningTask 'SupportsCleanAndInitializeTask' -Parameter $TaskParameter -InRunMode 'Clean'
                WhenRunningTask 'SupportsCleanAndInitializeTask' -Parameter $TaskParameter -InRunMode 'Initialize'
                ThenTaskRan 'SupportsCleanAndInitializeTask' -Times 2 -WithoutParameter $ExceptDuring
            }
        }

        Context 'if exists condition' {
            Context 'using <_> property name' -ForEach @('IfExists', '.IfExists', '.if_exists') {
                It 'runs <_> env: task' -ForEach $_ {
                    GivenEnvironmentVariable 'fubar'
                    $TaskParameter = @{ $_ = 'env:fubar' }
                    WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
                    ThenTaskRan 'NoOpTask'
                }

                It 'does not run <_> env: task' -forEach $_ {
                    $TaskParameter = @{ $_ = 'env:snafu' }
                    WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
                    ThenTaskNotRun 'NoOpTask'
                }

                It 'runs <_> file task' -ForEach $_ {
                    GivenFile 'fubar'
                    $TaskParameter = @{ $_ = 'fubar' }
                    WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
                    ThenTaskRan 'NoOpTask'
                }

                It 'does not run <_> file task' -ForEach $_ {
                    $TaskParameter = @{ $_ = 'fubar' }
                    WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
                    ThenTaskNotRun 'NoOpTask'
                }
            }
        }

        Context 'unless exists condition' {
            Context 'using <_> property name' -ForEach @('UnlessExists', '.UnlessExists', '.unless_exists') {
                It 'does not run <_> env: task' -ForEach $_ {
                    GivenEnvironmentVariable 'fubar'
                    $TaskParameter = @{ $_ = 'env:fubar' }
                    WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
                    ThenTaskNotRun 'NoOpTask'
                }

                It 'runs <_> env: task' -ForEach $_ {
                    $TaskParameter = @{ $_ = 'env:snafu' }
                    WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
                    ThenTaskRan 'NoOpTask'
                }

                It 'does not run <_> file task' -ForEach $_ {
                    GivenFile 'fubar'
                    $TaskParameter = @{ $_ = 'fubar' }
                    WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
                    ThenTaskNotRun 'NoOpTask'
                }

                It 'runs <_> file task' -ForEach $_ {
                    $TaskParameter = @{ $_ = 'fubar' }
                    WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
                    ThenTaskRan 'NoOpTask'
                }
            }
        }

        Context 'during conditions' {
            It 'prohibits both <ExceptDuring> and <OnlyDuring> properties' -ForEach $duringMatrix {
                WhenRunningMockedTask 'SupportsCleanAndInitializeTask' `
                                      -Parameter @{ $ExceptDuring = 'Clean'; $OnlyDuring = 'Clean' } `
                                      -ErrorAction SilentlyContinue
                ThenThrewException 'except_?during"\ and\ "\.?only_?during'
                ThenTaskNotRun 'SupportsCleanAndInitializeTask'
            }

            Context 'using <_> property name' -ForEach ($onlyDuringNames + $exceptDuringNames) {
                It 'validates value' -ForEach $_ {
                    WhenRunningMockedTask 'SupportsCleanAndInitializeTask' `
                                          -Parameter @{ $_ = 'InvalidValue' } `
                                          -ErrorAction SilentlyContinue
                    ThenThrewException "\.(only|except)_during.*invalid value"
                    ThenTaskNotRun 'SupportsCleanAndInitializeTask'
                }
            }
        }

        Context 'enum-value properties' {
            $testCases = $onlyByNames +
                         $exceptByNames +
                         $onlyDuringNames +
                         $exceptDuringNames +
                         $onlyOnPlatformNames +
                         $exceptOnPlatformNames
            Context '<_> property' -ForEach $testCases {
                It 'validates value' -ForEach $_ {
                    GivenDefaults @{ $_ = 'Snafu' } -ForTask 'NoOpTask'
                    WhenRunningMockedTask 'NoOpTask' -ErrorAction SilentlyContinue
                    ThenThrewException 'invalid\ .* "Snafu"'
                    ThenTaskNotRun 'NoOpTask'
                }
            }
        }

        Context 'string-value properties' {
            Context '<_> property' -ForEach $wdNames {
                It 'uses value from defaults task' -ForEach $_ {
                    GivenWorkingDirectory 'Snafu'
                    GivenDefaults @{ $_ = 'Snafu' } -ForTask 'NoOpTask'
                    WhenRunningMockedTask 'NoOpTask' -ThatMarksWorkingDirectory
                    ThenTaskRan 'NoOpTask' -InWorkingDirectory 'Snafu'
                }
            }
        }

        Context 'platform conditions' {
            It 'runs <_> Windows task' -ForEach $onlyOnPlatformNames {
                WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'Windows' }
                if ($IsWindows)
                {
                    ThenTaskRan 'NoOpTask'
                }
                else
                {
                    ThenTaskNotRun 'NoOpTask'
                }
            }

            It 'runs <_> Linux task' -ForEach $onlyOnPlatformNames {
                WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'Linux' }
                if( $IsLinux )
                {
                    ThenTaskRan 'NoOpTask'
                }
                else
                {
                    ThenTaskNotRun 'NoOpTask'
                }
            }

            It 'runs <_> macOS task' -ForEach $onlyOnPlatformNames {
                WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'MacOS' }
                if ($IsMacOS)
                {
                    ThenTaskRan 'NoOpTask'
                }
                else
                {
                    ThenTaskNotRun 'NoOpTask'
                }
            }

            It 'runs <_> Windows or macOS task' -ForEach $onlyOnPlatformNames {
                WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = @( 'Windows','MacOS' ) }
                if ($IsLinux)
                {
                    ThenTaskNotRun 'NoOpTask'
                }
                else
                {
                    ThenTaskRan 'NoOpTask'
                }
            }

            It 'runs <_> Windows task' -ForEach $exceptOnPlatformNames {
                WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'Windows' }
                if ($IsWindows)
                {
                    ThenTaskNotRun 'NoOpTask'
                }
                else
                {
                    ThenTaskRan 'NoOpTask'
                }
            }

            It 'runs <_> Linux task' -ForEach $exceptOnPlatformNames {
                WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'Linux' }
                if ($IsLinux)
                {
                    ThenTaskNotRun 'NoOpTask'
                }
                else
                {
                    ThenTaskRan 'NoOpTask'
                }
            }

            It 'runs <_> macOS task' -ForEach $exceptOnPlatformNames {
                WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'MacOS' }
                if ($IsMacOS)

                {
                    ThenTaskNotRun 'NoOpTask'
                }
                else
                {
                    ThenTaskRan 'NoOpTask'
                }
            }

            It 'runs <_> Windows and macOS task' -ForEach $exceptOnPlatformNames {
                WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = @( 'Windows','MacOS' ) }
                if ($IsLinux)
                {
                    ThenTaskRan 'NoOpTask'
                }
                else
                {
                    ThenTaskNotRun 'NoOpTask'
                }
            }
        }

        Context 'error action' {
            Context 'using <_> property name' -ForEach @('ErrorAction', '.ErrorAction', '.error_action') {
                It 'sets tasks''s ErrorActionPreference using <_> property' -ForEach $_ {
                    $ErrorActionPreference = 'Ignore'
                    WhenRunningTask 'Log' `
                                    -Parameter @{ Message = 'FAIL!'; Level = 'Error' ; $_ = 'Stop' } `
                                    -ErrorVariable 'errors'
                    ThenPipelineFailed
                    ThenThrewException 'FAIL!'
                }
            }
        }

        Context 'warning action' {
            Context 'using <_> property name' -ForEach @('WarningAction', '.WarningAction', '.warning_action') {
                It 'sets tasks''s WarningPreference using <_> property' -ForEach $_ {
                    $WarningPreference = 'Ignore'
                    WhenRunningTask 'Log' `
                                    -Parameter @{ Message = 'WARNING!'; Level = 'Warning' ; $_ = 'Continue' } `
                                    -WarningVariable 'warnings'
                    ThenPipelineSucceeded
                    $warnings | Should -Match 'WARNING!'
                }
            }
        }

        Context 'information action' {
            Context 'using <_> property name' -ForEach @('InformationAction', '.InformationAction', '.information_action') {
                It 'sets tasks''s InformationPreference' -ForEach $_ {
                    $InformationPreference = 'Ignore'
                    WhenRunningTask 'Log' `
                                    -Parameter @{ Message = 'INFORMATION!'; $_ = 'Continue' } `
                                    -InformationVariable 'infos'
                    ThenPipelineSucceeded
                    $infos | Should -Match 'INFORMATION!'
                }
            }
        }

        Context 'verbose preference' {
            Context 'using <_> property name' -ForEach @('Verbose', '.Verbose', '.verbose') {
                It 'sets tasks''s VerbosePreference using <_> property' -ForEach $_ {
                    $VerbosePreference = 'Ignore'
                    WhenRunningTask 'Log' -Parameter @{ Message = 'VERBOSE!'; 'Level' = 'Verbose'; $_ = 'true' }
                    ThenPipelineSucceeded
                    $script:output | Should -Match 'VERBOSE!'
                }
            }
        }

        Context 'debug preference' {
            Context 'using <_> property name' -ForEach @('Debug', '.Debug', '.debug') {
                It 'sets tasks''s DebugPreference using <_> property' -ForEach $_ {
                    $DebugPreference = 'Ignore'
                    WhenRunningTask 'Log' -Parameter @{ Message = 'DEBUG!'; 'Level' = 'Debug'; $_ = 'true' }
                    ThenPipelineSucceeded
                    $script:output | Should -Match 'DEBUG!'
                }
            }
        }

        Context 'out variable' {
            Context 'using <_> property name' -ForEach @('OutVariable', '.OutVariable', '.out_variable') {
                Context 'task does not have CmdletBinding attribute' -ForEach $_ {
                    It 'captures task output in Whiskey variable and sends to STDOUT' -ForEach $_ {
                        WhenRunningTask 'GenerateOutputTask' -Parameter @{ 'Output' = 'task output text'; $_ = 'TASK_OUTPUT' }
                        ThenPipelineSucceeded
                        $script:output | Should -Be 'task output text'
                        $script:context.Variables.ContainsKey('TASK_OUTPUT') | Should -BeTrue
                        $script:context.Variables['TASK_OUTPUT'] | Should -Be 'task output text'
                    }
                }

                Context 'task has CmdletBinding attribute' -ForEach $_ {
                    It 'captures task output in Whiskey variable and sends to STDOUT' -ForEach $_ {
                        WhenRunningTask 'GenerateOutputTaskWithCmdletBinding' `
                                        -Parameter @{ Output = 'task output text'; $_ = 'TASK_OUTPUT' }
                        ThenPipelineSucceeded
                        $script:output | Should -Be 'task output text'
                        $script:context.Variables.ContainsKey('TASK_OUTPUT') | Should -BeTrue
                        $script:context.Variables['TASK_OUTPUT'] | Should -Be 'task output text'
                    }
                }
            }
        }
    }
}

