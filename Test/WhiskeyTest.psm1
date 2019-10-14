
$exportPlatformVars = $false
if( -not (Get-Variable -Name 'IsLinux' -ErrorAction Ignore) )
{
    $IsLinux = $false
    $IsMacOS = $false
    $IsWindows = $true
    $exportPlatformVars = $true
}

$WhiskeyPlatform = [Whiskey.Platform]::Windows
if( $IsLinux )
{
    $WhiskeyPlatform = [Whiskey.Platform]::Linux
}
elseif( $IsMacOS )
{
    $WhiskeyPlatform = [Whiskey.Platform]::MacOS
}
$downloadCachePath = Join-Path -Path $PSScriptRoot -ChildPath ('.downloadcache-{0}' -f $WhiskeyPlatform)
$WhiskeyTestDownloadCachePath = $downloadCachePath

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

function Import-WhiskeyTestModule
{
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Switch]$Force
    )

    $modulesRoot = Join-Path -Path $PSScriptRoot -ChildPath ('..\{0}' -f $PSModulesDirectoryName) -Resolve
    if( $env:PSModulePath -notlike ('{0}{1}*' -f $modulesRoot,[IO.Path]::PathSeparator) )
    {
        $env:PSModulePath = '{0}{1}{2}' -f $modulesRoot,[IO.Path]::PathSeparator,$env:PSModulePath
    }
    Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath $Name -Resolve) -Force:$Force
}

function Initialize-WhiskeyTestPSModule
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BuildRoot,

        [string[]]$Name
    )

    $destinationRoot = Join-Path -Path $BuildRoot -ChildPath $PSModulesDirectoryName
    Write-WhiskeyTestTiming ('Copying Modules  {0}  START' -f $destinationRoot) 
    if( -not (Test-Path -Path $destinationRoot -PathType Container) )
    {
        New-Item -Path $destinationRoot -ItemType 'Directory' | Out-Null
    }

    $Name = & {
        # Don't continually download modules.
        'PackageManagement'
        'PowerShellGet'
        $Name
    }
    
    foreach( $module in (Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath ('..\{0}' -f $PSModulesDirectoryName) -Resolve) -Directory))
    {
        if( $module.Name -notin $Name )
        {
            continue
        }
        
        if( (Test-Path -Path (Join-Path -Path $destinationRoot -ChildPath $module.Name) ) )
        {
            continue
        }

        Write-WhiskeyTestTiming -Message ('{0} -> {1}' -f $module.FullName,$destinationRoot)
        Copy-Item -Path $module.FullName -Destination $destinationRoot -Recurse
    }
    
    Write-WhiskeyTestTiming -Message '                 END' 
}

