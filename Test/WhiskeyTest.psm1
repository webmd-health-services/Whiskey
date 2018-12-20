$numRobocopyThreads = 1
if( (Get-Command 'Get-CimInstance' -ErrorAction Ignore) )
{
    Write-Debug 'Get-CimInstance exists.'
    $numRobocopyThreads = Get-CimInstance -ClassName 'Win32_Processor' | 
        Select-Object -ExpandProperty 'NumberOfLogicalProcessors' | 
        Measure-Object -Sum | 
        Select-Object -ExpandProperty 'Sum'
    $numRobocopyThreads *= 2
}
else
{
    if( [Environment]::ProcessorCount )
    {
        $numRobocopyThreads = [Environment]::ProcessorCount * 2
    }
}

$downloadCachePath = Join-Path -Path $PSScriptRoot -ChildPath '.downloadcache'
if( -not (Test-Path -Path $downloadCachePath -PathType Container) )
{
    New-Item -Path $downloadCachePath -ItemType 'Directory'
}

function ConvertTo-Yaml
{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
        [System.Object]$Data,
        [Parameter(Mandatory=$false)]
        [string]$OutFile,
        [switch]$JsonCompatible=$false,
        [switch]$Force=$false
    )
    BEGIN {
        $d = [System.Collections.Generic.List[object]](New-Object "System.Collections.Generic.List[object]")
    }
    PROCESS {
        if($data -ne $null) {
            $d.Add($data)
        }
    }
    END {
        if($d -eq $null -or $d.Count -eq 0){
            return
        }
        if($d.Count -eq 1) {
            $d = $d[0]
        }
        #$norm = Convert-PSObjectToGenericObject $d
        if($OutFile) {
            $parent = Split-Path $OutFile
            if(!(Test-Path $parent)) {
                Throw "Parent folder for specified path does not exist"
            }
            if((Test-Path $OutFile) -and !$Force){
                Throw "Target file already exists. Use -Force to overwrite."
            }
            $wrt = New-Object "System.IO.StreamWriter" $OutFile
        } else {
            $wrt = New-Object "System.IO.StringWriter"
        }

        $options = 0
        try {
            $builder = New-Object 'YamlDotNet.Serialization.SerializerBuilder'
            if ($JsonCompatible) {
                # No indent options :~(
                $builder.JsonCompatible()
            }
            $serializer = $builder.Build()
            $serializer.Serialize($wrt, $d)
        } finally {
            $wrt.Close()
        }
        if($OutFile){
            return
        }else {
            return $wrt.ToString()
        }
    }
}

