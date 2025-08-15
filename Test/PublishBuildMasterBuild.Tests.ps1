
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:version = $null
    $script:apiKey = $null
    $script:apiKeyID = $null
    $script:release = $null
    $script:mockBuild = $null

    function GivenApiKey
    {
        param(
            [String] $Key,
            [String] $WithID
        )

        $script:apiKey = $Key
        $script:apiKeyID = $WithID
    }

    function GivenRelease
    {
        param(
            [String] $Named,
            [String] $InApplication,
            [int] $WithID
        )

        $script:release =
            [pscustomobject]@{ applicationName = $InApplication; name = $Named; id = $WithID; releaseName = $Named; }
    }

    function GivenVersion
    {
        param(
            [String] $Version
        )

        $script:version = $Version
    }

    function WhenCreatingBuild
    {
        [CmdletBinding()]
        param(
            [hashtable] $WithProperties = @{}
        )

        $context = New-WhiskeyTestContext -ForVersion $script:version `
                                                 -ForTaskName 'PublishBuildMasterBuild' `
                                                 -ForBuildServer `
                                                 -ForBuildRoot $testRoot `
                                                 -IncludePSModule 'BuildMasterAutomation'

        if( -not (Get-Module 'BuildMasterAutomation') )
        {
            Import-WhiskeyTestModule -Name 'BuildMasterAutomation'
        }

        if ($script:apiKey)
        {
            Add-WhiskeyApiKey -Context $context -ID $script:apiKeyID -Value $script:apiKey
        }

        $mockRelease = $script:release

        Mock -CommandName 'Get-BMRelease' `
             -ModuleName 'Whiskey' `
             -MockWith {
                    if ($mockRelease -and `
                        $Release -eq $mockRelease.name -and `
                        $Application -eq $mockRelease.applicationName)
                    {
                        return $mockRelease
                    }
                    return $null
                }

        $script:mockBuild = [pscustomobject]@{}
        Mock -CommandName 'New-BMBuild' -ModuleName 'Whiskey' -MockWith { return $mockBuild }
        Mock -CommandName 'Publish-BMReleaseBuild' -ModuleName 'Whiskey' -MockWith { return [pscustomobject]@{} }

        $script:threwException = $false
        try
        {
            $Global:Error.Clear()
            Invoke-WhiskeyTask -TaskContext $context -Name 'PublishBuildMasterBuild' -Parameter $WithProperties
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
            [String] $Name,

            [switch] $InRelease,

            [Parameter(Mandatory)]
            [String] $AtUrl,

            [Parameter(Mandatory)]
            [String] $UsingApiKey,

            [hashtable] $WithVariables,

            [String] $ForApplication,

            [string] $AssignedToPipeline
        )

        $inWhiskey = @{ ModuleName = 'Whiskey' }
        $mockRelease = $script:release

        Should -Invoke 'New-BMBuild' @inWhiskey -ParameterFilter { $BuildNumber -eq $Name }
        if ($ForApplication)
        {
            Should -Invoke 'New-BMBuild' @inWhiskey -ParameterFilter { $Application -eq $ForApplication }
        }
        if ($InRelease)
        {
            Should -Invoke 'Get-BMRelease' @inWhiskey -ParameterFilter { $Session.Uri -eq $AtUrl }
            Should -Invoke 'Get-BMRelease' @inWhiskey -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }

            Should -Invoke 'New-BMBuild' @inWhiskey -ParameterFilter { [Object]::ReferenceEquals($Release, $mockRelease) }
            Should -Invoke 'New-BMBuild' @inWhiskey -ParameterFilter { $Session.Uri -eq $AtUrl }
        }
        if ($AssignedToPipeline)
        {
            Should -Not -Invoke 'Get-BMRelease' @inWhiskey
            Should -Invoke 'New-BMBuild' @inWhiskey -ParameterFilter { $PipelineName -eq $AssignedToPipeline }
        }
        Should -Invoke 'New-BMBuild' @inWhiskey -ParameterFilter { $Session.ApiKey -eq $UsingApiKey }
        if ($WithVariables)
        {
            foreach( $variableName in $WithVariables.Keys )
            {
                $variableValue = $WithVariables[$variableName]
                Should -Invoke 'New-BMBuild' @inWhiskey -ParameterFilter {
                    # $DebugPreference = 'Continue'
                    Write-WhiskeyDebug ('Expected  {0}' -f $variableValue)
                    Write-WhiskeyDebug ('Actual    {0}' -f $Variable[$variableName])
                    $Variable.ContainsKey($variableName) -and $Variable[$variableName] -eq $variableValue
                }
            }
        }
        else
        {
            Should -Invoke 'New-BMBuild' @inWhiskey -ParameterFilter { $null -eq $Variable -or $Variable.Count -eq 0 }
        }

        # Pester 5 doesn't set preference variables, so until https://github.com/pester/Pester/issues/2255 is fixed,
        # these need to be left commented out.
        # Should -Invoke 'Get-BMRelease' `
        #        @inWhiskey `
        #        -ParameterFilter { $ErrorActionPreference -eq 'Stop' }
        # Should -Invoke 'New-BMBuild' `
        #        @inWhiskey `
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
        $mockBuild = $script:mockBuild
        Should -Invoke 'Publish-BMReleaseBuild' @inWhiskey -ParameterFilter { [Object]::ReferenceEquals($Build, $mockBuild) }
        # Pester 5 doesn't set preference variables, so until https://github.com/pester/Pester/issues/2255 is fixed,
        # this needs to be left commented out.
        # Should -Invoke 'Publish-BMReleaseBuild' `
        #        @inWhiskey `
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
        $script:version = $null
        $script:apiKeyID = $null
        $script:apiKey = $null
        $script:testRoot = New-WhiskeyTestRoot
        $script:release = $null
        $script:mockBuild = $null
        $Global:Error.Clear()
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }

    It 'publishes build' {
        GivenApiKey 'one' -WithID '1'
        GivenRelease 'release 1' -InApplication 'application 1' -WithID 1
        GivenVersion '1.1.1-rc.1+1'
        WhenCreatingBuild -WithProperties @{
            ApplicationName = 'application 1';
            ReleaseName = 'release 1';
            ApiKeyID = '1';
            Url = 'https://1';
            Variable = @{ One = 'Two'; Three = 'Four' };
        }
        ThenCreatedBuild '1.1.1' `
                         -InRelease `
                         -AtUrl 'https://1' `
                         -UsingApiKey 'one' `
                         -WithVariables @{ One = 'Two'; Three = 'Four' }
        ThenBuildDeployed -AtUrl 'https://1' -UsingApiKey 'one'
    }

    It 'publishes build with explicit build number' {
        GivenApiKey 'two' -WithID '2'
        GivenRelease 'release 2' -InApplication 'application 2' -WithID 2
        GivenVersion '2.2.2-rc.2+2'
        WhenCreatingBuild -WithProperties @{
            ApplicationName = 'application 2';
            ReleaseName = 'release 2';
            ApiKeyID = '2';
            Url = 'https://2';
            BuildNumber = 'my build number';
        }
        ThenCreatedBuild 'my build number' `
                         -InRelease `
                         -AtUrl 'https://2' `
                         -UsingApiKey 'two'
        ThenBuildDeployed -AtUrl 'https://2' -UsingApiKey 'two'
    }

    It 'deploys to a specific stage' {
        GivenApiKey 'three' -WithID '3'
        GivenRelease 'release 3' -InApplication 'application 3' -WithID 3
        GivenVersion '3.3.3-rc.3+3'
        WhenCreatingBuild -WithProperties @{
            ApplicationName = 'application 3';
            ReleaseName = 'release 3';
            ApiKeyID = '3';
            Url = 'https://3';
            StartAtStage = 'Stage 3';
        }
        ThenCreatedBuild '3.3.3' `
                         -InRelease `
                         -AtUrl 'https://3' `
                         -UsingApiKey 'three'
        ThenBuildDeployed -AtUrl 'https://3' -UsingApiKey 'three' -AtStage 'Stage 3'
    }

    It 'should publish without starting deploy' {
        GivenApiKey 'four' -WithID '4'
        GivenRelease 'release 4' -InApplication 'application 4' -WithID 4
        GivenVersion '4.4.4-rc.4+4'
        WhenCreatingBuild -WithProperties @{
            ApplicationName = 'application 4';
            ReleaseName = 'release 4';
            ApiKeyID = '4';
            Url = 'https://4';
            SkipDeploy = 'true';
        }
        ThenCreatedBuild '4.4.4' `
                         -InRelease `
                         -AtUrl 'https://4' `
                         -UsingApiKey 'four'
        ThenBuildNotDeployed
    }

    It 'should require an application and release' {
        GivenVersion '5.5.5-rc.5+5'
        GivenApiKey 'five' -WithID '5'
        WhenCreatingBuild -WithProperties @{
            ApplicationName = 'application 5';
            ReleaseName = 'release 5';
            Url = 'https://5';
            ApiKeyID = '5';
        } -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails 'unable\ to\ create\ and\ deploy\ a\ release\ build'
    }

    It 'should require ApplicationName property' {
        GivenVersion '6.6.6-rc.6+6'
        WhenCreatingBuild -WithProperties @{} -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails ('\bApplicationName\b.*\bmandatory\b')
    }

    It 'should require ReleaseName property' {
        GivenVersion '7.7.7-rc.7+7'
        WhenCreatingBuild -WithProperties @{ ApplicationName = 'application 7'; } -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails ('\bReleaseName\b.*\bmandatory\b')
    }

    It 'requires Url property' {
        GivenVersion '8.8.8-rc.8+8'
        WhenCreatingBuild -WithProperties @{
            ApplicationName = 'application 8';
            ReleaseName = 'application 8';
        } -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails ('\bUrl\b.*\bmandatory\b')
    }

    It 'requires ApiKeyID property' {
        GivenVersion '9.9.9-rc.9+9'
        WhenCreatingBuild -WithProperties @{
            ApplicationName = 'application 9';
            ReleaseName = 'application 9';
            Url = 'https://9';
        } -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenTaskFails ('\bApiKeyID\b.*\bmandatory\b')
    }

    It 'publishes release-less builds' {
        GivenApiKey 'ten' -WithID '10'
        GivenVersion '10.10.10-rc.10+10'
        WhenCreatingBuild -WithProperties @{
            Url = 'https://10';
            ApplicationName = 'application 10';
            ApiKeyID = '10';
            PipelineName = 'pipeline 10';
        }
        ThenCreatedBuild -Name '10.10.10' `
                         -AssignedToPipeline 'pipeline 10' `
                         -ForApplication 'application 10' `
                         -UsingApiKey 'ten' `
                         -AtUrl 'https://10'
        ThenBuildDeployed -AtUrl 'https://10' -UsingApiKey 'ten'
    }

    It 'rejects both release and pipeline' {
        WhenCreatingBuild -WithProperties @{
            ApplicationName = 'application 11';
            ReleaseName = 'release 11';
            PipelineName = 'pipeline 11';
        } -ErrorAction SilentlyContinue
        ThenBuildNotCreated
        ThenBuildNotDeployed
        ThenTaskFails 'mutually exclusive'
    }
}
