#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

#region Assertions
function Assert-CommitStatusSetTo
{
    param(
        [string]
        $ExpectedStatus
    )

    It ('should set commmit build status to ''{0}''' -f $ExpectedStatus) {
        Assert-MockCalled -CommandName 'Set-WhsCIBuildStatus' -ModuleName 'WhsCI' -Times 1 -ParameterFilter { $Status -eq $ExpectedStatus }
    }

    It 'should pass context when setting build status' {
        Assert-MockCalled -CommandName 'Set-WhsCIBuildStatus' -ModuleName 'WhsCI' -Times 1 -ParameterFilter { $Context }
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
        $ConfigurationPath | Split-Path | ForEach-Object { Get-WhsCIOutputDirectory -WorkingDirectory $_ } | Get-ChildItem -Filter 'nunit2*.xml' | Should BeNullOrEmpty
    }
}
#endregion

function Assert-CommitTagged
{
    Assert-MockCalled -CommandName 'Publish-WhsCITag' -ModuleName 'WhsCI' -Times 1
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

    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return $Version }.GetNewClosure()
    Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -ParameterFilter { $Path -eq 'env:GIT_BRANCH' } -MockWith { return $true }

    $context = New-WhsCITestContext -BuildConfiguration $configuration -ConfigurationPath $WithConfig @optionalParams

    $threwException = $false
    try
    {
        Invoke-WhsCIBuild -Context $context
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
    Mock -CommandName 'Set-WhsCIBuildStatus' -ModuleName 'WhsCI' -Verifiable
    Mock -CommandName 'Publish-WhsCITag' -ModuleName 'WhsCI' 
}

function New-MockBuildServer
{
    Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $true }
    Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = '80' } } -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = 'origin/develop' } } -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = 'deadbeefdeadbeefdeadbeefdeadbeef' } } -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }

    Mock -CommandName 'Test-Path' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $true }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = '80' } } -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = 'origin/develop' } } -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = 'deadbeefdeadbeefdeadbeefdeadbeef' } } -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }
}

function New-MockDeveloperEnvironment
{
    Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $false }
    Mock -CommandName 'Test-Path' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { $false }
}


function New-TestWhsBuildFile
{
    param(
        [Parameter(ParameterSetName='WithRawYaml')]
        [string]
        $Yaml
    )

    $config = $null
    $root = (Get-Item -Path 'TestDrive:').FullName
    $whsbuildymlpath = Join-Path -Path $root -ChildPath 'whsbuild.yml'
    $Yaml | Set-Content -Path $whsbuildymlpath
    return $whsbuildymlpath
}
#endregion

Describe 'Invoke-WhsCIBuild.when running an unknown task' {
    $configPath = New-TestWhsBuildFile -Yaml @'
BuildTasks:
    - FubarSnafu:
        Path: whsbuild.yml
'@
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    It 'should write an error' {
        $Global:Error[0] | Should Match 'not exist'
    }
}

