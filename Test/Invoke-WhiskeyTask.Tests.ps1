#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$whiskeyYmlPath = $null
$runByDeveloper = $false
$runByBuildServer = $false
$context = $null
$warnings = $null
$preTaskPluginCalled = $false
$postTaskPluginCalled = $false
$output = $null
$taskDefaults = @{ }

function Invoke-PreTaskPlugin
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [string]
        $TaskName,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

}

function Invoke-PostTaskPlugin
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [string]
        $TaskName,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )
}

function GivenFailingMSBuildProject
{
    param(
        $Project
    )

    New-MSBuildProject -FileName $project -ThatFails
}

function GivenMSBuildProject
{
    param(
        $Project
    )

    New-MSBuildProject -FileName $project -ThatFails
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
        [string]
        $ForSpecificTask
    )

    $taskNameParam = @{ }
    if( $ForSpecificTask )
    {
        $taskNameParam['TaskName'] = $ForSpecificTask
    }

    Register-WhiskeyEvent -CommandName 'Invoke-PostTaskPlugin' -Event AfterTask @taskNameParam
    Mock -CommandName 'Invoke-PostTaskPlugin' -ModuleName 'Whiskey'
    Register-WhiskeyEvent -CommandName 'Invoke-PreTaskPlugin' -Event BeforeTask @taskNameParam
    Mock -CommandName 'Invoke-PreTaskPlugin' -ModuleName 'Whiskey'
}

function GivenDefaults
{
    param(
        [hashtable]
        $Default,

        [string]
        $ForTask
    )

    $script:taskDefaults[$ForTask] = $Default
}

function GivenWhiskeyYmlBuildFile
{
    param(
        [Parameter(Position=0)]
        [string]
        $Yaml
    )

    $config = $null
    $root = (Get-Item -Path 'TestDrive:').FullName
    $script:whiskeyYmlPath = Join-Path -Path $root -ChildPath 'whiskey.yml'
    $Yaml | Set-Content -Path $whiskeyYmlPath
    return $whiskeyymlpath
}

function Init
{
    $script:taskDefaults = @{ }
    $script:output = $null
}

function ThenPipelineFailed
{
    It 'should throw exception' {
        $threwException | Should -Be $true
    }
}

function ThenBuildOutputRemoved
{
    It ('should remove .output directory') {
        Join-Path -Path ($whiskeyYmlPath | Split-Path) -ChildPath '.output' | Should -Not -Exist
    }
}

function ThenPipelineSucceeded
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'should not throw an exception' {
        $threwException | Should -Be $false
    }
}

function ThenDotNetProjectsCompilationFailed
{
    param(
        [string]
        $ConfigurationPath,

        [string[]]
        $ProjectName
    )

    $root = Split-Path -Path $ConfigurationPath -Parent
    foreach( $name in $ProjectName )
    {
        It ('should not run {0} project''s ''clean'' target' -f $name) {
            (Join-Path -Path $root -ChildPath ('{0}.clean' -f $ProjectName)) | Should Not Exist
        }

        It ('should not run {0} project''s ''build'' target' -f $name) {
            (Join-Path -Path $root -ChildPath ('{0}.build' -f $ProjectName)) | Should Not Exist
        }
    }
}

function ThenNUnitTestsNotRun
{
    param(
    )

    It 'should not run NUnit tests' {
        $context.OutputDirectory | Get-ChildItem -Filter 'nunit2*.xml' | Should BeNullOrEmpty
    }
}

function ThenPluginsRan
{
    param(
        $ForTaskNamed,

        $WithParameter,

        [int]
        $Times = 1
    )

    foreach( $pluginName in @( 'Invoke-PreTaskPlugin', 'Invoke-PostTaskPlugin' ) )
    {
        if( $Times -eq 0 )
        {
            It ('should not run plugin for ''{0}'' task' -f $ForTaskNamed) {
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times 0 -ParameterFilter { $TaskName -eq $ForTaskNamed }
            }
        }
        else
        {
            It ('should run {0}' -f $pluginName) {
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times $Times -ParameterFilter { $TaskContext -ne $null }
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times $Times -ParameterFilter { $TaskName -eq $ForTaskNamed }
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times $Times -ParameterFilter { 
                    if( $TaskParameter.Count -ne $WithParameter.Count )
                    {
                        return $false
                    }

                    foreach( $key in $WithParameter.Keys )
                    {
                        if( $TaskParameter[$key] -ne $WithParameter[$key] )
                        {
                            return $false
                        }
                    }

                    return $true
                }
            }
        }

        Unregister-WhiskeyEvent -CommandName $pluginName -Event AfterTask
        Unregister-WhiskeyEvent -CommandName $pluginName -Event AfterTask -TaskName $ForTaskNamed
        Unregister-WhiskeyEvent -CommandName $pluginName -Event BeforeTask
        Unregister-WhiskeyEvent -CommandName $pluginName -Event BeforeTask -TaskName $ForTaskNamed
    }
}

