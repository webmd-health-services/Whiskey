
function Set-WhsCIBuildStatus
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $Context,

        [Parameter(Mandatory=$true)]
        [ValidateSet('Started','Completed','Failed')]
        # The build status. Should be one of `Started`, `Completed`, or `Failed`.
        $Status
    )

    Set-StrictMode -Version 'Latest'

    if( $Context.ByDeveloper )
    {
        return
    }

    $reportingTo = $Context.Configuration['ReportBuildStatusTo']

    if( -not $reportingTo )
    {
        return
    }

    $reporterIdx = -1
    foreach( $reporter in $reportingTo )
    {
        $reporterIdx++
        $reporterName = $reporter.Keys | Select-Object -First 1
        $propertyDescription = 'ReportBuildStatusTo[{0}]: {1}' -f $reporterIdx,$reporterName
        $reporterConfig = $reporter[$reporterName]
        switch( $reporterName )
        {
            'BitbucketServer'
            {
                $uri = $reporterConfig['Uri']
                if( -not $uri )
                {
                    Stop-WhsCITask -TaskContext $Context -PropertyDescription $propertyDescription -Message (@'
Property 'Uri' does not exist or does not have a value. Set this property to the Bitbucket Server URI where you want build statuses reported to, e.g.,
 
    ReportBuildStatusTo:
    - BitbucketServer:
        Uri: BITBUCKET_SERVER_URI
        CredentialID: CREDENTIAL_ID
        
'@ -f $uri)
                }
                $credID = $reporterConfig['CredentialID']
                if( -not $credID )
                {
                    Stop-WhsCITask -TaskContext $Context -PropertyDescription $propertyDescription -Message (@'
Property 'CredentialID' does not exist or does not have a value. Set this property to the ID of the credential to use when connecting to the Bitbucket Server at '{0}', e.g.,
 
    ReportBuildStatusTo:
    - BitbucketServer:
        Uri: {0}
        CredentialID: CREDENTIAL_ID
 
Credentials are added to the build context object returned by `New-WhsCIContext`, e.g.  `$context.Credentials.Add( 'CREDENTIAL_ID', $credential )`
'@ -f $uri)
                }
                $credential = $Context.Credentials[$credID]
                if( -not $credential )
                {
                    Stop-WhsCITask -TaskContext $Context -PropertyDescription $propertyDescription -Message ('Credential ''{0}'' does not exist in the build context''s credential collection. Credentials must be added to the build context object returned by the `New-WhsCIContext` function, e.g.  `$context.Credentials.Add( ''{0}'', $credential )`. Check that the credential ID on this reporter is the same as the ID of the credential you added to the build context.' -f $credID)
                }
                $conn = New-BBServerConnection -Credential $credential -Uri $uri
                $statusMap = @{
                                    'Started' = 'INPROGRESS';
                                    'Completed' = 'Successful';
                                    'Failed' = 'Failed'
                              }
                Set-BBServerCommitBuildStatus -Connection $conn -Status $statusMap[$Status]
            }

            default
            {
                Stop-WhsCITask -TaskContext $Context -PropertyDescription $propertyDescription -Message ('Unknown build status reporter ''{0}''. Supported reporters are ''BitbucketServer''.' -f $reporterName)
            }
        }
    }
}
