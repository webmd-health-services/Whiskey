
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Import-WhiskeyTestTaskModule

$testRoot = $null
$whiskeyYmlPath = $null
$runByDeveloper = $false
$runByBuildServer = $false
[Whiskey.Context]$context = $null
$output = $null
$taskDefaults = @{ }
$scmBranch = $null
$taskProperties = @{ }
$taskRun = $false
$variables = @{ }
$enablePlugins = $null
$taskNameForPlugin = $null
$taskRunCount = 0
$tasks = Get-WhiskeyTask -Force

function Get-TaskCommandName
{
    param(
        [Parameter(Mandatory)]
        [String]$Name
    )

    $tasks | Where-Object { $_.Name -eq $Name } | Select-Object -ExpandProperty 'CommandName'
}

function Invoke-PreTaskPlugin
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

function Invoke-PostTaskPlugin
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

function GivenFailingMSBuildProject
{
    param(
        $Project
    )

    New-MSBuildProject -FileName $project -ThatFails
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

    # Don't use New-Item since it gets mocked.
    New-Item -Path (Join-Path -Path $testRoot -ChildPath $Name)
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

function GivenNoOpTask
{
    param(
        [switch]$SupportsClean,
        [switch]$SupportsInitialize
    )

}

function RemoveNoOpTask
{
    Remove-Item -Path 'function:NoOpTask'
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

    $variables[$Name] = $Value
}

function GivenWhiskeyYmlBuildFile
{
    param(
        [Parameter(Position=0)]
        [String]$Yaml
    )

    $script:whiskeyYmlPath = Join-Path -Path $testRoot -ChildPath 'whiskey.yml'
    $Yaml | Set-Content -Path $whiskeyYmlPath
    return $whiskeyymlpath
}

function GivenWorkingDirectory
{
    param(
        [String]$Directory
    )

    $wd = Join-Path -Path $testRoot -ChildPath $Directory
    [IO.Directory]::CreateDirectory($wd)
}

function Init
{
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

function ThenPipelineFailed
{
    $threwException | Should -BeTrue
}

function ThenBuildOutputRemoved
{
    Join-Path -Path ($whiskeyYmlPath | Split-Path) -ChildPath '.output' | Should -Not -Exist
}

function ThenPipelineSucceeded
{
    $Global:Error | Should -BeNullOrEmpty
    $threwException | Should -BeFalse
}

function ThenDotNetProjectsCompilationFailed
{
    param(
        [String]$ConfigurationPath,

        [String[]]$ProjectName
    )

    $root = Split-Path -Path $ConfigurationPath -Parent
    foreach( $name in $ProjectName )
    {
        (Join-Path -Path $root -ChildPath ('{0}.clean' -f $ProjectName)) | Should -Not -Exist
        (Join-Path -Path $root -ChildPath ('{0}.build' -f $ProjectName)) | Should -Not -Exist
    }
}

function ThenNoOutput
{
    $output | Should -BeNullOrEmpty
}
function ThenNUnitTestsNotRun
{
    param(
    )

    $context.OutputDirectory | Get-ChildItem -Filter 'nunit2*.xml' | Should -BeNullOrEmpty
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
            Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -Times $Times -ParameterFilter { $TaskContext -ne $null }
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

        Unregister-WhiskeyEvent -Context $context -CommandName $pluginName -Event AfterTask
        Unregister-WhiskeyEvent -Context $context -CommandName $pluginName -Event AfterTask -TaskName $ForTaskNamed
        Unregister-WhiskeyEvent -Context $context -CommandName $pluginName -Event BeforeTask
        Unregister-WhiskeyEvent -Context $context -CommandName $pluginName -Event BeforeTask -TaskName $ForTaskNamed
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
        $wd = Join-Path -Path $testRoot -ChildPath $InWorkingDirectory

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

    $expectedTempPath = Join-Path -Path $context.OutputDirectory -ChildPath ('Temp.{0}.' -f $TaskName)
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

    $expectedTempPath = Join-Path -Path $context.OutputDirectory -ChildPath ('Temp.{0}.*' -f $TaskName)
    $expectedTempPath | Should -Not -Exist
    $context.Temp | Should -Not -Exist
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
        $ErrorActionPreference.ToString() | Should -Be 'Stop' -Because 'should fail the build if install fails'
        $expectedInstallRoot = $testRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)
        Write-WhiskeyDebug -Message ('InstallRoot  expected  {0}' -f $expectedInstallRoot)
        Write-WhiskeyDebug -Message ('             actual    {0}' -f $InstallRoot)
        $InstallRoot -eq $expectedInstallRoot
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

    $taskProperties.ContainsKey($ParameterName) | Should -BeTrue
}

function ThenToolUninstalled
{
    param(
        $ToolName
    )

    $taskContext = $context
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
    if( $runByBuildServer )
    {
        $byItDepends = @{ 'ForBuildServer' = $true }
    }

    $script:context = New-WhiskeyTestContext @byItDepends -ForBuildRoot $testRoot
    $context.PipelineName = 'Build';
    $context.TaskName = $null;
    $context.TaskIndex = 1;
    foreach( $key in $taskDefaults.Keys )
    {
        $context.TaskDefaults.Add($key,$taskDefaults[$key])
    }

    if( $InRunMode )
    {
        $context.RunMode = $InRunMode;
    }

    if( $scmBranch )
    {
        $context.BuildMetadata.ScmBranch = $scmBranch
    }

    if( $enablePlugins )
    {
        $taskNameParam = @{}
        if( $taskNameForPlugin )
        {
            $taskNameParam['TaskName'] = $taskNameForPlugin
        }

        Register-WhiskeyEvent -Context $context -CommandName 'Invoke-PostTaskPlugin' -Event AfterTask @taskNameParam
        Mock -CommandName 'Invoke-PostTaskPlugin' -ModuleName 'Whiskey'
        Register-WhiskeyEvent -Context $context -CommandName 'Invoke-PreTaskPlugin' -Event BeforeTask @taskNameParam
        Mock -CommandName 'Invoke-PreTaskPlugin' -ModuleName 'Whiskey'
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
        $script:output = Invoke-WhiskeyTask -TaskContext $context -Name $Named -Parameter $Parameter 
    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }
}

Describe 'Invoke-WhiskeyTask.when running an unknown task' {
    It 'should fail' {
        Init
        WhenRunningTask 'Fubar' -Parameter @{ } -ErrorAction SilentlyContinue
        ThenPipelineFailed
        ThenThrewException 'not\ exist'
    }
}

Describe 'Invoke-WhiskeyTask.when a task fails' {
    It 'should fail builds' {
        Init
        WhenRunningTask 'FailingTask' -ErrorAction SilentlyContinue
        ThenPipelineFailed
        ThenThrewException 'Failed!'
        ThenTempDirectoryCreated 'FailingTask'
        ThenTempDirectoryRemoved 'FailingTask'
    }
}

Describe 'Invoke-WhiskeyTask.when there are registered event handlers' {
    It 'should run the event handlers' {
        Init
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
}

Describe 'Invoke-WhiskeyTask.when there are task-specific registered event handlers' {
    It 'should run events for just those tasks' {
        Init
        GivenPlugins -ForSpecificTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ Path = 'somefile.ps1' }
        ThenPipelineSucceeded
        ThenPluginsRan -ForTaskNamed 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' }
    }
}

Describe 'Invoke-WhiskeyTask.when there are task defaults' {
    It 'should apply those defaults if not specified' {
        Init
        $defaults = @{ 'Fubar' = @{ 'Snfau' = 'value1' ; 'Key2' = 'value1' }; 'Key3' = 'Value3' }
        GivenDefaults $defaults -ForTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' 
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter $defaults
    }
}

Describe 'Invoke-WhiskeyTask.when there are task defaults that are overwritten' {
    It 'should not overwrite user''s values' {
        Init
        $defaults = @{ 'Fubar' = @{ 'Snfau' = 'value1' ; 'Key2' = 'value1' }; 'Key3' = 'Value3' }
        GivenDefaults $defaults -ForTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Fubar' = @{ 'Snfau' = 'myvalue' } ; 'NotADefault' = 'NotADefault' }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Fubar' = @{ 'Snfau' = 'myvalue'; 'Key2' = 'value1' }; 'Key3' = 'Value3'; 'NotADefault' = 'NotADefault' }
    }
}