function ThenShouldWarn
{
    param(
        $Pattern
    )

    It ('should warn matching pattern /{0}/' -f $Pattern) {
        $warnings | Should -Match $Pattern
    }
}

function ThenTaskNotRun
{
    param(
        $CommandName
    )

    It ('should not run task ''{0}''' -f $CommandName) {
        Assert-MockCalled -CommandName $CommandName -ModuleName 'Whiskey' -Times 0
    }
}

function ThenTaskRanWithParameter
{
    param(
        $CommandName,
        [hashtable]
        $ExpectedParameter
    )

    It ('should call {0} with parameters' -f $CommandName) {
        $Global:actualParameter = $null
        Assert-MockCalled -CommandName $CommandName -ModuleName 'Whiskey' -ParameterFilter {
            $global:actualParameter = $TaskParameter
            return $true
        }

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
        Assert-Hashtable -Expected $ExpectedParameter -Actual $actualParameter
        Remove-Variable -Name 'actualParameter' -Scope 'Global'
    }
}

function ThenThrewException
{
    param(
        $Pattern
    )

    It ('should throw a terminating exception that matches /{0}/' -f $Pattern) {
        $threwException | Should -Be $true
        $Global:Error | Should -Match $Pattern
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [string]
        $Name,

        [hashtable]
        $Parameter,

        [string]
        $InRunMode
    )

    Mock -CommandName 'Invoke-PreTaskPlugin' -ModuleName 'Whiskey'
    Mock -CommandName 'invoke-PostTaskPlugin' -ModuleName 'Whiskey'

    $byItDepends = @{ 'ForDeveloper' = $true }
    if( $runByBuildServer )
    {
        $byItDepends = @{ 'ForBuildServer' = $true }
    }

    $script:context = New-WhiskeyTestContext @byItDepends
    $context.PipelineName = 'Build';
    $context.TaskName = $null;
    $context.TaskIndex = 1;
    $context.TaskDefaults = $taskDefaults;
    if( $InRunMode )
    {
        $context.RunMode = $InRunMode;
    }

    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Name $Name -Parameter $Parameter -WarningVariable 'warnings'
        $script:warnings = $warnings
    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }    
}

Describe 'Invoke-WhiskeyTask.when running an unknown task' {
    Init
    WhenRunningTask 'Fubar' -Parameter @{ } -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenThrewException 'not\ exist'
}

Describe 'Invoke-WhiskeyTask.when a task fails' {
    Init
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'idonotexist.ps1' } -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenThrewException 'not\ exist'
}

Describe 'Invoke-WhiskeyTask.when there are registered event handlers' {
    Init
    GivenPlugins
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ Path = 'somefile.ps1' }
    ThenPipelineSucceeded
    ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' }
}

Describe 'Invoke-WhiskeyTask.when there are task-specific registered event handlers' {
    Init
    GivenPlugins -ForSpecificTask 'PowerShell'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    Mock -CommandName 'Invoke-WhiskeyMSBuild' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ Path = 'somefile.ps1' }
    ThenPipelineSucceeded
    ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' }
}

Describe 'Invoke-WhiskeyTask.when there are task defaults' {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    $defaults = @{ 'Fubar' = @{ 'Snfau' = 'value1' ; 'Key2' = 'value1' }; 'Key3' = 'Value3' }
    GivenDefaults $defaults -ForTask 'PowerShell'
    WhenRunningTask 'PowerShell' -Parameter @{ }
    ThenPipelineSucceeded
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' $defaults
}

Describe 'Invoke-WhiskeyTask.when there are task defaults' {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    $defaults = @{ 'Fubar' = @{ 'Snfau' = 'value1' ; 'Key2' = 'value1' }; 'Key3' = 'Value3' }
    GivenDefaults $defaults -ForTask 'PowerShell'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Fubar' = @{ 'Snfau' = 'myvalue' } ; 'NotADefault' = 'NotADefault' }
    ThenPipelineSucceeded
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Fubar' = @{ 'Snfau' = 'myvalue'; 'Key2' = 'value1' }; 'Key3' = 'Value3'; 'NotADefault' = 'NotADefault' }
}

Describe 'Invoke-WhiskeyTask.when task should only be run by developer and being run by build server' {
    Init
    GivenRunByBuildServer
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Developer' }
    ThenPipelineSucceeded
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe 'Invoke-WhiskeyTask.when task should only be run by developer and being run by developer' {
    Init
    GivenRunByDeveloper
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Developer' }
    ThenPipelineSucceeded
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Developer' }
}

function ThenNoOutput
{
    It 'should not return anything' {
        $output | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-WhiskeyTask.when task has property variables' {
    Init
    GivenRunByDeveloper
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = '$(COMPUTERNAME)'; }
    ThenPipelineSucceeded
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = $env:COMPUTERNAME; }
    ThenNoOutput
}

