#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$configurationPath = $null
$parameter = @{ }
$whiskeyYmlPath = $null
$runByDeveloper = $false
$runByBuildServer = $false
$context = $null
$warnings = $null
$preTaskPluginCalled = $false
$postTaskPluginCalled = $false
$output = $null
$taskDefaults = @{ }
$scmBranch = $null
$taskProperties = @{ }
$taskRun = $false
$variables = @{ }

function Global::ToolTask
{
    [Whiskey.Task("ToolTask",SupportsClean=$true)]
    [Whiskey.RequiresTool("Node", "NodePath")]
    [CmdletBinding()]
    param(
        $TaskContext,
        $TaskParameter
    )

    $script:taskProperties = $TaskParameter
    $script:taskRun = $true
}

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

function GivenContext
{
    $byItDepends = @{ 'ForDeveloper' = $true }
    if( $runByBuildServer )
    {
        $byItDepends = @{ 'ForBuildServer' = $true }
    }

    $configurationPathParam = @{ }
    if ($configurationPath)
    {
        $configurationPathParam['ConfigurationPath'] = $configurationPath
    }

    $script:context = New-WhiskeyTestContext @byItDepends @configurationPathParam
}

function GivenFailingMSBuildProject
{
    param(
        $Project
    )

    New-MSBuildProject -FileName $project -ThatFails
}

function GivenMockTask
{
    param(
        [switch]
        $SupportsClean,
        [switch]
        $SupportsInitialize
    )

    if ($SupportsClean -and $SupportsInitialize)
    {
        function Global:MockTask {
            [Whiskey.TaskAttribute("MockTask", SupportsClean=$true, SupportsInitialize=$true)]
            param($TaskContext, $TaskParameter)
        }
    }
    elseif ($SupportsClean)
    {
        function Global:MockTask {
            [Whiskey.TaskAttribute("MockTask", SupportsClean=$true)]
            param($TaskContext, $TaskParameter)
        }
    }
    elseif ($SupportsInitialize)
    {
        function Global:MockTask {
            [Whiskey.TaskAttribute("MockTask", SupportsInitialize=$true)]
            param($TaskContext, $TaskParameter)
        }
    }
    else
    {
        function Global:MockTask {
            [Whiskey.TaskAttribute("MockTask")]
            param($TaskContext, $TaskParameter)
        }
    }

    Mock -CommandName 'MockTask' -ModuleName 'Whiskey'
}

