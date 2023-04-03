
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:mockPackage = [pscustomobject]@{ }
    $script:mockRelease = [pscustomobject]@{ }
    $script:mockDeploy = [pscustomobject]@{ }
    $script:packageVersion = 'version'
    $script:defaultApiKeyID = 'BuildMaster'
    $script:defaultApiKey = 'fubarsnafu'
    $script:defaultAppName = 'application'
    $script:defaultReleaseId = 483
    $script:packageVariable = @{ 'PackageVariable' = @{ 'One' = 'Two'; 'Three' = 'Four'; } }
    $script:context = $null
    $script:version = $null
    $script:releaseName = $null
    $script:appName = $null
    $script:taskParameter = $null
    $script:releaseId = $null
    $script:apiKeyID = $null
    $script:apiKey = $null
    $script:uri = $null
    $script:packageName = $null
    $script:startAtStage = $null
    $script:skipDeploy = $null

    function GivenNoApiKey
    {
        param(
            $ID,
            $ApiKey
        )

        $script:apiKeyID = $null
        $script:ApiKey = $null
    }

    function GivenNoApplicationName
    {
        $script:appName = $null
    }

    function GivenNoReleaseName
    {
        $script:releaseName = $null
    }

    function GivenNoRelease
    {
        param(
            [Parameter(Mandatory,Position=0)]
            [String]$Name,
            [Parameter(Mandatory)]
            [String]$ForApplication
        )

        $script:appName = $ForApplication
        $script:releaseId = $null
    }

    function GivenNoUri
    {
        $script:uri = $null
    }

    function GivenProperty
    {
        param(
            [Parameter(Mandatory,Position=0)]
            $Property
        )

        $script:taskParameter = $Property
    }

    function GivenPackageName
    {
        param(
            [Parameter(Mandatory,Position=0)]
            $Name
        )

        $script:packageName = $Name
    }

    function GivenStartAtStage
    {
        param(
            [Parameter(Mandatory,Position=0)]
            $Stage
        )

        $script:startAtStage = $Stage
    }

    function GivenSkipDeploy
    {
        param(
        )

        $script:skipDeploy = 'true'
    }

    function WhenCreatingPackage
    {
        [CmdletBinding()]
        param(
        )

        if( -not $taskParameter )
        {
            $taskParameter = @{ }
        }

        if( $appName )
        {
            $taskParameter['ApplicationName'] = $appName
        }

        if( $releaseName )
        {
            $taskParameter['ReleaseName'] = $releaseName
        }

        $script:context = New-WhiskeyTestContext -ForVersion $version `
                                                -ForTaskName 'PublishBuildMasterPackage' `
                                                -ForBuildServer `
                                                -ForBuildRoot $testRoot `
                                                -IncludePSModule 'BuildMasterAutomation'

        if( -not (Get-Module 'BuildMasterAutomation') )
        {
            Import-WhiskeyTestModule -Name 'BuildMasterAutomation'
        }

        if( $apiKeyID )
        {
            $taskParameter['ApiKeyID'] = $apiKeyID
            Add-WhiskeyApiKey -Context $context -ID $apiKeyID -Value $apiKey
        }

        if( $uri )
        {
            $taskParameter['Uri'] = $uri
        }

        if( $packageName )
        {
            $taskParameter['PackageName'] = $packageName
        }

        if( $startAtStage )
        {
            $taskParameter['StartAtStage'] = $startAtStage
        }

        if( $skipDeploy )
        {
            $taskParameter['SkipDeploy'] = $skipDeploy
        }

        $package = $mockPackage
        $deploy = $mockDeploy
        $release = [pscustomobject]@{ Application = $appName; Name = $releaseName; id = $releaseId  }

        if( $releaseId )
        {
            Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { return $release  }.GetNewClosure()
        }
        else
        {
            Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { }
        }
        Mock -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Release = $Release; PackageNumber = $PackageNumber; Variable = $Variable } }
        Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Package = $package } }

        $script:threwException = $false
        try
        {
            $Global:Error.Clear()
            Invoke-WhiskeyTask -TaskContext $context -Name 'PublishBuildMasterPackage' -Parameter $taskParameter
        }
        catch
        {
            $script:threwException = $true
            Write-Error $_
        }
    }

    function ThenCreatedPackage
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory,Position=0)]
            [String]$Name,

            [Parameter(Mandatory)]
            [String]$InRelease,

            [Parameter(Mandatory)]
            [String]$ForApplication,

            [Parameter(Mandatory)]
            [String]$AtUri,

            [Parameter(Mandatory)]
            [String]$UsingApiKey,

            [Parameter(Mandatory)]
            [hashtable]$WithVariables
        )

        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $PackageNumber -eq $Name }
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $InRelease }
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $Release.id -eq $releaseId }
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Application -eq $ForApplication }
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUri }
        Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
        Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }

        foreach( $variableName in $WithVariables.Keys )
        {
            $variableValue = $WithVariables[$variableName]
            Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -ParameterFilter {
                #$DebugPreference = 'Continue'
                Write-WhiskeyDebug ('Expected  {0}' -f $variableValue)
                Write-WhiskeyDebug ('Actual    {0}' -f $Variable[$variableName])
                $Variable.ContainsKey($variableName) -and $Variable[$variableName] -eq $variableValue
            }
        }

        # Pester 5 doesn't set preference variables, so until https://github.com/pester/Pester/issues/2255 is fixed,
        # these need to be left commented out.
        # Assert-MockCalled -CommandName 'Get-BMRelease' `
        #                   -ModuleName 'Whiskey' `
        #                   -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
        # Assert-MockCalled -CommandName 'New-BMPackage' `
        #                   -ModuleName 'Whiskey' `
        #                   -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
    }

    function ThenPackageDeployed
    {
        param(
            [Parameter(Mandatory)]
            [String]$AtUri,

            [Parameter(Mandatory)]
            [String]$UsingApiKey,

            [String]$AtStage
        )

        $assertMockArgs = @{
            CommandName = 'Publish-BMReleasePackage';
            ModuleName = 'Whiskey';
        }

        if( $AtStage )
        {
            Assert-MockCalled @assertMockArgs -ParameterFilter { $Stage -eq $AtStage }
        }
        else
        {
            Assert-MockCalled @assertMockArgs -ParameterFilter { $Stage -eq '' }
        }

        Assert-MockCalled @assertMockArgs -ParameterFilter { $Session.Uri -eq $AtUri }
        Assert-MockCalled @assertMockArgs -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
        # Pester 5 doesn't set preference variables, so until https://github.com/pester/Pester/issues/2255 is fixed,
        # this needs to be left commented out.
        # Assert-MockCalled -CommandName 'Publish-BMReleasePackage' `
        #                   -ModuleName 'Whiskey' `
        #                   -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
    }

    function ThenPackageNotDeployed
    {
        param(
        )

        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -Times 0
    }

    function ThenPackageNotCreated
    {
        [CmdletBinding()]
        param(
        )

        process
        {
            Assert-MockCalled -CommandName 'New-BMPackage' -ModuleName 'Whiskey' -Times 0

            ThenPackageNotDeployed
        }
    }

    function ThenTaskFails
    {
        param(
            $Pattern
        )

        $threwException | Should -BeTrue
        $Global:Error | Should -Match $Pattern
    }
}