function Install-Node
{
    param(
        [string[]]$WithModule,

        [string]$BuildRoot
    )

    $toolAttr = New-Object 'Whiskey.RequiresToolAttribute' 'Node','NodePath'
    Install-WhiskeyTool -ToolInfo $toolAttr -InstallRoot $downloadCachePath -TaskParameter @{ }

    $nodeRoot = Join-Path -Path $downloadCachePath -ChildPath '.node'

    if( -not $BuildRoot )
    {
        Write-Warning -Message ('Install-Node''s BuildRoot parameter will eventually be made mandatory. Please update usages.')
        $BuildRoot = $TestDrive.FullName
    }

    $destinationDir = Join-Path -Path $BuildRoot -ChildPath '.node'
    $modulesRoot = Join-Path -Path $nodeRoot -ChildPath 'node_modules'
    $modulesDestinationDir = Join-Path -Path $destinationDir -ChildPath 'node_modules'
    if( -not $IsWindows )
    {
        $modulesRoot = Join-Path -Path $nodeRoot -ChildPath 'lib/node_modules'
        $modulesDestinationDir = Join-Path -Path $destinationDir -ChildPath 'lib/node_modules'
    }
    foreach( $name in $WithModule )
    {
        if( (Test-Path -Path (Join-Path -Path $modulesRoot -ChildPath $name) -PathType Container) )
        {
            continue
        }

        Install-WhiskeyTool -ToolInfo (New-Object 'Whiskey.RequiresToolAttribute' ('NodeModule::{0}' -f $name),('{0}Path' -f $name)) -InstallRoot $downloadCachePath -TaskParameter @{ }
    }

    if( -not (Test-Path -Path $destinationDir -PathType Container) )
    {
        New-Item -Path $destinationDir -ItemType 'Directory'
    }

    Write-Debug -Message ('Copying {0} -> {1}' -f $nodeRoot,$destinationDir)
    Copy-Item -Path (Join-Path -Path $nodeRoot -ChildPath '*') -Exclude '*.zip','*.tar.*','lib','node_modules' -Destination $destinationDir -Recurse -ErrorAction Ignore

    Get-ChildItem -Path $modulesRoot |
        Where-Object { $_.Name -eq 'npm' -or $WithModule -contains $_.Name } |
        ForEach-Object {
            $moduleDestinationDir = Join-Path -Path $modulesDestinationDir -ChildPath $_.Name
            if( $IsWindows )
            {
                if( -not (Test-Path -Path $moduleDestinationDir -PathType Container) )
                {
                    New-Item -Path $moduleDestinationDir -ItemType 'Directory' -Force | Out-Null
                }
                $robocopyParameter = @{
                    'Source' = $_.FullName;
                    'Destination' = $moduleDestinationDir
                }
                Invoke-WhiskeyPrivateCommand -Name 'Invoke-WhiskeyRobocopy' -Parameter $robocopyParameter
            }
            else
            {
                Copy-Item -Path $_.FullName -Destination $moduleDestinationDir -Recurse
            }
        }

    Get-ChildItem -Path (Join-Path -Path $nodeRoot -ChildPath '*') -Include '*.zip','*.tar.*' |
        ForEach-Object { Join-Path -Path $destinationDir -ChildPath $_.Name } |
        Where-Object { -not (Test-Path -Path $_ -PathType Leaf) } |
        ForEach-Object { New-Item -Path $_ -ItemType 'File' }
}