function RemoveMockTask
{
    Remove-Item -Path 'function:MockTask'
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

function GivenParameter
{
    param(
        [hashtable]
        $Parameter
    )

    $script:parameter = $Parameter
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

function GivenScmBranch
{
    param(
        [string]
        $Branch
    )
    $script:scmBranch = $Branch
}

function GivenVariable
{
    param(
        $Name,
        $Value
    )

    $variables[$Name] = $Value
}

function GivenWhiskeyYml
{
    param(
        $Content
    )

    $script:configurationPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml'
    $Content | Set-Content -Path $script:configurationPath
}

function GivenWorkingDirectory
{
    param(
        [string]
        $Directory,

        [Switch]
        $SkipMock
    )

    $wd = Join-Path -Path $TestDrive.FullName -ChildPath $Directory
    New-Item -Path $wd -ItemType 'Directory' -Force

    if( $SkipMock )
    {
        return
    }

    Mock -CommandName 'Push-Location' -ModuleName 'Whiskey' -ParameterFilter { $workingDirectory -eq $wd }
    Mock -CommandName 'Pop-Location' -ModuleName 'Whiskey'
}

function Init
{
    $script:configurationPath = $null
    $script:parameter = @{ }
    $script:taskDefaults = @{ }
    $script:output = $null
    $script:scmBranch = $null
    $script:taskProperties = @{ }
    $script:taskRun = $false
    $script:variables = @{ }
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

function ThenNoOutput
{
    It 'should not return anything' {
        $output | Should -BeNullOrEmpty
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
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times $Times -ParameterFilter {
                    #$DebugPreference = 'Continue'
                    Write-Debug -Message ('TaskName  expected  {0}' -f $ForTaskNamed)
                    Write-Debug -Message ('          actual    {0}' -f $TaskName)
                    $TaskName -eq $ForTaskNamed
                }
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
        $Task
    )

    $taskCommandName = (Get-WhiskeyTask | Where-Object {$_.Name -eq $Task} | Select-Object -ExpandProperty 'CommandName')

    It ('should not run task ''{0}''' -f $Task) {
        if ($Task -eq 'ToolTask')
        {
            $taskRun | Should -Be $false
        }
        else
        {
            Assert-MockCalled -CommandName $taskCommandName -ModuleName 'Whiskey' -Times 0
        }
    }
}

function ThenRanTask
{
    param(
        [string]
        $Task,

        [int]
        $Times
    )

    $timesParam = @{}
    if ($Times -ne 0)
    {
        $timesParam = @{ 'Times' = $Times; 'Exactly' = $true }
    }

    $taskCommandName = (Get-WhiskeyTask | Where-Object {$_.Name -eq $Task} | Select-Object -ExpandProperty 'CommandName')
    It ('should run task ''{0}''' -f $Task) {
        Assert-MockCalled -CommandName $taskCommandName -ModuleName 'Whiskey' @timesParam
    }
}

function ThenTaskRanWithParameter
{
    param(
        $Task,
        $Parameter,
        $Value
    )

    $taskCommandName = (Get-WhiskeyTask | Where-Object {$_.Name -eq $Task} | Select-Object -ExpandProperty 'CommandName')

    if ($Value | Get-Member -Name 'Keys')
    {
        foreach ($key in $Value.Keys)
        {
            It ('should set task parameter ''{0}'' to include ''{1} = {2}''' -f $Parameter,$key,$Value[$key]) {
                Assert-MockCalled -CommandName $taskCommandName -ModuleName 'Whiskey' -ParameterFilter {
                    # $DebugPreference = 'Continue'
                    # $TaskParameter | Out-String | Write-Debug
                    $TaskParameter[$Parameter][$key] -eq $Value[$key]
                }
            }
        }
    }
    else
    {
        It ('should set task parameter ''{0}'' to ''{1}''' -f $Parameter,$Value) {
            Assert-MockCalled -CommandName $taskCommandName -ModuleName 'Whiskey' -ParameterFilter {
                # $DebugPreference = 'Continue'
                # $TaskParameter | Out-String | Write-Debug
                $TaskParameter[$Parameter] -eq $Value
            }
        }
    }
}

function ThenTaskRanWithoutParameter
{
    param(
        $Task,
        [string[]]
        $ParameterName
    )

    $taskCommandName = (Get-WhiskeyTask | Where-Object {$_.Name -eq $Task} | Select-Object -ExpandProperty 'CommandName')
    foreach( $name in $ParameterName )
    {
        It ('should not pass property ''{0}''' -f $name) {
            Assert-MockCalled -CommandName $taskCommandName -ModuleName 'Whiskey' -ParameterFilter { -not $TaskParameter.ContainsKey($name) }
        }
    }
}

function ThenTempDirectoryCreated
{
    param(
        $TaskName
    )

    $expectedTempPath = Join-Path -Path $context.OutputDirectory -ChildPath ('Temp.{0}.' -f $TaskName)
    $expectedTempPathRegex = '^{0}[a-z0-9]{{8}}\.[a-z0-9]{{3}}$' -f [regex]::escape($expectedTempPath)
    It ('should create a task-specific temp directory') {
        Assert-MockCalled -CommandName 'New-Item' -ModuleName 'Whiskey' -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug ('Path  expected  {0}' -f $expectedTempPathRegex)
            Write-Debug ('      actual    {0}' -f $Path)
            $Path -match $expectedTempPathRegex }
        Assert-MockCalled -CommandName 'New-Item' -ModuleName 'Whiskey' -ParameterFilter { $Force }
        Assert-MockCalled -CommandName 'New-Item' -ModuleName 'Whiskey' -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug ('ItemType  expected  {0}' -f 'Directory')
            Write-Debug ('          actual    {0}' -f $ItemType)
            $ItemType -eq 'Directory' }
    }
}

function ThenTempDirectoryRemoved
{
    param(
        $TaskName
    )

    $expectedTempPath = Join-Path -Path $context.OutputDirectory -ChildPath ('Temp.{0}.*' -f $TaskName)
    It ('should delete task-specific temp directory') {
        $expectedTempPath | Should -Not -Exist
        $context.Temp | Should -Not -Exist
    }
}

function ThenTaskRanInWorkingDirectory
{
    param(
        $Directory
    )

    $wd = Join-Path -Path $TestDrive.FullName -ChildPath $Directory

    It ('should push the working directory ''{0}'' before executing task' -f $Directory) {
        Assert-MockCalled -CommandName 'Push-Location' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq $wd }
    }

    It ('should pop the working directory ''{0}'' after executing task' -f $Directory) {
        Assert-MockCalled -CommandName 'Pop-Location' -ModuleName 'Whiskey'
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

function ThenToolInstalled
{
    param(
        $ToolName,
        $Parameter
    )

    $taskContext = $context
    It 'should install Node' {
        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $Toolinfo.Name -eq $ToolName }
        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter {
            #$DebugPreference = 'Continue'
            $expectedInstallRoot = (Resolve-Path -Path 'TestDrive:').ProviderPath.TrimEnd('\')
            Write-Debug -Message ('InstallRoot  expected  {0}' -f $expectedInstallRoot)
            Write-Debug -Message ('             actual    {0}' -f $InstallRoot)
            $InstallRoot -eq $expectedInstallRoot
        }

    }
}

function ThenToolNotCleaned
{
    It ('should not clean the tool') {
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -Times 0
    }
}

function ThenToolPathPassedToTask
{
    param(
        $ParameterName,
        $Path
    )

    It ('should pass path to tool to task as property') {
        $taskProperties.ContainsKey($ParameterName) | Should -Be $true
        $taskProperties[$ParameterName] | Should -Be $Path
    }
}

function ThenToolUninstalled
{
    param(
        $ToolName
    )

    $taskContext = $context
    It 'should uninstall Node' {
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $ToolName }
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { [Object]::ReferenceEquals($Context,$taskContext) }
    }
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [string]
        $Name,

        [string]
        $InRunMode
    )

    Mock -CommandName 'Invoke-PreTaskPlugin' -ModuleName 'Whiskey'
    Mock -CommandName 'invoke-PostTaskPlugin' -ModuleName 'Whiskey'

    $script:context.PipelineName = 'Build'
    $script:context.TaskName = $null
    $script:context.TaskIndex = 1
    
    if ($taskDefaults.Keys -gt 0)
    {
        $script:context.TaskDefaults = $taskDefaults
    }

    if( $InRunMode )
    {
        $script:context.RunMode = $InRunMode
    }

    if( $scmBranch )
    {
        $script:context.BuildMetadata.ScmBranch = $scmBranch
    }

    Mock -CommandName 'New-Item' -ModuleName 'Whiskey' -MockWith { [IO.Directory]::CreateDirectory($Path) }

    foreach( $variableName in $variables.Keys )
    {
        Add-WhiskeyVariable -Context $context -Name $variableName -Value $variables[$variableName]
    }

    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Name $Name -Parameter $parameter -WarningVariable 'warnings'
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
    GivenContext
    WhenRunningTask 'Fubar' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenThrewException 'not\ exist'
}