Describe 'Invoke-WhiskeyTask.when task should only be run by developer and being run by build server' {
    It 'should not run the task' {
        Init
        GivenRunByBuildServer
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Developer' }
        ThenPipelineSucceeded
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when task should only be run by developer and being run by developer' {
    It 'should run the task' {
        Init
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Developer' }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter 'OnlyBy'
    }
}

Describe 'Invoke-WhiskeyTask.when task has property variables' {
    It 'should replace variables with values' {
        Init
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = '$(MachineName)'; }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = [Environment]::MachineName; }
        ThenNoOutput
    }
}

Describe 'Invoke-WhiskeyTask.when task should only be run by build server and being run by build server' {
    It 'should run the task' {
        Init
        GivenRunByBuildServer
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'BuildServer' }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter 'OnlyBy'
    }
}

Describe 'Invoke-WhiskeyTask.when task should only be run by build server and being run by developer' {
    It 'should not run the task' {
        Init
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'OnlyBy' = 'BuildServer' }
        ThenPipelineSucceeded
        ThenTaskNotRun 'NoOpTask'
    }
}

foreach ($property in @('OnlyBy', 'ExceptBy'))
{
    Describe ('Invoke-WhiskeyTask.when {0} has an invalid value' -f $property) {
        It 'should fail' {
            Init
            GivenRunByDeveloper
            WhenRunningMockedTask 'NoOpTask' -Parameter @{ $property = 'Somebody' } -ErrorAction SilentlyContinue
            ThenThrewException 'invalid value'
            ThenTaskNotRun 'NoOpTask'
        }
    }
}

