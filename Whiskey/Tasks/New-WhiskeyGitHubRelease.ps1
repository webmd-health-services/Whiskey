
function New-WhiskeyGitHubRelease
{
    <#
    .SYNOPSIS
    

    .DESCRIPTION
    

    .EXAMPLE
    

    
    #>
    [CmdletBinding()]
    [Whiskey.Task('GitHubRelease')]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    function Invoke-GitHubApi
    {
        param(
            $Endpoint,
            $Parameter
        )


    }

    $apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID $TaskParameter['ApiKeyID'] -PropertyName 'ApiKeyID'
    $headers = @{
	                Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($apiKey + ":x-oauth-basic"))
                }
    $baseUri = [uri]'https://api.github.com/repos/{0}' -f $TaskParameter['RepositoryName']

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

    function Invoke-GitHubApi
    {
        [CmdletBinding(DefaultParameterSetName='NoBody')]
        param(
            [Parameter(Mandatory=$true)]
            [uri]
            $Uri,

            [Parameter(Mandatory=$true,ParameterSetName='FileUpload')]
            [string]
            $ContentType,

            [Parameter(Mandatory=$true,ParameterSetName='FileUpload')]
            [string]
            $InFile,

            [Parameter(Mandatory=$true,ParameterSetName='JsonRequest')]
            $Parameter,

            [Microsoft.PowerShell.Commands.WebRequestMethod]
            $Method = [Microsoft.PowerShell.Commands.WebRequestMethod]::Post
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
		    Invoke-RestMethod -Uri $Uri -Method $Method -Headers $headers -ContentType $ContentType @optionalParams
	    }
	    catch
	    {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('GitHub API call to "{0}" failed: {1}' -f $uri,$_)
	    }
    }

    $tag = $TaskParameter['Tag']
    $release = Invoke-GitHubApi -Uri ('{0}/releases/tags/{1}' -f $baseUri,[uri]::EscapeUriString($tag)) -Method Get

    $createOrEditMethod = [Microsoft.PowerShell.Commands.WebRequestMethod]::Post
    $actionDescription = 'Creating'
    if( $release )
    {
        $createOrEditMethod = [Microsoft.PowerShell.Commands.WebRequestMethod]::Patch
        $actionDescription = 'Updating'
    }

	$releaseData = @{
			            tag_name         = $TaskParameter['Tag']
			            target_commitish = $TaskContext.BuildMetadata.ScmCommitID
		            }

    if( $TaskParameter['Name'] )
    {
	    $releaseData['name'] = $TaskParameter['Name']
    }

    if( $TaskParameter['Description'] )
    {
        $releaseData['body'] = $TaskParameter['Description']
    }

    Write-WhiskeyInfo -Context $TaskContext -Message ('{0} release "{1}" "{2}" at commit "{3}".' -f $actionDescription,$TaskParameter['Name'],$TaskParameter['Tag'],$TaskContext.BuildMetadata.ScmCommitID)
    $release = Invoke-GitHubApi -Uri ('{0}/releases' -f $baseUri) -Parameter $releaseData -Method $createOrEditMethod
    $release

    $assetIdx = 0
    foreach( $asset in $TaskParameter['Assets'] )
    {
        $assetPath = $asset['Path'] | Resolve-WhiskeyTaskPath -TaskContext $TaskContext -PropertyName ('Assets[{0}].Path' -f $assetIdx++) -PathType File
        if( -not $assetPath )
        {
            continue
        }

        $assetName = $assetPath | Split-Path -Leaf

        $uri = $release.upload_url -replace '{[^}]+}$'
        $uri = '{0}?name={1}&label={2}' -f $uri,[uri]::EscapeDataString($assetName),[uri]::EscapeDataString($asset['Name'])
        Write-WhiskeyInfo -Context $TaskContext -Message ('Uploading file "{0}".' -f $assetPath)
        Invoke-GitHubApi -Method Post -Uri $uri -ContentType $asset['ContentType'] -InFile $assetPath
    }
}