Describe 'Invoke-WhiskeyTask.when a task fails' {
    Init
    GivenContext
    GivenParameter @{ 'Path' = 'idonotexist.ps1' }
    WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenThrewException 'not\ exist'
    ThenTempDirectoryCreated 'PowerShell'
    ThenTempDirectoryRemoved 'PowerShell'
}

Describe 'Invoke-WhiskeyTask.when there are registered event handlers' {
    Init
    GivenPlugins
    GivenContext
    GivenParameter @{ Path = 'somefile.ps1' }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenPipelineSucceeded
    ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' }
    ThenTempDirectoryCreated 'PowerShell.OnBeforeTask'
    ThenTempDirectoryCreated 'PowerShell'
    ThenTempDirectoryCreated 'PowerShell.OnAfterTask'
    ThenTempDirectoryRemoved 'PowerShell.OnBeforeTask'
    ThenTempDirectoryRemoved 'PowerShell'
    ThenTempDirectoryRemoved 'PowerShell.OnAfterTask'
}

Describe 'Invoke-WhiskeyTask.when there are task-specific registered event handlers' {
    Init
    GivenPlugins -ForSpecificTask 'PowerShell'
    GivenContext
    GivenParameter @{ Path = 'somefile.ps1' }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    Mock -CommandName 'Invoke-WhiskeyMSBuild' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenPipelineSucceeded
    ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' }
}

