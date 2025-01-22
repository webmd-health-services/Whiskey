
function Publish-WhiskeyNuGetPackage
{
    [Whiskey.Task('NuGetPush', Platform='Windows', Aliases=('PublishNuGetLibrary','PublishNuGetPackage'),
        WarnWhenUsingAlias)]
    [Whiskey.RequiresNuGetPackage('NuGet.CommandLine', Version='6.*', PathParameterName='NuGetPath')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(PathType='File')]
        [String[]]$Path,

        [String] $NuGetPath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    if( -not $Path )
    {
        $Path =
            Join-Path -Path $TaskContext.OutputDirectory.FullName -ChildPath '*.nupkg' |
            Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PathType 'File' -PropertyName 'Path'
    }

    $publishSymbols = $TaskParameter['Symbols'] | ConvertFrom-WhiskeyYamlScalar

    $paths = $Path |
                Where-Object {
                    $wildcard = '*.symbols.nupkg'
                    if( $publishSymbols )
                    {
                        $_ -like $wildcard
                    }
                    else
                    {
                        $_ -notlike $wildcard
                    }
                }

    $source = $TaskParameter['Uri']
    if( -not $source )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''Uri'' is mandatory. It should be the URI where NuGet packages should be published, e.g.

    Build:
    - PublishNuGetPackage:
        Uri: https://nuget.org
    ')
        return
    }

    $apiKey = ''
    $apiKeyID = $TaskParameter['ApiKeyID']
    if ($apiKeyID)
    {
        $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $apiKeyID -PropertyName 'ApiKeyID'
    }

    $NuGetPath = Join-Path -Path $NuGetPath -ChildPath 'tools\NuGet.exe' -Resolve
    if( -not $NuGetPath )
    {
        Stop-WhiskeyTask -Context $TaskContext -Message "NuGet.exe not found at ""$($NuGetPath)""."
        return
    }

    foreach ($packagePath in $paths)
    {
        $packageFilename = [IO.Path]::GetFileNameWithoutExtension(($packagePath | Split-Path -Leaf))
        $packageName = $packageFilename -replace '\.\d+\.\d+\.\d+(-.*)?(\.symbols)?',''

        $packageFilename -match '(\d+\.\d+\.\d+(?:-[0-9a-z]+)?)'
        $packageVersion = $Matches[1]

        $packageUri = '{0}/package/{1}/{2}' -f $source,$packageName,$packageVersion

        # Make sure this version doesn't exist.
        $packageExists = $false
        $numErrorsAtStart = $Global:Error.Count
        try
        {
            $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
            Invoke-WebRequest -Uri $packageUri -UseBasicParsing | Out-Null
            $packageExists = $true
        }
        catch
        {
            # Invoke-WebRequest throws differnt types of errors in Windows PowerShell and PowerShell Core. Handle the case where a non-HTTP exception occurs.
            if( -not ($_.Exception | Get-Member 'Response') )
            {
                Write-Error -ErrorRecord $_
                $msg = "Unknown failure checking if $($packageName) $($packageVersion) package already exists at " +
                       "$($packageUri): $($_)"
                Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                return
            }

            $response = $_.Exception.Response
            if( -not ($response | Get-Member 'StatusCode') )
            {
                Write-Error -ErrorRecord $_
                $msg = "Unable to determine HTTP status code from failed HTTP response to $($packageUri) checking if " +
                       "$($packageName) $($packageVersion) exists: $($_)"
                Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                return
            }

            if( $response.StatusCode -ne [Net.HttpStatusCode]::NotFound )
            {
                $content = ''
                if( $response | Get-Member 'GetResponseStream' )
                {
                    $responseStream = $response.GetResponseStream()
                    $responseStream.Position = 0
                    $reader = New-Object 'IO.StreamReader' $responseStream
                    $content = $reader.ReadToEnd() -replace '<[^>]+?>',''
                    $reader.Close()
                    $response.Close()
                }
                $msg = "Failure checking if $($packageName) $($packageVersion) package already exists at " +
                       "$($packageUri). The web request returned status code $($response.StatusCode) " +
                       "($([int]$response.StatusCode)) status code: $($content)"
                Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
                return
            }

            for( $idx = 0; $idx -lt ($Global:Error.Count - $numErrorsAtStart); ++$idx )
            {
                $Global:Error.RemoveAt(0)
            }
        }

        if( $packageExists )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('{0} {1} already exists. Please increment your library''s version number in ''{2}''.' -f $packageName,$packageVersion,$TaskContext.ConfigurationPath)
            return
        }

        $optionalArgs = @{}
        if ($apiKey)
        {
            $optionalArgs['ApiKey'] = $apiKey
        }
        # Publish package and symbols to NuGet
        Invoke-WhiskeyNuGetPush -Path $packagePath -Url $source -NuGetPath $NuGetPath @optionalArgs

        if( -not ($TaskParameter['SkipUploadedCheck'] | ConvertFrom-WhiskeyYamlScalar) )
        {
            try
            {
                $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
                Invoke-WebRequest -Uri $packageUri -UseBasicParsing | Out-Null
            }
            catch
            {
                # Invoke-WebRequest throws differnt types of errors in Windows PowerShell and PowerShell Core. Handle the case where a non-HTTP exception occurs.
                if( -not ($_.Exception | Get-Member 'Response') )
                {
                    Write-Error -ErrorRecord $_
                    Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Unknown failure checking if {0} {1} package was published to {2}. {3}' -f  $packageName,$packageVersion,$packageUri,$_)
                    return
                }

                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Failed to publish NuGet package {0} {1} to {2}. When we checked if that package existed, we got a {3} HTTP status code. Please see build output for more information.' -f $packageName,$packageVersion,$packageUri,$_.Exception.Response.StatusCode)
                return
            }
        }
    }
}
