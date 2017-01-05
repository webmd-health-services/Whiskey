
function Assert-WhsCIVersionAvailable
{
    <#
    .SYNOPSIS
    Ensures that a version isn't already in use/taken.

    .DESCRIPTION
    The `Assert-WhsCIVersionAvailable` function ensures that a particular version isn't already in use or taken. When releasing, it is customary to create a branch for that release. Once a release branch is created, the version being actively developed (i.e. the next version) should be incremented so that changes for the next release don't accidentally get deployed as part of the last release. This function looks at the branches defined in the current repository and makes sure there are no branches for the version passed in. This check is only done if the current branch *isn't* a release branch or the *master* branch.

    If the version wasn't incremented as in use in a release branch, this function throws a terminating exception and returns `$null`. If the version number is OK, it returns the version number passed in.

    .EXAMPLE
    '1.2.3' | ConvertTo-WhsCISemanticVersion | Assert-WhsCIVersionAvailable

    Demonstrates how to insure the version number was incremented when a release branch was created for the next release.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [SemVersion.SemanticVersion]
        # The version to check.
        $Version
    )

    Set-StrictMode -Version 'Latest'

    $currentBranch = Get-GitBranch -Current
    if( $currentBranch.Name -like 'release/*' -or $currentBranch.Name -eq 'master' )
    {
        return $Version
    }

    $branchExists = Get-GitBranch |
                        Where-Object { $_.Name -match '^release/(.+)$' } |
                        Where-Object { 
                                $rawVersion = $Matches[1]
                                [version]$releaseVersion = $null
                                if( -not [version]::TryParse($rawVersion, [ref]$releaseVersion) )
                                {
                                    [int]$majorVersion = $null
                                    if( -not [int]::TryParse($rawVersion, [ref]$majorVersion) )
                                    {
                                        return $false

                                    }
                                    $releaseVersion = New-Object -TypeName 'Version' -ArgumentList $majorVersion,0
                                }

                                $releaseVersion.Major -eq $Version.Major -and $releaseVersion.Minor -eq $Version.Minor
                            }
    if( $branchExists )
    {
        throw ('Version ''{0}.{1}'' is already in use in branch ''{2}''. Please make sure you increment the version number in your repository''s whsbuild.yml file.' -f $Version.Major,$Version.Minor,$branchExists.Name)
    }

    return $Version
}