Describe 'Invoke-WhiskeyTask.when there are task defaults' {
    Init
    GivenWhiskeyYml @'
TaskDefaults:
    PowerShell:
        Path: defaultScript.ps1
        Argument:
            Param1: value
'@
    GivenContext
    GivenParameter @{
        'Path' = 'script.ps1';
        'Argument' = @{ 'Force' = $true }
    }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenPipelineSucceeded
    ThenRanTask 'PowerShell'
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Path' -Value 'script.ps1'
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Argument' -Value @{ 'Force' = $true; 'Param1' = 'value'; }
}

Describe 'Invoke-WhiskeyTask.when there are task defaults that should get overriden by given task parameters' {
    Init
    GivenWhiskeyYml @'
TaskDefaults:
    PowerShell:
        SomeParam: foo
'@
    GivenContext
    GivenParameter @{
        'Path' = 'script.ps1';
        'SomeParam' = 'bar';
    }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenPipelineSucceeded
    ThenRanTask 'PowerShell'
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Path' -Value 'script.ps1'
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'SomeParam' -Value 'bar'
}

Describe 'Invoke-WhiskeyTask.when task should only be run by developer and being run by build server' {
    Init
    GivenRunByBuildServer
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Developer' }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenPipelineSucceeded
    ThenTaskNotRun 'PowerShell'
}

Describe 'Invoke-WhiskeyTask.when task should only be run by developer and being run by developer' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Developer' }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenPipelineSucceeded
    ThenRanTask 'PowerShell'
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Path' -Value 'somefile.ps1'
    ThenTaskRanWithoutParameter -Task 'PowerShell' -Parameter 'OnlyBy'
}

Describe 'Invoke-WhiskeyTask.when task has property variables' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = '$(COMPUTERNAME)'; }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenPipelineSucceeded
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Path' -Value $env:COMPUTERNAME
    ThenNoOutput
}

Describe 'Invoke-WhiskeyTask.when task should only be run by build server and being run by build server' {
    Init
    GivenRunByBuildServer
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'BuildServer' }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenPipelineSucceeded
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Path' -Value 'somefile.ps1'
    ThenTaskRanWithoutParameter -Task 'PowerShell' -Parameter 'OnlyBy'
}

Describe 'Invoke-WhiskeyTask.when task should only be run by build server and being run by developer' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'BuildServer' }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenPipelineSucceeded
    ThenTaskNotRun 'PowerShell'
}

Describe 'Invoke-WhiskeyTask.when OnlyBy has an invalid value' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Somebody' }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
    ThenThrewException 'invalid value'
    ThenTaskNotRun 'PowerShell'
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch contains current branch' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = 'develop' }
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Path' -Value 'somefile.ps1'
    ThenTaskRanWithoutParameter -Task 'PowerShell' -Parameter 'OnlyOnBranch'
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch contains wildcard matching current branch' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = @( 'master', 'dev*' ) }
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Path' -Value 'somefile.ps1'
    ThenTaskRanWithoutParameter -Task 'PowerShell' -Parameter 'OnlyOnBranch'
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch does not contain current branch' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = 'notDevelop' }
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
    ThenTaskNotRun 'PowerShell'
}

Describe 'Invoke-WhiskeyTask.when ExceptOnBranch contains current branch' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'ExceptOnBranch' = 'develop' }
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
    ThenTaskNotRun 'PowerShell'
}

