
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\Import-WhsCI.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\LibGit2\Import-LibGit2.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\Carbon\Import-Carbon.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\BitbucketServerAutomation\Import-BitbucketServerAutomation.ps1' -Resolve)
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\WhsCI\powershell-yaml' -Resolve) -Force
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\WhsAutomation\Import-WhsAutomation.ps1' -Resolve)

$downloadRoot = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WebMD Health Services\WhsCI'
$packageDownloadRoot = Join-Path -Path $downloadRoot -ChildPath 'packages'
$moduleDownloadRoot = Join-Path -Path $downloadRoot -ChildPath 'Modules'

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
            $shouldMatch = $true
            $buildInfo = New-BuildMetadata
            if( -not $buildInfo )
            {
                $shouldMatch = $false
            }

            $assemblyInfoRelativePath = $assemblyInfoInfo.FullName -replace [regex]::Escape($root),''
            $assemblyInfoRelativePath = $assemblyInfoRelativePath.Trim("\")
            foreach( $attribute in @( 'AssemblyVersion', 'AssemblyFileVersion' ) )
            {
                It ('should update {0} in {1} project''s {2} file' -f $attribute,$name,$assemblyInfoRelativePath) {
                    $expectedRegex = ('\("{0}"\)' -f [regex]::Escape($version))
                    $line = Get-Content -Path $assemblyInfoInfo.FullName | Where-Object { $_ -match ('\b{0}\b' -f $attribute) }
                    if( $shouldMatch )
                    {
                        $line | Should Match $expectedRegex
                    }
                    else
                    {
                        $line | Should Not Match $expectedRegex
                    }
                }
            }

            $expectedSemanticVersion = New-Object -TypeName 'SemVersion.SemanticVersion' -ArgumentList $AtVersion.Major,$AtVersion.Minor,$AtVersion.Patch,$AtVersion.Prerelease,$buildInfo

            It ('should update AssemblyInformationalVersion in {0} project''s {1} file' -f $name,$assemblyInfoRelativePath) {
                $expectedRegex = ('\("{0}"\)' -f [regex]::Escape($expectedSemanticVersion))
                $line = Get-Content -Path $assemblyInfoInfo.FullName | Where-Object { $_ -match ('\bAssemblyInformationalVersion\b' -f $attribute) }
                if( $shouldMatch )
                {
                    $line | Should Match $expectedRegex
                }
                else
                {
                    $line | Should Not Match $expectedRegex
                }
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
            $expectedUri = (Get-WhsSetting -Environment 'Dev' -Name 'BitbucketServerBaseUri')
            $expectedUsername = (Get-WhsSetting -Environment 'Dev' -Name 'BitbucketServerRestApiUsername')
            $expectedPassword = Get-WhsSecret -Environment 'Dev' -Name $expectedUsername

            #$DebugPreference = 'Continue'

            Write-Debug -Message ('Status                          expected  {0}' -f $ExpectedStatus)
            Write-Debug -Message ('                                actual    {0}' -f $Status)

            Write-Debug -Message ('Connection.Uri                  expected  {0}' -f $expectedUri)
            Write-Debug -Message ('                                actual    {0}' -f $Connection.Uri)

            Write-Debug -Message ('Connection.Credential.UserName  expected  {0}' -f $expectedUsername)
            Write-Debug -Message ('                                actual    {0}' -f $Connection.Credential.UserName)

            Write-Debug -Message ('CommitID                        expected  $null')
            Write-Debug -Message ('                                actual    {0}' -f $CommitID)

            Write-Debug -Message ('Key                             expected  $null')
            Write-Debug -Message ('                                actual    {0}' -f $Key)

            Write-Debug -Message ('BuildUri                        expected  $null')
            Write-Debug -Message ('                                actual    {0}' -f $BuildUri)

            Write-Debug -Message ('Name                            expected  $null')
            Write-Debug -Message ('                                actual    {0}' -f $Name)

            $Status -eq $ExpectedStatus -and
            $Connection -ne $null -and
            $Connection.Uri -eq $expectedUri -and
            $Connection.Credential.Username -eq $expectedUsername -and
            $Connection.Credential.GetNetworkCredential().Password -eq $expectedPassword -and 
            -not $CommitID -and
            -not $Key -and
            -not $BuildUri -and
            -not $Name
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
        $ConfigurationPath | Split-Path | Join-Path -ChildPath '.output' | Get-ChildItem -Filter 'nunit2*.xml' | Should BeNullOrEmpty
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
        $ConfigurationPath | Split-Path | Join-Path -ChildPath '.output' | Get-ChildItem -Filter 'nunit2*.xml' | Should Not BeNullOrEmpty
    }
}

