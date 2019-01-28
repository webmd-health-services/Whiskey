
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$whiskeyYmlPath = $null
$runByDeveloper = $false
$runByBuildServer = $false
[Whiskey.Context]$context = $null
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

    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Name) -ItemType 'File'
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
        $CommandName
    )

    if( $CommandName )
    {
        It ('should not run task ''{0}''' -f $CommandName) {
            Assert-MockCalled -CommandName $CommandName -ModuleName 'Whiskey' -Times 0
        }
    }
    else
    {
        It ('should not run the task') {
            $taskRun | Should -Be $false
        }
    }
}

function ThenTaskRanWithParameter
{
    param(
        $CommandName,
        [hashtable]
        $ExpectedParameter,
        [int]
        $Times
    )

    $TimesParam = @{}
    if ($Times -ne 0)
    {
        $TimesParam = @{ 'Times' = $Times; 'Exactly' = $true }
    }

    It ('should call task with parameters') {

        if( $CommandName )
        {
            $Global:actualParameter = $null
            Assert-MockCalled -CommandName $CommandName -ModuleName 'Whiskey' -ParameterFilter {
                $global:actualParameter = $TaskParameter
                return $true
            } @TimesParam
        }
        else
        {
            $taskRun | Should -Be $true
            $actualParameter = $taskProperties
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
        Remove-Variable -Name 'actualParameter' -Scope 'Global' -ErrorAction Ignore
    }
}

function ThenTaskRanWithoutParameter
{
    param(
        $CommandName,
        [string[]]
        $ParameterName
    )

    foreach( $name in $ParameterName )
    {
        It ('should not pass property ''{0}''' -f $name) {
            Assert-MockCalled -CommandName $CommandName -ModuleName 'Whiskey' -ParameterFilter { -not $TaskParameter.ContainsKey($name) }
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

    Mock -CommandName 'New-Item' -ModuleName 'Whiskey' -MockWith { [IO.Directory]::CreateDirectory($Path) }

    foreach( $variableName in $variables.Keys )
    {
        Add-WhiskeyVariable -Context $context -Name $variableName -Value $variables[$variableName]
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
    ThenTempDirectoryCreated 'PowerShell'
    ThenTempDirectoryRemoved 'PowerShell'
}

Describe 'Invoke-WhiskeyTask.when there are registered event handlers' {
    Init
    GivenPlugins
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ Path = 'somefile.ps1' }
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

Describe 'Invoke-WhiskeyTask.when there are task defaults that are overwritten' {
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
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'somefile.ps1' }
    ThenTaskRanWithoutParameter 'OnlyBy'
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
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'somefile.ps1' }
    ThenTaskRanWithoutParameter 'OnlyBy'
}

Describe 'Invoke-WhiskeyTask.when task should only be run by build server and being run by developer' {
    Init
    GivenRunByDeveloper
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'BuildServer' }
    ThenPipelineSucceeded
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

foreach ($property in @('OnlyBy', 'ExceptBy'))
{
    Describe ('Invoke-WhiskeyTask.when {0} has an invalid value' -f $property) {
        Init
        GivenRunByDeveloper
        Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
        WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; $property = 'Somebody' } -ErrorAction SilentlyContinue
        ThenThrewException 'invalid value'
        ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
    }
}

Describe 'Invoke-WhiskeyTask.when task should run except by build server and being run by build server' {
    Init
    GivenRunByBuildServer
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'ExceptBy' = 'BuildServer' }
    ThenPipelineSucceeded
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe 'Invoke-WhiskeyTask.when task should run except by build server and being run by developer' {
    Init
    GivenRunByDeveloper
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'ExceptBy' = 'BuildServer' }
    ThenPipelineSucceeded
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'somefile.ps1' }
}

