
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
        $ThatFails
    )

    $root = (Get-Item -Path 'TestDrive:').FullName

    foreach( $name in $FileName )
    {
        if( -not ([IO.Path]::IsPathRooted($name) ) )
        {
            $name = Join-Path -Path $root -ChildPath $name
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


function New-WhsCITestContext
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

        [Switch]
        $UseActualProGet,

        [string]
        $BuildConfiguration = 'Release',

        [string]
        $ConfigurationPath,

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

    $progetUri = 'https://proget.example.com'
    if( $UseActualProGet )
    {
        $progetUri = Get-ProGetUri -Environment 'Dev'
    }

    $optionalArgs = @{ }
    $testByBuildServerMock = { return $true }
    if( $PSCmdlet.ParameterSetName -eq 'ByBuildServer' )
    {
        $optionalArgs = @{
                           'BBServerCredential' = (New-Credential -UserName 'bbserver' -Password 'bbserver');
                           'BBServerUri' = 'https://bitbucket.example.com/'
                           'BuildMasterUri' = 'https://buildmaster.example.com/'
                           'BuildMasterApiKey' = 'racecaracecar';
                           'ProGetCredential' = (New-Credential -UserName 'proget' -Password 'proget');
                         }
    }
    else
    {
        $testByBuildServerMock = { return $false }
    }

    Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith $testByBuildServerMock

    if( $DownloadRoot )
    {
        $optionalArgs['DownloadRoot'] = $DownloadRoot
    }

    if( -not $ConfigurationPath )
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

        $ConfigurationPath = Join-Path -Path $ForBuildRoot -ChildPath 'whsbuild.yml'
        $configData | ConvertTo-Yaml | Set-Content -Path $ConfigurationPath
    }

    $context = New-WhsCIContext -ConfigurationPath $ConfigurationPath -BuildConfiguration $BuildConfiguration -ProGetUri $progetUri @optionalArgs
    if( $InReleaseMode )
    {
        $context.BuildConfiguration = 'Release'
    }

    if( $ForOutputDirectory -and $context.OutputDirectory -ne $ForOutputDirectory )
    {
        $context.OutputDirectory = $ForOutputDirectory
        New-Item -Path $context.OutputDirectory -ItemType 'Directory' -Force -ErrorAction Ignore | Out-String | Write-Debug
    }

    return $context
}

Export-ModuleMember -Function '*'