Describe 'Invoke-WhiskeyTask.when ExceptOnBranch contains wildcard matching current branch' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'ExceptOnBranch' = @( 'master', 'dev*' ) }
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
    ThenTaskNotRun 'PowerShell'
}

Describe 'Invoke-WhiskeyTask.when ExceptOnBranch does not contain current branch' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'ExceptOnBranch' = 'notDevelop' }
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Path' -Value 'somefile.ps1'
    ThenTaskRanWithoutParameter -Task 'PowerShell' -Parameter 'ExceptOnBranch'
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch and ExceptOnBranch properties are both defined' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = 'develop'; 'ExceptOnBranch' = 'develop' }
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
    ThenThrewException 'This task defines both OnlyOnBranch and ExceptOnBranch properties'
    ThenTaskNotRun 'PowerShell'
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is defined' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'Path' = 'somefile.ps1'; 'WorkingDirectory' = '.output' }
    GivenWorkingDirectory '.output'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell'
    ThenTaskRanInWorkingDirectory '.output'
    ThenTaskRanWithParameter -Task 'PowerShell' -Parameter 'Path' -Value 'somefile.ps1'
    ThenTaskRanWithoutParameter -Task 'PowerShell' -Parameter 'WorkingDirectory'
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is defined and installing a tool' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'WorkingDirectory' = '.output' }
    GivenWorkingDirectory '.output' -SkipMock
    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -MockWith {
            #$DebugPreference = 'Continue'
            $currentPath = (Get-Location).ProviderPath
            $expectedPath = (Resolve-Path -Path 'TestDrive:\.output').ProviderPath
            Write-Debug ('Current  Path   {0}' -f $currentPath)
            Write-Debug ('Expected Path   {0}' -f $expectedPath)
            if( $currentPath -ne $expectedPath )
            {
                throw 'tool installation didn''t happen in the task''s working directory'
            }
        }
    WhenRunningTask 'ToolTask'
    ThenToolInstalled 'Node'
    ThenPipelineSucceeded
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is defined and cleaning' {
    Init
    GivenRunByDeveloper
    GivenContext
    GivenParameter @{ 'WorkingDirectory' = '.output' }
    GivenWorkingDirectory '.output' -SkipMock
    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
    Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -MockWith {
            #$DebugPreference = 'Continue'
            $currentPath = (Get-Location).ProviderPath
            $expectedPath = (Resolve-Path -Path 'TestDrive:\.output').ProviderPath
            Write-Debug ('Current  Path   {0}' -f $currentPath)
            Write-Debug ('Expected Path   {0}' -f $expectedPath)
            if( $currentPath -ne $expectedPath )
            {
                throw 'tool uninstallation didn''t happen in the task''s working directory'
            }
        }
    WhenRunningTask 'ToolTask' -InRunMode 'Clean'
    ThenPipelineSucceeded
    ThenToolUninstalled 'Node'
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is invalid' {
    Init
    GivenContext
    GivenParameter @{ 'WorkingDirectory' = 'Invalid/Directory' }
    GivenRunByDeveloper
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
    ThenThrewException 'BuildTasks.+WorkingDirectory.+does not exist.'
    ThenTaskNotRun 'PowerShell'
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
        GivenContext
        WhenRunningTask 'MyTask' -InRunMode 'Clean'
        It 'should not run task that does not support clean' {
            $global:taskRan | Should -Be $false
        }
        WhenRunningTask 'MyCleanTask' -InRunMode 'Clean'
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

        Init
        GivenContext
        $global:taskRan = $false
        WhenRunningTask 'MyTask' -InRunMode 'Initialize'
        It 'should not run task that does not support initializes' {
            $global:taskRan | Should -Be $false
        }
        WhenRunningTask 'MyInitializeTask' -InRunMode 'Initialize'
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