Describe 'Invoke-WhiskeyTask.when OnlyBy and ExceptBy properties are both defined' {
    Init
    GivenRunByDeveloper
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyBy' = 'Developer'; 'ExceptBy' = 'Developer' } -ErrorAction SilentlyContinue
    ThenThrewException 'This\ task\ defines\ both\ "OnlyBy"\ and\ "ExceptBy"\ properties'
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch contains current branch' {
    Init
    GivenRunByDeveloper
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = 'develop' } -ErrorAction SilentlyContinue
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'somefile.ps1' }
    ThenTaskRanWithoutParameter 'OnlyOnBranch'
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch contains wildcard matching current branch' {
    Init
    GivenRunByDeveloper
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = @( 'master', 'dev*' ) } -ErrorAction SilentlyContinue
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'somefile.ps1' }
    ThenTaskRanWithoutParameter 'OnlyOnBranch'
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch does not contain current branch' {
    Init
    GivenRunByDeveloper
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = 'notDevelop' } -ErrorAction SilentlyContinue
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe 'Invoke-WhiskeyTask.when ExceptOnBranch contains current branch' {
    Init
    GivenRunByDeveloper
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'ExceptOnBranch' = 'develop' } -ErrorAction SilentlyContinue
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe 'Invoke-WhiskeyTask.when ExceptOnBranch contains wildcard matching current branch' {
    Init
    GivenRunByDeveloper
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'ExceptOnBranch' = @( 'master', 'dev*' ) } -ErrorAction SilentlyContinue
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe 'Invoke-WhiskeyTask.when ExceptOnBranch does not contain current branch' {
    Init
    GivenRunByDeveloper
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'ExceptOnBranch' = 'notDevelop' }
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'somefile.ps1' }
    ThenTaskRanWithoutParameter 'ExceptOnBranch'
}

Describe 'Invoke-WhiskeyTask.when OnlyOnBranch and ExceptOnBranch properties are both defined' {
    Init
    GivenRunByDeveloper
    GivenScmBranch 'develop'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'OnlyOnBranch' = 'develop'; 'ExceptOnBranch' = 'develop' } -ErrorAction SilentlyContinue
    ThenThrewException 'This task defines both OnlyOnBranch and ExceptOnBranch properties'
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is defined' {
    Init
    GivenRunByDeveloper
    GivenWorkingDirectory '.output'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1'; 'WorkingDirectory' = '.output' }
    ThenTaskRanInWorkingDirectory '.output'
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'somefile.ps1' }
    ThenTaskRanWithoutParameter 'Invoke-WhiskeyPowerShell' 'WorkingDirectory'
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is defined and installing a tool' {
    Init
    GivenRunByDeveloper
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
    $parameter = @{ 'WorkingDirectory' = '.output' }
    WhenRunningTask 'ToolTask' -Parameter $parameter
    ThenToolInstalled 'Node'
    ThenPipelineSucceeded
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is defined and cleaning' {
    Init
    GivenRunByDeveloper
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
    WhenRunningTask 'ToolTask' -Parameter @{ 'WorkingDirectory' = '.output' } -InRunMode 'Clean'
    ThenPipelineSucceeded
    ThenToolUninstalled 'Node'
}

