


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
[assembly: AssemblyVersion("1.0.0")]
[assembly: AssemblyFileVersion("1.0.0")]
[assembly: AssemblyInformationalVersion("1.0.0")]
'@ | Set-Content -Path (Join-Path -Path $RootPath -ChildPath 'AssemblyInfo.cs') 
}

function New-MSBuildProject
{
    param(
        [string[]]
        $FileName,

        [Switch]
        $ThatFails,

        [string]
        $BuildRoot
    )

    if( -not $BuildRoot )
    {
        $BuildRoot = (Get-Item -Path 'TestDrive:').FullName
    }

    if( -not (Test-Path -Path $BuildRoot -PathType Container) )
    {
        New-Item -Path $BuildRoot -ItemType 'Directory' -Force | Out-Null
    }

    foreach( $name in $FileName )
    {
        if( -not ([IO.Path]::IsPathRooted($name) ) )
        {
            $name = Join-Path -Path $BuildRoot -ChildPath $name
        }

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
"@ | Set-Content -Path $name

        New-AssemblyInfo -RootPath ($name | Split-Path)

        $name
    }
}


function New-WhiskeyTestContext
{
    param(
        [Switch]
        $WithMockToolData,

        [string]
        $ForBuildRoot,

        [string]
        $ForTaskName,

        [string]
        $ForOutputDirectory,

        [switch]
        $InReleaseMode,

        [string]
        $ForApplicationName,

        [string]
        $ForReleaseName,        
        [Parameter(Mandatory=$true,ParameterSetName='ByBuildServer')]
        [Switch]
        [Alias('ByBuildServer')]
        $ForBuildServer,

        [Parameter(Mandatory=$true,ParameterSetName='ByDeveloper')]
        [Switch]
        [Alias('ByDeveloper')]
        $ForDeveloper,

        [SemVersion.SemanticVersion]
        $ForVersion = [SemVersion.SemanticVersion]'1.2.3-rc.1+build',

        [string]
        $BuildConfiguration = 'Release',

        [string]
        $ConfigurationPath,

        [string]
        $ForYaml,

        [hashtable]
        $TaskParameter = @{},

        [string]
        $DownloadRoot
    )

    Set-StrictMode -Version 'Latest'

    if( -not $ForBuildRoot )
    {
        $ForBuildRoot = $TestDrive.FullName
    }

    if( -not [IO.Path]::IsPathRooted($ForBuildRoot) )
    {
        $ForBuildRoot = Join-Path -Path $TestDrive.FullName -ChildPath $ForBuildRoot
    }

    $progetUris = @( 'https://proget.example.com', 'https://proget.another.example.com' )
    $NpmFeedUri = 'https://registry.npmjs.org/'
    $NuGetFeedUri = 'https://nuget.org/'
    $PowerShellFeedUri = 'https://powershellgallery.com/api/v2/'

    $optionalArgs = @{ }
    $testByBuildServerMock = { return $true }
    if( $PSCmdlet.ParameterSetName -eq 'ByBuildServer' )
    {
        $optionalArgs = @{
                           'BBServerCredential' = (New-Credential -UserName 'bbserver' -Password 'bbserver');
                           'BBServerUri' = 'https://bitbucket.example.com/'
                           'ProGetCredential' = (New-Credential -UserName 'proget' -Password 'proget');
                         }
        $gitBranch = 'origin/develop'
        $filter = { $Path -eq 'env:GIT_BRANCH' }
        $mock = { [pscustomobject]@{ Value = $gitBranch } }.GetNewClosure()
        Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -ParameterFilter $filter -MockWith $mock
        Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -ParameterFilter $filter -MockWith { return $true }
        Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return $ForVersion }.GetNewClosure()
    }
    else
    {
        $testByBuildServerMock = { return $false }
    }

    Mock -CommandName 'Test-WhiskeyRunByBuildServer' -ModuleName 'Whiskey' -MockWith $testByBuildServerMock

    if( $DownloadRoot )
    {
        $optionalArgs['DownloadRoot'] = $DownloadRoot
    }

    if( -not $ConfigurationPath )
    {
        $ConfigurationPath = Join-Path -Path $ForBuildRoot -ChildPath 'whiskey.yml'
        if( $ForYaml )
        {
            $ForYaml | Set-Content -Path $ConfigurationPath
        }
        else
        {
            $configData = @{
                                'Version' = $ForVersion.ToString()
                           }
            if( $ForApplicationName )
            {
                $configData['ApplicationName'] = $ForApplicationName
            }

            if( $ForReleaseName )
            {
                $configData['ReleaseName'] = $ForReleaseName
            }

            if( $ForTaskName )
            {
                $configData['BuildTasks'] = @( @{ $ForTaskName = $TaskParameter } )
            }

            $configData | ConvertTo-Yaml | Set-Content -Path $ConfigurationPath
        }
    }
    $progetArgs = @{
                    NpmFeedUri = $NpmFeedUri;
                    NuGetFeedUri = $NuGetFeedUri;
                    PowerShellFeedUri = $PowerShellFeedUri;
                    }

    $context = New-WhiskeyContext -Environment 'verification' -ConfigurationPath $ConfigurationPath -BuildConfiguration $BuildConfiguration @optionalArgs @progetArgs
    if( $InReleaseMode )
    {
        $context.BuildConfiguration = 'Release'
    }

    if( $ForOutputDirectory -and $context.OutputDirectory -ne $ForOutputDirectory )
    {
        Remove-Item -Path $context.OutputDirectory -Recurse -Force
        $context.OutputDirectory = $ForOutputDirectory
        New-Item -Path $context.OutputDirectory -ItemType 'Directory' -Force -ErrorAction Ignore | Out-String | Write-Debug
    }

    return $context
}

Export-ModuleMember -Function '*'