function Invoke-WhiskeyPrivateCommand
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [hashtable]$Parameter = @{}
    )

    $Global:Name = $Name
    $Global:Parameter = $Parameter

    if( $VerbosePreference -eq 'Continue' )
    {
        $Parameter['Verbose'] = $true
    }

    $Parameter['ErrorAction'] = $ErrorActionPreference

    try
    {
        InModuleScope 'Whiskey' { 
            & $Name @Parameter 
        }
    }
    finally
    {
        Remove-Variable -Name 'Parameter' -Scope 'Global'
        Remove-Variable -Name 'Name' -Scope 'Global'
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
        [string]$ForBuildRoot,

        [string]$ForTaskName,

        [string]$ForOutputDirectory,

        [switch]$InReleaseMode,

        [Parameter(Mandatory=$true,ParameterSetName='ByBuildServer')]
        [Alias('ByBuildServer')]
        [Switch]$ForBuildServer,

        [Parameter(Mandatory=$true,ParameterSetName='ByDeveloper')]
        [Alias('ByDeveloper')]
        [Switch]$ForDeveloper,

        [SemVersion.SemanticVersion]$ForVersion = [SemVersion.SemanticVersion]'1.2.3-rc.1+build',

        [string]$ConfigurationPath,

        [string]$ForYaml,

        [hashtable]$TaskParameter = @{},

        [string]$DownloadRoot,

        [Switch]$IgnoreExistingOutputDirectory,

        [Switch]$InCleanMode,

        [Switch]$InInitMode,

        [string[]]$IncludePSModule
    )

    Set-StrictMode -Version 'Latest'

    if( -not $ForBuildRoot )
    {
        Write-Warning -Message ('New-WhiskeyTestContext''s "ForBuildRoot" parameter will soon become mandatory. Please update usages.')
        $ForBuildRoot = $TestDrive.FullName
    }

    if( -not [IO.Path]::IsPathRooted($ForBuildRoot) )
    {
        Write-Warning -Message ('New-WhiskeyTestContext''s "ForBuildRoot" parameter will soon become mandatory and will be required to be an absolute path. Please update usages.')
        $ForBuildRoot = Join-Path -Path $TestDrive.FullName -ChildPath $ForBuildRoot
    }

    if( $ConfigurationPath )
    {
        $configData = Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyYaml' -Parameter @{ 'Path' = $ConfigurationPath }
    }
    else
    {
        $ConfigurationPath = Join-Path -Path $ForBuildRoot -ChildPath 'whiskey.yml'
        if( $ForYaml )
        {
            $ForYaml | Set-Content -Path $ConfigurationPath
            $configData = Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyYaml' -Parameter @{ 'Yaml' = $ForYaml }
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

    $context = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyContextObject'
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

    Initialize-WhiskeyTestPSModule -BuildRoot $context.BuildRoot -Name $IncludePSModule

    return $context
}

function New-WhiskeyTestRoot
{
    # Eventually, I hope Invoke-Pester supports running individual `It` blocks (as of this writing, you can only run 
    # individual `Describe` blocks, which is why we use a single-It-per-Describe pattern). Unfortunately, Pester's test
    # drive is setup and torn down at the Describe block, which means all our tests were written with the expectation 
    # that they had the whole test drive to themselves. This function exists to give a test its own directory inside the
    # test drive. Today, it doesn't matter. But with it in place, we'll be able to more easily migrate to Pester 5, 
    # which will allow running specific `It` blocks.
    $testRoot = Join-Path -Path $TestDrive.FullName -ChildPath ([IO.Path]::GetRandomFileName())
    New-Item -Path $testRoot -ItemType 'Directory' | Out-Null
    return $testRoot
}

function Remove-Node
{
    param(
        [string]$BuildRoot
    )

    if( -not $BuildRoot )
    {
        Write-Warning -Message ('Remove-Node''s "BuildRoot" parameter will soon become mandatory. Please update usages.')
        $BuildRoot = $TestDrive.FullName
    }

    $parameter = @{ 'Path' = (Join-Path -Path $BuildRoot -ChildPath '.node\node_modules') }
    Invoke-WhiskeyPrivateCommand -Name 'Remove-WhiskeyFileSystemItem' -Parameter $parameter
}

function Remove-DotNet
{
    param(
        [string]$BuildRoot
    )

    if( -not $BuildRoot )
    {
        Write-Warning -Message ('Remove-DotNet''s "BuildRoot" parameter will soon become mandatory. Please update usages.')
        $BuildRoot = $TestDrive.FullName
    }

    Get-Process -Name 'dotnet' -ErrorAction Ignore |
        Where-Object { $_.Path -like ('{0}\*' -f $BuildRoot) } |
        ForEach-Object { 
            Write-Debug ('Killing process "{0}" (Id: {1}; Path: {2})' -f $_.Name,$_.Id,$_.Path)
            Stop-Process -Id $_.Id -Force }

    $parameter = @{
        'Path' = (Join-Path -Path $BuildRoot -ChildPath '.dotnet')
    }
    Invoke-WhiskeyPrivateCommand 'Remove-WhiskeyFileSystemItem' -Parameter $parameter
}

function Reset-WhiskeyTestPSModule
{
    Get-Module |
        Where-Object { $_.Path -like ('{0}*' -f $TestDrive.FullName) } |
        Remove-Module -Force
}

function ThenModuleInstalled
{
    param(
        [string]$InBuildRoot,

        [string]$Named,

        [string]$AtVersion
    )

    Join-Path -Path $InBuildRoot -ChildPath ('{0}\{1}\{2}' -f $PSModulesDirectoryName,$Named,$AtVersion) | 
        Should -Exist
}

function Write-WhiskeyTestTiming
{
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Invoke-WhiskeyPrivateCommand -Name 'Write-WhiskeyTiming' -Parameter @{ Message = $Message } 
}

$SuccessCommandScriptBlock = { 'exit 0' | sh }
$FailureCommandScriptBlock = { 'exit 1' | sh }
if( $IsWindows )
{
    $SuccessCommandScriptBlock = { cmd /c exit 0 }
    $FailureCommandScriptBlock = { cmd /c exit 1 }
}

$PSModulesDirectoryName = 'PSModules'

$variablesToExport = & {
    'WhiskeyTestDownloadCachePath'
    'SuccessCommandScriptBlock'
    'FailureCommandScriptBlock'
    'WhiskeyPlatform'
    'PSModulesDirectoryName'
    # PowerShell 5.1 doesn't have these variables so create them if they don't exist.
    if( $exportPlatformVars )
    {
        'IsLinux'
        'IsMacOS'
        'IsWindows'
    }
}

Export-ModuleMember -Function '*' -Variable $variablesToExport
