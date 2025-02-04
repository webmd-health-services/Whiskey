
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
            [Parameter(Mandatory,ParameterSetName='ByTaskName',Position=0)]
            [String]$Named,

            [Parameter(Mandatory,ParameterSetName='ByCommandName')]
            [String]$CommandNamed,

            [hashtable]$WithParameter = @{},

            [int]$Times = 1,

            [String]$InWorkingDirectory,

            [String[]]$WithoutParameter
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

    It 'should run OnlyBy Developer task' {
        GivenRunByBuildServer
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; '.OnlyBy' = 'Developer' }
        ThenPipelineSucceeded
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should not run OnlyBy Developer task' {
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; '.OnlyBy' = 'Developer' }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter '.OnlyBy'
    }

    It 'should replace variables with values' {
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = '$(MachineName)'; }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = [Environment]::MachineName; }
        ThenNoOutput
    }

    It 'should run OnlyBy BuildServer task ' {
        GivenRunByBuildServer
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; '.OnlyBy' = 'BuildServer' }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter '.OnlyBy'
    }

    It 'should not run OnlyBy BuildServer task' {
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.OnlyBy' = 'BuildServer' }
        ThenPipelineSucceeded
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should validate <_> value' -ForEach @('.OnlyBy', '.ExceptBy') {
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = 'Somebody' } -ErrorAction SilentlyContinue
        ThenThrewException 'invalid value'
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should not run ExceptBy BuildServer task' {
        GivenRunByBuildServer
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.ExceptBy' = 'BuildServer' }
        ThenPipelineSucceeded
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should run ExceptBy BuildServer  task' {
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; '.ExceptBy' = 'BuildServer' }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' }
    }

    It 'should not allow both OnlyBy an ExceptBy properties' {
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' `
                              -Parameter @{ '.OnlyBy' = 'Developer'; '.ExceptBy' = 'Developer' } `
                              -ErrorAction SilentlyContinue
        ThenThrewException ([regex]::Escape('".ExceptBy" and ".OnlyBy"'))
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should run OnlyOnBranch task' {
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' `
                              -Parameter @{ 'Path' = 'somefile.ps1'; '.OnlyOnBranch' = 'develop' } `
                              -ErrorAction SilentlyContinue
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter '.OnlyOnBranch'
    }

    It 'should run OnlyOnBranch * task' {
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' `
                              -Parameter @{ 'Path' = 'somefile.ps1'; '.OnlyOnBranch' = @( 'master', 'dev*' ) } `
                              -ErrorAction SilentlyContinue
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter '.OnlyOnBranch'
    }

    It 'should not run OnlyOnBranch task' {
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.OnlyOnBranch' = 'notDevelop' } -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should not run ExceptOnBranch task' {
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' `
                              -Parameter @{ 'Path' = 'somefile.ps1'; '.ExceptOnBranch' = 'develop' } `
                              -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should not run ExceptOnBranch * task' {
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' `
                              -Parameter @{ '.ExceptOnBranch' = @( 'master', 'dev*' ) } `
                              -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should run ExceptOnBranch task' {
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; '.ExceptOnBranch' = 'notDevelop' }
        ThenTaskRan 'NoOpTask' `
                    -WithParameter @{ 'Path' = 'somefile.ps1' } `
                    -WithoutParameter 'ExceptOnBranch','.ExceptOnBranch'
    }

    It 'prohibits OnlyOnBranch and ExceptOnBranch properties' {
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' `
                              -Parameter @{ '.OnlyOnBranch' = 'develop'; '.ExceptOnBranch' = 'develop' } `
                              -ErrorAction SilentlyContinue
        ThenThrewException ([regex]::Escape('".ExceptOnBranch" and ".OnlyOnBranch"'))
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should run task in a working directory' {
        GivenRunByDeveloper
        GivenWorkingDirectory '.output'
        WhenRunningMockedTask -Named 'NoOpTask' `
                              -Parameter @{ 'Path' = 'somefile.ps1'; '.WorkingDirectory' = '.output' } `
                              -ThatMarksWorkingDirectory
        ThenTaskRan -Named 'NoOpTask' `
                    -WithParameter @{ 'Path' = 'somefile.ps1' } `
                    -WithoutParameter '.WorkingDirectory' `
                    -InWorkingDirectory '.output'
    }

    It 'should always install tool in the build directory' {
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
                    throw 'tool installation didn''t happen in the build directory'
                }
            }
        $parameter = @{ '.WorkingDirectory' = '.output' }
        WhenRunningTask 'RequiresNodeTask' -Parameter $parameter
        ThenToolInstalled 'Node'
        ThenPipelineSucceeded
    }

    It 'should clean in custom working directory' {
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
        WhenRunningTask 'RequiresNodeTask' -Parameter @{ '.WorkingDirectory' = '.output' } -InRunMode 'Clean'
        ThenPipelineSucceeded
        ThenToolUninstalled 'Node'
    }

    It 'should validate working directory exists' {
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' `
                              -Parameter @{ '.WorkingDirectory' = 'Invalid/Directory' } `
                              -ErrorAction SilentlyContinue
        ThenThrewException '\bInvalid(\\|/)Directory\b.+does not exist'
        ThenTaskNotRun 'NoOpTask'
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

    It 'should not run <_> task' -ForEach @('Clean', 'Initialize', 'Build') {
        $TaskParameter = @{ '.ExceptDuring' = $_ }
        WhenRunningMockedTask 'SupportsCleanAndInitializeTask' -Parameter $TaskParameter
        WhenRunningTask 'SupportsCleanAndInitializeTask' -Parameter $TaskParameter -InRunMode 'Clean'
        WhenRunningTask 'SupportsCleanAndInitializeTask' -Parameter $TaskParameter -InRunMode 'Initialize'
        ThenTaskRan 'SupportsCleanAndInitializeTask' -Times 2 -WithoutParameter 'ExceptDuring', '.ExceptDuring'
    }

    AfterEach { Remove-Item -Path 'env:fubar' }
    It 'should run IfExists env: task' {
        GivenEnvironmentVariable 'fubar'
        $TaskParameter = @{ '.IfExists' = 'env:fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskRan 'NoOpTask'
    }

    It 'should not run IfExists env: task' {
        $TaskParameter = @{ '.IfExists' = 'env:snafu' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should run IfExists file task' {
        GivenFile 'fubar'
        $TaskParameter = @{ '.IfExists' = 'fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskRan 'NoOpTask'
    }

    It 'should not run IfExists file task' {
        $TaskParameter = @{ '.IfExists' = 'fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskNotRun 'NoOpTask'
    }

    AfterEach { Remove-Item -Path 'env:fubar' }
    It 'should not run UnlessExists env: task' {
        GivenEnvironmentVariable 'fubar'
        $TaskParameter = @{ '.UnlessExists' = 'env:fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should run UnlessExists env: task' {
        $TaskParameter = @{ '.UnlessExists' = 'env:snafu' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskRan 'NoOpTask'
    }

    It 'should not run UnlessExists file task' {
        GivenFile 'fubar'
        $TaskParameter = @{ '.UnlessExists' = 'fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should run UnlessExists file task' {
        $TaskParameter = @{ '.UnlessExists' = 'fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskRan 'NoOpTask'
    }

    It 'prohibits both OnlyDuring and ExceptDuring properties' {
        WhenRunningMockedTask 'SupportsCleanAndInitializeTask' `
                              -Parameter @{ '.OnlyDuring' = 'Clean'; '.ExceptDuring' = 'Clean' } `
                              -ErrorAction SilentlyContinue
        ThenThrewException ([regex]::Escape('".ExceptDuring" and ".OnlyDuring"'))
        ThenTaskNotRun 'SupportsCleanAndInitializeTask'
    }

    It 'should validate OnlyDuring' {
        WhenRunningMockedTask 'SupportsCleanAndInitializeTask' `
                              -Parameter @{ '.OnlyDuring' = 'InvalidValue' } `
                              -ErrorAction SilentlyContinue
        ThenThrewException 'OnlyDuring.*invalid value'
        ThenTaskNotRun 'SupportsCleanAndInitializeTask'
    }

    It 'should validate ExceptDuring' {
        WhenRunningMockedTask 'SupportsCleanAndInitializeTask' `
                              -Parameter @{ '.ExceptDuring' = 'InvalidValue' } `
                              -ErrorAction SilentlyContinue
        ThenThrewException 'ExceptDuring.*invalid value'
        ThenTaskNotRun 'SupportsCleanAndInitializeTask'
    }

    It 'should allow variable for <_> value' -ForEach @('.OnlyBy', '.ExceptBy', '.OnlyDuring', '.ExceptDuring') {
        GivenVariable 'Fubar' 'Snafu'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ $_ = '$(Fubar)' } -ErrorAction SilentlyContinue
        ThenThrewException 'invalid\ value\ "Snafu"'
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should allow variable for OnlyOnBranch property' {
        GivenVariable 'Fubar' 'Snafu'
        GivenScmBranch 'Snafu'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.OnlyOnBranch' = '$(Fubar)' }
        ThenTaskRan 'NoOpTask'
    }

    It 'should allow variable for ExceptOnBranch property' {
        GivenVariable 'Fubar' 'Snafu'
        GivenScmBranch 'Snafu'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.ExceptOnBranch' = '$(Fubar)' }
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should allow variable for WorkingDirectory property' {
        GivenWorkingDirectory 'Snafu'
        GivenVariable 'Fubar' 'Snafu'
        WhenRunningMockedTask -Named 'NoOpTask' `
                              -Parameter @{ '.WorkingDirectory' = '$(Fubar)' } `
                              -ThatMarksWorkingDirectory
        ThenTaskRan 'NoOpTask' -InWorkingDirectory 'Snafu'
    }

    It 'should use defaults value for <_> property' -ForEach @('.OnlyBy', '.ExceptBy', '.OnlyDuring', '.ExceptDuring') {
        GivenDefaults @{ $_ = 'Snafu' } -ForTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' -ErrorAction SilentlyContinue
        ThenThrewException 'invalid\ value\ "Snafu"'
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should use defaults value for OnlyOnBranch property' {
        GivenDefaults @{ '.OnlyOnBranch' = 'Snafu' } -ForTask 'NoOpTask'
        GivenScmBranch 'Snafu'
        WhenRunningMockedTask 'NoOpTask'
        ThenTaskRan 'NoOpTask'
    }

    It 'should use defaults value for ExceptOnBranch property' {
        GivenDefaults @{ '.ExceptOnBranch' = 'Snafu' } -ForTask 'NoOpTask'
        GivenScmBranch 'Snafu'
        WhenRunningMockedTask 'NoOpTask'
        ThenTaskNotRun 'NoOpTask'
    }

    It 'should use defaults value for WorkingDirectory property' {
        GivenWorkingDirectory 'Snafu'
        GivenDefaults @{ '.WorkingDirectory' = 'Snafu' } -ForTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' -ThatMarksWorkingDirectory
        ThenTaskRan 'NoOpTask' -InWorkingDirectory 'Snafu'
    }

    It 'should use defaults variable for WorkingDirectory property' {
        GivenVariable 'Fubar' 'Snafu'
        GivenWorkingDirectory 'Snafu'
        GivenDefaults @{ '.WorkingDirectory' = '$(Fubar)' } -ForTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' -ThatMarksWorkingDirectory
        ThenTaskRan 'NoOpTask' -InWorkingDirectory 'Snafu'
    }

    It 'should install task tool tool' {
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

    AfterEach { Remove-Node -BuildRoot $script:testRoot }
    It 'should remove tool when cleaning' {
        Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        WhenRunningTask 'RequiresNodeTask' -InRunMode 'Clean'
        ThenToolUninstalled 'Node'
        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $InCleanMode -eq $true }
    }

    AfterEach { Remove-Node -BuildRoot $script:testRoot }
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

    It 'should run or not run OnlyOnPlatform Windows task' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.OnlyOnPlatform' = 'Windows' }
        if( $IsWindows )
        {
            ThenTaskRan 'NoOpTask'
        }
        else
        {
            ThenTaskNotRun 'NoOpTask'
        }
    }

    It 'should run or not run OnlyOnPlatform Linux task' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.OnlyOnPlatform' = 'Linux' }
        if( $IsLinux )
        {
            ThenTaskRan 'NoOpTask'
        }
        else
        {
            ThenTaskNotRun 'NoOpTask'
        }
    }

    It 'should run or not run OnlyOnPlatform macOS task' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.OnlyOnPlatform' = 'MacOS' }
        if( $IsMacOS )
        {
            ThenTaskRan 'NoOpTask'
        }
        else
        {
            ThenTaskNotRun 'NoOpTask'
        }
    }

    It 'should run or not run OnlyOnPlatform Windows or macOS task' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.OnlyOnPlatform' = @( 'Windows','MacOS' ) }
        if( $IsLinux )
        {
            ThenTaskNotRun 'NoOpTask'
        }
        else
        {
            ThenTaskRan 'NoOpTask'
        }
    }

    It 'should validate OnlyOnPlatform' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.OnlyOnPlatform' = 'Blarg' } -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
        ThenThrewException ([regex]::Escape('Invalid platform "Blarg"'))
    }

    It 'should run or not run ExceptOnPlatform Windows task' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.ExceptOnPlatform' = 'Windows' }
        if( $IsWindows )
        {
            ThenTaskNotRun 'NoOpTask'
        }
        else
        {
            ThenTaskRan 'NoOpTask'
        }
    }

    It 'should run or not run ExceptOnPlatform Linux task' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.ExceptOnPlatform' = 'Linux' }
        if( $IsLinux )
        {
            ThenTaskNotRun 'NoOpTask'
        }
        else
        {
            ThenTaskRan 'NoOpTask'
        }
    }

    It 'should run or not run ExceptOnPlatform macOS task' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.ExceptOnPlatform' = 'MacOS' }
        if( $IsMacOS )

        {
            ThenTaskNotRun 'NoOpTask'
        }
        else
        {
            ThenTaskRan 'NoOpTask'
        }
    }

    It 'should run or not run ExceptOnPlatform Windows and macOS task' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.ExceptOnPlatform' = @( 'Windows','MacOS' ) }
        if( $IsLinux )
        {
            ThenTaskRan 'NoOpTask'
        }
        else
        {
            ThenTaskNotRun 'NoOpTask'
        }
    }

    It 'should validate ExceptOnPlatform' {
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ '.ExceptOnPlatform' = 'Blarg' } -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
        ThenThrewException ([regex]::Escape('Invalid platform "Blarg"'))
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

    It 'should set tasks''s ErrorActionPreference' {
        $ErrorActionPreference = 'Ignore'
        WhenRunningTask 'Log' `
                        -Parameter @{ Message = 'FAIL!'; Level = 'Error' ; '.ErrorAction' = 'Stop' } `
                        -ErrorVariable 'errors'
        ThenPipelineFailed
        ThenThrewException 'FAIL!'
    }

    It 'should set tasks''s WarningPreference' {
        $WarningPreference = 'Ignore'
        WhenRunningTask 'Log' `
                        -Parameter @{ Message = 'WARNING!'; Level = 'Warning' ; '.WarningAction' = 'Continue' } `
                        -WarningVariable 'warnings'
        ThenPipelineSucceeded
        $warnings | Should -Match 'WARNING!'
    }

    It 'should set tasks''s InformationPreference' {
        $InformationPreference = 'Ignore'
        WhenRunningTask 'Log' `
                        -Parameter @{ Message = 'INFORMATION!'; '.InformationAction' = 'Continue' } `
                        -InformationVariable 'infos'
        ThenPipelineSucceeded
        $infos | Should -Match 'INFORMATION!'
    }

    It 'should set tasks''s VerbosePreference' {
        $VerbosePreference = 'Ignore'
        WhenRunningTask 'Log' -Parameter @{ Message = 'VERBOSE!'; 'Level' = 'Verbose'; '.Verbose' = 'true' }
        ThenPipelineSucceeded
        $script:output | Should -Match 'VERBOSE!'
    }

    It 'should set tasks''s DebugPreference' {
        $DebugPreference = 'Ignore'
        WhenRunningTask 'Log' -Parameter @{ Message = 'DEBUG!'; 'Level' = 'Debug'; '.Debug' = 'true' }
        ThenPipelineSucceeded
        $script:output | Should -Match 'DEBUG!'
    }

    Context 'task does not have CmdletBinding attribute' {
        It 'captures task output in Whiskey variable and sends to STDOUT' {
            WhenRunningTask 'GenerateOutputTask' -Parameter @{ 'Output' = 'task output text'; '.OutVariable' = 'TASK_OUTPUT' }
            ThenPipelineSucceeded
            $script:output | Should -Be 'task output text'
            $script:context.Variables.ContainsKey('TASK_OUTPUT') | Should -BeTrue
            $script:context.Variables['TASK_OUTPUT'] | Should -Be 'task output text'
        }
    }

    Context 'task has CmdletBinding attribute' {
        It 'captures task output in Whiskey variable and sends to STDOUT' {
            WhenRunningTask 'GenerateOutputTaskWithCmdletBinding' `
                            -Parameter @{ Output = 'task output text'; '.OutVariable' = 'TASK_OUTPUT' }
            ThenPipelineSucceeded
            $script:output | Should -Be 'task output text'
            $script:context.Variables.ContainsKey('TASK_OUTPUT') | Should -BeTrue
            $script:context.Variables['TASK_OUTPUT'] | Should -Be 'task output text'
        }
    }

    It 'unrolls single object collections set to OutVariable' {
        # Single objects returned by PowerShell come back as a single element ArrayList.
        $ps = '[pscustomobject]@{ fubar = ''snafu'' }'
        WhenRunningTask 'PowerShell' -Parameter @{ 'ScriptBlock' = $ps ; '.OutVariable' = 'OUTPUT' }
        ThenPipelineSucceeded
        $script:context.Variables['OUTPUT'].GetType() | Should -Be ([pscustomobject]@{}).GetType()
        $script:context.Variables['OUTPUT'] | Should -HaveCount 1
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

    It 'resolves variables after evaluating condition' {
        WhenRunningTask 'Log' -Parameter @{ Message = '$(I_DO_NOT_EXIST)' ; '.IfExists' = 'env:FUBAR_SNAFU' }
        ThenPipelineSucceeded
    }
}

