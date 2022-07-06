
$TestPSModulesDirectoryName = 'PSModules'

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
$downloadCachePath = Join-Path -Path $PSScriptRoot -ChildPath ('..\.output\.downloadcache-{0}' -f $WhiskeyPlatform)
$downloadCachePath = [IO.Path]::GetFullPath($downloadCachePath)
$WhiskeyTestDownloadCachePath = $downloadCachePath

$testNum = 0

if( -not (Test-Path -Path $downloadCachePath -PathType Container) )
{
    New-Item -Path $downloadCachePath -ItemType 'Directory' -Force | Out-Null
}

function ConvertTo-Yaml
{
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline)]
        [System.Object]$Data,
        [String]$OutFile,
        [switch]$JsonCompatible=$false,
        [switch]$Force=$false
    )
    BEGIN {
        $d = [System.Collections.Generic.List[Object]](New-Object "System.Collections.Generic.List[Object]")
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
        [String[]]$Name,

        [switch]$Force
    )

    $modulesRoot = Join-Path -Path $PSScriptRoot -ChildPath ('..\{0}' -f $TestPSModulesDirectoryName) -Resolve

    Invoke-WhiskeyPrivateCommand -Name 'Register-WhiskeyPSModulePath' -Parameter @{ 'Path' = $modulesRoot }

    foreach( $moduleName in $Name )
    {
        Import-Module -Name (Join-Path -Path $modulesRoot -ChildPath $moduleName -Resolve) `
                      -Force:$Force `
                      -Global `
                      -WarningAction Ignore
    }
}

function Import-WhiskeyTestTaskModule
{
    if( (Get-Module -Name 'WhiskeyTestTasks') )
    {
        return
    }

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhiskeyTestTasks.psm1' -Resolve) -Global -Verbose:$false
}

function Initialize-WhiskeyTestPSModule
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$BuildRoot,

        [String[]]$Name
    )

    $destinationRoot = Join-Path -Path $BuildRoot -ChildPath $TestPSModulesDirectoryName
    Write-WhiskeyDebug ('Copying Modules  {0}  START' -f $destinationRoot)
    if( -not (Test-Path -Path $destinationRoot -PathType Container) )
    {
        New-Item -Path $destinationRoot -ItemType 'Directory' | Out-Null
    }

    $Name = & {
        $Name
    }

    foreach( $module in (Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath ('..\{0}' -f $TestPSModulesDirectoryName) -Resolve) -Directory))
    {
        if( $module.Name -notin $Name )
        {
            continue
        }

        if( (Test-Path -Path (Join-Path -Path $destinationRoot -ChildPath $module.Name) ) )
        {
            continue
        }

        Write-WhiskeyDebug -Message ('{0} -> {1}' -f $module.FullName,$destinationRoot)
        Copy-Item -Path $module.FullName -Destination $destinationRoot -Recurse
    }

    Write-WhiskeyDebug -Message '                 END'
}

function Install-Node
{
    param(
        [String]$BuildRoot
    )

    Install-WhiskeyTool -Name 'Node' -InstallRoot $downloadCachePath

    $nodeRoot = Join-Path -Path $downloadCachePath -ChildPath '.node'

    if( -not $BuildRoot )
    {
        $msg = 'Install-Node''s BuildRoot parameter will eventually be made mandatory. Please update usages.'
        Write-WhiskeyWarning -Message $msg
        $BuildRoot = $TestDrive.FullName
    }

    $destinationDir = Join-Path -Path $BuildRoot -ChildPath '.node'
    if( -not (Test-Path -Path $destinationDir -PathType Container) )
    {
        New-Item -Path $destinationDir -ItemType 'Directory' -Force | Out-Null
    }

    Write-WhiskeyDebug -Message ('Copying {0} -> {1}' -f $nodeRoot,$destinationDir)
    if( $IsWindows )
    {
        $robocopyParameter = @{
            'Source' = $nodeRoot;
            'Destination' = $destinationDir;
            'Exclude' = '*.zip','*.tar.*';
        }
        Invoke-WhiskeyPrivateCommand -Name 'Invoke-WhiskeyRobocopy' -Parameter $robocopyParameter
    }
    else
    {
        Copy-Item -Path (Join-Path -Path $nodeRoot -ChildPath '*') -Exclude '*.zip','*.tar.*' -Destination $destinationDir -Recurse -ErrorAction Ignore
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
        [String]$Name,
        [hashtable]$Parameter = @{}
    )

    $Global:WTName = $Name
    $Global:WTParameter = $Parameter

    if( $VerbosePreference -eq 'Continue' )
    {
        $Parameter['Verbose'] = $true
    }

    $Parameter['ErrorAction'] = $ErrorActionPreference

    try
    {
        InModuleScope 'Whiskey' {
            & $WTName @WTParameter
        }
    }
    finally
    {
        Remove-Variable -Name 'WTParameter' -Scope 'Global'
        Remove-Variable -Name 'WTName' -Scope 'Global'
    }
}
function New-AssemblyInfo
{
    param(
        [String]$RootPath
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
        [String[]]$FileName,

        [switch]$ThatFails,

        [String]$BuildRoot
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
        [String]$ForBuildRoot,

        [String]$ForTaskName,

        [String]$ForOutputDirectory,

        [switch]$InReleaseMode,

        [Parameter(Mandatory,ParameterSetName='ByBuildServer')]
        [Alias('ByBuildServer')]
        [switch]$ForBuildServer,

        [Parameter(Mandatory,ParameterSetName='ByDeveloper')]
        [Alias('ByDeveloper')]
        [switch]$ForDeveloper,

        [SemVersion.SemanticVersion]$ForVersion = [SemVersion.SemanticVersion]'1.2.3-rc.1+build',

        [String]$ConfigurationPath,

        [String]$ForYaml,

        [hashtable]$TaskParameter = @{},

        [String]$DownloadRoot,

        [switch]$IgnoreExistingOutputDirectory,

        [switch]$InCleanMode,

        [switch]$InInitMode,

        [String[]]$IncludePSModule
    )

    Set-StrictMode -Version 'Latest'

    if( -not $ForBuildRoot )
    {
        Write-WhiskeyWarning -Message ('New-WhiskeyTestContext''s "ForBuildRoot" parameter will soon become mandatory. Please update usages.')
        $ForBuildRoot = $TestDrive.FullName
    }

    if( -not [IO.Path]::IsPathRooted($ForBuildRoot) )
    {
        Write-WhiskeyWarning -Message ('New-WhiskeyTestContext''s "ForBuildRoot" parameter will soon become mandatory and will be required to be an absolute path. Please update usages.')
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
    $context.BuildRoot = Get-Item -Path $ForBuildRoot
    $context.Environment = 'Verification'
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

    if( $ForVersion )
    {
        $context.Version.SemVer2 = $ForVersion
        $context.Version.SemVer2NoBuildMetadata = New-Object 'SemVersion.SemanticVersion' $ForVersion.Major,$ForVersion.Minor,$ForVersion.Patch,$ForVersion.Prerelease,$null
        $context.Version.SemVer1 = New-Object 'SemVersion.SemanticVersion' $ForVersion.Major,$ForVersion.Minor,$ForVersion.Patch,($ForVersion.Prerelease -replace '[^A-Za-z0-9]',''),$null
        $context.Version.Version = [Version]('{0}.{1}.{2}' -f $ForVersion.Major,$ForVersion.Minor,$ForVersion.Patch)
    }

    if( -not $IgnoreExistingOutputDirectory -and (Test-Path -Path $context.OutputDirectory) )
    {
        Remove-Item -Path $context.OutputDirectory -Recurse -Force
    }
    New-Item -Path $context.OutputDirectory -ItemType 'Directory' -Force -ErrorAction Ignore | Out-String | Write-WhiskeyDebug

    Initialize-WhiskeyTestPSModule -BuildRoot $context.BuildRoot -Name $IncludePSModule

    $context.StartBuild()

    if( $ForTaskName )
    {
        $context.StartTask($ForTaskName)
    }

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
    $testRoot = Join-Path -Path $TestDrive.FullName -ChildPath ($script:testNum++)
    New-Item -Path $testRoot -ItemType 'Directory' | Out-Null
    return $testRoot
}

function Register-WhiskeyPSModulesPath
{
    param(
        # Return $true or $false if the PSModulePath env variable was modified or not, respectively.
        [switch] $PassThru
    )

    $pathBefore = $env:PSModulePath
    $whiskeyPSModulesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules' -Resolve
    Invoke-WhiskeyPrivateCommand -Name 'Register-WhiskeyPSModulePath' -Parameter @{ 'Path' = $whiskeyPSModulesPath }
    if( $PassThru )
    {
        return ($env:PSModulePath -ne $pathBefore)
    }
}

function Remove-Node
{
    param(
        [String]$BuildRoot
    )

    if( -not $BuildRoot )
    {
        Write-WhiskeyWarning -Message ('Remove-Node''s "BuildRoot" parameter will soon become mandatory. Please update usages.')
        $BuildRoot = $TestDrive.FullName
    }

    $parameter = @{ 'Path' = (Join-Path -Path $BuildRoot -ChildPath '.node\node_modules') }
    Invoke-WhiskeyPrivateCommand -Name 'Remove-WhiskeyFileSystemItem' -Parameter $parameter
}

function Remove-DotNet
{
    param(
        [String]$BuildRoot
    )

    if( -not $BuildRoot )
    {
        Write-WhiskeyWarning -Message ('Remove-DotNet''s "BuildRoot" parameter will soon become mandatory. Please update usages.')
        $BuildRoot = $TestDrive.FullName
    }

    Get-Process -Name 'dotnet' -ErrorAction Ignore |
        Where-Object { $_.Path -like ('{0}\*' -f $BuildRoot) } |
        ForEach-Object {
            Write-WhiskeyDebug ('Killing process "{0}" (Id: {1}; Path: {2})' -f $_.Name,$_.Id,$_.Path)
            Stop-Process -Id $_.Id -Force }

    $parameter = @{
        'Path' = (Join-Path -Path $BuildRoot -ChildPath '.dotnet')
    }
    Invoke-WhiskeyPrivateCommand 'Remove-WhiskeyFileSystemItem' -Parameter $parameter
}

function Reset-WhiskeyTestPSModule
{
    if( -not (Test-Path -Path 'variable:TestDrive') )
    {
        return
    }

    Get-Module |
        Where-Object { $_.Path -like ('{0}*' -f $TestDrive.FullName) } |
        Remove-Module -Force
    Reset-WhiskeyPSModulePath
}

function Reset-WhiskeyPSModulePath
{
    if( -not (Test-Path -Path 'variable:TestDrive') )
    {
        return
    }

    $pesterTestDriveRoot = $TestDrive.Fullname | Split-Path
    $pesterTestDriveRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $pesterTestDriveRoot = "$($pesterTestDriveRoot)$([IO.Path]::DirectorySeparatorChar)"
    $env:PSModulePath -split [IO.Path]::PathSeparator | 
        Where-Object { $_.StartsWith($pesterTestDriveRoot, [StringComparison]::InvariantCultureIgnoreCase) } |
        ForEach-Object {
            Invoke-WhiskeyPrivateCommand -Name 'Unregister-WhiskeyPSModulePath' -Parameter @{ 'Path' = $_ }
        }
}

function ThenErrorRecord
{
    param(
        [switch]$Empty,
        [String]$Matches
    )

    if( $Empty )
    {
        $Global:Error | Should -BeNullOrEmpty -Because 'the global error record should be empty'
    }

    if( $Matches )
    {
        $Global:Error | Should -Match $Matches -Because 'it should write the expected error message'
    }
}

function ThenModuleInstalled
{
    param(
        [String]$InBuildRoot,

        [String]$Named,

        [String]$AtVersion
    )

    if( -not $InBuildRoot )
    {
        $msg = 'The InBuildRoot parameter will eventually become a required parameter on ThenModuleInstalled. Please ' +
               'update your usages to pass in the build root.'
        Write-Warning -Message $msg
    }

    Join-Path -Path $InBuildRoot -ChildPath ('{0}\{1}\{2}' -f $TestPSModulesDirectoryName,$Named,$AtVersion) |
        Should -Exist
}

function Unregister-WhiskeyPSModulesPath
{
    $whiskeyPSModulesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules' -Resolve
    Invoke-WhiskeyPrivateCommand -Name 'Unregister-WhiskeyPSModulePath' -Parameter @{ 'Path' = $whiskeyPSModulesPath }
}

function Use-CallerPreference
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        #[Management.Automation.PSScriptCmdlet]
        # The module function's `$PSCmdlet` object. Requires the function be decorated with the `[CmdletBinding()]` attribute.
        $Cmdlet,

        [Parameter(Mandatory = $true)]
        [Management.Automation.SessionState]
        # The module function's `$ExecutionContext.SessionState` object.  Requires the function be decorated with the `[CmdletBinding()]` attribute.
        #
        # Used to set variables in its callers' scope, even if that caller is in a different script module.
        $SessionState
    )

    Set-StrictMode -Version 'Latest'

    # List of preference variables taken from the about_Preference_Variables and their common parameter name (taken from about_CommonParameters).
    $commonPreferences = @{
                              'ErrorActionPreference' = 'ErrorAction';
                              'DebugPreference' = 'Debug';
                              'ConfirmPreference' = 'Confirm';
                              'InformationPreference' = 'InformationAction';
                              'VerbosePreference' = 'Verbose';
                              'WarningPreference' = 'WarningAction';
                              'WhatIfPreference' = 'WhatIf';
                          }

    foreach( $prefName in $commonPreferences.Keys )
    {
        $parameterName = $commonPreferences[$prefName]

        # Don't do anything if the parameter was passed in.
        if( $Cmdlet.MyInvocation.BoundParameters.ContainsKey($parameterName) )
        {
            continue
        }

        $variable = $Cmdlet.SessionState.PSVariable.Get($prefName)
        # Don't do anything if caller didn't use a common parameter.
        if( -not $variable )
        {
            continue
        }

        if( $SessionState -eq $ExecutionContext.SessionState )
        {
            Set-Variable -Scope 1 -Name $variable.Name -Value $variable.Value -Force -Confirm:$false -WhatIf:$false
        }
        else
        {
            $SessionState.PSVariable.Set($variable.Name, $variable.Value)
        }
    }
}

function Write-CaughtError
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Management.Automation.ErrorRecord]$ErrorRecord
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $doNotWritePrefs = @(
        [Management.Automation.ActionPreference]::Ignore,
        [Management.Automation.ActionPreference]::SilentlyContinue
    )

    if( $ErrorActionPreference -in $doNotWritePrefs )
    {
        return
    }

    $message = [Management.Automation.HostInformationMessage]::new()
    $message.Message = $ErrorRecord | Out-String
    $message.ForegroundColor = $Host.PrivateData.ErrorForegroundColor
    $message.BackgroundColor = $Host.PrivateData.ErrorBackgroundColor
    Write-Information $message -InformationAction Continue
}

$SuccessCommandScriptBlock = { 'exit 0' | sh }
$FailureCommandScriptBlock = { 'exit 1' | sh }
if( $IsWindows )
{
    $SuccessCommandScriptBlock = { cmd /c exit 0 }
    $FailureCommandScriptBlock = { cmd /c exit 1 }
}

$variablesToExport = & {
    'WhiskeyTestDownloadCachePath'
    'SuccessCommandScriptBlock'
    'FailureCommandScriptBlock'
    'WhiskeyPlatform'
    'TestPSModulesDirectoryName'
    # PowerShell 5.1 doesn't have these variables so create them if they don't exist.
    if( $exportPlatformVars )
    {
        'IsLinux'
        'IsMacOS'
        'IsWindows'
    }
}

Export-ModuleMember -Function '*' -Variable $variablesToExport
