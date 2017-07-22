#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Tasks\Invoke-WhiskeyPowerShell.ps1' -Resolve)

$whiskeyYmlPath = $null
$context = $null
$warnings = $null

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

function WhenRunningPipeline
{
    [CmdletBinding()]
    param(
        [string]
        $Name
    )

    $environment = $PSCmdlet.ParameterSetName
    $configuration = 'FubarSnafu'
    $optionalParams = @{ }

    [SemVersion.SemanticVersion]$version = '5.4.1-prerelease+build'    

    $script:context = New-WhiskeyTestContext -BuildConfiguration $configuration -ConfigurationPath $whiskeyYmlPath -ForBuildServer -ForVersion $version
    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        Invoke-WhiskeyPipeline -Context $context -Name $Name -WarningVariable 'warnings'
        $script:warnings = $warnings
    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }    
}

Describe 'Invoke-WhiskeyPipeline.when running an unknown task' {
    GivenWhiskeyYmlBuildFile -Yaml @'
BuildTasks:
    - FubarSnafu:
        Path: whiskey.yml
'@
    WhenRunningPipeline 'BuildTasks' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenThrewException 'not\ exist'
}

Describe 'Invoke-WhiskeyPipeline.when a task fails' {
    $project = 'project.csproj'
    $assembly = 'assembly.dll'
    GivenWhiskeyYmlBuildFile -Yaml @'
BuildTasks:
- PowerShell:
    Path: idonotexist.ps1
- NUnit2:
    Path: assembly.dll
'@
    GivenFailingMSBuildProject $project
    WhenRunningPipeline 'BuildTasks' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenDotNetProjectsCompilationFailed -ConfigurationPath $whiskeyYmlPath -ProjectName $project
    ThenNUnitTestsNotRun -ConfigurationPath $whiskeyYmlPath
}

Describe 'Invoke-WhiskeyPipeline.when task has no properties' {
    GivenWhiskeyYmlBuildFile @"
BuildTasks:
- PublishNodeModule
- PublishNodeModule:
"@
    Mock -CommandName 'Publish-WhiskeyNodeModule' -Verifiable -ModuleName 'Whiskey'
    WhenRunningPipeline 'BuildTasks'
    ThenPipelineSucceeded
    
    It 'should still call the task' {
        Assert-MockCalled -CommandName 'Publish-WhiskeyNodeModule' -ModuleName 'Whiskey' -Times 2
    }
}

Describe 'Invoke-WhiskeyPipeline.when pipeline does not exist' {
    GivenWhiskeyYmlBuildFile @"
"@
    WhenRunningPipeline 'BuildTasks' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenThrewException 'Pipeline\ ''BuildTasks''\ does\ not\ exist'
}

Describe 'Invoke-WhiskeyPipeline.when pipeline is empty and not a YAML object' {
    GivenWhiskeyYmlBuildFile @"
BuildTasks
"@
    WhenRunningPipeline 'BuildTasks' 
    ThenPipelineSucceeded
    ThenShouldWarn 'doesn''t\ have\ any\ tasks'
}

Describe 'Invoke-WhiskeyPipeline.when pipeline is empty and is a YAML object' {
    GivenWhiskeyYmlBuildFile @"
BuildTasks:
"@
    WhenRunningPipeline 'BuildTasks' 
    ThenPipelineSucceeded
    ThenShouldWarn 'doesn''t\ have\ any\ tasks'
}

Describe 'Invoke-WhiskeyPipeline.when there are registered event handlers' {
    GivenWhiskeyYmlBuildFile @"
BuildTasks:
- PowerShell:
    Path: somefile.ps1
"@
    GivenPlugins
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'

    WhenRunningPipeline 'BuildTasks'
    ThenPipelineSucceeded
    ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' }
}

Describe 'Invoke-WhiskeyPipeline.when there are task-specific registered event handlers' {
    GivenWhiskeyYmlBuildFile @"
BuildTasks:
- PowerShell:
    Path: somefile.ps1
- MSBuild:
    Path: fubar.ps1
"@
    GivenPlugins -ForSpecificTask 'PowerShell'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    Mock -CommandName 'Invoke-WhiskeyMsBuildTask' -ModuleName 'Whiskey'

    WhenRunningPipeline 'BuildTasks'
    ThenPipelineSucceeded
    ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' }
    ThenPluginsRan -ForTaskNamed 'MSBuild' -Times 0
}

# Tasks that should be called with the WhatIf parameter when run by developers
$tasks = Get-WhiskeyTask
foreach( $task in $tasks )
{
    $taskName = $task.Name
    $functionName = $task.CommandName

    Describe ('Invoke-WhiskeyPipeline.when calling {0} task' -f $taskName) {

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

        GivenWhiskeyYmlBuildFile $whiskeyYml
        WhenRunningPipeline $pipelineName
        ThenPipelineSucceeded
        Assert-TaskCalled
    }
}
