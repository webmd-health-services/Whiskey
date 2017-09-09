
function Publish-ProGetUniversalPackage
{
    <#
    .SYNOPSIS
    Publishes a package to the specified ProGet instance

    .DESCRIPTION
    The `Publish-ProGetUniversalPackage` function will upload a package to the `FeedName` universal feed . It uses upack 2.0.0.1 to upload. If upack.exe returns a non-zero exit code, the upload failed.

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
    $proGetCredential = $Session.Credential

    $PackagePath = Resolve-Path -Path $PackagePath | Select-Object -ExpandProperty 'ProviderPath'
    if( -not $PackagePath )
    {
        Write-Error -Message ('Package ''{0}'' does not exist.' -f $PSBoundParameters['PackagePath'])
        return
    }

    $upackPath = Join-Path -Path $PSScriptRoot -ChildPath '..\bin\upack.exe' -Resolve
    if( -not $upackPath )
    {
        Write-Error -Message ('We couldn''t find the upack.exe executable.' -f $upackPath)
        return
    }

    $userMsg = ''
    if( $proGetCredential )
    {
        $userMsg = ' as ''{0}''' -f $proGetCredential.UserName
    }

    $operationDescription = 'Uploading ''{0}'' package to ProGet at ''{1}''{2}.' -f ($PackagePath | Split-Path -Leaf), $proGetPackageUri, $userMsg
    if( $PSCmdlet.ShouldProcess($operationDescription, $operationDescription, $shouldProcessCaption) )
    {
        Write-Verbose -Message $operationDescription

        $userArg = ''
        if( $proGetCredential )
        {
            $userArg = '--user={0}:{1}' -f $proGetCredential.UserName,$proGetCredential.GetNetworkCredential().Password
        }
        
        & $upackPath 'push' $PackagePath $proGetPackageUri $userArg
        if( $LASTEXITCODE )
        {
            Write-Error -Message ('Failed to upload ''{0}'' to ''{1}''{2}: ''{3}'' returned with exit code ''{4}''.' -f $PackagePath,$proGetPackageUri,$userMsg,$upackPath,$LASTEXITCODE)
            return
        }
    }
}
