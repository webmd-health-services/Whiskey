
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:mockBuild = [pscustomobject]@{ }
    $script:mockRelease = [pscustomobject]@{ }
    $script:buildVersion = 'version'
    $script:defaultApiKeyID = 'BuildMaster'
    $script:defaultApiKey = 'fubarsnafu'
    $script:defaultAppName = 'application'
    $script:defaultReleaseId = 483
    $script:buildVariable = @{ 'Variable' = @{ 'One' = 'Two'; 'Three' = 'Four'; } }
    $script:context = $null
    $script:version = $null
    $script:releaseName = $null
    $script:appName = $null
    $script:taskParameter = $null
    $script:releaseId = $null
    $script:apiKeyID = $null
    $script:apiKey = $null
    $script:url = $null
    $script:buildNumber = $null
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

    function GivenNoUrl
    {
        $script:url = $null
    }

    function GivenProperty
    {
        param(
            [Parameter(Mandatory,Position=0)]
            $Property
        )

        $script:taskParameter = $Property
    }

    function GivenBuildNumber
    {
        param(
            [Parameter(Mandatory,Position=0)]
            $Name
        )

        $script:buildNumber = $Name
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

    function WhenCreatingBuild
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
                                                -ForTaskName 'PublishBuildMasterBuild' `
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

        if( $url )
        {
            $taskParameter['Url'] = $url
        }

        if( $script:buildNumber )
        {
            $taskParameter['BuildNumber'] = $script:buildNumber
        }

        if( $startAtStage )
        {
            $taskParameter['StartAtStage'] = $startAtStage
        }

        if( $skipDeploy )
        {
            $taskParameter['SkipDeploy'] = $skipDeploy
        }

        $build = $script:mockBuild
        $release = [pscustomobject]@{ Application = $appName; Name = $releaseName; id = $releaseId  }

        if( $releaseId )
        {
            Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { return $release  }.GetNewClosure()
        }
        else
        {
            Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { }
        }
        Mock -CommandName 'New-BMBuild' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Release = $Release; BuildNumber = $BuildNumber; Variable = $Variable } }
        Mock -CommandName 'Publish-BMReleaseBuild' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{ Build = $build } }

        $script:threwException = $false
        try
        {
            $Global:Error.Clear()
            Invoke-WhiskeyTask -TaskContext $context -Name 'PublishBuildMasterBuild' -Parameter $taskParameter
        }
        catch
        {
            $script:threwException = $true
            Write-Error $_
        }
    }

    function ThenCreatedBuild
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
            [String]$AtUrl,

            [Parameter(Mandatory)]
            [String]$UsingApiKey,

            [Parameter(Mandatory)]
            [hashtable]$WithVariables
        )

        Should -Invoke 'New-BMBuild' -ModuleName 'Whiskey' -ParameterFilter { $BuildNumber -eq $Name }
        Should -Invoke 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $InRelease }
        Should -Invoke 'New-BMBuild' -ModuleName 'Whiskey' -ParameterFilter { $Release.id -eq $releaseId }
        Should -Invoke 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Application -eq $ForApplication }
        Should -Invoke 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUrl }
        Should -Invoke 'New-BMBuild' -ModuleName 'Whiskey' -ParameterFilter { $Session.Uri -eq $AtUrl }
        Should -Invoke 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
        Should -Invoke 'New-BMBuild' -ModuleName 'Whiskey' -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }

        foreach( $variableName in $WithVariables.Keys )
        {
            $variableValue = $WithVariables[$variableName]
            Should -Invoke 'New-BMBuild' -ModuleName 'Whiskey' -ParameterFilter {
                # $DebugPreference = 'Continue'
                Write-WhiskeyDebug ('Expected  {0}' -f $variableValue)
                Write-WhiskeyDebug ('Actual    {0}' -f $Variable[$variableName])
                $Variable.ContainsKey($variableName) -and $Variable[$variableName] -eq $variableValue
            }
        }

        # Pester 5 doesn't set preference variables, so until https://github.com/pester/Pester/issues/2255 is fixed,
        # these need to be left commented out.
        # Should -Invoke 'Get-BMRelease' `
        #        -ModuleName 'Whiskey' `
        #        -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
        # Should -Invoke 'New-BMBuild' `
        #        -ModuleName 'Whiskey' `
        #        -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
    }

    function ThenBuildDeployed
    {
        param(
            [Parameter(Mandatory)]
            [String]$AtUrl,

            [Parameter(Mandatory)]
            [String]$UsingApiKey,

            [String]$AtStage
        )

        $inWhiskey = @{ ModuleName = 'Whiskey'; }

        if( $AtStage )
        {
            Should -Invoke 'Publish-BMReleaseBuild' @inWhiskey -ParameterFilter { $Stage -eq $AtStage }
        }
        else
        {
            Should -Invoke 'Publish-BMReleaseBuild' @inWhiskey -ParameterFilter { $null -eq $Stage }
        }

        Should -Invoke 'Publish-BMReleaseBuild' @inWhiskey -ParameterFilter { $Session.Uri -eq $AtUrl }
        Should -Invoke 'Publish-BMReleaseBuild' @inWhiskey -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
        # Pester 5 doesn't set preference variables, so until https://github.com/pester/Pester/issues/2255 is fixed,
        # this needs to be left commented out.
        # Should -Invoke 'Publish-BMReleaseBuild' `
        #        -ModuleName 'Whiskey' `
        #        -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
    }

    function ThenBuildNotDeployed
    {
        param(
        )

        Should -Invoke 'Publish-BMReleaseBuild' -ModuleName 'Whiskey' -Times 0
    }

    function ThenBuildNotCreated
    {
        [CmdletBinding()]
        param(
        )

        process
        {
            Should -Invoke 'New-BMBuild' -ModuleName 'Whiskey' -Times 0

            ThenBuildNotDeployed
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

Describe 'PublishBuildMasterBuild' {
    BeforeEach {
        $script:version = '9.8.3-rc.1+build.deadbee'
        $script:appName = $defaultAppName
        $script:releaseName = 'release'
        $script:url = 'https://buildmaster.example.com'
        $script:apiKeyID = $defaultApiKeyID
        $script:apiKey = $defaultApiKey
        $script:releaseId = $defaultReleaseId
        $script:buildVariable = @{ 'Variable' = @{ 'One' = 'Two'; 'Three' = 'Four'; } }
        $script:taskParameter = @{ }
        $script:buildNumber = $null
        $script:startAtStage = $null
        $script:skipDeploy = 'false'
        $script:testRoot = New-WhiskeyTestRoot
        $Global:Error.Clear()
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }

    It 'publishes build' {
        GivenProperty $script:buildVariable
        WhenCreatingBuild
        ThenCreatedBuild '9.8.3' `
                         -InRelease 'release' `
                         -ForApplication 'application' `
                         -AtUrl 'https://buildmaster.example.com' `
                         -UsingApiKey 'fubarsnafu' `
                         -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenBuildDeployed -AtUrl 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu'
    }

    It 'publishes build with explicit build number' {
        $buildNumberOverride = 'PackageABCD'
        GivenBuildNumber $buildNumberOverride
        GivenProperty $script:buildVariable
        WhenCreatingBuild
        ThenCreatedBuild $buildNumberOverride -InRelease 'release' -ForApplication 'application' -AtUrl 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenBuildDeployed -AtUrl 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu'
    }

    It 'deploys to a specific stage' {
        $releaseStage = 'Test'
        GivenStartAtStage $releaseStage
        GivenProperty $script:buildVariable
        WhenCreatingBuild
        ThenCreatedBuild '9.8.3' -InRelease 'release' -ForApplication 'application' -AtUrl 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenBuildDeployed -AtUrl 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -AtStage $releaseStage
    }

    It 'should publish without starting deploy' {
        GivenSkipDeploy
        GivenProperty $script:buildVariable
        WhenCreatingBuild
        ThenCreatedBuild '9.8.3' -InRelease 'release' -ForApplication 'application' -AtUrl 'https://buildmaster.example.com' -UsingApiKey 'fubarsnafu' -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenBuildNotDeployed
    }

    It 'should require an application and release' {
        GivenNoRelease 'release' -ForApplication 'application'
        WhenCreatingBuild -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails 'unable\ to\ create\ and\ deploy\ a\ release\ build'
    }

    It 'should require ApplicationName property' {
        GivenNoApplicationName
        WhenCreatingBuild -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails ('\bApplicationName\b.*\bmandatory\b')
    }

    It 'should require ReleaseName property' {
        GivenNoReleaseName
        WhenCreatingBuild -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails ('\bReleaseName\b.*\bmandatory\b')
    }

    It 'requires Url property' {
        GivenNoUrl
        WhenCreatingBuild -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails ('\bUrl\b.*\bmandatory\b')
    }

    It 'should require ApiKeyID property' {
        GivenNoApiKey
        WhenCreatingBuild -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails ('\bApiKeyID\b.*\bmandatory\b')
    }
}
