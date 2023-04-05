
$startedAt = Get-Date
function Write-Timing
{
    param(
        [Parameter(Position=0)]
        $Message
    )

    $now = Get-Date
    Write-Debug -Message ('[{0:hh":"mm":"ss"."ff}]  {1}' -f ($now - $startedAt),$Message)
}

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
$psModulesDirectoryName = 'PSModules'

$whiskeyScriptRoot = $PSScriptRoot
$whiskeyBinPath = Join-Path -Path $whiskeyScriptRoot -ChildPath 'bin' -Resolve

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
$buildStartedAt = [DateTime]::MinValue

$PSModuleAutoLoadingPreference = 'None'

# The indentation to use when writing task messages.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
$taskWriteIndent = '  '

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
$indentLevel = 0

# PowerShell 5.1 doesn't have these variables so create them if they don't exist.
if( -not (Get-Variable -Name 'IsLinux' -ErrorAction Ignore) )
{
    # We only set these variables on platforms where they're not defined.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '')]
    $IsLinux = $false

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '')]
    $IsMacOS = $false

    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', '')]
    $IsWindows = $true
}

if( -not (Test-Path -Path 'env:WHISKEY_DISABLE_ERROR_FORMAT') )
{
    Write-Timing 'Updating formats.'
    $prependFormats = @(
                            (Join-Path -Path $PSScriptRoot -ChildPath 'Formats\System.Management.Automation.ErrorRecord.ps1xml'),
                            (Join-Path -Path $PSScriptRoot -ChildPath 'Formats\System.Exception.ps1xml')
                        )
    Update-FormatData -PrependPath $prependFormats
}

Write-Timing 'Loading assemblies.'

# .NET Framework 4.6.2 won't load netstandard2.0 assemblies.
$frameworkMoniker = 'netstandard2.0'
$net4Key = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Ignore
$net462Release = 460798
if( $net4Key -and $net4Key.Release -le $net462Release )
{
    $frameworkMoniker = 'net452'
}

foreach( $assemblyBaseName in @('SemanticVersion', 'YamlDotNet', 'Whiskey') )
{
    $assemblyPath = Join-Path -Path $whiskeyBinPath -ChildPath $frameworkMoniker
    $assemblyPath = Join-Path -Path $assemblyPath -ChildPath "$($assemblyBaseName).dll"
    $addTypeErrors = @()
    Add-Type -Path $assemblyPath -ErrorVariable 'addTypeErrors' -ErrorAction Continue
    if( $addTypeErrors )
    {
        $ex = $addTypeErrors | Select-Object -First 1
        while( $ex.InnerException )
        {
            $ex = $ex.InnerException
        }

        if( $ex | Get-Member 'LoaderExceptions' )
        {
            $ex = $ex.LoaderExceptions | Select-Object -First 1
        }

        Write-Error -Message "Exception loading assembly ""$($assemblyPath)"": $($ex)" -ErrorAction Stop
    }
}
Add-Type -AssemblyName 'System.IO.Compression.FileSystem'

Write-Timing 'Updating serialiazation depths on Whiskey objects.'
# Make sure our custom objects get serialized/deserialized correctly, otherwise they don't get passed to PowerShell tasks correctly.
Update-TypeData -TypeName 'Whiskey.BuildContext' -SerializationDepth 50 -ErrorAction Ignore
Update-TypeData -TypeName 'Whiskey.BuildInfo' -SerializationDepth 50 -ErrorAction Ignore
Update-TypeData -TypeName 'Whiskey.BuildVersion' -SerializationDepth 50 -ErrorAction Ignore

Write-Timing 'Testing that correct Whiskey assembly is loaded.'
$oldVersionLoadedMsg = 'You''ve got an old version of Whiskey loaded. Please open a new PowerShell session.'

function New-WhiskeyObject
{
    param(
        [Parameter(Mandatory)]
        [String]$TypeName,

        [Object[]]$ArgumentList
    )

    try
    {
        return (New-Object -TypeName $TypeName -ArgumentList $ArgumentList -ErrorAction Ignore)
    }
    catch
    {
        Write-Error -Message ('Unable to find type "{0}". {1}' -f $TypeName,$oldVersionLoadedMsg) -ErrorAction Stop
    }
}

