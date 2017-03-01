#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\Import-WhsCI.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\LibGit2\Import-LibGit2.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\Carbon\Import-Carbon.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\BitbucketServerAutomation\Import-BitbucketServerAutomation.ps1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\powershell-yaml' -Resolve) -Force
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\WhsAutomation\Import-WhsAutomation.ps1' -Resolve)

$downloadRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI'
$moduleDownloadRoot = Join-Path -Path $downloadRoot -ChildPath 'Modules'

$defaultAssemblyVersion = '1.2.3-final+80.develop.deadbee'

#region Assertions
function Assert-AssemblyVersionSet
{
    param(
        [string]
        $ConfigurationPath,

        [string[]]
        $ProjectName,

        [SemVersion.SemanticVersion]
        $AtVersion
    )

    $root = Split-Path -Path $ConfigurationPath -Parent
    $version = '{0}.{1}.{2}' -f $AtVersion.Major,$AtVersion.Minor,$AtVersion.Patch

    foreach( $name in $ProjectName )
    {
        $projectRoot = $name | Split-Path
        $projectRoot = Join-Path -Path $root -ChildPath $projectRoot
        foreach( $assemblyInfoInfo in (Get-ChildItem -Path $projectRoot -Recurse -Filter 'AssemblyInfo.cs') )
        {
            $buildInfo = New-BuildMetadata

            $assemblyInfoRelativePath = $assemblyInfoInfo.FullName -replace [regex]::Escape($root),''
            $assemblyInfoRelativePath = $assemblyInfoRelativePath.Trim("\")
            foreach( $attribute in @( 'AssemblyVersion', 'AssemblyFileVersion' ) )
            {
                It ('should update {0} in {1} project''s {2} file' -f $attribute,$name,$assemblyInfoRelativePath) {
                    $expectedRegex = ('\("{0}"\)' -f [regex]::Escape($version))
                    $line = Get-Content -Path $assemblyInfoInfo.FullName | Where-Object { $_ -match ('\b{0}\b' -f $attribute) }
                    $line | Should Match $expectedRegex
                }
            }

            $expectedSemanticVersion = New-Object -TypeName 'SemVersion.SemanticVersion' -ArgumentList $AtVersion.Major,$AtVersion.Minor,$AtVersion.Patch,$AtVersion.Prerelease,$buildInfo

            It ('should update AssemblyInformationalVersion in {0} project''s {1} file' -f $name,$assemblyInfoRelativePath) {
                $expectedRegex = ('\("{0}"\)' -f [regex]::Escape($expectedSemanticVersion))
                $line = Get-Content -Path $assemblyInfoInfo.FullName | Where-Object { $_ -match ('\bAssemblyInformationalVersion\b' -f $attribute) }
                $line | Should Match $expectedRegex
            }
        }
    }
}

function Assert-BitbucketServerNotContacted
{
    It 'should not contact Bitbucket Server' {
        Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI' -Times 0
    }
}

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

function Assert-CommitMarkedAsSuccessful
{
    Assert-CommitStatusSetTo 'Successful'
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

function Assert-DotNetProjectsCompiled
{
    param(
        [string]
        $ConfigurationPath,

        [string[]]
        $ProjectName,

        [SemVersion.SemanticVersion]
        $AtVersion
    )

    $root = Split-Path -Path $ConfigurationPath -Parent

    foreach( $name in $ProjectName )
    {
        $projectRoot = $name | Split-Path
        $projectRoot = Join-Path -Path $root -ChildPath $projectRoot
        It ('should run {0} project''s ''clean'' target' -f $name) {
            (Join-Path -Path $root -ChildPath ('{0}.clean' -f $name)) | Should Exist
        }

        It ('should run {0} project''s ''build'' target' -f $name) {
            (Join-Path -Path $root -ChildPath ('{0}.build' -f $name)) | Should Exist
        }
    }

    
    if( $AtVersion )
    {
        Assert-AssemblyVersionSet -Project $ProjectName -AtVersion $AtVersion -ConfigurationPath $ConfigurationPath
    }
}

function Assert-DotNetProjectBuildConfiguration
{
    param(
        [string]
        $ExpectedConfiguration,

        [string]
        $ConfigurationPath,

        [SemVersion.SemanticVersion]
        $AtVersion,

        [string[]]
        $ProjectName
    )

    It ('should compile with {0} configuration' -f $ExpectedConfiguration)  {
        Assert-MockCalled -CommandName 'Invoke-MSBuild' -ModuleName 'WhsCI' -Times 1 -ParameterFilter { 
            #$DebugPreference = 'Continue'

            $expectedProperty = 'Configuration={0}' -f $expectedConfiguration
            Write-Debug -Message ('Property[0]  expected {0}' -f $expectedProperty)
            Write-Debug -Message ('             actual   {0}' -f $Property[0])
            $Property.Count -eq 1 -and $Property[0] -eq $expectedProperty
        }
    }

    if( $AtVersion )
    {
        Assert-AssemblyVersionSet -ConfigurationPath $ConfigurationPath -ProjectName $ProjectName -AtVersion $AtVersion
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

function Assert-NUnitTestsRun
{
    param(
        $ConfigurationPath,

        [string[]]
        $ExpectedAssembly,

        [string]
        $ExpectedBinRoot
    )

    It 'should run NUnit tests' {
        $ConfigurationPath | Split-Path | ForEach-Object { Get-WhsCIOutputDirectory -WorkingDirectory $_ } | Get-ChildItem -Filter 'nunit2*.xml' | Should Not BeNullOrEmpty
    }
}
#endregion


function Invoke-Build
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Developer')]
        [Switch]
        $ByDeveloper,

        [Parameter(Mandatory=$true,ParameterSetName='Dev')]
        [Switch]
        $ByJenkins,

        [string]
        $WithConfig,

        [Switch]
        $ThatFails,

        [string]
        $DownloadRoot,

        [Switch]
        $NoGitRepository,

        [SemVersion.SemanticVersion]
        $Version = '5.4.1-prerelease+build'
    )

    $runningUnderABuildServer = $false
    $environment = $PSCmdlet.ParameterSetName
    if( $PSCmdlet.ParameterSetName -eq 'Developer' )
    {
        New-MockDeveloperEnvironment
    }
    else
    {
        $runningUnderABuildServer = $true
        New-MockBuildServer
    }
    New-MockBitbucketServer

    Mock -CommandName 'Get-WhsSecret' -ModuleName 'WhsCI' -MockWith { return New-Credential -UserName 'fubar' -Password 'snafu' }

    if( -not ($NoGitRepository) )
    {
        Mock -CommandName 'Assert-WhsCIVersionAvailable' -ModuleName 'WhsCI' -MockWith { return $Version }
    }

    $configuration = Get-WhsSetting -Environment $environment -Name '.NETProjectBuildConfiguration'
    $optionalParams = @{ }
    if( (Test-WhsCIRunByBuildServer) )
    {
        $optionalParams['ForBuildServer'] = $true
    }

    if( $DownloadRoot )
    {
        $optionalParams['DownloadRoot'] = $DownloadRoot
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

    if( $runningUnderABuildServer )
    {
        Assert-CommitMarkedAsInProgress
    }
    
    if( $ThatFails )
    {
        It 'should throw a terminating exception' {
            $threwException | Should Be $true
        }

        if( $runningUnderABuildServer )
        {
            Assert-CommitMarkedAsFailed
        }
    }
    else
    {
        It 'should not throw a terminating exception' {
            $threwException | Should Be $false
        }

        if( $runningUnderABuildServer )
        {
            Assert-CommitMarkedAsSuccessful
        }
    }

    if( $PSCmdlet.ParameterSetName -eq 'Developer' )
    {
        Assert-BitbucketServerNotContacted
    }
}

function New-BuildMetadata
{
    if( (Test-WhsCIRunByBuildServer) )
    {
        # * If on build server, add $(BUILD_ID).$(GIT_BRANCH).$(GIT_COMMIT). Remove "origin/" from branch name. Replace other non-alphanumeric characters with '-'; Shrink GIT_COMMIT to short commit id.
        $branch = (Get-Item -Path 'env:GIT_BRANCH').Value -replace '^origin/',''
        $commitID = (Get-Item -Path 'env:GIT_COMMIT').Value.Substring(0,7)
        return '{0}.{1}.{2}' -f (Get-Item -Path 'env:BUILD_ID').Value,$branch,$commitID
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
        $AssemblyName,

        [Switch]
        $ThatFail
    )

    $root = $ConfigurationPath | Split-Path

    if( $ThatFail )
    {
        $sourceAssembly = $failingNUnit2TestAssemblyPath
    }
    else
    {
        $sourceAssembly = $passingNUnit2TestAssemblyPath
    }

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
        $Yaml,

        [Parameter(ParameterSetName='SingleTask')]
        [SemVersion.SemanticVersion]
        $Version,

        [Parameter(ParameterSetName='SingleTask')]
        [string]
        $TaskName,

        [Parameter(ParameterSetName='SingleTask')]
        [string[]]
        $Path,

        [Parameter(ParameterSetname='SingleTask')]
        [hashtable]
        $TaskProperty
    )

    $config = $null
    if( $PSCmdlet.ParameterSetName -eq 'SingleTask' )
    {
        if( -not $TaskProperty )
        {
            $TaskProperty = @{}
        }
        if( $Path )
        {
            $TaskProperty['Path'] = $Path
        }
        $config = @{
                        BuildTasks = @(
                                    @{
                                        $TaskName = $TaskProperty
                                     }
                                 )
                   }
    }

    if( $config )
    {
        if( $Version )
        {
            $config['Version'] = $Version.ToString()
        }
        $Yaml = $config | ConvertTo-Yaml 
        #$DebugPreference = 'Continue'
        Write-Debug -Message ('{0}{1}' -f ([Environment]::NewLine),$Yaml)
    }

    $root = (Get-Item -Path 'TestDrive:').FullName
    $whsbuildymlpath = Join-Path -Path $root -ChildPath 'whsbuild.yml'
    $Yaml | Set-Content -Path $whsbuildymlpath
    return $whsbuildymlpath
}
#endregion

$failingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
$passingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'
$nunitWhsBuildYmlFile = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whsbuild.yml'

<#
Get-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit*\Properties\AssemblyInfo.cs') |
    ForEach-Object { git checkout HEAD $_.FullName }
#>

$pesterPassingConfig = Join-Path -Path $PSScriptRoot -ChildPath 'Pester\whsbuild_passing.yml' -Resolve
Describe 'Invoke-WhsCIBuild.when running Pester task' {
    Mock -CommandName 'Install-WhsCITool' -ModuleName 'WhsCI' -MockWith { return (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\Pester') }.GetNewClosure()
    $downloadRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'downloads'
    Invoke-Build -ByJenkins -WithConfig $pesterPassingConfig -DownloadRoot $downloadRoot

    $pesterOutput = Get-WhsCIOutputDirectory -WorkingDirectory ($pesterPassingConfig | Split-Path)
    $testReports = Get-ChildItem -Path $pesterOutput -Filter 'pester-*.xml'
    It 'should run pester tests' {
        $testReports | Should Not BeNullOrEmpty
    }
}

Describe 'Invoke-WhsCIBuild.when running PowerShell task' {
    $fileNames = @( 'task1.ps1', 'task2.ps1' )
    $configPath = New-TestWhsBuildFile -TaskName 'PowerShell' -Path $fileNames

    $root = Split-Path -Path $configPath -Parent
    foreach( $fileName in $fileNames )
    {
        @'
$scriptName = Split-Path -Leaf -Path $PSCommandPath
$outputFileName = '{0}.output' -f $scriptName
$outputFilePath = Join-Path -Path $PSScriptRoot -ChildPath $outputFileName
New-Item -ItemType 'File' -Path $outputFilePath
exit 0
'@ | Set-Content -Path (Join-Path -Path $root -ChildPath $fileName)
    }

    Invoke-Build -ByJenkins -WithConfig $configPath 

    foreach( $fileName in $fileNames )
    {
        It ('should run {0} PowerShell script' -f $fileNames) {
            (Join-Path -Path $root -ChildPath ('{0}.output' -f $fileName)) | Should Exist
        }
    }
}

Describe 'Invoke-WhsCIBuild.when PowerShell task defined with a working directory' {
    $fileName = 'task1.ps1'

    $configPath = New-TestWhsBuildFile -TaskName 'PowerShell' -Path $fileName -TaskProperty @{ 'WorkingDirectory' = 'bin' }

    $root = Split-Path -Path $configPath -Parent
    $binRoot = Join-Path -Path $root -ChildPath 'bin'
    New-Item -Path $binRoot -ItemType 'Directory'

    @'
'' | Set-Content -Path 'ran'
'@ | Set-Content -Path (Join-Path -Path $root -ChildPath $fileName)

    Invoke-Build -ByJenkins -WithConfig $configPath 

    It ('should run PowerShell script in the working directory') {
        Join-Path -Path $binRoot -ChildPath 'ran' | Should Exist
    }
}

Describe 'Invoke-WhsCIBuild.when a task path does not exist' {
    $path = 'FubarSnafu'
    $configPath = New-TestWhsBuildFile -TaskName 'Pester3' -Path $path
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue
    
    It 'should write an error that the file does not exist' {
        $Global:Error[0] | Should Match 'not exist'
    }
}

Describe 'Invoke-WhsCIBuild.when a task path is absolute' {
    $configPath = New-TestWhsBuildFile -TaskName 'Pester3' -Path 'C:\FubarSnafu'
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    It 'should write an error that the path is absolute' {
        $Global:Error[0] | Should Match 'absolute'
    }
}

Describe 'Invoke-WhsCIBuild.when a task has no properties' {
    $configPath = New-TestWhsBuildFile -Yaml @'
BuildTasks:
- Pester3:
'@
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    It 'should write an error that the task is incomplete' {
        $Global:Error[0] | Should Match 'is mandatory'
    }
}

Describe 'Invoke-WhsCIBuild.when running an unknown task' {
    $configPath = New-TestWhsBuildFile -Yaml @'
BuildTasks:
    - FubarSnafu:
        Path: whsbuild.yml
'@
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails

    It 'should write an error' {
        $Global:Error[0] | Should Match 'not exist'
    }
}

Describe 'Invoke-WhsCIBuild.when a task fails' {
    $project = 'project.csproj'
    $assembly = 'assembly.dll'
    $configPath = New-TestWhsBuildFile -Yaml @'
BuildTasks:
- MSBuild:
    Path: project.csproj
- NUnit2:
    Path: assembly.dll
'@

    New-MSBuildProject -FileName $project -ThatFails
    New-NUnitTestAssembly -ConfigurationPath $configPath -AssemblyName $assembly

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails 2>&1

    Assert-DotNetProjectsCompilationFailed -ConfigurationPath $configPath -ProjectName $project
    Assert-NUnitTestsNotRun -ConfigurationPath $configPath
}

Describe 'Invoke-WhsCIBuild.when using NuGetPack task' {
    $project = New-MSBuildProject -FileName 'project.csproj'
    $project2 = New-MSBuildProject -FileName 'project2.csproj'
    $projectPaths = $project,$project2
    $expectedVersion = '1.6.7-rc1'
    $configPath = New-TestWhsBuildFile -TaskName 'NuGetPack' -Path 'project.csproj','project2.csproj' -Version $expectedVersion

    Mock -CommandName 'Invoke-WhsCINuGetPackTask' -ModuleName 'WhsCI' -Verifiable
    
    Invoke-Build -ByJenkins -WithConfig $configPath -Version $expectedVersion

    It 'should call Invoke-WhsCINuGetPackTask' {
        foreach( $projectPath in $projectPaths )
        {
            Assert-MockCalled -CommandName 'Invoke-WhsCINuGetPackTask' -ModuleName 'WhsCI' -ParameterFilter {
                #$DebugPreference = 'Continue'
                Write-Debug -Message ('Path               expected  {0}' -f $projectPath)
                Write-Debug -Message ('                   actual    {0}' -f $Path)
                $expectedOutputRoot = Join-Path -Path ($configPath | Split-Path) -Child '.output'
                Write-Debug -Message ('OutputDirectory    expected  {0}' -f $expectedOutputRoot)
                Write-Debug -Message ('                   actual    {0}' -f $OutputDirectory)
                Write-Debug -Message ('Version            expected  {0}' -f $expectedVersion)
                Write-Debug -Message ('                   actual    {0}' -f $Version)
                $configuration = Get-WhsSetting -Environment 'Dev' -Name '.NETProjectBuildConfiguration'
                Write-Debug -Message ('BuildConfiguration expected  {0}' -f $configuration)
                Write-Debug -Message ('                   actual    {0}' -f $BuildConfiguration)

                $projectPath -eq $Path -and $expectedOutputRoot -eq $OutputDirectory -and $expectedVersion -eq $Version -and $configuration -eq $BuildConfiguration
            }
        }
    }
}

# Tasks that should be called with the WhatIf parameter when run by developers
$whatIfTasks = @{ 'AppPackage' = $true; 'NodeAppPackage' = $true; }
# TODO: Once:
# * all task logic is migrated into its corresponding task function
# * all tasks use the same interface
# * task functions are created for all tasks
#
# Then we can update this to get the task list by using `Get-Command -Name 'Invoke-WhsCI*Task' -Module 'WhsCI'`
foreach( $taskName in @( 'AppPackage', 'NodeAppPackage', 'Node' ) )
{
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

            if( $context.ByBuildSErver )
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
            }
            else
            {
                It 'should not set build status' {
                    Assert-MockCalled -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI' -Times 0
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
            $context = New-WhsCITestContext -ForTaskName $taskName -TaskParameter @{ 'Path' = $taskName }
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
