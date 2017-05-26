
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function GivenACommit
{
    param(
        [Switch]
        $ThatIsInvalid
    )

    $gitBranchFilter = { $Path -eq 'env:GIT_BRANCH' }
    mock -CommandName 'Test-Path' -ModuleName 'WhsCI' -ParameterFilter $gitBranchFilter -MockWith { return $true }
    
    $gitURLFilter = { $Path -eq 'env:GIT_URL' }
    $urlValue = 'ssh://git@mock.git.url:7999/mock/url.git'
    $urlMock = { [pscustomobject]@{ Name = 'Mock Git URL'; Value = $urlValue } }.GetNewClosure()
    mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -ParameterFilter $gitURLFilter -MockWith $urlMock
    mock -CommandName 'Get-Item' -ParameterFilter $gitURLFilter -MockWith $urlMock

    mock -CommandName 'New-BBServerTag' -ModuleName 'WhsCI' -MockWith { return }

    if( -not $ThatIsInvalid )
    {
        mock -CommandName 'Get-WhsCICommitID' -ModuleName 'WhsCI' -MockWith { return "ValidCommitHash" }
    }
    else
    {
        mock -CommandName 'Get-WhsCICommitID' -ModuleName 'WhsCI' -MockWith { return $null }
    }
}

function WhenTaggingACommit
{
    param(
        [Switch]
        $ThatWillFail,

        [Switch]
        $WithoutPublishing
    )

    $context = New-WhsCITestContext -ForBuildServer 

    if ( $WithoutPublishing )
    {
        $context.Publish = $false
    }

    $global:Error.Clear()
    $failed = $false
    try
    {
        Publish-WhsCITag -TaskContext $context
    }
    catch
    {
        $failed = $true
    }
    if( $ThatWillFail )
    {
        it 'should throw an error' {
            $failed | Should be $true
        }
    }
    else
    {
        it 'should not throw an error' {
            $failed | should be $false
        }
    }
}

function ThenTheCommitShouldBeTagged
{
    it 'should tag the commit' {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'WhsCI' -Times 1
    }
    it 'should not write any errors' {
        $Global:Error | Should beNullOrEmpty
    }
}

function ThenTheCommitShouldNotBeTagged
{
    param(
        [String]
        $WithError
    )
    it 'should not tag the commit' {
        Assert-MockCalled -CommandName 'New-BBServerTag' -ModuleName 'WhsCI' -Times 0
    }
    if( $WithError )
    {
        it 'should write errors' {
            $Global:Error | Should match $WithError
        }
    }
}


Describe 'Publish-WhsCITag. when tagging a valid commit.' {
    GivenACommit 
    WhenTaggingACommit
    ThenTheCommitShouldBeTagged
}

Describe 'Publish-WhsCITag. when attempting to tag without a valid commit.' {
    GivenACommit -ThatIsInvalid
    WhenTaggingACommit -ThatWillFail
    ThenTheCommitShouldNotBeTagged -WithError 'Unable to identify a valid commit to tag'
}

Describe 'Publish-WhsCITag. when $TaskContext.Publish is false' {
    GivenACommit
    WhenTaggingACommit -WithoutPublishing
    ThenTheCommitShouldNotBeTagged 
}

