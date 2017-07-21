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
        $TaskParameter,

        [Switch]
        $Clean
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
        $TaskParameter,

        [Switch]
        $Clean
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
        $ConfigurationPath
    )

    It 'should not run NUnit tests' {
        $ConfigurationPath | Split-Path | ForEach-Object { Get-WhiskeyOutputDirectory -WorkingDirectory $_ } | Get-ChildItem -Filter 'nunit2*.xml' | Should BeNullOrEmpty
    }
}

function ThenPluginsRan
{
    param(
        $ForTaskNamed,

        $WithParameter,

        [Switch]
        $InCleanMode,

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
                Assert-MockCalled -CommandName $pluginName -ModuleName 'Whiskey' -ParameterFilter { 
                    #$DebugPreference = 'Continue'
                    Write-Debug ('Clean  expected  {0}' -f $InCleanMode.IsPresent)
                    Write-Debug ('       actual    {0}' -f [bool]$Clean)
                    [bool]$Clean -eq $InCleanMode.IsPresent
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

        [Switch]
        $WithCleanSwitch
    )

    Mock -CommandName 'Invoke-PreTaskPlugin' -ModuleName 'Whiskey'
    Mock -CommandName 'invoke-PostTaskPlugin' -ModuleName 'Whiskey'

    $script:context = [pscustomobject]@{
                                            ConfigurationPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml'
                                            PipelineName = 'Build';
                                            TaskName = $null;
                                            TaskIndex = 1;
                                            BuildRoot = $TestDrive.FullName;
                                            TaskDefaults = $taskDefaults;
                                       }

    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        $cleanParam = @{}
        if( $WithCleanSwitch )
        {
            $cleanParam['Clean'] = $true
        }
        Invoke-WhiskeyTask -TaskContext $context -Name $Name -Parameter $Parameter @cleanParam -WarningVariable 'warnings'
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
    Context 'not in clean mode' {
        Init
        GivenPlugins
        Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
        WhenRunningTask 'PowerShell' -Parameter @{ Path = 'somefile.ps1' }
        ThenPipelineSucceeded
        ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' }
    }
    Context 'in clean mode' {
        Init
        GivenPlugins
        Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'

        WhenRunningTask 'PowerShell' -Parameter @{ 'Path' = 'somefile.ps1' } -WithCleanSwitch
        ThenPipelineSucceeded
        ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' } -InCleanMode
    }
}

Describe 'Invoke-WhiskeyTask.when there are task-specific registered event handlers' {
    Init
    GivenPlugins -ForSpecificTask 'PowerShell'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    Mock -CommandName 'Invoke-WhiskeyMsBuildTask' -ModuleName 'Whiskey'
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

# Tasks that should be called with the WhatIf parameter when run by developers
$tasks = Get-WhiskeyTasks
foreach( $taskName in ($tasks.Keys) )
{
    $functionName = $tasks[$taskName]

    Describe ('Invoke-WhiskeyTask.when calling {0} task' -f $taskName) {

        function Assert-TaskCalled
        {
            param(
                [Switch]
                $WithCleanSwitch
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

            if( $WithCleanSwitch )
            {
                It 'should use Clean switch' {
                    Assert-MockCalled -CommandName $functionName -ModuleName 'Whiskey' -ParameterFilter {
                        $PSBoundParameters['Clean'] -eq $true
                    }
                }
            }
            else
            {
                It 'should not use Clean switch' {
                    Assert-MockCalled -CommandName $functionName -ModuleName 'Whiskey' -ParameterFilter {
                        $PSBoundParameters.ContainsKey('Clean') -eq $false
                    }
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

        Context 'In Default Mode' {
            Init
            WhenRunningTask $taskName -Parameter @{ Path = $taskName }
            ThenPipelineSucceeded
            Assert-TaskCalled
        }

        Context 'In Clean Mode' {
            Init
            WhenRunningTask $taskName -Parameter @{ Path = $taskName } -WithCleanSwitch
            ThenPipelineSucceeded
            Assert-TaskCalled -WithCleanSwitch
        }
    }
}