Describe 'Invoke-WhiskeyTask.when WorkingDirectory property is invalid' {
    Init
    GivenRunByDeveloper
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    WhenRunningTask 'PowerShell' -Parameter @{ 'WorkingDirectory' = 'Invalid/Directory' } -ErrorAction SilentlyContinue
    ThenThrewException 'Build.+WorkingDirectory.+does not exist.'
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
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

Describe 'Invoke-WhiskeyTask.when given OnlyDuring parameter' {
    try
    {
        Init
        GivenMockTask -SupportsClean -SupportsInitialize

        foreach( $runMode in @('Clean', 'Initialize', 'Build') )
        {
            Context ('OnlyDuring is {0}' -f $runMode) {
                $TaskParameter = @{ 'OnlyDuring' = $runMode }
                WhenRunningTask 'MockTask' -Parameter $TaskParameter
                WhenRunningTask 'MockTask' -Parameter $TaskParameter -InRunMode 'Clean'
                WhenRunningTask 'MockTask' -Parameter $TaskParameter -InRunMode 'Initialize'
                ThenTaskRanWithParameter 'MockTask' @{ } -Times 1
                ThenTaskRanWithoutParameter 'OnlyDuring'
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

        foreach ($runMode in @('Clean', 'Initialize', 'Build'))
        {
            Context ('ExceptDuring is {0}' -f $runMode) {
                $TaskParameter = @{ 'ExceptDuring' = $runMode }
                WhenRunningTask 'MockTask' -Parameter $TaskParameter
                WhenRunningTask 'MockTask' -Parameter $TaskParameter -InRunMode 'Clean'
                WhenRunningTask 'MockTask' -Parameter $TaskParameter -InRunMode 'Initialize'
                ThenTaskRanWithParameter 'MockTask' @{ } -Times 2
                ThenTaskRanWithoutParameter 'ExceptDuring'
            }
        }
    }
    finally
    {
        RemoveMockTask
    }
}

Describe 'Invoke-WhiskeyTask.when given IfExists parameter and environment variable exists' {
    Init
    GivenMockTask
    GivenEnvironmentVariable 'fubar'
    try
    {
        $TaskParameter = @{ 'IfExists' = 'env:fubar' }
        WhenRunningTask 'MockTask' -Parameter $TaskParameter
        ThenTaskRanWithParameter 'MockTask' @{ } -Times 1
    }
    finally
    {
        Remove-Item -Path 'env:fubar'
    }
}

Describe 'Invoke-WhiskeyTask.when given IfExists parameter and environment variable exists does not exist' {
    Init
    GivenMockTask
    $TaskParameter = @{ 'IfExists' = 'env:snafu' }
    WhenRunningTask 'MockTask' -Parameter $TaskParameter
    ThenTaskNotRun 'MockTask'
}

Describe 'Invoke-WhiskeyTask.when given IfExists parameter and file exists' {
    Init
    GivenMockTask
    GivenFile 'fubar'
    $TaskParameter = @{ 'IfExists' = 'fubar' }
    WhenRunningTask 'MockTask' -Parameter $TaskParameter
    ThenTaskRanWithParameter 'MockTask' @{ } -Times 1
}

Describe 'Invoke-WhiskeyTask.when given IfExists parameter and file does not exist' {
    Init
    GivenMockTask
    $TaskParameter = @{ 'IfExists' = 'fubar' }
    WhenRunningTask 'MockTask' -Parameter $TaskParameter
    ThenTaskNotRun 'MockTask'
}

Describe 'Invoke-WhiskeyTask.when given UnlessExists parameter and environment variable exists' {
    Init
    GivenMockTask
    GivenEnvironmentVariable 'fubar'
    try
    {
        $TaskParameter = @{ 'UnlessExists' = 'env:fubar' }
        WhenRunningTask 'MockTask' -Parameter $TaskParameter
        ThenTaskNotRun 'MockTask'
    }
    finally
    {
        Remove-Item -Path 'env:fubar'
    }
}

Describe 'Invoke-WhiskeyTask.when given UnlessExists parameter and environment variable exists does not exist' {
    Init
    GivenMockTask
    $TaskParameter = @{ 'UnlessExists' = 'env:snafu' }
    WhenRunningTask 'MockTask' -Parameter $TaskParameter
    ThenTaskRanWithParameter 'MockTask' @{ } -Times 1
}

Describe 'Invoke-WhiskeyTask.when given UnlessExists parameter and file exists' {
    Init
    GivenMockTask
    GivenFile 'fubar'
    $TaskParameter = @{ 'UnlessExists' = 'fubar' }
    WhenRunningTask 'MockTask' -Parameter $TaskParameter
    ThenTaskNotRun 'MockTask'
}

Describe 'Invoke-WhiskeyTask.when given UnlessExists parameter and file does not exist' {
    Init
    GivenMockTask
    $TaskParameter = @{ 'UnlessExists' = 'fubar' }
    WhenRunningTask 'MockTask' -Parameter $TaskParameter
    ThenTaskRanWithParameter 'MockTask' @{ } -Times 1
}

Describe 'Invoke-WhiskeyTask.when given both OnlyDuring and ExceptDuring' {
    try
    {
        Init
        GivenMockTask -SupportsClean -SupportsInitialize
        WhenRunningTask 'MockTask' -Parameter @{ 'OnlyDuring' = 'Clean'; 'ExceptDuring' = 'Clean' } -ErrorAction SilentlyContinue
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
        GivenMockTask -SupportsClean -SupportsInitialize

        Context 'OnlyDuring is invalid' {
            WhenRunningTask 'MockTask' -Parameter @{ 'OnlyDuring' = 'InvalidValue' } -ErrorAction SilentlyContinue
            ThenThrewException 'Property ''OnlyDuring'' has an invalid value'
            ThenTaskNotRun 'MockTask'
        }

        Context 'ExceptDuring is invalid' {
            WhenRunningTask 'MockTask' -Parameter @{ 'ExceptDuring' = 'InvalidValue' } -ErrorAction SilentlyContinue
            ThenThrewException 'Property ''ExceptDuring'' has an invalid value'
            ThenTaskNotRun 'MockTask'
        }
    }
    finally
    {
        RemoveMockTask
    }
}

foreach( $commonPropertyName in @( 'OnlyBy', 'ExceptBy', 'OnlyDuring', 'ExceptDuring' ) )
{
    Describe ('Invoke-WhiskeyTask.when {0} property has variable for a value' -f $commonPropertyName) {
        Init
        $taskProperties = @{ }
        Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
        GivenVariable 'Fubar' 'Snafu'
        WhenRunningTask 'PowerShell' -Parameter @{ $commonPropertyName = '$(Fubar)' } -ErrorAction SilentlyContinue
        ThenThrewException 'invalid\ value:\ ''Snafu'''
    }
}

Describe ('Invoke-WhiskeyTask.when OnlyOnBranch property has variable for a value') {
    Init
    $taskProperties = @{ }
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenVariable 'Fubar' 'Snafu'
    GivenScmBranch 'Snafu'
    WhenRunningTask 'PowerShell' -Parameter @{ 'OnlyOnBranch' = '$(Fubar)' }
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' -ExpectedParameter @{ }
}

Describe ('Invoke-WhiskeyTask.when ExceptOnBranch property has variable for a value') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenVariable 'Fubar' 'Snafu'
    GivenScmBranch 'Snafu'
    WhenRunningTask 'PowerShell' -Parameter @{ 'ExceptOnBranch' = '$(Fubar)' }
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe ('Invoke-WhiskeyTask.when WorkingDirectory property has a variable for a value') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenWorkingDirectory 'Snafu'
    GivenVariable 'Fubar' 'Snafu'
    WhenRunningTask 'PowerShell' -Parameter @{ 'WorkingDirectory' = '$(Fubar)' }
    ThenTaskRanInWorkingDirectory 'Snafu'
}

foreach( $commonPropertyName in @( 'OnlyBy', 'ExceptBy', 'OnlyDuring', 'ExceptDuring' ) )
{
    Describe ('Invoke-WhiskeyTask.when {0} property comes from defaults' -f $commonPropertyName) {
        Init
        Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
        GivenDefaults @{ $commonPropertyName = 'Snafu' } -ForTask 'PowerShell'
        WhenRunningTask 'PowerShell' -Parameter @{ } -ErrorAction SilentlyContinue
        ThenThrewException 'invalid\ value:\ ''Snafu'''
    }
}

Describe ('Invoke-WhiskeyTask.when OnlyOnBranch property comes from defaults') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenDefaults @{ 'OnlyOnBranch' = 'Snafu' } -ForTask 'PowerShell'
    GivenScmBranch 'Snafu'
    WhenRunningTask 'PowerShell' -Parameter @{ }
    ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' -ExpectedParameter @{ }
}

Describe ('Invoke-WhiskeyTask.when ExceptOnBranch property comes from defaults') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenDefaults @{ 'ExceptOnBranch' = 'Snafu' } -ForTask 'PowerShell'
    GivenScmBranch 'Snafu'
    WhenRunningTask 'PowerShell' -Parameter @{ }
    ThenTaskNotRun 'Invoke-WhiskeyPowerShell'
}