Describe 'Invoke-WhiskeyTask.when task should only be run by build server and being run by build server' {
    Init
    GivenRunByBuildServer
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'BuildServer' }
    ThenPipelineSucceeded
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'somefile.ps1' ; 'OnlyBy' = 'BuildServer' }
}

Describe 'Invoke-WhiskeyTask.when task should only be run by build server and being run by developer' {
    Init
    GivenRunByDeveloper
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'BuildServer' }
    ThenPipelineSucceeded
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe 'Invoke-WhiskeyTask.when OnlyBy has an invalid value' {
    Init
    GivenRunByDeveloper
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Somebody' } -ErrorAction SilentlyContinue
    ThenThrewException 'invalid value'
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

$tasks = Get-WhiskeyTask
foreach( $task in ($tasks) )
{
    $taskName = $task.Name
    $functionName = $task.CommandName

    Describe ('Invoke-WhiskeyTask.when calling {0} task' -f $taskName) {

        function Assert-TaskCalled
        {
            param(
            )

            $context = $script:context

            It 'should pass context to task' {
                Assert-MockCalled -CommandName $functionName -ModuleName 'Whiskey' -ParameterFilter {
                    [object]::ReferenceEquals($TaskContext, $Context) 
                }
            }
            
            It 'should pass task parameters' {
                Assert-MockCalled -CommandName $functionName -ModuleName 'Whiskey' -ParameterFilter {
                    #$DebugPreference = 'Continue'
                    $TaskParameter | Out-String | Write-Debug
                    Write-Debug ('Path  EXPECTED  {0}' -f $TaskParameter['Path'])
                    Write-Debug ('      ACTUAL    {0}' -f $taskName)
                    return $TaskParameter.ContainsKey('Path') -and $TaskParameter['Path'] -eq $taskName
                }
            }
        }

        Mock -CommandName $functionName -ModuleName 'Whiskey'

        $pipelineName = 'BuildTasks'
        $whiskeyYml = (@'
{0}:
- {1}:
    Path: {1}
'@ -f $pipelineName,$taskName)

        Init
        WhenRunningTask $taskName -Parameter @{ Path = $taskName }
        ThenPipelineSucceeded
        Assert-TaskCalled
    }
}

Describe 'Invoke-WhiskeyTask.when run in clean mode' {
    try
    {
        $global:cleanTaskRan = $false
        function global:TaskThatSupportsClean
        {
            [Whiskey.TaskAttribute("MyCleanTask",SupportsClean=$true)]
            param(
            )

            $global:cleanTaskRan = $true
        }

        $global:taskRan = $false
        function global:SomeTask
        {
            [Whiskey.TaskAttribute("MyTask")]
            param(
            )

            $global:taskRan = $true
        }

        Init
        WhenRunningTask 'MyTask' @{ } -InRunMode 'Clean'
        It 'should not run task that does not support clean' {
            $global:taskRan | Should -Be $false
        }
        WhenRunningTask 'MyCleanTask' @{ } -InRunMode 'Clean'
        It ('should run task that supports clean') {
            $global:cleanTaskRan | Should Be $true
        }
    }
    finally
    {
        Remove-Item 'function:TaskThatSupportsClean'
        Remove-Item 'function:SomeTask'
        Remove-Item 'variable:cleanTaskRan'
        Remove-Item 'variable:taskRan'
    }
}


Describe 'Invoke-WhiskeyTask.when run in initialize mode' {
    try
    {
        $global:initializeTaskRan = $false
        function global:TaskThatSupportsInitialize
        {
            [Whiskey.TaskAttribute("MyInitializeTask",SupportsInitialize=$true)]
            param(
            )

             $global:initializeTaskRan = $true
        }

        $global:taskRan = $false
        function global:SomeTask
        {
            [Whiskey.TaskAttribute("MyTask")]
            param(
            )

            $global:taskRan = $true
        }

        $global:taskRan = $false
        WhenRunningTask 'MyTask' @{ } -InRunMode 'Initialize'
        It 'should not run task that does not support initializes' {
            $global:taskRan | Should -Be $false
        }
        WhenRunningTask 'MyInitializeTask' @{ } -InRunMode 'Initialize'
        It ('should run task that supports initialize') {
            $global:initializeTaskRan | Should Be $true
        }
    }
    finally
    {
        Remove-Item 'function:TaskThatSupportsInitialize'
        Remove-Item 'function:SomeTask'
        Remove-Item 'variable:initializeTaskRan'
        Remove-Item 'variable:taskRan'
    }
}
