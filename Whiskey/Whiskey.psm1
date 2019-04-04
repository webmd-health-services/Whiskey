
$events = @{ }

$powerShellModulesDirectoryName = 'PSModules'

$buildStartedAt = [DateTime]::MinValue

$PSModuleAutoLoadingPreference = 'None'

$supportsWriteInformation = Get-Command -Name 'Write-Information' -ErrorAction Ignore

# Make sure our custom objects get serialized/deserialized correctly, otherwise they don't get passed to PowerShell tasks correctly.
Update-TypeData -TypeName 'Whiskey.BuildContext' -SerializationDepth 50 -ErrorAction Ignore
Update-TypeData -TypeName 'Whiskey.BuildInfo' -SerializationDepth 50 -ErrorAction Ignore
Update-TypeData -TypeName 'Whiskey.BuildVersion' -SerializationDepth 50 -ErrorAction Ignore

$attr = New-Object -TypeName 'Whiskey.TaskAttribute' -ArgumentList 'Whiskey' -ErrorAction Ignore
if( -not ($attr | Get-Member 'Platform') )
{
    Write-Error -Message ('You''ve got an old version of Whiskey loaded. Please open a new PowerShell session.') -ErrorAction Stop
}

$context = New-Object -TypeName 'Whiskey.Context'
$propertiesToCheck = @( 'TaskPaths', 'MSBuildConfiguration', 'ApiKeys' )
foreach( $propertyToCheck in $propertiesToCheck )
{
    if( -not ($context | Get-Member $propertyToCheck) )
    {
        Write-Error -Message ('You''ve got an old version of Whiskey loaded. Please open a new PowerShell session.') -ErrorAction Stop
    }
}

[Type]$apiKeysType = $context.ApiKeys.GetType()
$apiKeysDictGenericTypes = $apiKeysType.GenericTypeArguments
if( -not $apiKeysDictGenericTypes -or $apiKeysDictGenericTypes.Count -ne 2 -or $apiKeysDictGenericTypes[1].FullName -ne [SecureString].FullName )
{
    Write-Error -Message ('You''ve got an old version of Whiskey loaded. Please open a new PowerShell session.') -ErrorAction Stop
}

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

Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Functions'),(Join-Path -Path $PSScriptRoot -ChildPath 'Tasks') -Filter '*.ps1' |
    ForEach-Object { . $_.FullName }
