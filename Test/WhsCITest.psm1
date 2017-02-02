Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function New-TestWhsBuildFile
{
    param(
        [Parameter(ParameterSetName='WithRawYaml')]
        [string]
        $Yaml,

        [Parameter(ParameterSetName='SingleTask')]
        [SemVersion.SemanticVersion]
        $Version,

        [Parameter(ParameterSetName='SingleTask')]
        [string]
        $TaskName,

        [Parameter(ParameterSetName='SingleTask')]
        [string[]]
        $Path,

        [Parameter(ParameterSetname='SingleTask')]
        [hashtable]
        $TaskProperty
    )

    $config = $null
    if( $PSCmdlet.ParameterSetName -eq 'SingleTask' )
    {
        if( -not $TaskProperty )
        {
            $TaskProperty = @{}
        }
        if( $Path )
        {
            $TaskProperty['Path'] = $Path
        }
        $config = @{
                        BuildTasks = @(
                                    @{
                                        $TaskName = $TaskProperty
                                     }
                                 )
                   }
    }

    if( $config )
    {
        if( $Version )
        {
            $config['Version'] = $Version.ToString()
        }
        $Yaml = $config | ConvertTo-Yaml 
        #$DebugPreference = 'Continue'
        Write-Debug -Message ('{0}{1}' -f ([Environment]::NewLine),$Yaml)
    }

    $root = (Get-Item -Path 'TestDrive:').FullName
    $whsbuildymlpath = Join-Path -Path $root -ChildPath 'whsbuild.yml'
    $Yaml | Set-Content -Path $whsbuildymlpath
    return $whsbuildymlpath
}


function New-NUnitTestAssembly
{
    param(
        [string]
        $ConfigurationPath,

        [string[]]
        $AssemblyName,

        [Switch]
        $ThatFail
    )

    $root = $ConfigurationPath | Split-Path

    if( $ThatFail )
    {
        $sourceAssembly = $failingNUnit2TestAssemblyPath
    }
    else
    {
        $sourceAssembly = $passingNUnit2TestAssemblyPath
    }

    $sourceAssembly | Split-Path | Get-ChildItem -Filter 'nunit.framework.dll' | Copy-Item -Destination $root

    foreach( $name in $AssemblyName )
    {
        $destinationPath = Join-Path -Path $root -ChildPath $name
        Install-Directory -Path ($destinationPath | Split-Path)
        $sourceAssembly | Copy-Item -Destination $destinationPath
    }
}