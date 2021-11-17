
function Publish-WhiskeyNuGetPackage
{
    [Whiskey.Task('NuGetPush',Platform='Windows',Aliases=('PublishNuGetLibrary','PublishNuGetPackage'),WarnWhenUsingAlias=$true)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter,

        [Whiskey.Tasks.ValidatePath(PathType='File')]
        [String[]]$Path
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

    $apiKeyID = $TaskParameter['ApiKeyID']
    if( -not $apiKeyID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property ''ApiKeyID'' is mandatory. It should be the ID/name of the API key to use when publishing NuGet packages to {0}, e.g.:

    Build:
    - PublishNuGetPackage:
        Uri: {0}
        ApiKeyID: API_KEY_ID

Use the `Add-WhiskeyApiKey` function to add the API key to the build.

            ' -f $source)
        return
    }
    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $apiKeyID -PropertyName 'ApiKeyID'

    $nuGetPath = Install-WhiskeyNuGet -DownloadRoot $TaskContext.BuildRoot -Version $TaskParameter['Version']
    if( -not $nugetPath )
    {
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
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Unknown failure checking if {0} {1} package already exists at {2}. {3}' -f  $packageName,$packageVersion,$packageUri,$_)
                return
            }

            $response = $_.Exception.Response
            if( $response.StatusCode -ne [Net.HttpStatusCode]::NotFound )
            {
                $error = ''
                if( $response | Get-Member 'GetResponseStream' )
                {
                    $content = $response.GetResponseStream()
                    $content.Position = 0
                    $reader = New-Object 'IO.StreamReader' $content
                    $error = $reader.ReadToEnd() -replace '<[^>]+?>',''
                    $reader.Close()
                    $response.Close()
                }
                Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Failure checking if {0} {1} package already exists at {2}. The web request returned a {3} ({4}) status code:{5} {5}{6}' -f $packageName,$packageVersion,$packageUri,$response.StatusCode,[int]$response.StatusCode,[Environment]::NewLine,$error)
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

        # Publish package and symbols to NuGet
        Invoke-WhiskeyNuGetPush -Path $packagePath -Uri $source -ApiKey $apiKey -NuGetPath $nuGetPath

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
