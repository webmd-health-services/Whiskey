
function New-WhiskeyGitHubRelease
{
    [CmdletBinding()]
    [Whiskey.Task('GitHubRelease')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $apiKeyID = $TaskParameter['ApiKeyID']
    if( -not $apiKeyID )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "ApiKeyID" is mandatory. It should be set to the ID of the API key to use when talking to the GitHub API. API keys are added to your build with the "Add-WhiskeyApiKey" function.')
        return
    }

    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $apiKeyID -PropertyName 'ApiKeyID'
    $headers = @{
                    Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($apiKey + ":x-oauth-basic"))
                }
    $repositoryName = $TaskParameter['RepositoryName']
    if( -not $repositoryName )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "RepositoryName" is mandatory. It should be the owner and repository name of the repository you want to access as a URI path, e.g. OWNER/REPO.')
        return
    }

    if( $repositoryName -notmatch '^[^/]+/[^/]+$' )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "RepositoryName" is invalid. It should be the owner and repository name of the repository you want to access as a URI path, e.g. OWNER/REPO.')
        return
    }

    $baseUri = [Uri]'https://api.github.com/repos/{0}' -f $repositoryName

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

    function Invoke-GitHubApi
    {
        [CmdletBinding(DefaultParameterSetName='NoBody')]
        param(
            [Parameter(Mandatory)]
            [Uri]$Uri,

            [Parameter(Mandatory,ParameterSetName='FileUpload')]
            [String]$ContentType,

            [Parameter(Mandatory,ParameterSetName='FileUpload')]
            [String]$InFile,

            [Parameter(Mandatory,ParameterSetName='JsonRequest')]
            $Parameter,

            [Microsoft.PowerShell.Commands.WebRequestMethod]$Method = 'Post'
        )

        $optionalParams = @{ }
        if( $PSCmdlet.ParameterSetName -eq 'JsonRequest' )
        {
            if( $Parameter )
            {
                $optionalParams['Body'] = $Parameter | ConvertTo-Json
                Write-WhiskeyVerbose -Context $TaskContext -Message $optionalParams['Body']
            }
            $ContentType = 'application/json'
        }
        elseif( $PSCmdlet.ParameterSetName -eq 'FileUpload' )
        {
            $optionalParams['InFile'] = $InFile
        }

        try
        {
            $ProgressPreference = [Management.Automation.ActionPreference]::SilentlyContinue
            Invoke-RestMethod -Uri $Uri -Method $Method -Headers $headers -ContentType $ContentType @optionalParams
        }
        catch
        {
            if( $ErrorActionPreference -eq 'Ignore' )
            {
                $Global:Error.RemoveAt(0)
            }
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('GitHub API call to "{0}" failed: {1}' -f $uri,$_)
            return
        }
    }

    $tag = $TaskParameter['Tag']
    if( -not $tag )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Property "Tag" is mandatory. It should be the tag to create in your repository for this release. This is usually a version number. We recommend using the `$(WHISKEY_SEMVER2_NO_BUILD_METADATA)` variable to use the version number of the current build.')
        return
    }
    $release = Invoke-GitHubApi -Uri ('{0}/releases/tags/{1}' -f $baseUri,[Uri]::EscapeUriString($tag)) -Method Get -ErrorAction Ignore

    $createOrEditMethod = [Microsoft.PowerShell.Commands.WebRequestMethod]::Post
    $actionDescription = 'Creating'
    $createOrEditUri = '{0}/releases' -f $baseUri
    if( $release )
    {
        $createOrEditMethod = [Microsoft.PowerShell.Commands.WebRequestMethod]::Patch
        $actionDescription = 'Updating'
        $createOrEditUri = $release.url
    }

    $releaseName = $TaskParameter['Name']
    $releaseNameDesc = ''

    $releaseData = @{
                        tag_name = $tag
                    }

    if( $TaskParameter['Commitish'] )
    {
        $releaseData['target_commitish'] = $TaskParameter['Commitish']
    }

    if( $releaseName )
    {
        $releaseData['name'] = $releaseName
        $releaseNameDesc = '"{0}" ' -f $releaseName
    }

    if( $TaskParameter['Description'] )
    {
        $releaseData['body'] = $TaskParameter['Description']
    }

    Write-WhiskeyInfo -Context $TaskContext -Message ('{0} release {1}with tag "{2}" at commit "{3}".' -f $actionDescription,$releaseNameDesc,$tag,$TaskContext.BuildMetadata.ScmCommitID)
    $release = Invoke-GitHubApi -Uri $createOrEditUri -Parameter $releaseData -Method $createOrEditMethod
    $release

    if( $TaskParameter['Assets'] )
    {
        $existingAssets = Invoke-GitHubApi -Uri $release.assets_url -Method Get

        $assetIdx = 0
        foreach( $asset in $TaskParameter['Assets'] )
        {
            $basePropertyName = 'Assets[{0}]' -f $assetIdx++
            $assetPath = 
                $asset['Path'] | 
                Resolve-WhiskeyTaskPath -TaskContext $TaskContext `
                                        -PropertyName ('{0}.Path:' -f $basePropertyName) `
                                        -PathType File `
                                        -Mandatory `
                                        -OnlySinglePath
            if( -not $assetPath )
            {
                continue
            }

            $assetName = $asset['Name']
            if( -not $assetName ) 
            {
                $assetName = $assetPath | Split-Path -Leaf
            }

            $existingAsset = $existingAssets | Where-Object { $_ -and $_.name -eq $assetName }
            if( $existingAsset )
            {
                Write-WhiskeyInfo -Context $TaskContext -Message ('Updating asset "{0}" from file "{1}.' -f $assetName,$assetPath)
                Invoke-GitHubApi -Method Patch -Uri $existingAsset.url -Parameter @{ name = $assetName; label = $assetName }
            }
            else
            {
                $uri = $release.upload_url -replace '{[^}]+}$'
                $uri = '{0}?name={1}&label={1}' -f $uri,[Uri]::EscapeDataString($assetName)
                $contentType = $asset['ContentType']
                if( -not $contentType )
                {
                    Stop-WhiskeyTask -TaskContext $TaskContext -PropertyName $basePropertyName -Message ('Property "ContentType" is mandatory. It must be the "{0}" file''s media type. For a list of acceptable types, see https://www.iana.org/assignments/media-types/media-types.xhtml.' -f $assetPath)
                    continue
                }
                Write-WhiskeyInfo -Context $TaskContext -Message ('Uploading asset "{0}" from file "{1}".' -f $assetName,$assetPath)
                Invoke-GitHubApi -Method Post -Uri $uri -ContentType $asset['ContentType'] -InFile $assetPath
            }
        }
    }
}
