
function Publish-ProGetUniversalPackage
{
    <#
    .SYNOPSIS
    Publishes a package to the specified ProGet instance

    .DESCRIPTION
    The `Publish-ProGetUniversalPackage` function will upload a package to the specified Proget instance/feed.

    .EXAMPLE
    Publish-ProGetUniversalPackage -Session $ProGetSession -FeedName 'Apps' -PackagePath 'C:\ProGetPackages\TestPackage.upack'

    Demonstrates how to call `Publish-ProGetUniversalPackage`. In this case, the package named 'TestPackage.upack' will be published to the 'Apps' feed located at $Session.Uri using the $Session.Credential authentication credentials
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true)]
        [pscustomobject]
        # The session includes ProGet's URI and the credentials to use when utilizing ProGet's API.
        $Session,

        [Parameter(Mandatory=$true)]
        [string]
        # The feed name indicates the appropriate feed where the package should be published.
        $FeedName,

        [Parameter(Mandatory=$true)]
        [string]
        # The path to the package that will be published to ProGet.
        $PackagePath
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    $shouldProcessCaption = ('creating {0} package' -f $PackagePath)
    $proGetPackageUri = [String]$Session.Uri + 'upack/' + $FeedName
    if (!$Session.Credential)
    {
        Write-Error -Message ('Unable to upload ''{0}'' package to ProGet at {1}. Uploading a package requires ProGet credentials (i.e. a username and password), but the credential on the ProGet session is missing. Please use `New-ProGetSession` to create a session and pass a credential that can upload universal packages via the `Credential` parameter.' -f ($PackagePath | Split-Path -Leaf), $proGetPackageUri)
        return
    }
    $proGetCredential = $Session.Credential

    $headers = @{}
    $bytes = [Text.Encoding]::UTF8.GetBytes(('{0}:{1}' -f $proGetCredential.UserName,$proGetCredential.GetNetworkCredential().Password))
    $creds = 'Basic ' + [Convert]::ToBase64String($bytes)
    
    $operationDescription = 'Uploading ''{0}'' package to ProGet {1}' -f ($PackagePath | Split-Path -Leaf), $proGetPackageUri
    if( $PSCmdlet.ShouldProcess($operationDescription, $operationDescription, $shouldProcessCaption) )
    {
        Write-Verbose -Message ('PUT {0}' -f $proGetPackageUri)
    
        # Invoke-RestMethod runs out memory when uploading 100MB ZIP files (or larger). UploadFile doesn't have that problem.
        $client = New-Object 'Net.WebClient'
        $client.Headers.Add('Authorization', $creds)
        try
        {
            $client.UploadFile($proGetPackageUri, 'PUT', $PackagePath)
        }
        catch
        {
            $ex = $_.Exception
            while( $ex.InnerException )
            {
                $ex = $ex.InnerException
            }

            $result = ''
            if( $ex -is [Net.WebException] )
            {
                [Net.HttpWebResponse]$response = $ex.Response
                if( $response )
                {
                    $stream = $response.GetResponseStream()
                    $reader = New-Object 'IO.StreamReader' $stream
                    $result = $reader.ReadToEnd()
                }
            }

            if( -not $result )
            {
                $result = $ex.Message
            }

            $Global:Error.RemoveAt(0)
            Write-Error -Message ('Failed to upload ''{0}'' package to {1}{2}{3}' -f ($PackagePath | Split-Path -Leaf),$proGetPackageUri,[Environment]::NewLine,$result)
        }
    }
}
