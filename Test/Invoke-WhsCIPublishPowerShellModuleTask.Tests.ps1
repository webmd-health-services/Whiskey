Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

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
        $WithDefaultRepo,

        [String]
        $ThatFailsWith,

        [Switch]
        $withNoProgetURI,

        [Switch]
        $WithInvalidPath,

        [Switch]
        $WithNonExistentPath,

        [Switch]
        $WithoutPathParameter
    )
    
    $Global:Error.Clear()

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
    if( $WithInvalidPath )
    {
        $TaskParameter.Add( 'Path', 'MyModule.ps1' )
        New-Item -Path $TestDrive.FullName -ItemType 'file' -Name 'MyModule.ps1'
    }
    elseif( $WithNonExistentPath )
    {
        $TaskParameter.Add( 'Path', 'MyModule.ps1' )
    }
    elseif( -not $WithoutPathParameter )
    {
        $TaskParameter.Add( 'Path', 'MyModule' )
        New-Item -Path $TestDrive.FullName -ItemType 'directory' -Name 'MyModule' 
    }
    if( -not $withNoProgetURI )
    {
        $publishLocation = New-Object 'Uri' ([uri]$TaskContext.ProgetSession.Uri), $ForFeedName
    }
    if( $withoutRegisteredRepo )
    {
        Mock -CommandName 'Get-PSRepository' -ModuleName 'WhsCI' -MockWith { return $false }
    }
    else
    {
        Mock -CommandName 'Get-PSRepository' -ModuleName 'WhsCI' -MockWith { return $true }
    }

    Add-Type -AssemblyName System.Net.Http
    Mock -CommandName 'Register-PSRepository' -ModuleName 'WhsCI' -MockWith { return }
    Mock -CommandName 'Publish-Module' -ModuleName 'WhsCI' -MockWith { return }
    $failed = $False

    try
    {
        Invoke-WhsCIPublishPowerShellModuleTask -TaskContext $TaskContext -TaskParameter $TaskParameter
    }
    catch
    {
        $failed = $True
    }
    if( $ThatFailsWith )
    {
        It 'should throw an exception' {
            $failed | Should Be $True
        }
        It 'should exit with error' {
            $Global:Error | Should Match $ThatFailsWith
        }
    }
    else
    {
        It 'should not throw an exception'{
            $failed | Should Be $False
        }
        It 'should exit without error'{
            $Global:Error | Should BeNullOrEmpty
        }
    }
}

function Assert-ModuleNotPublished
{    
    It 'should not attempt to register the module'{
        Assert-MockCalled -CommandName 'Get-PSRepository' -ModuleName 'WhsCI' -Times 0
        Assert-MockCalled -CommandName 'Register-PSRepository' -ModuleName 'WhsCI' -Times 0
    }    
    It 'should not attempt to publish the module'{
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'WhsCI' -Times 0
    }
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
        $ExpectedRepositoryName = 'thisRepo',

        [String]
        $ExpectedPathName = $TestDrive.FullName+'\MyModule',

        [switch]
        $WithDefaultRepo
    )
    
    if( $WithDefaultRepo )
    {
        $ExpectedRepositoryName = 'WhsPowerShellVerification'
    }
    
    It ('should publish the Module')  {
        $expectedApiKey = ('{0}:{1}' -f $TaskContext.ProGetSession.Credential.UserName, $TaskContext.ProGetSession.Credential.GetNetworkCredential().Password)
        Assert-MockCalled -CommandName 'Publish-Module' -ModuleName 'WhsCI' -Times 1 -ParameterFilter {
            #$DebugPreference = 'Continue'
            Write-Debug -Message ('Path Name                       expected {0}' -f $ExpectedPathName)
            Write-Debug -Message ('                                actual   {0}' -f $Path)

            Write-Debug -Message ('Repository Name                 expected {0}' -f $ExpectedRepositoryName)
            Write-Debug -Message ('                                actual   {0}' -f $Repository)

            Write-Debug -Message ('ApiKey                          expected {0}' -f $expectedApiKey)
            Write-Debug -Message ('                                actual   {0}' -f $NuGetApiKey)
            
            $Path -eq $ExpectedPathName -and
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

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. when run by developer, not publishing.' {
    $context = New-WhsCITestContext -ForDeveloper
    Invoke-Publish -TaskContext $context
    Assert-ModuleNotPublished
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
    $errorMatch = 'The property ''Uri'' cannot be found on this object. Verify that the property exists.'
    
    Invoke-Publish -withoutRegisteredRepo -withNoProgetURI -TaskContext $context -ThatFailsWith $errorMatch
    Assert-ModuleNotPublished
}

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. when Path Parameter is not included' {
    Initialize-Test
    $context = New-WhsCITestContext -ForBuildServer
    $errorMatch = 'Element ''Path'' is mandatory'

    Invoke-Publish -WithoutPathParameter -TaskContext $context -ThatFailsWith $errorMatch
    Assert-ModuleNotPublished
}

Describe 'Invoke-WhsCIPublishPowerShellModuleTask. with non-existent path parameter' {
    Initialize-Test
    $context = New-WhsCITestContext -ForBuildServer
    $errorMatch = 'does not exist'

    Invoke-Publish -WithNonExistentPath -TaskContext $context -ThatFailsWith $errorMatch
    Assert-ModuleNotPublished
}

Describe 'Invoke-WhsPublishPowerShellModuleTask. with non-directory path parameter' {
    Initialize-Test
    $context = New-WhsCITestContext -ForBuildServer
    $errorMatch = 'must point to a directory'

    Invoke-Publish -WithInvalidPath -TaskContext $context -ThatFailsWith $errorMatch
    Assert-ModuleNotPublished
}


