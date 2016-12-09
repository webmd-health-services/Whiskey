
function New-BBServerRepository
{
    <#
    .SYNOPSIS
    Creates a new repository in Bitbucket Server.

    .DESCRIPTION
    The `New-BBServerRepository` function creates a new Git repository in Bitbucket Server. It requires an project to exist where the repository should exist (all repositories in Bitbucket Server are part of a project).

    By default, the repository is setup to allow forking and be private. To disable forking, use the `NotForkable` switch. To make the repository public, use the `Public` switch.

    Use the `New-BBServerConnection` function to generate the connection object that should get passed to the `Connection` parameter.

    .EXAMPLE
    New-BBServerRepository -Connection $conn -ProjectKey 'whs' -Name 'fubarsnafu'

    Demonstrates how to create a repository.

    .EXAMPLE
    New-BBServerRepository -Connection $conn -ProjectKey 'whs' -Name 'fubarsnafu' -NotForkable -Public

    Demonstrates how to create a repository with different default settings. The repository will be not be forkable and will be public, not private.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The connection information that describe what Bitbucket Server instance to connect to, what credentials to use, etc. Use the `New-BBServerConnection` function to create a connection object.
        $Connection,

        [Parameter(Mandatory=$true)]
        [string]
        # The key/ID that identifies the project where the repository will be created. This is *not* the project name.
        $ProjectKey,

        [Parameter(Mandatory=$true)]
        [ValidateLength(1,128)]
        [string]
        # The name of the repository to create.
        $Name,

        [Switch]
        # Disable the ability to fork the repository. The default is to allow forking.
        $NotForkable,

        [Switch]
        # Make the repository public. Not sure what that means.
        $Public
    )

    Set-StrictMode -Version 'Latest'

    $forkable = $true
    if( $NotForkable )
    {
        $forkable = $false
    }

    $newRepoInfo = @{
                        name = $Name;
                        scmId = 'git';
                        forkable = $forkable;
                        public = [bool]$Public;
                    }

    $repo = $newRepoInfo | Invoke-BBServerRestMethod -Connection $Connection -Method Post -ApiName 'api' -ResourcePath ('projects/{0}/repos' -f $ProjectKey)
    if( $repo )
    {
        $repo | Add-PSTypeName -RepositoryInfo
    }
}