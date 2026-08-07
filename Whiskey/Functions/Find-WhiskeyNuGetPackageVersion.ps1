
function Find-WhiskeyNuGetPackageVersion
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $ID
    )

    # We don't want `Invoke-RestMethod` to throw a terminating error so wrap it in a try/catch block.
    function Invoke-InvokeRestMethod
    {
        [CmdletBinding()]
        param(
            [Uri] $Uri
        )

        $numErrorsBefore = $Global:Error.Count
        try
        {
            Invoke-RestMethod @PSBoundParameters
        }
        catch
        {
            Write-Error $_ -ErrorAction $ErrorActionPreference
        }

        if ($ErrorActionPreference -eq 'Ignore')
        {
            $numErrorsToClear = $Global:Error.Count - $numErrorsBefore
            for ($idx = 0; $idx -lt $numErrorsToClear; ++$idx)
            {
                $Global:Error.RemoveAt(0)
            }
        }
    }

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    $ProgressPreference = 'SilentlyContinue'

    foreach ($pkgSource in (Get-PackageSource -ProviderName 'NuGet'))
    {
        $results = @()
        $pkgSourceName = $pkgSource.Name
        $pkgSourceUrl = $pkgSource.Location
        $pkgIndexUrl = $pkgSourceUrl
        $v3Path = '/v3/index.json'
        $v3Wildcard = "*${v3Path}"
        if ($pkgIndexUrl -notlike $v3Wildcard)
        {
            $pkgIndexUrl = "${pkgIndexUrl}${v3Path}"
        }

        $pkgIndex = $null

        Write-WhiskeyVerbose "GET ${pkgIndexUrl}"
        $pkgIndex = Invoke-InvokeRestMethod -Uri $pkgIndexUrl -ErrorAction Ignore

        if (-not $pkgIndex -and $pkgSourceUrl -like $v3Wildcard)
        {
            $msg = "Skipping NuGet package source ${pkgSourceName} (${pkgSourceUrl}) because it didnt' return an " +
                   'index.'
            Write-WhiskeyVerbose $msg
            continue
        }

        # It's a v2 endpoint, so we can use PackageManagement.
        if (-not $pkgIndex)
        {
            $msg = "Using Find-Package because the ${pkgSourceName} (${pkgSourceUrl}) NuGet package source doesn't " +
                   'support the NuGet v3 API.'
            Write-WhiskeyVerbose $msg

            $allowPrereleaseArg = Get-AllowPrereleaseArg -CommandName 'Find-Package' -AllowPrerelease
            $pkgSource |
                Find-Package -Name $ID -AllVersions @allowPrereleaseArg -ErrorAction Ignore |
                Select-Object -ExpandProperty 'Version' |
                Write-Output -OutVariable 'results'

            $msg = "Find-Package returned $(($results | Measure-Object).Count) versions of NuGet package ${ID} from " +
                   "NuGet package source ${pkgSourceName} (${pkgSourceUrl})."
            Write-WhiskeyVerbose $msg
            continue
        }

        $searchResources =
            Invoke-InvokeRestMethod -Uri $pkgIndexUrl |
            Select-Object -ExpandProperty 'resources' -ErrorAction Ignore |
            Where-Object '@type' -EQ 'SearchQueryService'
        if (-not $searchResources)
        {
            $msg = "Failed to query NuGet package source ${pkgSourceName} (${pkgSourceUrl}) for package ID because " +
                   'that package source doesn''t have a SearchQueryService resource.'
            Write-WhiskeyVerbose -Message $msg
            continue
        }

        foreach ($searchResource in $searchResources)
        {
            if (-not ($searchResource | Get-Member -Name '@id') -or -not $searchResource.'@id')
            {
                $msg = "Failed to query NuGet package source ${pkgSourceName} (${pkgSourceUrl}) because its " +
                       'SearchQueryService resource didn''t return a URL (@id property).'
                Write-WhiskeyVerbose -Message $msg
                continue
            }

            $searchUrl =
                "$($searchResource.'@id')?q=$([uri]::EscapeDataString($ID))&semVerLevel=2.0.0&prerelease=true"
            Write-WhiskeyVerbose "GET ${searchUrl}"
            Invoke-InvokeRestMethod -Uri $searchUrl |
                Select-Object -ExpandProperty 'data' -ErrorAction Ignore |
                Where-Object 'id' -EQ $ID |
                Select-Object -ExpandProperty 'versions' |
                Select-Object -ExpandProperty 'version' |
                Write-Output -OutVariable 'results'

            $msg = "Search query ${searchUrl} to package source ${pkgSourceName} (${pkgSourceUrl}) returned " +
                   "$(($results | Measure-Object).Count) versions of NuGet package ${ID}."
            Write-WhiskeyVerbose $msg

            if ($results)
            {
                break
            }
        }
    }
}

