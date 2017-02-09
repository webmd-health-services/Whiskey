Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\WhsAutomation\Import-WhsAutomation.ps1' -Resolve)

Invoke-WhsCIBuild -ConfigurationPath (Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whsbuild.yml' -Resolve) -BuildConfiguration 'Release'


#region Assertions
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

            # For some reason, when run under Jenkins, there is a global $commitID variable 
            # that hides the parameter, so we need to explicitly set the parameter.
            $CommitID = $null
            if( $PSBoundParameters.ContainsKey('CommitID') )
            {
                $CommitID = $PSBoundParameters['CommitID']
            }
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
#endRegion

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
        $NoGitRepository
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

    if( -not ($NoGitRepository) )
    {
        Mock -CommandName 'Assert-WhsCIVersionAvailable' -ModuleName 'WhsCI' -MockWith { return $Version }
    }

    $configuration = Get-WhsSetting -Environment $environment -Name '.NETProjectBuildConfiguration'
    $devParams = @{ }
    if( (Test-WhsCIRunByBuildServer) )
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

    $threwException = $false
    try
    {
        Invoke-WhsCIMSBuildTask -ConfigurationPath $WithConfig `
                                -BuildConfiguration $configuration `
                                @devParams `
                                @downloadRootParam
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

#region Mocks
function New-MockBitbucketServer
{
    Mock -CommandName 'Set-BBServerCommitBuildStatus' -ModuleName 'WhsCI' -Verifiable
}

function New-MockDeveloperEnvironment
{
    Mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -MockWith { $false } -ParameterFilter { $Path -eq 'env:JENKINS_URL' }
    Mock -CommandName 'Test-Path' -MockWith { $false } -ParameterFilter { $Path -eq 'env:JENKINS_URL' }
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
#endRegion


$failingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2FailingTest\bin\Release\NUnit2FailingTest.dll'
$passingNUnit2TestAssemblyPath = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\NUnit2PassingTest\bin\Release\NUnit2PassingTest.dll'

<#
$nunitWhsBuildYmlFile = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies\whsbuild.yml'

Describe 'Invoke-WhsCIBuild.when building real projects' {
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

    $outputRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Assemblies'
    $outputRoot = Get-WhsCIOutputDirectory -WorkingDirectory $outputRoot
    foreach( $name in @( 'Passing', 'Failing' ) )
    {
        It ('should create NuGet package for NUnit2{0}Test' -f $name) {
            (Join-Path -Path $outputRoot -ChildPath ('NUnit2{0}Test.1.2.3-final.nupkg' -f $name)) | Should Exist
        }

        It ('should create a NuGet symbols package for NUnit2{0}Test' -f $name) {
            (Join-Path -Path $outputRoot -ChildPath ('NUnit2{0}Test.1.2.3-final.symbols.nupkg' -f $name)) | Should Exist
        }
    }
}
#>
Describe 'Invoke-WhsCIBuild.when Version in configuration file is invalid' {
    $configPath = New-TestWhsBuildFile -Yaml @'
Version: fubar
'@
    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    It 'should write an error' {
        $Global:Error[0] | Should Match 'not a valid semantic version'
    }
}

Describe 'Invoke-WhsCIBuild.when building NET assemblies.' {
    $version = '3.2.1-rc.1'
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path 'FubarSnafu.csproj' -Version $version

    New-MSBuildProject -FileName 'FubarSnafu.csproj'

    Invoke-Build -ByJenkins -WithConfig $configPath

    Assert-DotNetProjectsCompiled -ConfigurationPath $configPath -ProjectName 'FubarSnafu.csproj' -AtVersion $version
}

Describe 'Invoke-WhsCIBuild.when building multiple projects' {
    $projects = @( 'FubarSnafu.csproj','SnafuFubar.csproj' )
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $projects

    New-MSBuildProject -FileName $projects

    Invoke-Build -ByJenkins -WithConfig $configPath

    Assert-DotNetProjectsCompiled -ConfigurationPath $configPath -ProjectName $projects
}

Describe 'Invoke-WhsCIBuild.when compilation fails' {
    $project = 'FubarSnafu.csproj' 
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $project
    
    New-MSBuildProject -FileName $project -ThatFails

    Invoke-Build -ByJenkins -WithConfig $configPath -ThatFails -ErrorAction SilentlyContinue

    Assert-DotNetProjectsCompilationFailed -ConfigurationPath $configPath -ProjectName $project
}

Describe 'Invoke-WhsCIBuild.when multiple AssemblyInfoCs files' {
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

Describe 'Invoke-WhsCIBuild.when a developer is compiling dotNET project' {
    $project = 'developer.csproj'
    $version = '45.4.3-beta.1'
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $project -Version $version
    New-MSBuildProject -FileName $project
    Mock -CommandName 'Invoke-MSBuild' -ModuleName 'WhsCI' -Verifiable
    
    Invoke-Build -ByDeveloper -WithConfig $configPath 

    Assert-DotNetProjectBuildConfiguration 'Debug' -ConfigurationPath $configPath -AtVersion $version -ProjectName $project
}

Describe 'Invoke-WhsCIBuild.when compiling a dotNET project on the build server' {
    $project = 'project.csproj'
    $configPath = New-TestWhsBuildFile -TaskName 'MSBuild' -Path $project
    
    New-MSBuildProject -FileName $project
    Mock -CommandName 'Invoke-MSBuild' -ModuleName 'WhsCI' -Verifiable
    
    Invoke-Build -ByJenkins -WithConfig $configPath

    Assert-DotNetProjectBuildConfiguration 'Release'
}

