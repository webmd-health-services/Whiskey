
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function GivenRunningUnderABuildServer
{
    param(
        [Switch]
        $WithGitBranch
    )
    mock -CommandName 'Test-WhiskeyRunByBuildServer' -ModuleName 'Whiskey' -MockWith { return $true }
    mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { return $item = @{
                                                                                    Value = 'CommitHash'
                                                                                }
                                                                }
    if( $WithGitBranch )
    {
        mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { return $true }
    }
    else
    {
        mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { return $false }
    }
}

function GivenRunningAsADeveloper
{
    mock -CommandName 'Test-WhiskeyRunByBuildServer' -ModuleName 'Whiskey' -MockWith { return $false }
}

function WhenGettingCommitID
{
    [cmdletbinding()]
    param(
        
        [Switch]
        $ThatShouldFail
    )

    $Global:Error.Clear()
    $failed = $false
    $commitID = $null
    try
    {
        $commitID = Get-WhiskeyCommitID
    }
    catch
    {
        $failed = $true
    }

    if( $ThatShouldFail )
    {
        it 'Should throw an error' {
            $failed | Should Be $true
        }
    }
    else
    {
        it 'Should not throw an error' {
            $failed | Should be $false
        }
    }
    return $commitID
}

function ThenTheCommitIDShouldBeObtained
{
    param(
        [String]
        $CommitID
    )
    it 'should return the correct commit hash' {
        $CommitID | Should match 'CommitH'
    }

    it 'should not write any errors' {
        $Global:Error | Should beNullOrEmpty
    }
    it 'should call Get-Item to get the commitID' {
        Assert-MockCalled -CommandName 'Get-Item' -ModuleName 'Whiskey' -Times 1
    }


}

function ThenTheCommitIDShouldNotBeObtained
{
    param(
        [String]
        $CommitID,

        [String]
        $Error
    )
    it 'should not return a commit hash' {
        $CommitID | Should beNullOrEmpty
    }

    it 'should write errors' {
        $Global:Error | Should match $Error
    }

}

Describe 'Get-WhiskeyCommitID. when running under a build server.' {
    GivenRunningUnderABuildServer -WithGitBranch
    $commitID = WhenGettingCommitID
    ThenTheCommitIDShouldBeObtained -CommitID $commitID
}

Describe 'Get-WhiskeyCommitID. when the environment variable GIT_BRANCH is unavailable.' {
    GivenRunningUnderABuildServer
    $commitID = WhenGettingCommitID -ThatShouldFail
    ThenTheCommitIDShouldNotBeObtained -CommitID $commitID -Error 'Environment variable GIT_COMMIT does not exist'
}