function Assert-Member
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [Object]$Object,

        [String[]]$Property = @()
    )

    $oldVersionLoadedMsg = 'You''ve got an old version of Whiskey loaded. Please open a new PowerShell session.'

    if( -not $Object )
    {
        Write-Error -Message $oldVersionLoadedMsg -ErrorAction Stop
    }

    foreach( $propertyToCheck in $Property )
    {
        if( -not ($Object | Get-Member $propertyToCheck) )
        {
            $msg = 'Object "{0}" is missing member "{1}".' -f $Object.GetType().FullName,$propertyToCheck
            Write-Error -Message ('{0} {1}' -f $msg,$oldVersionLoadedMsg) -ErrorAction Stop
        }
    }
}

Write-Timing 'Checking Whiskey assembly loaded.'
$context = New-WhiskeyObject -TypeName 'Whiskey.Context'
Assert-Member -Object $context `
              -Property @( 'TaskPaths', 'MSBuildConfiguration', 'ApiKeys', 'BuildStopwatch', 'TaskStopwatch' )

Write-Timing 'Checking Whiskey.TaskAttribute class.'
$attr = New-WhiskeyObject -TypeName 'Whiskey.TaskAttribute' -ArgumentList 'Whiskey'
Assert-Member -Object $attr -Property @( 'Aliases', 'WarnWhenUsingAlias', 'Obsolete', 'ObsoleteMessage', 'Platform' )

Write-Timing 'Checking for Whiskey.RequiresPowerShellModuleAttribute class.'
New-WhiskeyObject -TypeName 'Whiskey.RequiresPowerShellModuleAttribute' -ArgumentList ('Whiskey') | Out-Null

$attr = New-WhiskeyObject -TypeName 'Whiskey.Tasks.ValidatePathAttribute'
Assert-Member -Object $attr -Property @( 'Create' )

$buildInfo = New-WhiskeyObject -TypeName 'Whiskey.BuildInfo'
Assert-Member -Object $buildInfo -Property @( 'ScmSourceBranch' )

New-WhiskeyObject -TypeName 'Whiskey.RequiresNuGetPackageAttribute' -ArgumentList 'NuGet.CommandLine' | Out-Null

[Type]$apiKeysType = $context.ApiKeys.GetType()
$apiKeysDictGenericTypes = $apiKeysType.GenericTypeArguments
if( -not $apiKeysDictGenericTypes -or $apiKeysDictGenericTypes.Count -ne 2 -or $apiKeysDictGenericTypes[1].FullName -ne [securestring].FullName )
{
    Write-Error -Message  $oldVersionLoadedMsg -ErrorAction Stop
}

Write-Timing ('Creating internal module variables.')

$dotNetExeName = 'dotnet'
$nodeExeName = 'node'
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
$nodeDirName = 'bin'
if( $IsWindows )
{
    $dotNetExeName = '{0}.exe' -f $dotNetExeName
    $nodeExeName = '{0}.exe' -f $nodeExeName
    $nodeDirName = ''
}

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '')]
$CurrentPlatform = [Whiskey.Platform]::Unknown
if( $IsLinux )
{
    $CurrentPlatform = [Whiskey.Platform]::Linux
}
elseif( $IsMacOS )
{
    $CurrentPlatform = [Whiskey.Platform]::MacOS
}
elseif( $IsWindows )
{
    $CurrentPlatform = [Whiskey.Platform]::Windows
}

$script:internalPSModulesPath = Join-Path -Path $whiskeyScriptRoot -ChildPath 'Modules' -Resolve

Write-Timing -Message ('Dot-sourcing files.')
$count = 0
& {
        Join-Path -Path $PSScriptRoot -ChildPath 'Functions'
        Join-Path -Path $PSScriptRoot -ChildPath 'Tasks'
    } |
    Where-Object { Test-Path -Path $_ } |
    Get-ChildItem -Filter '*.ps1' |
    ForEach-Object {
        $count += 1
        . $_.FullName
    }
Write-Timing -Message ('Finished dot-sourcing {0} files.' -f $count)
