
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function Assert-ThatAssertWhsCIVersionAvailable
{
    [CmdletBinding()]
    param(
        [string]
        $AllowsVersion,

        [string]
        $RejectsVersion
    )

    $rawVersion = $AllowsVersion
    if( $RejectsVersion )
    {
        $rawVersion = $RejectsVersion
    }

    $semVersion = $rawVersion | ConvertTo-WhsCISemanticVersion 
    $failed = $false
    $version = $null
    try
    {
        $version = $semVersion | Assert-WhsCIVersionAvailable
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $failed = $true
    }

    if( $AllowsVersion )
    {
        It 'should not fail' {
            $failed | Should Be $false
        }

        It 'should return the version' {
            $version | Should Be $semVersion
        }
    }
    
    if( $RejectsVersion ) 
    {
        It 'should throw terminating exception' {
            $failed | Should Be $true
        }

        It 'should return nothing' {
            $version | Should BeNullOrEmpty
        }
    }
}

function Initialize-Test
{
    param(
        [string[]]
        $GivenReleaseBranches,

        [string]
        $GivenCurrentBranchIs = 'develop'
    )

    $currentBranch = [pscustomobject]@{
                        CanonicalName = ('refs/heads/{0}' -f $GivenCurrentBranchIs);
                        Name = $GivenCurrentBranchIs;
                        UpstreamBranchCanonicalName = ('refs/heads/{0}' -f $GivenCurrentBranchIs);
                        IsRemote = $false;
                        IsTracking = $true;
                        IsCurrentRepositoryHead = $true;
                     }


    Mock -CommandName 'Get-GitBranch' -ModuleName 'WhsCI' -MockWith {

        [pscustomobject]@{
                            CanonicalName = 'refs/heads/master';
                            Name = 'master';
                            UpstreamBranchCanonicalName = 'refs/heads/master';
                            IsRemote = $false;
                            IsTracking = $true;
                            IsCurrentRepositoryHead = $false;
                            }

        foreach( $release in $GivenReleaseBranches )
        {
            [pscustomobject]@{
                                CanonicalName = ('refs/heads/release/{0}' -f $release);
                                Name = ('release/{0}' -f $release);
                                UpstreamBranchCanonicalName = ('refs/heads/release/{0}' -f $release);
                                IsRemote = $false;
                                IsTracking = $true;
                                IsCurrentRepositoryHead = $false;
                                }
        }
        $currentBranch
     }.GetNewClosure()

    Mock -CommandName 'Get-GitBranch' -ModuleName 'WhsCI' -ParameterFilter { $Current } -MockWith { $currentBranch }.GetNewClosure()
}

Describe 'Assert-WhsCIVersionAvailable.when there are no release branches' {
    Initialize-Test
    Assert-ThatAssertWhsCIVersionAvailable -AllowsVersion '1.2.3'
}

Describe 'Assert-WhsCIVersionAvailable.when there are release branches for other versions and the version is MAJOR' {
    Initialize-Test -GivenReleaseBranches '2','3.1','4.1'
    Assert-ThatAssertWhsCIVersionAvailable -AllowsVersion '4'
}

Describe 'Assert-WhsCIVersionAvailable.when there are release branches for other versions and the version is MAJOR and MINOR' {
    Initialize-Test -GivenReleaseBranches '2','3.1','4.1'
    Assert-ThatAssertWhsCIVersionAvailable -AllowsVersion '4.0'
}

Describe 'Assert-WhsCIVersionAvailable.when there are release branches for other versions' {
    Initialize-Test -GivenReleaseBranches '2','3.1','4.1'
    Assert-ThatAssertWhsCIVersionAvailable -AllowsVersion '4'
}

Describe 'Assert-WhsCIVersionAvailable.when there is a release branch for the version and the version is MAJOR only' {
    Initialize-Test -GivenReleaseBranches '4'
    Assert-ThatAssertWhsCIVersionAvailable -RejectsVersion '4' -ErrorAction SilentlyContinue
}

Describe 'Assert-WhsCIVersionAvailable.when there is a release branch for the version and the version is MAJOR and MINOR' {
    Initialize-Test -GivenReleaseBranches '5.1'
    Assert-ThatAssertWhsCIVersionAvailable -RejectsVersion '5.1' -ErrorAction SilentlyContinue
}

Describe 'Assert-WhsCIVersionAvailable.when there is a release branch and current branch is a release branch' {
    Initialize-Test -GivenReleaseBranches '4' -GivenCurrentBranchIs 'release/5'
    Assert-ThatAssertWhsCIVersionAvailable -AllowsVersion '4'
}

Describe 'Assert-WhsCIVersionAvailable.when there is a release branch and current branch is master branch' {
    Initialize-Test -GivenReleaseBranches '5' -GivenCurrentBranchIs 'master'
    Assert-ThatAssertWhsCIVersionAvailable -AllowsVersion '5'
}

Describe 'Assert-WhsCIVersionAvailable.when there is a release branch with patch version' {
    Initialize-Test -GivenReleaseBranches '5.4.3' 
    Assert-ThatAssertWhsCIVersionAvailable -AllowsVersion '5.5'
}


Describe 'Assert-WhsCIVersionAvailable.when there is a release branch that exists with patch version' {
    Initialize-Test -GivenReleaseBranches '5.4.3' 
    Assert-ThatAssertWhsCIVersionAvailable -RejectsVersion '5.4' -ErrorAction SilentlyContinue
}