Describe 'PublishBuildMasterPackage' {
    BeforeEach {
        $script:version = '9.8.3-rc.1+build.deadbee'
        $script:appName = $defaultAppName
        $script:releaseName = 'release'
        $script:uri = 'https://buildmaster.example.com'
        $script:apiKeyID = $defaultApiKeyID
        $script:apiKey = $defaultApiKey
        $script:releaseId = $defaultReleaseId
        $script:packageVariable = @{ 'PackageVariable' = @{ 'One' = 'Two'; 'Three' = 'Four'; } }
        $script:taskParameter = @{ }
        $script:packageName = $null
        $script:startAtStage = $null
        $script:skipDeploy = 'false'
        $script:testRoot = New-WhiskeyTestRoot
        $Global:Error.Clear()
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }

    It 'should publish package' {
        GivenProperty $packageVariable
        WhenCreatingPackage
        ThenCreatedPackage '9.8.3' `
                           -InRelease 'release' `
                           -ForApplication 'application' `
                           -AtUri 'https://buildmaster.example.com' `
                           -UsingApiKey 'fubarsnafu' `
                           -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenPackageDeployed -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu'
    }

    It 'should publish named package' {
        $packageNameOverride = 'PackageABCD'
        GivenPackageName $packageNameOverride
        GivenProperty $packageVariable
        WhenCreatingPackage
        ThenCreatedPackage $packageNameOverride -InRelease 'release' -ForApplication 'application' -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenPackageDeployed -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu'
    }

    It 'should to a specific stage' {
        $releaseStage = 'Test'
        GivenStartAtStage $releaseStage
        GivenProperty $packageVariable
        WhenCreatingPackage
        ThenCreatedPackage '9.8.3' -InRelease 'release' -ForApplication 'application' -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenPackageDeployed -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -AtStage $releaseStage
    }

    It 'should publish without starting deploy' {
        GivenSkipDeploy
        GivenProperty $packageVariable
        WhenCreatingPackage
        ThenCreatedPackage '9.8.3' -InRelease 'release' -ForApplication 'application' -AtUri 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenPackageNotDeployed
    }

    It 'should require an application and release' {
        GivenNoRelease 'release' -ForApplication 'application'
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails 'unable\ to\ create\ and\ deploy\ a\ release\ package'
    }

    It 'should require ApplicationName property' {
        GivenNoApplicationName
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails ('\bApplicationName\b.*\bmandatory\b')
    }

    It 'should require ReleaseName property' {
        GivenNoReleaseName
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails ('\bReleaseName\b.*\bmandatory\b')
    }

    It 'should require Uri property' {
        GivenNoUri
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails ('\bUri\b.*\bmandatory\b')
    }

    It 'should require ApiKeyID property' {
        GivenNoApiKey
        WhenCreatingPackage -ErrorAction SilentlyContinue
        ThenPackageNotCreated
        ThenTaskFails ('\bApiKeyID\b.*\bmandatory\b')
    }
}
