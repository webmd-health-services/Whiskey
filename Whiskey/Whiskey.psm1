
$startedAt = Get-Date
function Write-Timing
{
    param(
        [Parameter(Position=0)]
        $Message
    )

    $now = Get-Date
    Write-Debug -Message ('[{0}]  [{1}]  {2}' -f $now,($now - $startedAt),$Message)
}

$events = @{ }

$powerShellModulesDirectoryName = 'PSModules'

$whiskeyScriptRoot = $PSScriptRoot
$whiskeyModulesRoot = Join-Path -Path $whiskeyScriptRoot -ChildPath 'Modules' -Resolve
$whiskeyBinPath = Join-Path -Path $whiskeyScriptRoot -ChildPath 'bin' -Resolve
$whiskeyNuGetExePath = Join-Path -Path $whiskeyBinPath -ChildPath 'NuGet.exe' -Resolve

$buildStartedAt = [DateTime]::MinValue

$PSModuleAutoLoadingPreference = 'None'

$supportsWriteInformation = Get-Command -Name 'Write-Information' -ErrorAction Ignore

Write-Timing 'Updating serialiazation depths on Whiskey objects.'
# Make sure our custom objects get serialized/deserialized correctly, otherwise they don't get passed to PowerShell tasks correctly.
Update-TypeData -TypeName 'Whiskey.BuildContext' -SerializationDepth 50 -ErrorAction Ignore
Update-TypeData -TypeName 'Whiskey.BuildInfo' -SerializationDepth 50 -ErrorAction Ignore
Update-TypeData -TypeName 'Whiskey.BuildVersion' -SerializationDepth 50 -ErrorAction Ignore

Write-Timing 'Testing that correct Whiskey assembly is loaded.'
$attr = New-Object -TypeName 'Whiskey.TaskAttribute' -ArgumentList 'Whiskey' -ErrorAction Ignore
if( -not ($attr | Get-Member 'Platform') )
{
    Write-Error -Message ('You''ve got an old version of Whiskey loaded. Please open a new PowerShell session.') -ErrorAction Stop
}

function Assert-Member
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]
        $Object,

        [Parameter(Mandatory)]
        [string[]]
        $Property
    )

    foreach( $propertyToCheck in $Property )
    {
        if( -not ($Object | Get-Member $propertyToCheck) )
        {
            Write-Debug -Message ('Object "{0}" is missing member "{1}".' -f $Object.GetType().FullName,$propertyToCheck)
            Write-Error -Message ('You''ve got an old version of Whiskey loaded. Please open a new PowerShell session.') -ErrorAction Stop
        }
    }
}

$context = New-Object -TypeName 'Whiskey.Context'
Assert-Member -Object $context -Property @( 'TaskPaths', 'MSBuildConfiguration', 'ApiKeys' )

$taskAttribute = New-Object -TypeName 'Whiskey.TaskAttribute' -ArgumentList 'Fubar'
Assert-Member -Object $taskAttribute -Property @( 'Aliases', 'WarnWhenUsingAlias', 'Obsolete', 'ObsoleteMessage' )

[Type]$apiKeysType = $context.ApiKeys.GetType()
$apiKeysDictGenericTypes = $apiKeysType.GenericTypeArguments
if( -not $apiKeysDictGenericTypes -or $apiKeysDictGenericTypes.Count -ne 2 -or $apiKeysDictGenericTypes[1].FullName -ne [SecureString].FullName )
{
    Write-Error -Message ('You''ve got an old version of Whiskey loaded. Please open a new PowerShell session.') -ErrorAction Stop 
}

Write-Timing ('Creating internal module variables.')

# PowerShell 5.1 doesn't have these variables so create them if they don't exist.
if( -not (Get-Variable -Name 'IsLinux' -ErrorAction Ignore) )
{
    $IsLinux = $false
    $IsMacOS = $false
    $IsWindows = $true
}

$dotNetExeName = 'dotnet'
$nodeExeName = 'node'
$nodeDirName = 'bin'
if( $IsWindows )
{
    $dotNetExeName = '{0}.exe' -f $dotNetExeName
    $nodeExeName = '{0}.exe' -f $nodeExeName
    $nodeDirName = ''
}

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