function Assert-PesterRan
{
    param(
        [Parameter(Mandatory=$true)]
        [int]
        $FailureCount,
            
        [Parameter(Mandatory=$true)]
        [int]
        $PassingCount
    )

    $pesterOutput = Join-Path -Path $PSScriptRoot -ChildPath 'Pester\.output'
    $testReports = Get-ChildItem -Path $pesterOutput -Filter 'pester-*.xml'
    It 'should run pester tests' {
            $testReports | Should Not BeNullOrEmpty
    }

    $total = 0
    $failed = 0
    $passed = 0
    foreach( $testReport in $testReports )
    {
        $xml = [xml](Get-Content -Path $testReport.FullName -Raw)
        $thisTotal = [int]($xml.'test-results'.'total')
        $thisFailed = [int]($xml.'test-results'.'failures')
        $thisPassed = ($thisTotal - $thisFailed)
        $total += $thisTotal
        $failed += $thisFailed
        $passed += $thisPassed
    }

    $expectedTotal = $FailureCount + $PassingCount
    It ('should run {0} tests' -f $expectedTotal) {
        $total | Should Be $expectedTotal
    }

    It ('should have {0} failed tests' -f $FailureCount) {
        $failed | Should Be $FailureCount
    }

    It ('should run {0} passing tests' -f $PassingCount) {
        $passed | Should Be $PassingCount
    }
}