Describe ('Invoke-WhiskeyTask.when WorkingDirectory property comes from defaults') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenWorkingDirectory 'Snafu'
    GivenDefaults @{ 'WorkingDirectory' = 'Snafu' } -ForTask 'PowerShell'
    WhenRunningTask 'PowerShell' -Parameter @{ }
    ThenTaskRanInWorkingDirectory 'Snafu'
}

Describe ('Invoke-WhiskeyTask.when WorkingDirectory property comes from defaults and default has a variable') {
    Init
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    GivenVariable 'Fubar' 'Snafu'
    GivenWorkingDirectory 'Snafu'
    GivenDefaults @{ 'WorkingDirectory' = '$(Fubar)' } -ForTask 'PowerShell'
    WhenRunningTask 'PowerShell' -Parameter @{ }
    ThenTaskRanInWorkingDirectory 'Snafu'
}

Describe 'Invoke-WhiskeyTask.when task requires tools' {
    Init
    Mock -CommandName 'Uninstall-WhiskeyTool' -ModuleName 'Whiskey'
    Mock -CommandName 'Install-WhiskeyTool' -ModuleName 'Whiskey'
    $parameter = @{ }
    WhenRunningTask 'ToolTask' -Parameter $parameter
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
    $parameter = @{ }
    WhenRunningTask 'ToolTask' -Parameter $parameter -InRunMode 'Initialize'
    ThenToolInstalled 'Node'
    ThenTaskNotRun
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
        WhenRunningTask 'ToolTask' -Parameter @{ } -InRunMode 'Clean'
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
        WhenRunningTask 'ToolTask' -Parameter @{} -InRunMode 'Clean'
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

Describe 'Invoke-WhiskeyTask.when a task runs another task' {
    try
    {
        function Global::PowerShellWrapperTask
        {
            [Whiskey.Task("PowerShellWrapperTask")]
            [CmdletBinding()]
            param(
                $TaskContext,
                $TaskParameter
            )

            Invoke-WhiskeyTask -TaskContext $TaskContext -Parameter $TaskParameter -Name 'PowerShell'
        }

        Init
        Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
        WhenRunningTask 'PowerShellWrapperTask' -Parameter @{ 'Path' = 'script.ps1' }
        ThenTaskRanWithParameter 'Invoke-WhiskeyPowerShell' @{ 'Path' = 'script.ps1' }
        ThenTempDirectoryCreated 'PowerShellWrapperTask'
        ThenTempDirectoryCreated 'PowerShell'
        ThenTempDirectoryRemoved 'PowerShellWrapperTask'
        ThenTempDirectoryRemoved 'PowerShell'
        ThenPipelineSucceeded
    }
    finally
    {
        Remove-Item -Path 'function:PowerShellWrapperTask' -ErrorAction Ignore
    }
}

function Global::ToolTaskWindows
{
    [Whiskey.Task("ToolTaskWindows",Platform=[Whiskey.Platform]::Windows)]
    [CmdletBinding()]
    param(
        $TaskContext,
        $TaskParameter
    )

    $script:taskProperties = $TaskParameter
    $script:taskRun = $true
}

function Global::ToolTaskLinux
{
    [Whiskey.Task("ToolTaskLinux",Platform=[Whiskey.Platform]::Linux)]
    [CmdletBinding()]
    param(
        $TaskContext,
        $TaskParameter
    )

    $script:taskProperties = $TaskParameter
    $script:taskRun = $true
}

function Global::ToolTaskMacOS
{
    [Whiskey.Task("ToolTaskMacOS",Platform=[Whiskey.Platform]::MacOS)]
    [CmdletBinding()]
    param(
        $TaskContext,
        $TaskParameter
    )

    $script:taskProperties = $TaskParameter
    $script:taskRun = $true
}

function Global::ToolTaskWindowsAndLinux
{
    [Whiskey.Task("ToolTaskWindowsAndLinux",Platform=([Whiskey.Platform]::Windows -bor [Whiskey.Platform]::Linux))]
    [CmdletBinding()]
    param(
        $TaskContext,
        $TaskParameter
    )

    $script:taskProperties = $TaskParameter
    $script:taskRun = $true
}

$currentPlatform = 'Windows'
if( $IsLinux )
{
    $currentPlatform = 'Linux'
}
elseif( $IsMacOS )
{
    $currentPlatform = 'MacOS'
}

Describe ('Invoke-WhiskeyTask.when running Windows-only task on {0} platform' -f $currentPlatform) {
    Init
    WhenRunningTask 'ToolTaskWindows' -Parameter @{} -ErrorAction SilentlyContinue
    if( $IsWindows )
    {
        ThenTaskRanWithParameter -ExpectedParameter @{}
    }
    else
    {
        ThenTaskNotRun 
        ThenThrewException -Pattern 'only\ supported\ on\ the\ Windows\ platform'
    }
}

Describe ('Invoke-WhiskeyTask.when running Linux-only task on {0} platform' -f $currentPlatform) {
    Init
    WhenRunningTask 'ToolTaskLinux' -Parameter @{} -ErrorAction SilentlyContinue
    if( $IsLinux )
    {
        ThenTaskRanWithParameter -ExpectedParameter @{}
    }
    else
    {
        ThenTaskNotRun 
        ThenThrewException -Pattern 'only\ supported\ on\ the\ Linux\ platform'
    }
}

Describe ('Invoke-WhiskeyTask.when running MacOS-only task on {0} platform' -f $currentPlatform) {
    Init
    WhenRunningTask 'ToolTaskMacOS' -Parameter @{} -ErrorAction SilentlyContinue
    if( $IsMacOS )
    {
        ThenTaskRanWithParameter -ExpectedParameter @{}
    }
    else
    {
        ThenTaskNotRun 
        ThenThrewException -Pattern 'only\ supported\ on\ the\ MacOS\ platform'
    }
}

Describe ('Invoke-WhiskeyTask.when running Windows or Linux only task on {0} platform' -f $currentPlatform) {
    Init
    WhenRunningTask 'ToolTaskWindowsAndLinux' -Parameter @{} -ErrorAction SilentlyContinue
    if( $IsMacOS )
    {
        ThenTaskNotRun 
        ThenThrewException -Pattern 'only\ supported\ on\ the\ Windows, Linux\ platform'
    }
    else
    {
        ThenTaskRanWithParameter -ExpectedParameter @{}
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and OnlyOnPlatform is Windows' -f $currentPlatform) {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ OnlyOnPlatform = 'Windows' }
    if( $IsWindows )
    {
        ThenTaskRanWithParameter 'MockTask' -ExpectedParameter @{}
    }
    else
    {
        ThenTaskNotRun -CommandName 'MockTask'
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and OnlyOnPlatform is Linux' -f $currentPlatform) {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ OnlyOnPlatform = 'Linux' }
    if( $IsLinux )
    {
        ThenTaskRanWithParameter 'MockTask' -ExpectedParameter @{}
    }
    else
    {
        ThenTaskNotRun -CommandName 'MockTask'
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and OnlyOnPlatform is MacOS' -f $currentPlatform) {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ OnlyOnPlatform = 'MacOS' }
    if( $IsMacOS )
    {
        ThenTaskRanWithParameter 'MockTask' -ExpectedParameter @{}
    }
    else
    {
        ThenTaskNotRun -CommandName 'MockTask'
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and OnlyOnPlatform is Windows,MacOS' -f $currentPlatform) {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ OnlyOnPlatform = @( 'Windows','MacOS' ) }
    if( $IsLinux )
    {
        ThenTaskNotRun -CommandName 'MockTask'
    }
    else
    {
        ThenTaskRanWithParameter 'MockTask' -ExpectedParameter @{}
    }
}

Describe ('Invoke-WhiskeyTask.when OnlyOnPlatform is invalid') {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ OnlyOnPlatform = 'Blarg' } -ErrorAction SilentlyContinue
    ThenTaskNotRun -CommandName 'MockTask'
    ThenThrewException ([regex]::Escape('Invalid platform "Blarg"'))
}

Describe ('Invoke-WhiskeyTask.when run on {0} and ExceptOnPlatform is Windows' -f $currentPlatform) {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ ExceptOnPlatform = 'Windows' }
    if( $IsWindows )
    {
        ThenTaskNotRun -CommandName 'MockTask'
    }
    else
    {
        ThenTaskRanWithParameter 'MockTask' -ExpectedParameter @{}
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and ExceptOnPlatform is Linux' -f $currentPlatform) {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ ExceptOnPlatform = 'Linux' }
    if( $IsLinux )
    {
        ThenTaskNotRun -CommandName 'MockTask'
    }
    else
    {
        ThenTaskRanWithParameter 'MockTask' -ExpectedParameter @{}
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and ExceptOnPlatform is MacOS' -f $currentPlatform) {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ ExceptOnPlatform = 'MacOS' }
    if( $IsMacOS )
    {
        ThenTaskNotRun -CommandName 'MockTask'
    }
    else
    {
        ThenTaskRanWithParameter 'MockTask' -ExpectedParameter @{}
    }
}

Describe ('Invoke-WhiskeyTask.when run on {0} and ExceptOnPlatform is Windows,MacOS' -f $currentPlatform) {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ ExceptOnPlatform = @( 'Windows','MacOS' ) }
    if( $IsLinux )
    {
        ThenTaskRanWithParameter 'MockTask' -ExpectedParameter @{}
    }
    else
    {
        ThenTaskNotRun -CommandName 'MockTask'
    }
}

Describe ('Invoke-WhiskeyTask.when ExceptOnPlatform is invalid') {
    Init
    GivenMockTask
    WhenRunningTask 'MockTask' -Parameter @{ ExceptOnPlatform = 'Blarg' } -ErrorAction SilentlyContinue
    ThenTaskNotRun -CommandName 'MockTask'
    ThenThrewException ([regex]::Escape('Invalid platform "Blarg"'))
}

Remove-Item -Path 'function:ToolTask' -ErrorAction Ignore