Describe 'Invoke-WhiskeyTask.when given OnlyDuring parameter' {
    try
    {
        Init
        GivenMockTask -SupportsClean -SupportsInitialize

        foreach ($runMode in @('Clean', 'Initialize'))
        {
            Context ('OnlyDuring is {0}' -f $runMode) {
                GivenContext
                GivenParameter @{ 'OnlyDuring' = $runMode }
                WhenRunningTask 'MockTask'
                WhenRunningTask 'MockTask' -InRunMode 'Clean'
                WhenRunningTask 'MockTask' -InRunMode 'Initialize'
                ThenRanTask 'MockTask' -Times 1
                ThenTaskRanWithoutParameter -Task 'MockTask' -ParameterName 'OnlyDuring'
            }
        }
    }
    finally
    {
        RemoveMockTask
    }
}

Describe 'Invoke-WhiskeyTask.when given ExceptDuring parameter' {
    try
    {
        Init
        GivenMockTask -SupportsClean -SupportsInitialize

        foreach ($runMode in @('Clean', 'Initialize'))
        {
            Context ('ExceptDuring is {0}' -f $runMode) {
                GivenContext
                GivenParameter @{ 'ExceptDuring' = $runMode }
                WhenRunningTask 'MockTask'
                WhenRunningTask 'MockTask' -InRunMode 'Clean'
                WhenRunningTask 'MockTask' -InRunMode 'Initialize'
                ThenRanTask 'MockTask' -Times 2
                ThenTaskRanWithoutParameter -Task 'MockTask' -ParameterName 'ExceptDuring'
            }
        }
    }
    finally
    {
        RemoveMockTask
    }
}

Describe 'Invoke-WhiskeyTask.when given both OnlyDuring and ExceptDuring' {
    try
    {
        Init
        GivenContext
        GivenParameter @{ 'OnlyDuring' = 'Clean'; 'ExceptDuring' = 'Clean' }
        GivenMockTask -SupportsClean -SupportsInitialize
        WhenRunningTask 'MockTask' -ErrorAction SilentlyContinue
        ThenThrewException 'Both ''OnlyDuring'' and ''ExceptDuring'' properties are used. These properties are mutually exclusive'
        ThenTaskNotRun 'MockTask'
    }
    finally
    {
        RemoveMockTask
    }
}

Describe 'Invoke-WhiskeyTask.when OnlyDuring or ExceptDuring contains invalid value' {
    try
    {
        Init
        GivenContext
        GivenMockTask -SupportsClean -SupportsInitialize

        Context 'OnlyDuring is invalid' {
            GivenParameter @{ 'OnlyDuring' = 'InvalidValue' }
            WhenRunningTask 'MockTask' -ErrorAction SilentlyContinue
            ThenThrewException 'Property ''OnlyDuring'' has an invalid value'
            ThenTaskNotRun 'MockTask'
        }

        Context 'ExceptDuring is invalid' {
            GivenParameter @{ 'ExceptDuring' = 'InvalidValue' }
            WhenRunningTask 'MockTask' -ErrorAction SilentlyContinue
            ThenThrewException 'Property ''ExceptDuring'' has an invalid value'
            ThenTaskNotRun 'MockTask'
        }
    }
    finally
    {
        RemoveMockTask
    }
}

foreach( $commonPropertyName in @( 'OnlyBy', 'OnlyDuring', 'ExceptDuring' ) )
{
    Describe ('Invoke-WhiskeyTask.when {0} property has variable for a value' -f $commonPropertyName) {
        Init
        GivenContext
        GivenParameter @{ $commonPropertyName = '$(Fubar)' }
        GivenVariable 'Fubar' 'Snafu'
        Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
        WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
        ThenThrewException 'has\ an\ invalid\ value:\ ''Snafu'''
    }
}

Describe ('Invoke-WhiskeyTask.when OnlyOnBranch property has variable for a value') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenContext
    GivenParameter @{ 'OnlyOnBranch' = '$(Fubar)' }
    GivenVariable 'Fubar' 'Snafu'
    GivenScmBranch 'Snafu'
    WhenRunningTask 'PowerShell'
    ThenRanTask 'PowerShell'
}

Describe ('Invoke-WhiskeyTask.when ExceptOnBranch property has variable for a value') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenContext
    GivenParameter @{ 'ExceptOnBranch' = '$(Fubar)' }
    GivenVariable 'Fubar' 'Snafu'
    GivenScmBranch 'Snafu'
    WhenRunningTask 'PowerShell'
    ThenTaskNotRun 'PowerShell'
}

