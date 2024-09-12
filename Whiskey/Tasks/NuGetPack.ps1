
function New-WhiskeyNuGetPackage
{
    [Whiskey.Task('NuGetPack',Platform='Windows')]
    [Whiskey.RequiresNuGetPackage('NuGet.CommandLine', Version='6.10.*', PathParameterName='NuGetPath')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String[]]$Path,

        [String] $NuGetPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    $symbols = $TaskParameter['Symbols'] | ConvertFrom-WhiskeyYamlScalar
    $symbolsArg = $null
    $symbolsFileNameSuffix = ''
    if ($symbols)
    {
        $symbolsArg = '-Symbols'
        $symbolsFileNameSuffix = '.symbols'
    }

    $NuGetPath = Join-Path -Path $NuGetPath -ChildPath 'tools\NuGet.exe' -Resolve
    if( -not $NuGetPath )
    {
        Stop-WhiskeyTask -Context $TaskContext -Message "NuGet.exe not found at ""$($nugetPath)""."
        return
    }

    $properties = $TaskParameter['Properties']
    $propertiesArgs = @()
    if( $properties )
    {
        if( -not (Get-Member -InputObject $properties -Name 'Keys') )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName 'Properties' -Message ('Property is invalid. This property must be a name/value mapping of properties to pass to nuget.exe pack command''s "-Properties" parameter.')
            return
        }

        $propertiesArgs = $properties.Keys |
                                ForEach-Object {
                                    '-Properties'
                                    '{0}={1}' -f $_,$properties[$_]
                                }
    }

    foreach ($pathItem in $Path)
    {
        $projectName = $TaskParameter['PackageID']
        if( -not $projectName )
        {
            $projectName = [IO.Path]::GetFileNameWithoutExtension(($pathItem | Split-Path -Leaf))
        }
        $packageVersion = $TaskParameter['PackageVersion']
        if (-not $packageVersion)
        {
            $packageVersion = $TaskContext.Version.SemVer1
        }

        # Create NuGet package
        $configuration = Get-WhiskeyMSBuildConfiguration -Context $TaskContext

        $configPropertyArg = "Configuration=${configuration}"
        Write-WhiskeyCommand -Path $NuGetPath `
                             -ArgumentList @(
                                'pack',
                                '-Version',
                                $packageVersion,
                                '-OutputDirectory',
                                $TaskContext.OutputDirectory,
                                $symbolsArg,
                                $configPropertyArg,
                                $propertiesArgs,
                                $pathItem
                             )
        & $nugetPath pack `
                     -Version $packageVersion `
                     -OutputDirectory $TaskContext.OutputDirectory `
                     $symbolsArg `
                     -Properties ('Configuration={0}' -f $configuration) `
                     $propertiesArgs `
                     $pathItem

        # Make sure package was created.
        $filename = '{0}.{1}{2}.nupkg' -f $projectName,$packageVersion,$symbolsFileNameSuffix

        $packagePath = Join-Path -Path $TaskContext.OutputDirectory -childPath $filename
        if( -not (Test-Path -Path $packagePath -PathType Leaf) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('We ran nuget pack against "{0}" but the expected NuGet package "{1}" does not exist.' -f $pathItem,$packagePath)
            return
        }
    }
}
