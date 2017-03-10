Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon\Import-Carbon.ps1' -Resolve)
& (Join-Path -Path $PSScriptRoot -ChildPath '..\Arc\WhsAutomation\Import-WhsAutomation.ps1' -Resolve)

function Initialize-Test
{
    param(
    )
    $gitBranch = 'origin/develop'
    $filter = { $Path -eq 'env:GIT_BRANCH' }
    $mock = { [pscustomobject]@{ Value = $gitBranch } }.GetNewClosure()
    Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -ParameterFilter $filter -MockWith $mock
    Mock -CommandName 'Get-Item' -ParameterFilter $filter -MockWith $mock
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return [SemVersion.SemanticVersion]'1.2.3' }
}

function Invoke-Publish
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [Switch]
        $withoutRegisteredRepo,

        [Switch]
        $withoutPublish,

        [String]
        $ForRepositoryName,

        [String]
        $ForFeedName,

        [Switch]
        $WithDefaultRepo
    )
    
    if( -not $ForRepositoryName )
    {
        $ForRepositoryName = 'thisRepo'
    }
    if ( -not $ForFeedName )
    {
        $ForFeedName = 'thisFeed'
    }
    if( $WithDefaultRepo )
    {
        $TaskParameter = @{ }
    }
    else
    {
        $TaskParameter = @{
                            RepositoryName = $ForRepositoryName;
                            FeedName = $ForFeedName;
        }
    }

    $publishLocation = New-Object 'Uri' ([uri]$TaskContext.ProgetSession.Uri), $ForFeedName
    if( $withoutRegisteredRepo )
    {
        Mock -CommandName 'Get-PSRepository' -ModuleName 'WhsCI' -MockWith { return $false }
    }
    else
    {
        Mock -CommandName 'Get-PSRepository' -ModuleName 'WhsCI' -MockWith { return $true }
    }
    
    Mock -CommandName 'Register-PSRepository' -ModuleName 'WhsCI' -MockWith { return }
    Mock -CommandName 'Publish-Module' -ModuleName 'WhsCI' -MockWith { return }

    Invoke-WhsCIPublishPowerShellModuleTask -TaskContext $TaskContext -TaskParameter $TaskParameter


}

function Assert-ModuleRegistered
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,
    
        [String]
        $ExpectedRepositoryName,

        [String]
        $ExpectedFeedName,

        [switch]
        $WithDefaultRepo
    )
    if ( $WithDefaultRepo )
    {
        $ExpectedRepositoryName = 'WhsPowerShellVerification'
        $ExpectedFeedName = 'nuget/PowerShellVerification'
    }
    else
    {
        if( -not $ExpectedRepositoryName )
        {
            $ExpectedRepositoryName = 'thisRepo'
        }
        if ( -not $ExpectedFeedName )
        {
            $ExpectedFeedName = 'thisFeed'
        }
    }
    
    $expectedPublishLocation = New-Object 'Uri' ([uri]$TaskContext.ProgetSession.Uri), $ExpectedFeedName
    It ('should register the Module')  {
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'WhsCI' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Repository Name                 expected {0}' -f $ExpectedRepositoryName)
            Write-Debug -Message ('                                actual   {0}' -f $Name)

            Write-Debug -Message ('Source Location                 expected {0}' -f $expectedPublishLocation)
            Write-Debug -Message ('                                actual   {0}' -f $SourceLocation)

            Write-Debug -Message ('Publish Location                expected {0}' -f $expectedPublishLocation)
            Write-Debug -Message ('                                actual   {0}' -f $PublishLocation)

            $Name -eq $ExpectedRepositoryName -and
            $SourceLocation -eq $expectedPublishLocation -and
            $PublishLocation -eq $expectedPublishLocation

        }
    }
    
}

function Assert-ModulePublished
{
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [String]
        $ExpectedRepositoryName,

        [switch]
        $WithDefaultRepo
    )
    
    if( $WithDefaultRepo )
    {
        $ExpectedRepositoryName = 'WhsPowerShellVerification'
    }
    elseif( -not $ExpectedRepositoryName )
    {
        $ExpectedRepositoryName = 'thisRepo'
    }
    It ('should publish the Module')  {
        $expectedApiKey = ('{0}:{1}' -f $TaskContext.ProGetSession.Credential.UserName, $TaskContext.ProGetSession.Credential.GetNetworkCredential().Password)
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'WhsCI' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Repository Name                 expected {0}' -f $ExpectedRepositoryName)
            Write-Debug -Message ('                                actual   {0}' -f $Repository)

            Write-Debug -Message ('ApiKey                          expected {0}' -f $expectedApiKey)
            Write-Debug -Message ('                                actual   {0}' -f $NuGetApiKey)

            $Repository -eq $ExpectedRepositoryName -and
            $NuGetApiKey -eq $expectedApiKey
        }
    }
}

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. when publishing new module.'{
    Initialize-Test
    $context = New-WhsCITestContext -ForBuildServer
    Invoke-Publish -WithoutRegisteredRepo -TaskContext $context
    Assert-ModuleRegistered -TaskContext $context
    Assert-ModulePublished -TaskContext $context
}

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. when publishing new module with default repository.'{
    Initialize-Test
    $context = New-WhsCITestContext -ForBuildServer
    Invoke-Publish -WithoutRegisteredRepo -WithDefaultRepo -TaskContext $context
    Assert-ModuleRegistered -TaskContext $context -WithDefaultRepo
    Assert-ModulePublished -TaskContext $context -WithDefaultRepo
}

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. when publishing previously published module.'{
    Initialize-Test
    $context = New-WhsCITestContext -ForBuildServer
    Invoke-Publish -TaskContext $context
    Assert-ModulePublished -TaskContext $context
}

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. when not run by developer, not publishing.' {
    $context = New-WhsCITestContext -ForDeveloper
    Invoke-Publish -TaskContext $context
    It 'should return without attempting to register the module'{
        Assert-MockCalled -CommandName 'Get-PSRepository' -ModuleName 'WhsCI' -Times 0
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'WhsCI' -Times 0
    }    
    It 'should not attempt to publish the module'{
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'WhsCI' -Times 0
    }
}

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. when publishing new module with custom repository name.'{
    Initialize-Test
    $context = New-WhsCITestContext -ForBuildServer
    $repository = 'fubarepo'
    Invoke-Publish -WithoutRegisteredRepo -ForRepositoryName $repository -TaskContext $context
    Assert-ModuleRegistered -TaskContext $context -ExpectedRepositoryName $repository
    Assert-ModulePublished -TaskContext $context -ExpectedRepositoryName $repository
}

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. when publishing new module with custom feed name.'{
    Initialize-Test
    $context = New-WhsCITestContext -ForBuildServer
    $feed = 'snafeed'
    Invoke-Publish -WithoutRegisteredRepo -ForFeedName $feed -TaskContext $context
    Assert-ModuleRegistered -TaskContext $context -ExpectedFeedName $feed 
    Assert-ModulePublished -TaskContext $context 
}

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. with no ProGet URI.'{
    Initialize-Test
    $context = New-WhsCITestContext -ForBuildServer
    $context.ProGetSession = 'foo'

    $Global:Error.Clear()
       
    It 'should throw an exception' {
        { Invoke-Publish -WithoutRegisteredRepo -TaskContext $context } | Should Throw
    }

    It 'should exit with error' {
        $Global:Error | Should Match ('The property ''Uri'' cannot be found on this object. Verify that the property exists.')
    }
}

