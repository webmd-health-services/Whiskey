#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$whiskeyYmlPath = $null
$runByDeveloper = $false
$runByBuildServer = $false
$context = $null
$warnings = $null

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
        $Name,

        [Switch]
        $WithCleanSwitch
    )

    $environment = $PSCmdlet.ParameterSetName
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $true }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = '80' } } -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = 'origin/develop' } } -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = 'deadbeefdeadbeefdeadbeefdeadbeef' } } -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }

    Mock -CommandName 'Test-Path' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $true }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = '80' } } -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = 'origin/develop' } } -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = 'deadbeefdeadbeefdeadbeefdeadbeef' } } -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }

    Mock -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' -Verifiable
    Mock -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey' 

    $configuration = 'FubarSnafu'
    $optionalParams = @{ }
    if( $runByBuildServer )
    {
        $optionalParams['ForBuildServer'] = $true
    }

    if( $runByDeveloper )
    {
        $optionalParams['ForDeveloper'] = $true
    }

    [SemVersion.SemanticVersion]$version = '5.4.1-prerelease+build'    
    $optionalParams['ForVersion'] = $Version

    Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return $Version }.GetNewClosure()
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_BRANCH' } -MockWith { return $true }

    $script:context = New-WhiskeyTestContext -BuildConfiguration $configuration -ConfigurationPath $whiskeyYmlPath @optionalParams

    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        $cleanParam = @{}
        if( $WithCleanSwitch )
        {
            $cleanParam['Clean'] = $true
        }
        Invoke-WhiskeyPipeline -Context $context -Name $Name @cleanParam -WarningVariable 'warnings'
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
    GivenRunByBuildServer
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
    GivenRunByBuildServer
    GivenFailingMSBuildProject $project
    WhenRunningPipeline 'BuildTasks' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenDotNetProjectsCompilationFailed -ConfigurationPath $whiskeyYmlPath -ProjectName $project
    ThenNUnitTestsNotRun -ConfigurationPath $whiskeyYmlPath
}

Describe 'Invoke-WhiskeyPipeline.when task has no properties' {
    GivenRunByDeveloper
    GivenWhiskeyYmlBuildFile @"
BuildTasks:
- PublishNodeModule
- PublishNodeModule:
"@
    Mock -CommandName 'Invoke-WhiskeyPublishNodeModuleTask' -Verifiable -ModuleName 'Whiskey'
    WhenRunningPipeline 'BuildTasks'
    ThenPipelineSucceeded
    
    It 'should still call the task' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyPublishNodeModuleTask' -ModuleName 'Whiskey' -Times 2
    }
}

Describe 'Invoke-WhiskeyPipeline.when pipeline does not exist' {
    GivenRunByDeveloper
    GivenWhiskeyYmlBuildFile @"
"@
    WhenRunningPipeline 'BuildTasks' -ErrorAction SilentlyContinue
    ThenPipelineFailed
    ThenThrewException 'Pipeline\ ''BuildTasks''\ does\ not\ exist'
}

Describe 'Invoke-WhiskeyPipeline.when pipeline is empty and not a YAML object' {
    GivenRunByDeveloper
    GivenWhiskeyYmlBuildFile @"
BuildTasks
"@
    WhenRunningPipeline 'BuildTasks' 
    ThenPipelineSucceeded
    ThenShouldWarn 'doesn''t\ have\ any\ tasks'
}

Describe 'Invoke-WhiskeyPipeline.when pipeline is empty and is a YAML object' {
    GivenRunByDeveloper
    GivenWhiskeyYmlBuildFile @"
BuildTasks:
"@
    WhenRunningPipeline 'BuildTasks' 
    ThenPipelineSucceeded
    ThenShouldWarn 'doesn''t\ have\ any\ tasks'
}

# Tasks that should be called with the WhatIf parameter when run by developers
$tasks = Get-WhiskeyTasks
foreach( $taskName in ($tasks.Keys) )
{
    $functionName = $tasks[$taskName]

    Describe ('Invoke-WhiskeyPipeline.when calling {0} task' -f $taskName) {

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


        # $version = '4.3.5-rc.1'
        # $functionName = 'Invoke-Whiskey{0}Task' -f $taskName

        Mock -CommandName $functionName -ModuleName 'Whiskey'
        # Mock -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey'
        # Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
        # Mock -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey' -Verifiable

        $pipelineName = 'BuildTasks'
        $whiskeyYml = (@'
{0}:
- {1}:
    Path: {1}
'@ -f $pipelineName,$taskName)

        Context 'By Developer' {
            GivenRunByDeveloper
            GivenWhiskeyYmlBuildFile $whiskeyYml
            WhenRunningPipeline $pipelineName
            ThenPipelineSucceeded
            Assert-TaskCalled
            # Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { return $false }
            # $context = New-WhiskeyTestContext -ForTaskName $taskName -TaskParameter @{ 'Path' = $taskName } -ForDeveloper
            # $context.ByDeveloper = $true
            # $context.ByBuildServer = $false
            # Invoke-WhiskeyPipeline -Context $context -Name 'BuildTasks'
        }

        Context 'By Jenkins' {
            GivenRunByBuildServer
            GivenWhiskeyYmlBuildFile $whiskeyYml
            WhenRunningPipeline $pipelineName
            ThenPipelineSucceeded
            Assert-TaskCalled
        }
    
        Context 'With Clean Switch' {
            GivenRunByDeveloper
            GivenWhiskeyYmlBuildFile $whiskeyYml
            WhenRunningPipeline $pipelineName -WithCleanSwitch
            ThenPipelineSucceeded
            Assert-TaskCalled -WithCleanSwitch
        }
    }
}
