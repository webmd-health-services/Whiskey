#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

#region Assertions
function Assert-CommitStatusSetTo
{
    param(
        [string]
        $ExpectedStatus
    )

    It ('should set commmit build status to ''{0}''' -f $ExpectedStatus) {
        Assert-MockCalled -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Status -eq $ExpectedStatus }
    }

    It 'should pass context when setting build status' {
        Assert-MockCalled -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Context }
    }
}

function Assert-CommitMarkedAsInProgress
{
    Assert-CommitStatusSetTo 'Started'
}

function Assert-CommitMarkedAsFailed
{
    Assert-CommitStatusSetTo 'Failed'
}

function Assert-DotNetProjectsCompilationFailed
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

function Assert-NUnitTestsNotRun
{
    param(
        $ConfigurationPath
    )

    It 'should not run NUnit tests' {
        $ConfigurationPath | Split-Path | ForEach-Object { Get-WhiskeyOutputDirectory -WorkingDirectory $_ } | Get-ChildItem -Filter 'nunit2*.xml' | Should BeNullOrEmpty
    }
}
#endregion

function Assert-CommitTagged
{
    Assert-MockCalled -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey' -Times 1
}

function Invoke-Build
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Dev')]
        [Switch]
        $ByJenkins,

        [string]
        $WithConfig,

        [Switch]
        $ThatFails,

        [SemVersion.SemanticVersion]
        $Version = '5.4.1-prerelease+build'
    )

    $environment = $PSCmdlet.ParameterSetName
    New-MockBuildServer
    New-MockBitbucketServer

    $configuration = 'FubarSnafu'
    $optionalParams = @{ }
    if( $ByJenkins )
    {
        $optionalParams['ForBuildServer'] = $true
    }

    if( $Version )
    {
        $optionalParams['ForVersion'] = $Version
    }

    Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return $Version }.GetNewClosure()
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:GIT_BRANCH' } -MockWith { return $true }

    $context = New-WhiskeyTestContext -BuildConfiguration $configuration -ConfigurationPath $WithConfig @optionalParams

    $threwException = $false
    try
    {
        Invoke-WhiskeyBuild -Context $context
    }
    catch
    {
        $threwException = $true
        Write-Error $_
    }    
    Assert-CommitMarkedAsInProgress

    
    if( $ThatFails )
    {
        It 'should throw a terminating exception' {
            $threwException | Should Be $true
        }

        Assert-CommitMarkedAsFailed
    }
    else
    {
        Assert-CommitTagged
    }
}

#region Mocks
function New-MockBitbucketServer
{
    Mock -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey' -Verifiable
    Mock -CommandName 'Publish-WhiskeyTag' -ModuleName 'Whiskey' 
}

function New-MockBuildServer
{
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $true }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = '80' } } -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = 'origin/develop' } } -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = 'deadbeefdeadbeefdeadbeefdeadbeef' } } -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }

    Mock -CommandName 'Test-Path' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $true }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = '80' } } -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = 'origin/develop' } } -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = 'deadbeefdeadbeefdeadbeefdeadbeef' } } -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }
}

function New-MockDeveloperEnvironment
{
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $false }
    Mock -CommandName 'Test-Path' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $false }
}


function New-TestWhiskeyBuildFile
{
    param(
        [Parameter(ParameterSetName='WithRawYaml')]
        [string]
        $Yaml
    )

    $config = $null
    $root = (Get-Item -Path 'TestDrive:').FullName
    $whiskeyymlpath = Join-Path -Path $root -ChildPath 'whiskey.yml'
    $Yaml | Set-Content -Path $whiskeyymlpath
    return $whiskeyymlpath
}
#endregion

Describe 'Invoke-WhiskeyBuild.when running an unknown task' {
    $configPath = New-TestWhiskeyBuildFile -Yaml @'
BuildTasks:
    - FubarSnafu:
        Path: whiskey.yml
'@
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    It 'should write an error' {
        $Global:Error[0] | Should Match 'not exist'
    }
}

Describe 'Invoke-WhiskeyBuild.when a task fails' {
    $project = 'project.csproj'
    $assembly = 'assembly.dll'
    $configPath = New-TestWhiskeyBuildFile -Yaml @'
BuildTasks:
- PowerShell:
    Path: idonotexist.ps1
- NUnit2:
    Path: assembly.dll
'@

    New-MSBuildProject -FileName $project -ThatFails

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails 2>&1

    Assert-DotNetProjectsCompilationFailed -ConfigurationPath $configPath -ProjectName $project
    Assert-NUnitTestsNotRun -ConfigurationPath $configPath
}

Describe 'Invoke-WhiskeyBuild.when New-WhiskeyBuildMasterPackage fails' {
    Mock -CommandName 'New-WhiskeyBuildMasterPackage' -ModuleName 'Whiskey' -MockWith `
        { throw 'Build Master Pipeline failed' }
    $project = 'project.csproj'
    $assembly = 'assembly.dll'
    $configPath = New-TestWhiskeyBuildFile -Yaml @'
BuildTasks:
'@

    New-MSBuildProject -FileName $project 
    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue
        
    it ( 'should call New-WhiskeyBuildMasterPackage mock once' ){
        Assert-MockCalled -CommandName 'New-WhiskeyBuildMasterPackage' -ModuleName 'Whiskey' -Times 1     
    }
}

Describe 'Invoke-WhiskeyBuild.when running with Clean switch' {
    $context = New-WhiskeyTestContext -ForDeveloper
    $context.Configuration = @{ 'BuildTasks' = @( ) }
    Invoke-WhiskeyBuild -Context $context -Clean
    $withWhatIfSwitchParam = @{ }

    it( 'should remove .output dir'){
        $context.OutputDirectory | should not exist
    }
}

Describe 'Invoke-WhiskeyBuild.when task has no properties' {
    $context = New-WhiskeyTestContext -ForDeveloper -ForYaml @"
BuildTasks:
- PublishNodeModule
- PublishNodeModule:
"@
    $Global:Error.Clear()
    Mock -CommandName 'Invoke-WhiskeyPublishNodeModuleTask' -Verifiable -ModuleName 'Whiskey'
    Invoke-WhiskeyBuild -Context $context
    It 'should not write an error' {
        $Global:Error | Should -BeNullOrEmpty
    }
    It 'should call the task' {
        Assert-MockCalled -CommandName 'Invoke-WhiskeyPublishNodeModuleTask' -ModuleName 'Whiskey' -Times 2
    }
}

# Tasks that should be called with the WhatIf parameter when run by developers
$whatIfTasks = @{ 'ProGetUniversalPackage' = $true; }
foreach( $functionName in (Get-Command -Module 'Whiskey' -Name 'Invoke-Whiskey*Task' | Sort-Object -Property 'Name') )
{
    $taskName = $functionName -replace '^Invoke-Whiskey(.*)Task$','$1'

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


