
function Add-PSTypeName
{
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        $InputObject,

        [Switch]
        $RepositoryInfo
    )

    process
    {
        if( $RepositoryInfo )
        {
            $InputObject.pstypenames.Add( 'Atlassian.Bitbucket.Server.RepositoryInfo' )
        }

        $InputObject
    }
}