Describe 'Invoke-WhsCIBuild.when a task fails' {
    $project = 'project.csproj'
    $assembly = 'assembly.dll'
    $configPath = New-TestWhsBuildFile -Yaml @'
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

Describe 'Invoke-WhsCIBuild.when New-WhsCIBuildMasterPackage fails' {
    Mock -CommandName 'New-WhsCIBuildMasterPackage' -ModuleName 'WhsCI' -MockWith `
        { throw 'Build Master Pipeline failed' }
    $project = 'project.csproj'
    $assembly = 'assembly.dll'
    $configPath = New-TestWhsBuildFile -Yaml @'
BuildTasks:
'@

    New-MSBuildProject -FileName $project 
    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue
        
    it ( 'should call New-WhsCIBuildMasterPackage mock once' ){
        Assert-MockCalled -CommandName 'New-WhsCIBuildMasterPackage' -ModuleName 'WhsCI' -Times 1     
    }
}

Describe 'Invoke-WhsCIBuild.when running with Clean switch' {
    $context = New-WhsCITestContext -ForDeveloper
    $context.Configuration = @{ }
    Invoke-WhsCIBuild -Context $context -Clean
    $withWhatIfSwitchParam = @{ }

    it( 'should remove .output dir'){
        $context.OutputDirectory | should not exist
    }
}

Describe 'Invoke-WhsCIBuild.when task has no properties' {
    $context = New-WhsCITestContext -ForDeveloper -ForYaml @"
BuildTasks:
- PublishNodeModule
- PublishNodeModule:
"@
    $Global:Error.Clear()
    Mock -CommandName 'Invoke-WhsCIPublishNodeModuleTask' -Verifiable -ModuleName 'WhsCI'
    Invoke-WhsCIBuild -Context $context
    It 'should not write an error' {
        $Global:Error | Should -BeNullOrEmpty
    }
    It 'should call the task' {
        Assert-MockCalled -CommandName 'Invoke-WhsCIPublishNodeModuleTask' -ModuleName 'WhsCI' -Times 2
    }
}

# Tasks that should be called with the WhatIf parameter when run by developers
$whatIfTasks = @{ 'ProGetUniversalPackage' = $true; }
foreach( $functionName in (Get-Command -Module 'WhsCI' -Name 'Invoke-WhsCI*Task' | Sort-Object -Property 'Name') )
{
    $taskName = $functionName -replace '^Invoke-WhsCI(.*)Task$','$1'

    Describe ('Invoke-WhsCIBuild.when calling {0} task' -f $taskName) {

        function Assert-TaskCalled
        {
            param(
                [object]
                $WithContext,

                [Switch]
                $WithWhatIfSwitch
            )

            It 'should pass context to task' {
                Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'WhsCI' -ParameterFilter {
                    [object]::ReferenceEquals($TaskContext, $WithContext) 
                }
            }
            
            It 'should pass task parameters' {
                Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'WhsCI' -ParameterFilter {
                    return $TaskParameter.ContainsKey('Path') -and $TaskParameter['Path'] -eq $taskName
                }
            }

            if( $WithWhatIfSwitch )
            {
                It 'should use WhatIf switch' {
                    Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'WhsCI' -ParameterFilter {
                        $PSBoundParameters['WhatIf'] -eq $true
                    }
                }
            }
            else
            {
                It 'should not use WhatIf switch' {
                    Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'WhsCI' -ParameterFilter {
                        $PSBoundParameters.ContainsKey('WhatIf') -eq $false
                    }
                }
            }

            It 'should set build status' {
                Assert-MockCalled -CommandName 'Set-WhsCIBuildStatus' -ModuleName 'WhsCI' 
            }
            It 'should set build status to in progress' {
                Assert-MockCalled -CommandName 'Set-WhsCIBuildStatus' -ModuleName 'WhsCI' -ParameterFilter { $Status -eq 'Started' }
            }
            It 'should set build status to passed' {
                Assert-MockCalled -CommandName 'Set-WhsCIBuildStatus' -ModuleName 'WhsCI' -ParameterFilter {  $Status -eq 'Completed' }
            }

            if( $WithContext.ByBuildServer )
            {
                It 'should tag the commit' {
                    Assert-MockCalled -CommandName 'Publish-WhsCITag' -ModuleName 'WhsCI' -Times 1
                }
            }
        }


        $version = '4.3.5-rc.1'
        $taskFunctionName = 'Invoke-WhsCI{0}Task' -f $taskName

        Mock -CommandName $taskFunctionName -ModuleName 'WhsCI' -Verifiable
        Mock -CommandName 'Set-WhsCIBuildStatus' -ModuleName 'WhsCI'
        Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
        Mock -CommandName 'Publish-WhsCITag' -ModuleName 'WhsCI' -Verifiable

        Context 'By Developer' {
            Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { return $false }
            $context = New-WhsCITestContext -ForTaskName $taskName -TaskParameter @{ 'Path' = $taskName } -ForDeveloper
            $context.ByDeveloper = $true
            $context.ByBuildServer = $false
            Invoke-WhsCIBuild -Context $context
            $withWhatIfSwitchParam = @{ }
            if( $whatIfTasks.ContainsKey($taskName) )
            {
                $withWhatIfSwitchParam['WithWhatIfSwitch'] = $true
            }
            Assert-TaskCalled -WithContext $context @withWhatIfSwitchParam
        }

        Context 'By Jenkins' {
            Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -ParameterFilter { $Path -eq 'env:JENKINS_URL' } -MockWith { return $true }
            Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -ParameterFilter { $Path -eq 'env:GIT_BRANCH' } -MockWith { return $true }
            $context = New-WhsCITestContext -ForBuildServer -ForTaskName $taskName -TaskParameter @{ 'Path' = $taskName }
            $context.ByDeveloper = $false
            $context.ByBuildServer = $true
            Invoke-WhsCIBuild -Context $context
            Assert-TaskCalled -WithContext $context
        }
    }
    
    Describe ('Invoke-WhsCIBuild.when calling {0} task with Clean switch' -f $taskName) {
        $taskFunctionName = 'Invoke-WhsCI{0}Task' -f $taskName
        $context = New-WhsCITestContext -ForTaskName $taskName -TaskParameter @{ 'Path' = $taskName } -ForDeveloper
        Mock -CommandName $taskFunctionName -ModuleName 'WhsCI' -Verifiable

        Invoke-WhsCIBuild -Context $context -Clean
        It 'should call task with active Clean switch' {
            Assert-MockCalled -CommandName $taskFunctionName -ModuleName 'WhsCI' -ParameterFilter {
                $PSBoundParameters['Clean'] -eq $true
            }
        }
    }
}