Describe ('Invoke-WhiskeyTask.when WorkingDirectory property has a variable for a value') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenContext
    GivenParameter @{ 'WorkingDirectory' = '$(Fubar)' }
    GivenWorkingDirectory 'Snafu'
    GivenVariable 'Fubar' 'Snafu'
    WhenRunningTask 'PowerShell'
    ThenTaskRanInWorkingDirectory 'Snafu'
}

foreach( $commonPropertyName in @( 'OnlyBy', 'OnlyDuring', 'ExceptDuring' ) )
{
    Describe ('Invoke-WhiskeyTask.when {0} property comes from defaults' -f $commonPropertyName) {
        Init
        Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
        GivenContext
        GivenDefaults @{ $commonPropertyName = 'Snafu' } -ForTask 'PowerShell'
        WhenRunningTask 'PowerShell' -ErrorAction SilentlyContinue
        ThenThrewException 'has\ an\ invalid\ value:\ ''Snafu'''
    }
}

Describe ('Invoke-WhiskeyTask.when OnlyOnBranch property comes from defaults') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenContext
    GivenDefaults @{ 'OnlyOnBranch' = 'Snafu' } -ForTask 'PowerShell'
    GivenScmBranch 'Snafu'
    WhenRunningTask 'PowerShell'
    ThenRanTask 'PowerShell'
}

Describe ('Invoke-WhiskeyTask.when ExceptOnBranch property comes from defaults') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenContext
    GivenDefaults @{ 'ExceptOnBranch' = 'Snafu' } -ForTask 'PowerShell'
    GivenScmBranch 'Snafu'
    WhenRunningTask 'PowerShell'
    ThenTaskNotRun 'PowerShell'
}

Describe ('Invoke-WhiskeyTask.when WorkingDirectory property comes from defaults') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenContext
    GivenWorkingDirectory 'Snafu'
    GivenDefaults @{ 'WorkingDirectory' = 'Snafu' } -ForTask 'PowerShell'
    WhenRunningTask 'PowerShell'
    ThenTaskRanInWorkingDirectory 'Snafu'
}

Describe ('Invoke-WhiskeyTask.when WorkingDirectory property comes from defaults and default has a variable') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenContext
    GivenVariable 'Fubar' 'Snafu'
    GivenWorkingDirectory 'Snafu'
    GivenDefaults @{ 'WorkingDirectory' = '$(Fubar)' } -ForTask 'PowerShell'
    WhenRunningTask 'PowerShell'
    ThenTaskRanInWorkingDirectory 'Snafu'
}

Describe 'Invoke-WhiskeyTask.when task requires tools' {
    Init
    Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
    GivenContext
    WhenRunningTask 'ToolTask'
    ThenPipelineSucceeded
    ThenToolInstalled 'Node'
    ThenToolNotCleaned
    It 'should run the task' {
        $taskRun | Should -Be $true
    }
}

Describe 'Invoke-WhiskeyTask.when task requires tools and initializing' {
    Init
    Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
    GivenContext
    WhenRunningTask 'ToolTask' -InRunMode 'Initialize'
    ThenToolInstalled 'Node'
    ThenTaskNotRun 'ToolTask'
    ThenToolNotCleaned
    It ('should fail the build if installation fails') {
        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
    }
}

Describe 'Invoke-WhiskeyTask.when task requires tools and cleaning' {
    try
    {
        Init
        Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        GivenContext
        WhenRunningTask 'ToolTask' -InRunMode 'Clean'
        ThenToolUninstalled 'Node'
        It ('should not install any tools in clean mode') {
            Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $InCleanMode -eq $true }
        }
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Invoke-WhiskeyTask.when task needs a required tool in order to clean' {
    try
    {
        Init
        Install-Node
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey'
        GivenContext
        WhenRunningTask 'ToolTask' -InRunMode 'Clean'
        ThenPipelineSucceeded
        It 'should not re-install too' {
            Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 0
        }
    }
    finally
    {
        Remove-Node
    }
}

Remove-Item -Path 'function:ToolTask' -ErrorAction Ignore
