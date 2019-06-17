
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Tasks\Invoke-WhiskeyPowerShell.ps1' -Resolve)

$whiskeyYmlPath = $null
$context = $null
$warnings = $null

function GivenFile
{
    param(
        [Parameter(Mandatory)]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [string]
        $Content
    )

    $path = Join-Path -Path $TestDrive.FullName -ChildPath $Name
    $Content | Set-Content -Path $path
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

function ThenFile
{
    param(
        [Parameter(Mandatory)]
        [string]
        $Named,

        [Switch]
        $Not,

        [Parameter(Mandatory)]
        [Switch]
        $Exists,

        [Parameter(Mandatory)]
        [string]
        $Because
    )

    It $Because {
        Join-Path -Path $TestDrive.FullName -ChildPath $Named | Should -Not:$Not -Exist
    }
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
        Get-ChildItem -Path $context.OutputDirectory -Filter 'nunit2*.xml' | Should BeNullOrEmpty
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

    $script:context = New-WhiskeyTestContext -ConfigurationPath $whiskeyYmlPath -ForBuildServer -ForVersion $version
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

Describe 'Pipeline.when running an unknown task' {
    GivenWhiskeyYmlBuildFile -Yaml @'
Build:
    - FubarSnafu:
        Path: whiskey.yml
'@
    WhenRunningPipeline 'Build' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenThrewException 'not\ exist'
}

Describe 'Pipeline.when a task fails' {
    GivenFile 'ishouldnotrun.ps1' @'
New-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'iran.txt')
'@
    GivenWhiskeyYmlBuildFile -Yaml @'
Build:
- PowerShell:
    Path: idonotexist.ps1
- PowerShell:
    Path: ishouldnotrun.ps1
'@
    WhenRunningPipeline 'Build' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenFile 'iran.txt' -Not -Exists -Because 'should not execute additional tasks'
}

Describe 'Pipeline.when task has no properties' {
    GivenWhiskeyYmlBuildFile @"
Build:
- PublishNodeModule
- PublishNodeModule:
"@
    Mock -CommandName 'Publish-WhiskeyNodeModule' -Verifiable -ModuleName 'Whiskey'
    WhenRunningPipeline 'Build'
    ThenPipelineSucceeded
    
    It 'should still call the task' {
        Assert-MockCalled -CommandName 'Publish-WhiskeyNodeModule' -ModuleName 'Whiskey' -Times 2
    }
}

Describe 'Pipeline.when task has a default property' {
    GivenWhiskeyYmlBuildFile @"
Build:
- Exec: This is a default property
"@
    Mock -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'This is a default property' }
    WhenRunningPipeline 'Build'
    ThenPipelineSucceeded

    It 'should call the task with the default property' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'This is a default property' }
    }
}

Describe 'Pipeline.when task has a default property with quoted arguments' {
    GivenWhiskeyYmlBuildFile @"
Build:
- Exec: someexec somearg
"@
    Mock -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec somearg' }
    WhenRunningPipeline 'Build'
    ThenPipelineSucceeded

    It 'should call the task with the default property' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec somearg' }
    }
}

Describe 'Pipeline.when task has a default property when entire string is quoted' {
    GivenWhiskeyYmlBuildFile @"
Build:
- Exec: 'someexec "some arg"'
"@
    Mock -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec "some arg"' }
    WhenRunningPipeline 'Build'
    ThenPipelineSucceeded

    It 'should call the task with the default property' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec "some arg"' }
    }
}

Describe 'Pipeline.when pipeline does not exist' {
    GivenWhiskeyYmlBuildFile @"
"@
    WhenRunningPipeline 'Build' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenThrewException 'Pipeline\ ''Build''\ does\ not\ exist'
}

Describe 'Pipeline.when pipeline is empty and not a YAML object' {
    GivenWhiskeyYmlBuildFile @"
Build
"@
    WhenRunningPipeline 'Build' 
    ThenPipelineSucceeded
    ThenShouldWarn 'doesn''t\ have\ any\ tasks'
}

Describe 'Pipeline.when pipeline is empty and is a YAML object' {
    GivenWhiskeyYmlBuildFile @"
Build:
"@
    WhenRunningPipeline 'Build' 
    ThenPipelineSucceeded
    ThenShouldWarn 'doesn''t\ have\ any\ tasks'
}

Describe 'Pipeline.when there are registered event handlers' {
    GivenWhiskeyYmlBuildFile @"
Build:
- PowerShell:
    Path: somefile.ps1
"@
    GivenPlugins
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'

    WhenRunningPipeline 'Build'
    ThenPipelineSucceeded
    ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' }
}

Describe 'Pipeline.when there are task-specific registered event handlers' {
    GivenWhiskeyYmlBuildFile @"
Build:
- PowerShell:
    Path: somefile.ps1
- Version:
    Version: 0.0.0
"@
    GivenPlugins -ForSpecificTask 'PowerShell'
    Mock -CommandName 'Invoke-WhiskeyPowerShell' -ModuleName 'Whiskey'
    Mock -CommandName 'Set-WhiskeyVersion' -ModuleName 'Whiskey'

    WhenRunningPipeline 'Build'
    ThenPipelineSucceeded
    ThenPluginsRan -ForTaskNamed 'PowerShell' -WithParameter @{ 'Path' = 'somefile.ps1' }
    ThenPluginsRan -ForTaskNamed 'Version' -Times 0
}
