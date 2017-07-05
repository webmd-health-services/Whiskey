#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$whiskeyYmlPath = $null
$runByDeveloper = $false
$runByBuildServer = $false

function GivenPublishingToBuildMasterFails
{
    Mock -CommandName 'New-WhiskeyBuildMasterPackage' -ModuleName 'Whiskey' -MockWith { throw 'Build Master Pipeline failed' }
}

function GivenPreviousBuildOutput
{
    New-Item -Path (Join-Path -Path ($whiskeyYmlPath | Split-Path) -ChildPath '.output\file.txt') -ItemType 'File' -Force
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

function GivenVersion
{
    param(
        $Version
    )

    $script:version = $Version
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

function ThenBuildFailed
{
    ThenCommitNotTagged
    ThenBuildStatusMarkedAsStarted
    ThenBuildStatusMarkedAsFailed
}

function ThenBuildOutputRemoved
{
    It ('should remove .output directory') {
        Join-Path -Path ($whiskeyYmlPath | Split-Path) -ChildPath '.output' | Should -Not -Exist
    }
}

function ThenBuildStatusSetTo
{
    param(
        [string]
        $ExpectedStatus
    )

    It ('should set commmit build status to ''{0}''' -f $ExpectedStatus) {
        Assert-MockCalled -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Status -eq $ExpectedStatus }
    }
}

function ThenBuildStatusMarkedAsCompleted
{
    ThenBuildStatusSetTo 'Completed'
}

function ThenBuildStatusMarkedAsStarted
{
    ThenBuildStatusSetTo 'Started'
    ThenContextPassedWhenSettingBuildStatus
}

function ThenBuildStatusMarkedAsFailed
{
    ThenBuildStatusSetTo 'Failed'
    ThenContextPassedWhenSettingBuildStatus
}

function ThenBuildSucceeded
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
            
    ThenBuildStatusMarkedAsStarted
    ThenBuildStatusMarkedAsCompleted
}

function ThenCommitNotTagged
{
    Assert-MockCalled -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey' -Times 0
}

function ThenCommitTagged
{
    Assert-MockCalled -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey' -Times 1
}

