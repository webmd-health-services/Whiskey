
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$whiskeyYmlPath = $null
$context = $null
$warnings = $null

# So we can mock Whiskey's internal version.
function Invoke-WhiskeyPowerShell
{
}
function GivenFile
{
    param(
        [Parameter(Mandatory)]
        [String]$Name,

        [Parameter(Mandatory)]
        [String]$Content
    )

    $path = Join-Path -Path $TestDrive.FullName -ChildPath $Name
    $Content | Set-Content -Path $path
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

function GivenPlugins
{
    param(
        [String]$ForSpecificTask
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
        [String]$Yaml
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
        [String]$Named,

        [switch]$Not,

        [Parameter(Mandatory)]
        [switch]$Exists,

        [Parameter(Mandatory)]
        [String]$Because
    )

    Join-Path -Path $TestDrive.FullName -ChildPath $Named | Should -Not:$Not -Exist
}
function ThenPipelineFailed
{
    $threwException | Should -Be $true
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

function ThenNUnitTestsNotRun
{
    param(
    )

    Get-ChildItem -Path $context.OutputDirectory -Filter 'nunit2*.xml' | Should -BeNullOrEmpty
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

    $warnings | Should -Match $Pattern
}

function ThenThrewException
{
    param(
        $Pattern
    )

    $threwException | Should -Be $true
    $Global:Error | Should -Match $Pattern
}

function WhenRunningPipeline
{
    [CmdletBinding()]
    param(
        [String]$Name
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
    It 'should fail' {
        GivenWhiskeyYmlBuildFile -Yaml @'
Build:
    - FubarSnafu:
        Path: whiskey.yml
'@
        WhenRunningPipeline 'Build' -ErrorAction SilentlyContinue
        ThenPipelineFailed
        ThenThrewException 'not\ exist'
    }
}

Describe 'Pipeline.when a task fails' {
    It 'should fail' {
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
}

Describe 'Pipeline.when task has no properties' {
    It 'should run tasks' {
        GivenWhiskeyYmlBuildFile @"
Build:
- PublishNodeModule
- PublishNodeModule:
"@
        Mock -CommandName 'Publish-WhiskeyNodeModule' -Verifiable -ModuleName 'Whiskey'
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Publish-WhiskeyNodeModule' -ModuleName 'Whiskey' -Times 2
    }
}

Describe 'Pipeline.when task has a default property' {
    It 'should pass default property' {
        GivenWhiskeyYmlBuildFile @"
Build:
- Exec: This is a default property
"@
        Mock -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'This is a default property' }
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'This is a default property' }
    }
}

Describe 'Pipeline.when task has a default property with quoted arguments' {
    It 'should pass default property' {
        GivenWhiskeyYmlBuildFile @"
Build:
- Exec: someexec somearg
"@
        Mock -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec somearg' }
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec somearg' }
    }
}

Describe 'Pipeline.when task has a default property when entire string is quoted' {
    It 'should pass default property' {
        GivenWhiskeyYmlBuildFile @"
Build:
- Exec: 'someexec "some arg"'
"@
        Mock -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec "some arg"' }
        WhenRunningPipeline 'Build'
        ThenPipelineSucceeded
        Assert-MockCalled -CommandName 'Invoke-WhiskeyExec' -ModuleName 'Whiskey' -ParameterFilter { $TaskParameter[''] -eq 'someexec "some arg"' }
    }
}

Describe 'Pipeline.when pipeline does not exist' {
    It 'should fail' {
        GivenWhiskeyYmlBuildFile @"
"@
        WhenRunningPipeline 'Build' -ErrorAction SilentlyContinue
        ThenPipelineFailed
        ThenThrewException 'Pipeline\ ''Build''\ does\ not\ exist'
    }
}

Describe 'Pipeline.when pipeline is empty and not a YAML object' {
    It 'should write warning and succeed' {
        GivenWhiskeyYmlBuildFile @"
Build
"@
        WhenRunningPipeline 'Build' 
        ThenPipelineSucceeded
        ThenShouldWarn 'doesn''t\ have\ any\ tasks'
    }
}

Describe 'Pipeline.when pipeline is empty and is a YAML object' {
    It 'should write warning and succeed' {
        GivenWhiskeyYmlBuildFile @"
Build:
"@
        WhenRunningPipeline 'Build' 
        ThenPipelineSucceeded
        ThenShouldWarn 'doesn''t\ have\ any\ tasks'
    }
}

Describe 'Pipeline.when there are registered event handlers' {
    It 'should run plugins' {
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
}

Describe 'Pipeline.when there are task-specific registered event handlers' {
    It 'should run task plug-ins' {
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
}
