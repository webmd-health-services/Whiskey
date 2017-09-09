
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
        $PackagePath,

        [Switch]
        # Replace the package if it already exists in ProGet.
        $Force
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

    if( -not $Force )
    {
        $version = $null
        $name = $null
        $group = $null
        $zip = $null
        $foundUpackJson = $true
        $invalidUpackJson = $false
        try
        {
            $zip = [IO.Compression.ZipFile]::OpenRead($PackagePath)
            $foundUpackJson = $false
            foreach( $entry in $zip.Entries )
            {
                if($entry.FullName -ne "upack.json" )
                {
                    continue
                }

                $foundUpackJson = $true
                $stream = $entry.Open()
                $stringReader = New-Object 'IO.StreamReader' $stream
                try
                {
                    $packageJson = $stringReader.ReadToEnd() | ConvertFrom-Json
                    $version = $packageJson.version
                    $name = $packageJson.name
                    if( $packageJson | Get-Member -Name 'group' )
                    {
                        $group = $packageJson.group
                    }
                }
                catch
                {
                    $invalidUpackJson = $true
                }
                finally
                {
                    $stringReader.Close()
                    $stream.Close()
                }
                break
            }
        }
        catch
        {
            Write-Error -Message ('The upack file ''{0}'' isn''t a valid ZIP file.' -f $PackagePath)
            return
        }
        finally
        {
            if( $zip )
            {
                $zip.Dispose()
            }
        }

        if( -not $foundUpackJson )
        {
            Write-Error -Message ('The upack file ''{0}'' is invalid. It must contain a upack.json metadata file. See http://inedo.com/support/documentation/various/universal-packages/universal-feed-api for more information.' -f $PackagePath) 
            return
        }

        if( $invalidUpackJson )
        {
            Write-Error -Message (@"
The upack.json metadata file in '$($PackagePath)' is invalid. It must be a valid JSON file with ''version'' and ''name'' properties that have values, e.g. 
    
    {
        ""name"": ""HDARS"",
        ""version": ""1.3.9""
    }
    
See http://inedo.com/support/documentation/various/universal-packages/universal-feed-api for more information.
    
"@)        
            return
        }

        if( -not $name -or -not $version )
        {
            [string[]]$propertyNames = @( 'name', 'version') | Where-Object { -not (Get-Variable -Name $_ -ValueOnly) }
            $description = 'property doesn''t have a value'
            if( $propertyNames.Count -gt 1 )
            {
                $description = 'properties don''t have values'
            }
            $emptyPropertyNames =  $propertyNames -join ''' and '''
                                    
            Write-Error -Message ('The upack.json metadata file in ''{0}'' is invalid. The ''{1}'' {2}. See http://inedo.com/support/documentation/various/universal-packages/universal-feed-api for more information.' -f $PackagePath,$emptyPropertyNames,$description)
            return
        }

        $groupParam = ''
        if( $group )
        {
            $groupParam = '&group={0}' -f [Web.HttpUtility]::UrlEncode($group)
        }
        $path = '/upack/{0}/packages?name={1}{2}' -f $FeedName,[Web.HttpUtility]::UrlEncode($name),$groupParam
        $packageInfo = Invoke-ProGetRestMethod -Session $Session -Path $path -Method Get -ErrorAction Ignore
        if( $packageInfo -and $packageInfo.versions -contains $version )
        {
            Write-Error -Message ('Package {0} {1} already exists in universal ProGet feed ''{2}''.' -f $name,$version,$proGetPackageUri)
            return
        }
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