function Assert-WhsAppPackageCreated
{
    param(
        $ConfigurationPath,
        $Version,
        $Name,
        $ExpectedDir,
        $ExpectedWhitelist
    )

    It 'should create package' {
        Assert-MockCalled -CommandName 'New-WhsAppPackage' -ModuleName 'WhsCI' -Times 1 -ParameterFilter {
            $root = $ConfigurationPath | Split-Path
            $expectedOutputFile = Join-Path -Path $root -ChildPath ('.output\{0}.{1}.upack' -f $Name,$Version)
            $expectedPath = $ExpectedDir | ForEach-Object { Join-Path -Path $root -ChildPath $_ }

            #$DebugPreference = 'Continue'

            Write-Debug -Message ('Path.Count  expected  {0}' -f $expectedPath.Count)
            Write-Debug -Message ('            actual    {0}' -f $Path.Count)

            if( ($Path.Count -ne $expectedPath.Count) )
            {
                return $false
            }

            for( $idx = 0; $idx -lt $Path.Count; ++$idx )
            {
                Write-Debug -Message ('Path[{0}]   expected  {1}' -f $idx,$expectedPath[$idx])
                Write-Debug -Message ('          actual    {0}' -f $Path[$idx])
                if( $Path[$idx] -ne $expectedPath[$idx] )
                {
                    return $false
                }
            }

            Write-Debug -Message ('Whitelist.Count  expected  {0}' -f $expectedWhitelist.Count)
            Write-Debug -Message ('                 actual    {0}' -f $Whitelist.Count)

            if( ($Whitelist.Count -ne $expectedWhitelist.Count) )
            {
                return $false
            }
            for( $idx = 0; $idx -lt $Whitelist.Count; ++$idx )
            {
                Write-Debug -Message ('Whitelist[{0}]   expected  {1}' -f $idx,$expectedWhitelist[$idx])
                Write-Debug -Message ('               actual    {0}' -f $Whitelist[$idx])
                if( $Whitelist[$idx] -ne $expectedWhitelist[$idx] )
                {
                    return $false
                }
            }

            Write-Debug -Message ('OutputFile  expected  {0}' -f $expectedOutputFile)
            Write-Debug -Message ('            actual    {0}' -f $OutputFile)
            return $OutputFile -eq $expectedOutputFile
        }
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
        $DownloadRoot
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

    $configuration = Get-WhsSetting -Environment $environment -Name '.NETProjectBuildConfiguration'
    $devParams = @{ }
    if( (Test-Path -Path 'env:JENKINS_URL') )
    {
        $bbServerCredUsername = Get-WhsSetting -Environment $Environment -Name 'BitbucketServerRestApiUsername'
        $devParams['BBServerCredential'] = Get-WhsSecret -Environment $Environment -Name $bbServerCredUsername -AsCredential 

        $devParams['BBServerUri'] = Get-WhsSetting -Environment $Environment -Name 'BitbucketServerBaseUri'
    }

    $downloadRootParam = @{ }
    if( $DownloadRoot )
    {
        $downloadRootParam['DownloadRoot'] = $DownloadRoot
    }

    $failed = $false
    try
    {
        Invoke-WhsCIBuild -ConfigurationPath $WithConfig `
                          -BuildConfiguration $configuration `
                          @devParams `
                          @downloadRootParam
    }
    catch
    {
        $failed = $true
    }    

    if( $runningUnderABuildServer )
    {
        Assert-CommitMarkedAsInProgress
    }
    
    if( $ThatFails )
    {
        It 'should throw a terminating exception' {
            $failed | Should Be $true
        }

        if( $runningUnderABuildServer )
        {
            Assert-CommitMarkedAsFailed
        }
    }
    else
    {
        It 'should not throw a terminating exception' {
            $failed | Should Be $false
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

function New-AssemblyInfo
{
    param(
        [string]
        $RootPath
    )

    @'
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

// General Information about an assembly is controlled through the following 
// set of attributes. Change these attribute values to modify the information
// associated with an assembly.
[assembly: AssemblyTitle("NUnit2FailingTest")]
[assembly: AssemblyDescription("")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("")]
[assembly: AssemblyProduct("NUnit2FailingTest")]
[assembly: AssemblyCopyright("Copyright (c) 2016")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyCulture("")]

// Setting ComVisible to false makes the types in this assembly not visible 
// to COM components.  If you need to access a type in this assembly from 
// COM, set the ComVisible attribute to true on that type.
[assembly: ComVisible(false)]

// The following GUID is for the ID of the typelib if this project is exposed to COM
[assembly: Guid("05b909ba-da71-42f6-836f-f1ec9b96e54d")]

// Version information for an assembly consists of the following four values:
//
//      Major Version
//      Minor Version 
//      Build Number
//      Revision
//
// You can specify all the values or you can default the Build and Revision Numbers 
// by using the '*' as shown below:
// [assembly: AssemblyVersion("1.0.*")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
[assembly: AssemblyInformationalVersion("1.0.0.0")]
'@ | Set-Content -Path (Join-Path -Path $RootPath -ChildPath 'AssemblyInfo.cs') 
}

function New-BuildMetadata
{
    if( (Test-Path -Path 'env:JENKINS_URL') )
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
    Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -MockWith { $true } -ParameterFilter { $Path -eq 'env:JENKINS_URL' }
    Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = '80' } } -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = 'origin/develop' } } -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = 'deadbeefdeadbeefdeadbeefdeadbeef' } } -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }

    Mock -CommandName 'Test-Path' -MockWith { $true } -ParameterFilter { $Path -eq 'env:JENKINS_URL' }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = '80' } } -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = 'origin/develop' } } -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Get-Item' -MockWith { [pscustomobject]@{ Value = 'deadbeefdeadbeefdeadbeefdeadbeef' } } -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }
}

function New-MockDeveloperEnvironment
{
    Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -MockWith { $false } -ParameterFilter { $Path -eq 'env:JENKINS_URL' }
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

function New-MSBuildProject
{
    param(
        [string[]]
        $FileName,

        [Switch]
        $ThatFails
    )

    $root = (Get-Item -Path 'TestDrive:').FullName

    foreach( $name in $FileName )
    {
        @"
<?xml version="1.0" encoding="UTF-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003" ToolsVersion="4.0">

    <Target Name="clean">
        <Error Condition="'$ThatFails' == 'True'" Text="FAILURE!" />
        <WriteLinesToFile File="`$(MSBuildThisFileDirectory)\`$(MSBuildProjectFile).clean" />
    </Target>

    <Target Name="build">
        <Error Condition="'$ThatFails' == 'True'" Text="FAILURE!" />
        <WriteLinesToFile File="`$(MSBuildThisFileDirectory)\`$(MSBuildProjectFile).build" />
    </Target>

</Project>
"@ | Set-Content -Path (Join-Path -Path $root -ChildPath $name)

        New-AssemblyInfo -RootPath (Join-Path -Path $root -ChildPath ($name | Split-Path))
    }
}

function New-TestWhsBuildFile
{
    param(
        [Parameter(ParameterSetName='WithRawYaml')]
        [string]
        $Yaml,

        [Parameter(ParameterSetName='PackageTask')]
        [string]
        $PackageName,

        [Parameter(ParameterSetName='PackageTask')]
        [string[]]
        $Whitelist,

        [Parameter(ParameterSetName='SingleTask')]
        [string]
        $TaskName,

        [Parameter(ParameterSetName='PackageTask')]
        [Parameter(ParameterSetName='SingleTask')]
        [string[]]
        $Path,

        [Parameter(ParameterSetName='PackageTask')]
        [Parameter(ParameterSetName='SingleTask')]
        [SemVersion.SemanticVersion]
        $Version
    )

    $config = $null
    if( $PSCmdlet.ParameterSetName -eq 'SingleTask' )
    {
        $config = @{
                        BuildTasks = @(
                                    @{
                                        $TaskName = @{
                                                        Path = $Path 
                                                     }
                                     }
                                 )
                   }
    }
    elseif( $PSCmdlet.ParameterSetName -eq 'PackageTask' )
    {
        $config = @{
                        BuildTasks = @(
                                        @{
                                            'WhsAppPackage' = @{
                                                                    Name = $PackageName;
                                                                    Path = $Path;
                                                                    Whitelist = $Whitelist;
                                                                }
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

$failingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
$passingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'
$nunitWhsBuildYmlFile = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whsbuild.yml'

Describe 'Invoke-WhsCIBuild when building real projects' {
    # Get rid of any existing packages directories.
    Get-ChildItem -Path $PSScriptRoot 'packages' -Recurse -Directory | Remove-Item -Recurse -Force
    
    $errors = @()
    Invoke-Build -ByJenkins -WithConfig $nunitWhsBuildYmlFile -ErrorVariable 'errors'
    It 'should write no errors' {
        $errors | Should Not Match 'MSBuild'
    }
    It 'should restore NuGet packages' {
        Get-ChildItem -Path $PSScriptRoot -Filter 'packages' -Recurse -Directory | Should Not BeNullOrEmpty
    }
    $config = Get-Content -Path $nunitWhsBuildYmlFile -Raw | ConvertFrom-Yaml
    $semVersion = [SemVersion.SemanticVersion]::Parse($config.Version)
    $version = [version]('{0}.{1}.{2}' -f $semVersion.Major,$semVersion.Minor,$semVersion.Patch)

    It 'should build assemblies' {
        $failingNUnit2TestAssemblyPath | Should Exist
        $passingNUnit2TestAssemblyPath | Should Exist
    }

    foreach( $assembly in @( $failingNUnit2TestAssemblyPath, $passingNUnit2TestAssemblyPath ) )
    {
        It ('should version the {0} assembly' -f ($assembly | Split-Path -Leaf)) {
            $fileInfo = Get-Item -Path $assembly
            $fileVersionInfo = $fileInfo.VersionInfo
            $fileVersionInfo.FileVersion | Should Be $version.ToString()
            $fileVersionInfo.ProductVersion | Should Be ('{0}+{1}' -f $semVersion,(New-BuildMetadata))
        }
    }

    foreach( $name in @( 'Passing', 'Failing' ) )
    {
        It ('should create NuGet package for NUnit2{0}Test' -f $name) {
            (Join-Path -Path $PSScriptRoot -ChildPath ('Assemblies\.output\NUnit2{0}Test.1.2.3-final.nupkg' -f $name)) | Should Exist
        }

        It ('should create a NuGet symbols package for NUnit2{0}Test' -f $name) {
            (Join-Path -Path $PSScriptRoot -ChildPath ('Assemblies\.output\NUnit2{0}Test.1.2.3-final.symbols.nupkg' -f $name)) | Should Exist
        }
    }
}

<#
Get-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit*\Properties\AssemblyInfo.cs') |
    ForEach-Object { git checkout HEAD $_.FullName }
#>
Describe 'Invoke-WhsCIBuild when Version in configuration file is invalid' {
    $configPath = New-TestWhsBuildFile -Yaml @'
Version: 1
'@
    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    It 'should write an error' {
        $Global:Error[0] | Should Match 'not a valid semantic version'
    }
}

$pesterPassingConfig = Join-Path -Path $PSScriptRoot -ChildPath 'Pester\whsbuild_passing.yml' -Resolve
$pesterFailingConfig = Join-Path -Path $PSScriptRoot -ChildPath 'Pester\whsbuild_failing.yml' -Resolve
Describe 'Invoke-WhsCIBuild when running passing Pester tests' {
    $downloadRoot = Join-Path -Path $TestDrive.FullName -ChildPath 'downloads'
    Invoke-Build -ByJenkins -WithConfig $pesterPassingConfig -DownloadRoot $downloadRoot

    Assert-PesterRan -FailureCount 0 -PassingCount 4

    It 'should download Pester' {
        Join-Path -Path $downloadRoot -ChildPath 'Modules\Pester' | Should Exist
    }
}

Describe 'Invoke-WhsCIBuild when running failing Pester tests' {
    Invoke-Build -ByJenkins -WithConfig $pesterFailingConfig -ThatFails
    
    Assert-PesterRan -FailureCount 4 -PassingCount 4
}

Describe 'Invoke-WhsCIBuild when building .NET assemblies.' {
    $version = '3.2.1-rc.1'
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path 'FubarSnafu.csproj' -Version $version

    New-MSBuildProject -FileName 'FubarSnafu.csproj'

    Invoke-Build -ByJenkins -WithConfig $configPath

    Assert-DotNetProjectsCompiled -ConfigurationPath $configPath -ProjectName 'FubarSnafu.csproj' -AtVersion $version
}

Describe 'Invoke-WhsCIBuild when building multiple projects' {
    $projects = @( 'FubarSnafu.csproj','SnafuFubar.csproj' )
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $projects

    New-MSBuildProject -FileName $projects

    Invoke-Build -ByJenkins -WithConfig $configPath

    Assert-DotNetProjectsCompiled -ConfigurationPath $configPath -ProjectName $projects
}

Describe 'Invoke-WhsCIBuild when compilation fails' {
    $project = 'FubarSnafu.csproj' 
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $project
    
    New-MSBuildProject -FileName $project -ThatFails

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    Assert-DotNetProjectsCompilationFailed -ConfigurationPath $configPath -ProjectName $project
}

Describe 'Invoke-WhsCIBuild when multiple AssemblyInfoCs files' {
    $version = '4.3.2-fubar'
    $project = 'FubarSnafu.csproj'
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $project -Version $version

    $propertiesRoot = Join-Path -Path ($configPath | Split-Path) -ChildPath 'Properties'
    Install-Directory $propertiesRoot
    New-AssemblyInfo -RootPath $propertiesRoot

    New-MSBuildProject -FileName $project

    Invoke-Build -ByJenkins -WithConfig $configPath

    Assert-DotNetProjectsCompiled -ConfigurationPath $configPath -ProjectName $project -AtVersion $version
}

Describe 'Invoke-WhsCIBuild when running a PowerShell task' {
    $script = 'task.ps1'
    $configPath = New-TestWhsBuildFile -TaskName 'PowerShell' -Path $script

    $root = Split-Path -Path $configPath -Parent
    @"
'' | Set-Content -Path (Join-Path -Path `$PSScriptRoot -ChildPath '$script.output')
exit 0
"@ | Set-Content -Path (Join-Path -Path $root -ChildPath $script)

    Invoke-Build -ByJenkins -WithConfig $configPath

    It 'should run PowerShell script' {
        (Join-Path -Path $root -ChildPath ('{0}.output' -f $script)) | Should Exist
    }
}

Describe 'Invoke-WhsCIBuild when running a PowerShell task fails' {
    $script = 'task.ps1'
    $configPath = New-TestWhsBuildFile -TaskName 'PowerShell' -Path $script

    $root = Split-Path -Path $configPath -Parent
    @'
exit 1
'@ | Set-Content -Path (Join-Path -Path $root -ChildPath $script)

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails
}

Describe 'Invoke-WhsCIBuild when running multiple PowerShell scripts' {
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

Describe 'Invoke-WhsCIBuild when a task path does not exist' {
    $path = 'FubarSnafu'
    $configPath = New-TestWhsBuildFile -TaskName 'Pester' -Path $path
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue
    
    It 'should write an error that the file does not exist' {
        $Global:Error[0] | Should Match 'not exist'
    }
}

Describe 'Invoke-WhsCIBuild when a task path is absolute' {
    $configPath = New-TestWhsBuildFile -TaskName 'Pester' -Path 'C:\FubarSnafu'
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    It 'should write an error that the path is absolute' {
        $Global:Error[0] | Should Match 'absolute'
    }
}

Describe 'Invoke-WhsCIBuild when a task path is missing' {
    $configPath = New-TestWhsBuildFile -Yaml @'
BuildTasks:
- Pester:
    Pith: fubar
'@
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue
    
    It 'should write an error that the path is mandatory' {
        $Global:Error[0] | Should Match 'is mandatory'
    }
}


Describe 'Invoke-WhsCIBuild when a task has no properties' {
    $configPath = New-TestWhsBuildFile -Yaml @'
BuildTasks:
- Pester:
'@
    
    $Global:Error.Clear()

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    It 'should write an error that the task is incomplete' {
        $Global:Error[0] | Should Match 'is mandatory'
    }
}

Describe 'Invoke-WhsCIBuild when a task has no properties' {
    $project = 'developer.csproj'
    $version = '45.4.3-beta.1'
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $project -Version $version
    New-MSBuildProject -FileName $project
    Mock -CommandName 'Invoke-MSBuild' -ModuleName 'WhsCI' -Verifiable
    
    Invoke-Build -ByDeveloper -WithConfig $configPath 

    Assert-DotNetProjectBuildConfiguration 'Debug' -ConfigurationPath $configPath -AtVersion $version -ProjectName $project
}

Describe 'Invoke-WhsCIBuild when compiling a .NET project on the build server' {
    $project = 'project.csproj'
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $project
    
    New-MSBuildProject -FileName $project
    Mock -CommandName 'Invoke-MSBuild' -ModuleName 'WhsCI' -Verifiable
    
    Invoke-Build -ByJenkins -WithConfig $configPath

    Assert-DotNetProjectBuildConfiguration 'Release'
}

Describe 'Invoke-WhsCIBuild when running an unknown task' {
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

Describe 'Invoke-WhsCIBuild when path contains wildcards' {
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path '*.csproj'
    New-MSBuildProject -FileName 'developer.csproj','developer2.csproj'

    Invoke-Build -ByJenkins -WithConfig $configPath

    Assert-DotNetProjectsCompiled -ConfigurationPath $configPath -ProjectName 'developer.csproj','developer2.csproj'
}

Describe 'Invoke-WhsCIBuild when running NUnit tests' {
    $assemblyNames = 'assembly.dll','assembly2.dll'
    $configPath = New-TestWhsBuildFile -TaskName 'NUnit2' -Path $assemblyNames

    New-NUnitTestAssembly -Configuration $configPath -Assembly $assemblyNames

    $downloadroot = Join-Path -Path $TestDrive.Fullname -ChildPath 'downloads'
    Invoke-Build -ByJenkins -WithConfig $configPath -DownloadRoot $downloadroot

    Assert-NUnitTestsRun -ConfigurationPath $configPath `
                         -ExpectedAssembly $assemblyNames

    It 'should download NUnitRunners' {
        (Join-Path -Path $downloadroot -ChildPath 'packages\NUnit.Runners.*.*.*') | Should Exist
    }
}

Describe 'Invoke-WhsCIBuild when running failing NUnit2 tests' {
    $assemblyNames = 'assembly.dll','assembly2.dll'
    $configPath = New-TestWhsBuildFile -TaskName 'NUnit2' -Path $assemblyNames

    New-NUnitTestAssembly -Configuration $configPath -Assembly $assemblyNames -ThatFail

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails
    
    Assert-NUnitTestsRun -ConfigurationPath $configPath -ExpectedAssembly $assemblyNames
}

Describe 'Invoke-WhsCIBuild when running NUnit2 tests from multiple bin directories' {
    $assemblyNames = 'BinOne\assembly.dll','BinTwo\assembly2.dll'
    $configPath = New-TestWhsBuildFile -TaskName 'NUnit2' -Path $assemblyNames

    New-NUnitTestAssembly -Configuration $configPath -Assembly $assemblyNames

    Invoke-Build -ByJenkins -WithConfig $configPath

    $root = Split-Path -Path $configPath -Parent
    Assert-NUnitTestsRun -ConfigurationPath $configPath -ExpectedAssembly 'assembly.dll' -ExpectedBinRoot (Join-Path -Path $root -ChildPath 'BinOne')
    Assert-NUnitTestsRun -ConfigurationPath $configPath -ExpectedAssembly 'assembly2.dll' -ExpectedBinRoot (Join-Path -Path $root -ChildPath 'BinTwo')
}

Describe 'Invoke-WhsCIBuild when output exists from a previous build' {
    $project = 'project.csproj'
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $project
    New-MSBuildProject -FileName $project

    $root = $configPath | Split-Path -Parent
    $output = Join-Path -Path $root -ChildPath '.output'
    Install-Directory -Path $output

    $outputSubDir = Join-Path -Path $output -ChildPath 'fubar'
    Install-Directory -Path $outputSubDir

    $outputFile = Join-Path -Path $outputSubDir -ChildPath 'snafu'
    '' | Set-Content -Path $outputFile

    Invoke-Build -ByJenkins -WithConfig $configPath

    It 'should delete pre-existing output' {
        $outputFile | Should Not Exist
    }
}

Describe 'Invoke-WhsCIBuild when a task fails' {
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

Describe 'Invoke-WhsCIBuild when creating a NuGet package with an invalid project' {
    $project = 'project.csproj'
    $configPath = New-TestWhsBuildFile -TaskName 'NuGetPack' -Path $project
    New-MSBuildProject -FileName $project
    
    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails 2>&1

    function Assert-NuGetPackagesNotCreated
    {
        param(
            $ConfigurationPath
        )

        It 'should write an error' {
            $Global:Error[0] | Should Match 'pack command failed'
        }

        It 'should not create any .nupkg files' {
            (Join-Path -Path ($ConfigurationPath | Split-Path) -ChildPath '.output\*.nupkg') | Should Not Exist
        }
    }
    Assert-NuGetPackagesNotCreated -ConfigurationPath $configPath
}

Describe 'Invoke-WhsCIBuild when version looks like a date after 2000 and isn''t quoted' {
    $configPath = New-TestWhsBuildFile -Yaml @'
Version: 2.13.1
'@

    $Global:Error.Clear()

    Invoke-Build -ByDeveloper -WithConfig $configPath

    it 'should not write any errors' {
        $Global:Error | Should Not Match 'is not a valid semantic version' 
    }
}

Describe 'Invoke-WhsCIBuild when version looks like a date before 1900 and isn''t quoted' {
    $configPath = New-TestWhsBuildFile -Yaml @'
Version: 2.13.80
'@

    $Global:Error.Clear()

    Invoke-Build -ByDeveloper -WithConfig $configPath

    it 'should not write any errors' {
        $Global:Error | Should Not Match 'is not a valid semantic version' 
    }
}
<#
Describe 'Invoke-WhsCIBuild when creating a WHS package' {
    $version = '4.23.80'
    $dirs = 'dir1','dir2'
    $whitelist = '*.html','*.txt'
    $configPath = New-TestWhsBuildFile -PackageName 'MyPack' -Whitelist $whitelist -Path $dirs -Version $version
    $root = $configPath | Split-Path 
    $dir1Path = Join-Path -Path $root -ChildPath 'dir1'
    $dir2Path = Join-Path -Path $root -ChildPath 'dir2'
    $dir1Path,$dir2Path | ForEach-Object { 
        $dirPath = $_
        Install-Directory -Path $dirPath
    }

    Mock -CommandName 'New-WhsAppPackage' -ModuleName 'WhsCI' -Verifiable

    Invoke-Build -ByJenkins -WithConfig $configPath

    $expectedWhitelist = $whitelist

    Assert-WhsAppPackageCreated -ConfigurationPath $configPath -Name 'MyPack' -Version $version -ExpectedDir $dirs -ExpectedWhitelist $whitelist
}
#>