function Install-Node
{
    param(
        [string[]]
        $WithModule
    )

    $toolAttr = New-Object 'Whiskey.RequiresToolAttribute' 'Node','NodePath'
    Install-WhiskeyTool -ToolInfo $toolAttr -InstallRoot $downloadCachePath -TaskParameter @{ }

    $nodeRoot = Join-Path -Path $downloadCachePath -ChildPath '.node'
    $modulesRoot = Join-Path -Path $nodeRoot -ChildPath 'node_modules'
    foreach( $name in $WithModule )
    {
        if( (Test-Path -Path (Join-Path -Path $modulesRoot -ChildPath $name) -PathType Container) )
        {
            continue
        }

        Install-WhiskeyTool -ToolInfo (New-Object 'Whiskey.RequiresToolAttribute' ('NodeModule::{0}' -f $name),('{0}Path' -f $name)) -InstallRoot $downloadCachePath -TaskParameter @{ }
    }

    $destinationDir = Join-Path -Path $TestDrive.FullName -ChildPath '.node'
    if( -not (Test-Path -Path $destinationDir -PathType Container) )
    {
        New-Item -Path $destinationDir -ItemType 'Directory'
    }

    $exclude = & {
                        '/XF'
                        '*.zip'
                        Get-ChildItem -Path $modulesRoot |
                            Where-Object { $_.Name -ne 'npm' -and $WithModule -notcontains $_.Name } |
                            ForEach-Object {
                                '/XD'
                                $_.FullName
                            }
                }
    robocopy (Join-Path -Path $downloadCachePath -ChildPath '.node') $destinationDir /COPY:D /E /NP /NFL /NDL /NJH /NJS /R:0 ('/MT:{0}' -f $numRobocopyThreads) $exclude

    Get-ChildItem -Path (Join-Path -Path $nodeRoot -ChildPath '*') -Filter '*.zip' |
        ForEach-Object { Join-Path -Path $destinationDir -ChildPath $_.Name } |
        Where-Object { -not (Test-Path -Path $_ -PathType Leaf) } |
        ForEach-Object { New-Item -Path $_ -ItemType 'File' }
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
        [string]
        $ForBuildRoot,

        [string]
        $ForTaskName,

        [string]
        $ForOutputDirectory,

        [switch]
        $InReleaseMode,

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
        $ConfigurationPath,

        [string]
        $ForYaml,

        [hashtable]
        $TaskParameter = @{},

        [string]
        $DownloadRoot,

        [Switch]
        $IgnoreExistingOutputDirectory,

        [Switch]
        $InCleanMode,

        [Switch]
        $InInitMode
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

    if( $ConfigurationPath )
    {
        $configData = Import-WhiskeyYaml -Path $ConfigurationPath
    }
    else
    {
        $ConfigurationPath = Join-Path -Path $ForBuildRoot -ChildPath 'whiskey.yml'
        if( $ForYaml )
        {
            $ForYaml | Set-Content -Path $ConfigurationPath
            $configData = Import-WhiskeyYaml -Yaml $ForYaml
        }
        else
        {
            $configData = @{ }
            if( $ForVersion )
            {
                $configData['Version'] = $ForVersion.ToString()
            }

            if( $ForTaskName )
            {
                $configData['Build'] = @( @{ $ForTaskName = $TaskParameter } )
            }

            $configData | ConvertTo-Yaml | Set-Content -Path $ConfigurationPath
        }
    }

    $context = New-WhiskeyContextObject
    $context.BuildRoot = $ForBuildRoot
    $context.Environment = 'Verificaiton'
    $context.ConfigurationPath = $ConfigurationPath
    $context.DownloadRoot = $context.BuildRoot
    $context.Configuration = $configData

    if( $InCleanMode )
    {
        $context.RunMode = [Whiskey.RunMode]::Clean
    }
    elseif( $InInitMode )
    {
        $context.RunMode = [Whiskey.RunMode]::Initialize
    }

    if( -not $ForOutputDirectory )
    {
        $ForOutputDirectory = Join-Path -Path $context.BuildRoot -ChildPath '.output'
    }
    $context.OutputDirectory = $ForOutputDirectory

    if( $DownloadRoot )
    {
        $context.DownloadRoot
    }

    $runBy = [Whiskey.RunBy]::BuildServer
    if( $PSCmdlet.ParameterSetName -eq 'ByDeveloper' )
    {
        $runBy = [Whiskey.RunBy]::Developer
    }
    $context.Publish = $PSCmdlet.ParameterSetName -eq 'ByBuildServer'
    $context.RunBy = $runBy

    if( $ForTaskName )
    {
        $context.TaskName = $ForTaskName
    }

    if( $ForVersion )
    {
        $context.Version.SemVer2 = $ForVersion
        $context.Version.SemVer2NoBuildMetadata = New-Object 'SemVersion.SemanticVersion' $ForVersion.Major,$ForVersion.Minor,$ForVersion.Patch,$ForVersion.Prerelease,$null
        $context.Version.SemVer1 = New-Object 'SemVersion.SemanticVersion' $ForVersion.Major,$ForVersion.Minor,$ForVersion.Patch,($ForVersion.Prerelease -replace '[^A-Za-z0-9]',''),$null
        $context.Version.Version = [version]('{0}.{1}.{2}' -f $ForVersion.Major,$ForVersion.Minor,$ForVersion.Patch)
    }

    if( -not $IgnoreExistingOutputDirectory -and (Test-Path -Path $context.OutputDirectory) )
    {
        Remove-Item -Path $context.OutputDirectory -Recurse -Force
    }
    New-Item -Path $context.OutputDirectory -ItemType 'Directory' -Force -ErrorAction Ignore | Out-String | Write-Debug

    return $context
}

function Remove-Node
{
    Remove-WhiskeyFileSystemItem -Path (Join-Path -Path $TestDrive.FullName -ChildPath '.node\node_modules')
}

function Remove-DotNet
{
    Get-Process -Name 'dotnet' -ErrorAction Ignore |
        Where-Object { $_.Path -like ('{0}\*\.dotnet\dotnet' -f ([IO.Path]::GetTempPath())) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

    Remove-WhiskeyFileSystemItem -Path (Join-Path -Path $TestDrive.FullName -ChildPath '.dotnet')
}

. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Use-CallerPreference.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\New-WhiskeyContextObject.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\New-WhiskeyVersionObject.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\New-WhiskeyBuildMetadataObject.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Import-WhiskeyYaml.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Get-WhiskeyMSBuildConfiguration.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Invoke-WhiskeyRobocopy.ps1' -Resolve)
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\Functions\Remove-WhiskeyFileSystemItem.ps1' -Resolve)

Export-ModuleMember -Function '*'



