
function Invoke-WhiskeyMSBuild
{
    [Whiskey.Task('MSBuild', SupportsClean, Platform='Windows')]
    [Whiskey.RequiresPowerShellModule('VSSetup', Version='2.*', VersionParameterName='VSSetupVersion')]
    [Whiskey.RequiresNuGetPackage('NuGet.CommandLine', Version='6.14.*', VersionParameterName='NuGetVersion',
        PathParameterName='NuGetPath')]
    [CmdletBinding()]
    param(
        [Whiskey.Context]$TaskContext,

        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String[]]$Path,

        [Whiskey.Tasks.ValidatePath(AllowNonexistent,PathType='Directory',Create)]
        [String]$OutputDirectory,

        [String] $NuGetPath
    )

    Set-StrictMode -version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    #setup
    $msbuildInfos = Get-MSBuild | Sort-Object -Descending 'Version'
    $version = $TaskParameter['Version']
    if( $version )
    {
        $msbuildInfo = $msbuildInfos | Where-Object { $_.Name -eq $version } | Select-Object -First 1
    }
    else
    {
        $msbuildInfo = $msbuildInfos | Select-Object -First 1
    }

    if( -not $msbuildInfo )
    {
        $msbuildVersionNumbers = $msbuildInfos | Select-Object -ExpandProperty 'Name'
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('MSBuild {0} is not installed. Installed versions are: {1}' -f $version,($msbuildVersionNumbers -join ', '))
        return
    }

    $msbuildExePath = $msbuildInfo.Path
    if( $TaskParameter.ContainsKey('Use32Bit') -and ($TaskParameter['Use32Bit'] | ConvertFrom-WhiskeyYamlScalar) )
    {
        $msbuildExePath = $msbuildInfo.Path32
        if( -not $msbuildExePath )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('A 32-bit version of MSBuild {0} does not exist.' -f $version)
            return
        }
    }
    Write-WhiskeyVerbose -Context $TaskContext -Message ('{0}' -f $msbuildExePath)

    $target = @( 'build' )
    if( $TaskContext.ShouldClean )
    {
        $target = 'clean'
    }
    else
    {
        if( $TaskParameter.ContainsKey('Target') )
        {
            $target = $TaskParameter['Target']
        }
    }

    $NuGetPath = Join-Path -Path $NuGetPath -ChildPath 'tools\NuGet.exe' -Resolve
    if( -not $NuGetPath )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message "NuGet.exe not found at ""$($nugetPath)""."
        return
    }

    foreach( $projectPath in $Path )
    {
        Write-WhiskeyVerbose -Context $TaskContext -Message ('  {0}' -f $projectPath)
        if( $projectPath -like '*.sln' )
        {
            if( $TaskContext.ShouldClean )
            {
                $packageDirectoryPath = Join-Path -Path ( Split-Path -Path $projectPath -Parent ) -ChildPath 'packages'
                if( Test-Path -Path $packageDirectoryPath -PathType Container )
                {
                    Write-WhiskeyVerbose -Context $TaskContext -Message ('  Removing NuGet packages at {0}.' -f $packageDirectoryPath)
                    Remove-Item $packageDirectoryPath -Recurse -Force
                }
            }
            else
            {
                Write-WhiskeyCommand -Path $NuGetPath -ArgumentList 'restore', $projectPath
                & $NuGetPath restore $projectPath
            }
        }

        if( $TaskContext.ByBuildServer )
        {
            $projectPath |
                Split-Path |
                Get-ChildItem -Filter 'AssemblyInfo.cs' -Recurse |
                ForEach-Object {
                    $assemblyInfo = $_
                    $assemblyInfoPath = $assemblyInfo.FullName
                    $newContent = Get-Content -Path $assemblyInfoPath | Where-Object { $_ -notmatch '\bAssembly(File|Informational)?Version\b' }
                    $newContent | Set-Content -Path $assemblyInfoPath
                    Write-WhiskeyVerbose -Context $TaskContext -Message ('    Updating version in {0}.' -f $assemblyInfoPath)
    @"
[assembly: System.Reflection.AssemblyVersion("{0}")]
[assembly: System.Reflection.AssemblyFileVersion("{0}")]
[assembly: System.Reflection.AssemblyInformationalVersion("{1}")]
"@ -f $TaskContext.Version.Version,$TaskContext.Version.SemVer2 | Add-Content -Path $assemblyInfoPath
                }
        }

        $verbosity = 'm'
        if( $TaskParameter['Verbosity'] )
        {
            $verbosity = $TaskParameter['Verbosity']
        }

        $configuration = Get-WhiskeyMSBuildConfiguration -Context $TaskContext

        $property = Invoke-Command {
            Write-Output ('Configuration={0}' -f $configuration)

            if( $TaskParameter.ContainsKey('Property') )
            {
                Write-Output ($TaskParameter['Property'])
            }

            if( $OutputDirectory )
            {
                # Get an absolute path. MSBuild interprets relative paths as being relative to .csproj being compiled.
                $OutputDirectory = Resolve-Path -Path $OutputDirectory | Select-Object -ExpandProperty 'ProviderPath'
                Write-Output ('OutDir={0}' -f $OutputDirectory)
            }
        }

        $cpuArg = '/maxcpucount'
        $cpuCount = $TaskParameter['CpuCount'] | ConvertFrom-WhiskeyYamlScalar
        if( $cpuCount )
        {
            $cpuArg = '/maxcpucount:{0}' -f $TaskParameter['CpuCount']
        }

        if( ($TaskParameter['NoMaxCpuCountArgument'] | ConvertFrom-WhiskeyYamlScalar) )
        {
            $cpuArg = ''
        }

        $noFileLogger = $TaskParameter['NoFileLogger'] | ConvertFrom-WhiskeyYamlScalar

        $projectFileName = $projectPath | Split-Path -Leaf
        $logFilePath = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('msbuild.{0}.log' -f $projectFileName)
        $msbuildArgs = Invoke-Command {
                                            ('/verbosity:{0}' -f $verbosity)
                                            $cpuArg
                                            $TaskParameter['Argument']
                                            if( -not $noFileLogger )
                                            {
                                                '/filelogger9'
                                                ('/flp9:LogFile={0};Verbosity=d' -f $logFilePath)
                                            }
                                      } | Where-Object { $_ }
        $separator = '{0}VERBOSE:               ' -f [Environment]::NewLine
        Write-WhiskeyVerbose -Context $TaskContext -Message ('  Target      {0}' -f ($target -join $separator))
        Write-WhiskeyVerbose -Context $TaskContext -Message ('  Property    {0}' -f ($property -join $separator))
        Write-WhiskeyVerbose -Context $TaskContext -Message ('  Argument    {0}' -f ($msbuildArgs -join $separator))

        $propertyArgs = & {
            if ($property)
            {
                Write-WhiskeyVerbose "Escaping MSBuild property values."
            }

            foreach ($item in $property)
            {
                $name,$value = $item -split '=',2
                # Unescape first in case the there's already an escaped character in there.
                $value = [Uri]::UnescapeDataString($value)
                $value = [Uri]::EscapeDataString($value)
                Write-WhiskeyVerbose "  ${item} -> ${name}=${value}"
                "/p:${name}=${value}"
            }
        }

        $targetArg = '/t:{0}' -f ($target -join ';')

        Write-WhiskeyCommand -Path $msbuildExepath `
                             -ArgumentList (& { $projectPath ; $targetArg ; $propertyArgs ; $msbuildArgs })
        & $msbuildExePath $projectPath $targetArg $propertyArgs $msbuildArgs /nologo
        if( $LASTEXITCODE -ne 0 )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('MSBuild exited with code {0}.' -f $LASTEXITCODE)
            return
        }
    }
}