function ThenContextPassedWhenSettingBuildStatus
{
    It 'should pass context when setting build status' {
        Assert-MockCalled -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Context }
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

function WhenRunningBuild
{
    [CmdletBinding()]
    param(
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

    $context = New-WhiskeyTestContext -BuildConfiguration $configuration -ConfigurationPath $whiskeyYmlPath @optionalParams

    $Global:Error.Clear()
    $script:threwException = $false
    try
    {
        $cleanParam = @{}
        if( $WithCleanSwitch )
        {
            $cleanParam['Clean'] = $true
        }
        Invoke-WhiskeyBuild -Context $context @cleanParam
    }
    catch
    {
        $script:threwException = $true
        Write-Error $_
    }    
    # ThenBuildStatusMarkedAsStarted
    # 
    # 
    # if( $ThatFails )
    # {
    #     It 'should throw a terminating exception' {
    #         $threwException | Should Be $true
    #     }
    # 
    #     ThenBuildStatusMarkedAsFailed
    # }
    # else
    # {
    #     Assert-CommitTagged
    # }
}

Describe 'Invoke-WhiskeyBuild.when running an unknown task' {
    GivenWhiskeyYmlBuildFile -Yaml @'
BuildTasks:
    - FubarSnafu:
        Path: whiskey.yml
'@
    GivenRunByBuildServer
    WhenRunningBuild -ErrorAction SilentlyContinue
    ThenBuildFailed
    ThenThrewException 'not\ exist'
}

Describe 'Invoke-WhiskeyBuild.when a task fails' {
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
    New-MSBuildProject -FileName $project -ThatFails
    WhenRunningBuild
    ThenBuildFailed
    ThenDotNetProjectsCompilationFailed -ConfigurationPath $whiskeyYmlPath -ProjectName $project
    ThenNUnitTestsNotRun -ConfigurationPath $whiskeyYmlPath
}

Describe 'Invoke-WhiskeyBuild.when New-WhiskeyBuildMasterPackage fails' {
    GivenPublishingToBuildMasterFails
    $project = 'project.csproj'
    $assembly = 'assembly.dll'
    GivenWhiskeyYmlBuildFile -Yaml @'
BuildTasks:
'@
    GivenRunByBuildServer
    New-MSBuildProject -FileName $project 
    WhenRunningBuild -ErrorAction SilentlyContinue
    ThenBuildStatusMarkedAsFailed
    ThenBuildStatusMarkedAsStarted
    ThenCommitNotTagged
    ThenThrewException 'Build\ Master\ Pipeline\ failed'
}

Describe 'Invoke-WhiskeyBuild.when running with Clean switch' {
    GivenWhiskeyYmlBuildFile -Yaml @'
BuildTasks:
'@
    GivenPreviousBuildOutput
    GivenRunByDeveloper
    WhenRunningBuild -WithCleanSwitch
    ThenBuildOutputRemoved
}

Describe 'Invoke-WhiskeyBuild.when task has no properties' {
    GivenRunByDeveloper
    GivenWhiskeyYmlBuildFile @"
BuildTasks:
- PublishNodeModule
- PublishNodeModule:
"@
    Mock -CommandName 'Invoke-WhiskeyPublishNodeModuleTask' -Verifiable -ModuleName 'Whiskey'
    WhenRunningBuild
    ThenBuildSucceeded
    ThenCommitNotTagged
    
    It 'should still call the task' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyPublishNodeModuleTask' -ModuleName 'Whiskey' -Times 2
    }
}

# Tasks that should be called with the WhatIf parameter when run by developers
$whatIfTasks = @{ 'ProGetUniversalPackage' = $true; }
$tasks = Get-WhiskeyTasks
foreach( $taskName in ($tasks.Keys) )
{
    $functionName = $tasks[$taskName]

    Describe ('Invoke-WhiskeyBuild.when calling {0} task' -f $taskName) {

        function Assert-TaskCalled
        {
            param(
                [object]
                $WithContext,

                [Switch]
                $WithWhatIfSwitch
            )

            It 'should pass context to task' {
                Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'Whiskey' -ParameterFilter {
                    [object]::ReferenceEquals($TaskContext, $WithContext) 
                }
            }
            
            It 'should pass task parameters' {
                Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'Whiskey' -ParameterFilter {
                    return $TaskParameter.ContainsKey('Path') -and $TaskParameter['Path'] -eq $taskName
                }
            }

            if( $WithWhatIfSwitch )
            {
                It 'should use WhatIf switch' {
                    Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'Whiskey' -ParameterFilter {
                        $PSBoundParameters['WhatIf'] -eq $true
                    }
                }
            }
            else
            {
                It 'should not use WhatIf switch' {
                    Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'Whiskey' -ParameterFilter {
                        $PSBoundParameters.ContainsKey('WhatIf') -eq $false
                    }
                }
            }

            It 'should set build status' {
                Assert-MockCalled -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' 
            }
            It 'should set build status to in progress' {
                Assert-MockCalled -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' -ParameterFilter { $Status -eq 'Started' }
            }
            It 'should set build status to passed' {
                Assert-MockCalled -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' -ParameterFilter {  $Status -eq 'Completed' }
            }

            if( $WithContext.ByBuildServer )
            {
                It 'should tag the commit' {
                    Assert-MockCalled -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey' -Times 1
                }
            }
        }


        $version = '4.3.5-rc.1'
        $taskFunctionName = 'Invoke-Whiskey{0}Task' -f $taskName

        Mock -CommandName $taskFunctionName -ModuleName 'Whiskey' -Verifiable
        Mock -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey'
        Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
        Mock -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey' -Verifiable

        Context 'By Developer' {
            Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { return $false }
            $context = New-WhiskeyTestContext -ForTaskName $taskName -TaskParameter @{ 'Path' = $taskName } -ForDeveloper
            $context.ByDeveloper = $true
            $context.ByBuildServer = $false
            Invoke-WhiskeyBuild -Context $context
            $withWhatIfSwitchParam = @{ }
            if( $whatIfTasks.ContainsKey($taskName) )
            {
                $withWhatIfSwitchParam['WithWhatIfSwitch'] = $true
            }
            Assert-TaskCalled -WithContext $context @withWhatIfSwitchParam
        }

        Context 'By Jenkins' {
            Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { return $true }
            Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_BRANCH' } -MockWith { return $true }
            $context = New-WhiskeyTestContext -ForBuildServer -ForTaskName $taskName -TaskParameter @{ 'Path' = $taskName }
            $context.ByDeveloper = $false
            $context.ByBuildServer = $true
            Invoke-WhiskeyBuild -Context $context
            Assert-TaskCalled -WithContext $context
        }
    }
    
    Describe ('Invoke-WhiskeyBuild.when calling {0} task with Clean switch' -f $taskName) {
        $taskFunctionName = 'Invoke-Whiskey{0}Task' -f $taskName
        $context = New-WhiskeyTestContext -ForTaskName $taskName -TaskParameter @{ 'Path' = $taskName } -ForDeveloper
        Mock -CommandName $taskFunctionName -ModuleName 'Whiskey' -Verifiable

        Invoke-WhiskeyBuild -Context $context -Clean
        It 'should call task with active Clean switch' {
            Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'Whiskey' -ParameterFilter {
                $PSBoundParameters['Clean'] -eq $true
            }
        }
    }
}
