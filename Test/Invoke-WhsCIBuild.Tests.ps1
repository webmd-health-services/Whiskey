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
        
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI' -Times 1 -ParameterFilter {
            $expectedUri = 'https://bitbucket.example.com/'
            $expectedUsername = 'bbserver'
            $expectedPassword = 'bbserver'

            #$DebugPreference = 'Continue'

            Write-Debug -Message ('Status                          expected  {0}' -f $ExpectedStatus)
            Write-Debug -Message ('                                actual    {0}' -f $Status)

            Write-Debug -Message ('Connection.Uri                  expected  {0}' -f $expectedUri)
            Write-Debug -Message ('                                actual    {0}' -f $Connection.Uri)

            Write-Debug -Message ('Connection.Credential.UserName  expected  {0}' -f $expectedUsername)
            Write-Debug -Message ('                                actual    {0}' -f $Connection.Credential.UserName)

            $Status -eq $ExpectedStatus -and
            $Connection -ne $null -and
            $Connection.Uri -eq $expectedUri -and
            $Connection.Credential.Username -eq $expectedUsername -and
            $Connection.Credential.GetNetworkCredential().Password -eq $expectedPassword 
        }
    }
}

function Assert-CommitMarkedAsInProgress
{
    Assert-CommitStatusSetTo 'InProgress'
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
}

#region Mocks
function New-MockBitbucketServer
{
    Mock -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI' -Verifiable
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


function New-NUnitTestAssembly
{
    param(
        [string]
        $ConfigurationPath,

        [string[]]
        $AssemblyName
    )

    $root = $ConfigurationPath | Split-Path

    $sourceAssembly = $passingNUnit2TestAssemblyPath

    $sourceAssembly | Split-Path | Get-ChildItem -Filter 'nunit.framework.dll' | Copy-Item -Destination $root

    foreach( $name in $AssemblyName )
    {
        $destinationPath = Join-Path -Path $root -ChildPath $name
        Install-Directory -Path ($destinationPath | Split-Path)
        $sourceAssembly | Copy-Item -Destination $destinationPath
    }
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

$passingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'

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
    New-NUnitTestAssembly -ConfigurationPath $configPath -AssemblyName $assembly

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

# Tasks that should be called with the WhatIf parameter when run by developers
$whatIfTasks = @{ 'AppPackage' = $true; 'NodeAppPackage' = $true; }
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

            $versionJsonPath = Join-Path -Path $WithContext.BuildRoot -ChildPath 'version.json'
            if( $WithContext.ByBuildServer )
            {
                It 'should set build status' {
                    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI' -ParameterFilter {
                        [object]::ReferenceEquals($WithContext.BBServerConnection,$Connection)
                    }
                }
                It 'should set build status to in progress' {
                    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI' -ParameterFilter {
                        $Status -eq 'InProgress'
                    }
                }
                It 'should set build status to passed' {
                    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI' -ParameterFilter {
                        $Status -eq 'Successful'
                    }
                }

                It 'version.json should exist' {
                    $versionJsonPath | Should Exist
                }

                $version = Get-Content -Path $versionJsonPath -Raw | ConvertFrom-Json
                It 'version.json should have Version property' {
                    $version.Version | Should Be $WithContext.Version.Version
                }
                It 'version.json should have PrereleaseMetadata property' {
                    $version.PrereleaseMetadata | Should Be $WithContext.Version.Prerelease
                }
                It 'version.json shuld have BuildMetadata property' {
                    $version.BuildMetadata | Should Be $WithContext.Version.Build
                }
                It 'version.json should have full semantic version' {
                    $version.SemanticVersion | Should Be $WithContext.Version
                }
            }
            else
            {
                It 'should not set build status' {
                    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI' -Times 0
                }

                It 'version.json should not exist' {
                    $versionJsonPath | Should Not Exist
                }
            }
        }


        $version = '4.3.5-rc.1'
        $taskFunctionName = 'Invoke-WhsCI{0}Task' -f $taskName

        Mock -CommandName $taskFunctionName -ModuleName 'WhsCI' -Verifiable
        Mock -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI'
        Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }

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
            $context = New-WhsCITestContext -ForBuildServer -ForTaskName $taskName -TaskParameter @{ 'Path' = $taskName }
            $context.ByDeveloper = $false
            $context.ByBuildServer = $true
            Invoke-WhsCIBuild -Context $context
            Assert-TaskCalled -WithContext $context
        }
    }
}