Describe 'Invoke-WhiskeyTask.when task should run except by build server and being run by build server' {
    It 'should not run the task' {
        Init
        GivenRunByBuildServer
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'ExceptBy' = 'BuildServer' }
        ThenPipelineSucceeded
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when task should run except by build server and being run by developer' {
    It 'should run the task' {
        Init
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; 'ExceptBy' = 'BuildServer' }
        ThenPipelineSucceeded
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' }
    }
}

Describe 'Invoke-WhiskeyTask.when OnlyBy and ExceptBy properties are both defined' {
    It 'should fail' {
        Init
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'OnlyBy' = 'Developer'; 'ExceptBy' = 'Developer' } -ErrorAction SilentlyContinue
        ThenThrewException 'This\ task\ defines\ both\ "OnlyBy"\ and\ "ExceptBy"\ properties'
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch contains current branch' {
    It 'should run the task' {
        Init
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = 'develop' } -ErrorAction SilentlyContinue
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter 'OnlyOnBranch'
    }
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch contains wildcard matching current branch' {
    It 'should run the task' {
        Init
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = @( 'master', 'dev*' ) } -ErrorAction SilentlyContinue
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter 'OnlyOnBranch'
    }
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch does not contain current branch' {
    It 'should not run the task' {
        Init
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'OnlyOnBranch' = 'notDevelop' } -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when ExceptOnBranch contains current branch' {
    It 'should not run the task' {
        Init
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; 'ExceptOnBranch' = 'develop' } -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when ExceptOnBranch contains wildcard matching current branch' {
    It 'should not run the task' {
        Init
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'ExceptOnBranch' = @( 'master', 'dev*' ) } -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when ExceptOnBranch does not contain current branch' {
    It 'should run the task' {
        Init
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'Path' = 'somefile.ps1'; 'ExceptOnBranch' = 'notDevelop' }
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'somefile.ps1' } -WithoutParameter 'ExceptOnBranch'
    }
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch and ExceptOnBranch properties are both defined' {
    It 'should fail' {
        Init
        GivenRunByDeveloper
        GivenScmBranch 'develop'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'OnlyOnBranch' = 'develop'; 'ExceptOnBranch' = 'develop' } -ErrorAction SilentlyContinue
        ThenThrewException 'This task defines both OnlyOnBranch and ExceptOnBranch properties'
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is defined' {
    It 'should run task in that directory' {
        Init
        GivenRunByDeveloper
        GivenWorkingDirectory '.output'
        WhenRunningMockedTask -Named 'NoOpTask' `
                              -Parameter @{ 'Path' = 'somefile.ps1'; 'WorkingDirectory' = '.output' } `
                              -ThatMarksWorkingDirectory
        ThenTaskRan -Named 'NoOpTask' `
                    -WithParameter @{ 'Path' = 'somefile.ps1' } `
                    -WithoutParameter 'WorkingDirectory' `
                    -InWorkingDirectory '.output'
    }
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is defined and installing a tool' {
    It 'should install tool in that directory' {
        Init
        GivenRunByDeveloper
        GivenWorkingDirectory '.output'
        $testRoot = $script:testRoot
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -MockWith {
                #$DebugPreference = 'Continue'
                $currentPath = (Get-Location).ProviderPath
                $expectedPath = Join-Path -Path $testRoot -ChildPath '.output'
                Write-WhiskeyDebug ('Current  Path   {0}' -f $currentPath)
                Write-WhiskeyDebug ('Expected Path   {0}' -f $expectedPath)
                if( $currentPath -ne $expectedPath )
                {
                    throw 'tool installation didn''t happen in the task''s working directory'
                }
            }.GetNewClosure()
        $parameter = @{ 'WorkingDirectory' = '.output' }
        WhenRunningTask 'RequiresNodeTask' -Parameter $parameter
        ThenToolInstalled 'Node'
        ThenPipelineSucceeded
    }
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is defined and cleaning' {
    It 'should clean in that directory' {
        Init
        GivenRunByDeveloper
        GivenWorkingDirectory '.output' 
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        $testRoot = $script:testRoot
        Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey' -MockWith {
                #$DebugPreference = 'Continue'
                $currentPath = (Get-Location).ProviderPath
                $expectedPath = Join-Path -Path $testRoot -ChildPath '.output' 
                Write-WhiskeyDebug ('Current  Path   {0}' -f $currentPath)
                Write-WhiskeyDebug ('Expected Path   {0}' -f $expectedPath)
                if( $currentPath -ne $expectedPath )
                {
                    throw 'tool uninstallation didn''t happen in the task''s working directory'
                }
            }.GetNewClosure()
        WhenRunningTask 'RequiresNodeTask' -Parameter @{ 'WorkingDirectory' = '.output' } -InRunMode 'Clean'
        ThenPipelineSucceeded
        ThenToolUninstalled 'Node'
    }
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is invalid' {
    It 'should fail' {
        Init
        GivenRunByDeveloper
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'WorkingDirectory' = 'Invalid/Directory' } -ErrorAction SilentlyContinue
        ThenThrewException 'WorkingDirectory.+does not exist.'
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when run in clean mode' {
    Context 'task doesn''t support clean mode' {
        It 'should not run task' {
            Init
            WhenRunningMockedTask 'BuildOnlyTask' -InRunMode 'Clean'
            ThenTaskNotRun 'BuildOnlyTask'
        }
    }
    Context 'task supports clean mode' {
        It 'should run task' {
            Init
            WhenRunningMockedTask 'SupportsCleanTask' -InRunMode 'Clean'
            ThenTaskRan 'SupportsCleanTask'
        }
    }
}

Describe 'Invoke-WhiskeyTask.when run in initialize mode' {
    Context 'task doesn''t support initialize mode' {
        It 'should not run task' {
            Init
            WhenRunningMockedTask 'BuildOnlyTask' -InRunMode 'Initialize'
            ThenTaskNotRun 'BuildOnlyTask'
        }
    }
    Context 'task supports initialize mode' {
        It 'should run task' {
            Init
            WhenRunningMockedTask 'SupportsInitializeTask' -InRunMode 'Initialize'
            ThenTaskRan 'SupportsInitializeTask'
        }
    }
}

Describe 'Invoke-WhiskeyTask.when given ExceptDuring parameter' {
    foreach ($runMode in @('Clean', 'Initialize', 'Build'))
    {
        Context ('ExceptDuring is {0}' -f $runMode) {
            It 'should not run tasks in those modes' {
                Init
                $TaskParameter = @{ 'ExceptDuring' = $runMode }
                WhenRunningMockedTask 'SupportsCleanAndInitializeTask' -Parameter $TaskParameter
                WhenRunningTask 'SupportsCleanAndInitializeTask' -Parameter $TaskParameter -InRunMode 'Clean'
                WhenRunningTask 'SupportsCleanAndInitializeTask' -Parameter $TaskParameter -InRunMode 'Initialize'
                ThenTaskRan 'SupportsCleanAndInitializeTask' -Times 2 -WithoutParameter 'ExceptDuring'
            }
        }
    }
}

Describe 'Invoke-WhiskeyTask.when given IfExists parameter and environment variable exists' {
    AfterEach { Remove-Item -Path 'env:fubar' }
    It 'should run the task' {
        Init
        GivenEnvironmentVariable 'fubar'
        $TaskParameter = @{ 'IfExists' = 'env:fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskRan 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when given IfExists parameter and environment variable does not exist' {
    It 'should not run the task' {
        Init
        $TaskParameter = @{ 'IfExists' = 'env:snafu' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when given IfExists parameter and file exists' {
    It 'should run the task' {
        Init
        GivenFile 'fubar'
        $TaskParameter = @{ 'IfExists' = 'fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskRan 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when given IfExists parameter and file does not exist' {
    It 'should not run the task' {
        Init
        $TaskParameter = @{ 'IfExists' = 'fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when given UnlessExists parameter and environment variable exists' {
    AfterEach { Remove-Item -Path 'env:fubar' }
    It 'should not run the task' {
        Init
        GivenEnvironmentVariable 'fubar'
        $TaskParameter = @{ 'UnlessExists' = 'env:fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when given UnlessExists parameter and environment variable does not exist' {
    It 'should run the task' {
        Init
        $TaskParameter = @{ 'UnlessExists' = 'env:snafu' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskRan 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when given UnlessExists and file exists' {
    It 'should not run the task' {
        Init
        GivenFile 'fubar'
        $TaskParameter = @{ 'UnlessExists' = 'fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when given UnlessExists parameter and file does not exist' {
    It 'should run the task' {
        Init
        $TaskParameter = @{ 'UnlessExists' = 'fubar' }
        WhenRunningMockedTask 'NoOpTask' -Parameter $TaskParameter
        ThenTaskRan 'NoOpTask'
    }
}

Describe 'Invoke-WhiskeyTask.when given both OnlyDuring and ExceptDuring' {
    It 'should fail' {
        Init
        WhenRunningMockedTask 'SupportsCleanAndInitializeTask' -Parameter @{ 'OnlyDuring' = 'Clean'; 'ExceptDuring' = 'Clean' } -ErrorAction SilentlyContinue
        ThenThrewException 'Both ''OnlyDuring'' and ''ExceptDuring'' properties are used. These properties are mutually exclusive'
        ThenTaskNotRun 'SupportsCleanAndInitializeTask'
    }
}

Describe 'Invoke-WhiskeyTask.when OnlyDuring or ExceptDuring contains invalid value' {
    Context 'OnlyDuring is invalid' {
        It 'should fail' {
            Init
            WhenRunningMockedTask 'SupportsCleanAndInitializeTask' -Parameter @{ 'OnlyDuring' = 'InvalidValue' } -ErrorAction SilentlyContinue
            ThenThrewException 'Property ''OnlyDuring'' has an invalid value'
            ThenTaskNotRun 'SupportsCleanAndInitializeTask'
        }
    }

    Context 'ExceptDuring is invalid' {
        It 'should fail' {
            Init
            WhenRunningMockedTask 'SupportsCleanAndInitializeTask' -Parameter @{ 'ExceptDuring' = 'InvalidValue' } -ErrorAction SilentlyContinue
            ThenThrewException 'Property ''ExceptDuring'' has an invalid value'
            ThenTaskNotRun 'SupportsCleanAndInitializeTask'
        }
    }
}

foreach( $commonPropertyName in @( 'OnlyBy', 'ExceptBy', 'OnlyDuring', 'ExceptDuring' ) )
{
    Describe ('Invoke-WhiskeyTask.when {0} property has variable for a value' -f $commonPropertyName) {
        It 'should evaluate variable and fail' {
            Init
            GivenVariable 'Fubar' 'Snafu'
            WhenRunningMockedTask 'NoOpTask' -Parameter @{ $commonPropertyName = '$(Fubar)' } -ErrorAction SilentlyContinue
            ThenThrewException 'invalid\ value:\ ''Snafu'''
            ThenTaskNotRun 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when OnlyOnBranch property has variable for a value') {
    It 'should evaluate variable' {
        Init
        GivenVariable 'Fubar' 'Snafu'
        GivenScmBranch 'Snafu'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'OnlyOnBranch' = '$(Fubar)' }
        ThenTaskRan 'NoOpTask'
    }
}

Describe ('Invoke-WhiskeyTask.when ExceptOnBranch property has variable for a value') {
    It 'should evalute variable' {
        Init
        GivenVariable 'Fubar' 'Snafu'
        GivenScmBranch 'Snafu'
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ 'ExceptOnBranch' = '$(Fubar)' }
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe ('Invoke-WhiskeyTask.when WorkingDirectory property has a variable for a value') {
    It 'should evaluate variable' {
        Init
        GivenWorkingDirectory 'Snafu'
        GivenVariable 'Fubar' 'Snafu'
        WhenRunningMockedTask -Named 'NoOpTask' `
                              -Parameter @{ 'WorkingDirectory' = '$(Fubar)' } `
                              -ThatMarksWorkingDirectory
        ThenTaskRan 'NoOpTask' -InWorkingDirectory 'Snafu'
    }
}

foreach( $commonPropertyName in @( 'OnlyBy', 'ExceptBy', 'OnlyDuring', 'ExceptDuring' ) )
{
    Describe ('Invoke-WhiskeyTask.when {0} property comes from defaults' -f $commonPropertyName) {
        It 'should read value from defaults' {
            Init
            GivenDefaults @{ $commonPropertyName = 'Snafu' } -ForTask 'NoOpTask'
            WhenRunningMockedTask 'NoOpTask' -ErrorAction SilentlyContinue
            ThenThrewException 'invalid\ value:\ ''Snafu'''
            ThenTaskNotRun 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when OnlyOnBranch property comes from defaults') {
    It 'should read value from defaults' {
        Init
        GivenDefaults @{ 'OnlyOnBranch' = 'Snafu' } -ForTask 'NoOpTask'
        GivenScmBranch 'Snafu'
        WhenRunningMockedTask 'NoOpTask' 
        ThenTaskRan 'NoOpTask' 
    }
}

Describe ('Invoke-WhiskeyTask.when ExceptOnBranch property comes from defaults') {
    It 'should read value from defaults' {
        Init
        GivenDefaults @{ 'ExceptOnBranch' = 'Snafu' } -ForTask 'NoOpTask'
        GivenScmBranch 'Snafu'
        WhenRunningMockedTask 'NoOpTask' 
        ThenTaskNotRun 'NoOpTask'
    }
}

Describe ('Invoke-WhiskeyTask.when WorkingDirectory property comes from defaults') {
    It 'should read value from defaults' {
        Init
        GivenWorkingDirectory 'Snafu'
        GivenDefaults @{ 'WorkingDirectory' = 'Snafu' } -ForTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' -ThatMarksWorkingDirectory
        ThenTaskRan 'NoOpTask' -InWorkingDirectory 'Snafu'
    }
}

Describe ('Invoke-WhiskeyTask.when WorkingDirectory property comes from defaults and default has a variable') {
    It 'should use defaults and resolve variable''s value' {
        Init
        GivenVariable 'Fubar' 'Snafu'
        GivenWorkingDirectory 'Snafu'
        GivenDefaults @{ 'WorkingDirectory' = '$(Fubar)' } -ForTask 'NoOpTask'
        WhenRunningMockedTask 'NoOpTask' -ThatMarksWorkingDirectory
        ThenTaskRan 'NoOpTask' -InWorkingDirectory 'Snafu'
    }
}

Describe 'Invoke-WhiskeyTask.when task requires tools' {
    It 'should install the tool' {
        Init
        Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        WhenRunningTask 'RequiresNodeTask' 
        ThenPipelineSucceeded
        ThenToolInstalled 'Node'
        ThenToolNotCleaned
    }
}

Describe 'Invoke-WhiskeyTask.when task requires tools and initializing' {
    It 'should install the tool' {
        Init
        Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        WhenRunningTask 'RequiresNodeFailingTask' -InRunMode 'Initialize'
        ThenToolInstalled 'Node'
        ThenToolNotCleaned
        ThenPipelineSucceeded
    }
}

Describe 'Invoke-WhiskeyTask.when task requires tools and cleaning' {
    AfterEach { Remove-Node -BuildRoot $testRoot }
    It 'should remove the tool' {
        Init
        Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
        Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
        WhenRunningTask 'RequiresNodeTask' -InRunMode 'Clean'
        ThenToolUninstalled 'Node'
        Assert-MockCalled -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey' -ParameterFilter { $InCleanMode -eq $true }
    }
}

Describe 'Invoke-WhiskeyTask.when task needs a required tool in order to clean' {
    AfterEach { Remove-Node -BuildRoot $testRoot }
    It 'should should not download the tool' {
        Init
        Install-Node -BuildRoot $testRoot
        Mock -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey'
        WhenRunningTask 'RequiresNodeTask' -InRunMode 'Clean'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 0
    }
}

Describe 'Invoke-WhiskeyTask.when a task runs another task' {
    It 'should handle tasks being wrapped' {
        Init
        GivenMockedTask 'NoOpTask'
        WhenRunningTask 'WrapsNoOpTask' -Parameter @{ 'Path' = 'script.ps1' }
        ThenTaskRan 'NoOpTask' -WithParameter @{ 'Path' = 'script.ps1' }
        ThenTempDirectoryCreated 'WrapsNoOpTask'
        ThenTempDirectoryCreated 'NoOpTask'
        ThenTempDirectoryRemoved 'WrapsNoOpTask'
        ThenTempDirectoryRemoved 'NoOpTask'
        ThenPipelineSucceeded
    }
}

Describe ('Invoke-WhiskeyTask.when running Windows-only task on {0} platform' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
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
}

Describe ('Invoke-WhiskeyTask.when running Linux-only task on {0} platform' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
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
}

Describe ('Invoke-WhiskeyTask.when running MacOS-only task on {0} platform' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
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
}

Describe ('Invoke-WhiskeyTask.when running Windows or Linux only task on {0} platform' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
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
}

Describe ('Invoke-WhiskeyTask.when run on {0} and OnlyOnPlatform is Windows' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ OnlyOnPlatform = 'Windows' }
        if( $IsWindows )
        {
            ThenTaskRan 'NoOpTask'
        }
        else
        {
            ThenTaskNotRun 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and OnlyOnPlatform is Linux' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ OnlyOnPlatform = 'Linux' }
        if( $IsLinux )
        {
            ThenTaskRan 'NoOpTask'
        }
        else
        {
            ThenTaskNotRun 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and OnlyOnPlatform is MacOS' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ OnlyOnPlatform = 'MacOS' }
        if( $IsMacOS )
        {
            ThenTaskRan 'NoOpTask'
        }
        else
        {
            ThenTaskNotRun 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and OnlyOnPlatform is Windows,MacOS' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ OnlyOnPlatform = @( 'Windows','MacOS' ) }
        if( $IsLinux )
        {
            ThenTaskNotRun 'NoOpTask'
        }
        else
        {
            ThenTaskRan 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when OnlyOnPlatform is invalid') {
    It 'should fail' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ OnlyOnPlatform = 'Blarg' } -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
        ThenThrewException ([regex]::Escape('Invalid platform "Blarg"'))
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and ExceptOnPlatform is Windows' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ ExceptOnPlatform = 'Windows' }
        if( $IsWindows )
        {
            ThenTaskNotRun 'NoOpTask'
        }
        else
        {
            ThenTaskRan 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and ExceptOnPlatform is Linux' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ ExceptOnPlatform = 'Linux' }
        if( $IsLinux )
        {
            ThenTaskNotRun 'NoOpTask'
        }
        else
        {
            ThenTaskRan 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and ExceptOnPlatform is MacOS' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ ExceptOnPlatform = 'MacOS' }
        if( $IsMacOS )
        {
            ThenTaskNotRun 'NoOpTask'
        }
        else
        {
            ThenTaskRan 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and ExceptOnPlatform is Windows,MacOS' -f $WhiskeyPlatform) {
    It 'should run or not run the task' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ ExceptOnPlatform = @( 'Windows','MacOS' ) }
        if( $IsLinux )
        {
            ThenTaskRan 'NoOpTask'
        }
        else
        {
            ThenTaskNotRun 'NoOpTask'
        }
    }
}

Describe ('Invoke-WhiskeyTask.when ExceptOnPlatform is invalid') {
    It 'should fail' {
        Init
        WhenRunningMockedTask 'NoOpTask' -Parameter @{ ExceptOnPlatform = 'Blarg' } -ErrorAction SilentlyContinue
        ThenTaskNotRun 'NoOpTask'
        ThenThrewException ([regex]::Escape('Invalid platform "Blarg"'))
    }
}

Describe ('Invoke-WhiskeyTask.when invoking a task using its alias') {
    It 'should run the original task' {
        Init
        GivenMockedTask 'AliasedTask'
        WhenRunningTask 'OldAliasedTaskName'
        WhenRunningTask 'AnotherOldAliasedTaskName'
        ThenTaskRan 'AliasedTask' -Times 2
    }
}

Describe ('Invoke-WhiskeyTask.when task wants a warning when someone uses an alias') {
    It 'should warn not to use the alias' {
        Init
        GivenMockedTask 'ObsoleteAliasTask'
        WhenRunningTask 'OldObsoleteAliasTaskName' -WarningVariable 'warnings'
        $warnings | Should -Not -BeNullOrEmpty
        $warnings | Should -Match 'is\ an\ alias'
        ThenTaskRan -CommandNamed 'ObsoleteAliasTask'
    }
}

Describe ('Invoke-WhiskeyTask.when multiple tasks have the same alias') {
    It 'should fail' {
        Init
        GivenMockedTask 'DuplicateAliasTask1'
        GivenMockedTask 'DuplicateAliasTask2'
        WhenRunningTask 'DuplicateAliasTask' -Parameter @{} -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'Found\ \d+\ tasks\ with\ alias'
        ThenTaskNotRun -CommandName 'DuplicateAliasTask1'
        ThenTaskNotRun -CommandName 'DuplicateAliasTask2'
    }
}

Describe ('Invoke-WhiskeyTask.when multiple tasks have the same name') {
    It 'should fail' {
        Init
        GivenMockedTask -CommandName 'DuplicateTask1'
        GivenMockedTask -CommandName 'DuplicateTask2'
        WhenRunningTask 'DuplicateTask' -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'Found\ \d+\ tasks\ named'
        ThenTaskNotRun -CommandName 'DuplicateTask1'
        ThenTaskNotRun -CommandName 'DuplicateTask2'
    }
}

Describe ('Invoke-WhiskeyTask.when task is obsolete') {
    It 'should warn that the task is obsolete' {
        Init
        WhenRunningMockedTask 'ObsoleteTask' -WarningVariable 'warnings'
        $warnings | Should -Match 'is\ obsolete'
        ThenTaskRan 'ObsoleteTask'
    }
}

Describe ('Invoke-WhiskeyTask.when task is obsolete and user provides custom obsolete message') {
    It 'should warn not to use the task using the custom message' {
        Init
        WhenRunningTask 'ObsoleteWithCustomMessageTask' -WarningVariable 'warnings'
        $warnings | Should -Match 'Use\ the\ NonObsoleteTask\ instead\.'
        $warnings | Should -Not -Match 'is\ obsolete'
    }
}

Remove-Module -Name 'WhiskeyTestTasks' -Force -ErrorAction Ignore
