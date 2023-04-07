
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testDirPath = $null
    [Whiskey.Context]$script:context = $null
    $script:runByDeveloper = $false
    $script:runByBuildServer = $false
    $script:publish = $false
    $script:publishingTasks = $null
    $script:buildPipelineFails = $false
    $script:buildPipelineName = 'Build'
    $script:publishPipelineFails = $false
    $script:publishPipelineName = 'Publish'

    function GivenBuildPipelineFails
    {
        $script:buildPipelineFails = $true
    }

    function GivenBuildPipelinePasses
    {
        $script:buildPipelineFails = $false
    }

    function GivenBuildPipelineName
    {
        param(
            $Name
        )

        $script:buildPipelineName = $Name
    }

    function GivenPreviousBuildOutput
    {
        New-Item -Path (Join-Path -Path $script:testDirPath -ChildPath '.output\file.txt') -ItemType 'File' -Force
    }

    function GivenNotPublishing
    {
        $script:publish = $false
    }

    function GivenPublishing
    {
        $script:publish = $true
    }

    function GivenPublishingPipelineFails
    {
        $script:publishPipelineFails = $true
    }

    function GivenPublishPipelineName
    {
        param(
            $Name
        )

        $script:publishPipelineName = $Name
    }

    function GivenPublishingPipelineSucceeds
    {
        $script:publishPipelineFails = $false
    }

    function GivenRunByBuildServer
    {
        $script:runByDeveloper = $false
        $script:runByBuildServer = $true
    }

    function GivenRunByDeveloper
    {
        $script:runByDeveloper = $true
        $script:runByBuildServer = $false
    }

    function GivenThereAreNoPublishingTasks
    {
        $script:publishingTasks = $null
    }

    function GivenThereArePublishingTasks
    {
        $script:publishing = $true
        $script:publishingTasks = @( @{ 'TaskOne' = @{ } } )
    }

    function GivenWhiskeyYml
    {
        param(
            [Parameter(Mandatory)]
            [String]$Content
        )

        $Content | Set-Content -Path (Join-Path $script:testDirPath -ChildPath 'whiskey.yml')
    }

    function ThenBuildFailed
    {
        param(
            $WithErrorMessage
        )

        $threwException | Should -BeTrue
        if( $WithErrorMessage )
        {
            $Global:Error | Select-Object -First 1 | Should -Match $WithErrorMessage
        }
    }

    function ThenBuildOutputRemoved
    {
        Join-Path -Path ($whiskeyYmlPath | Split-Path) -ChildPath '.output' | Should -Not -Exist
    }

    function ThenContextPassedTo
    {
        param(
            $FunctionName,
            $Times = 1
        )

        $expectedContext = $script:context
        Should -Invoke $FunctionName -ModuleName 'Whiskey' -Times $Times -ParameterFilter {
            if( $TaskContext )
            {
                $Context = $TaskContext
            }

            #$DebugPreference = 'Continue'
            Write-WhiskeyDebug ('-' * 80)
            Write-WhiskeyDebug 'TaskContext:'
            $TaskContext | Out-String | Write-WhiskeyDebug
            Write-WhiskeyDebug 'Context:'
            $Context | Out-String | Write-WhiskeyDebug
            Write-WhiskeyDebug 'Expected Context:'
            $expectedContext | Out-String | Write-WhiskeyDebug
            Write-WhiskeyDebug ('-' * 80)
            [Object]::ReferenceEquals($Context,$expectedContext)
        }
    }

    function ThenPipelineRan
    {
        param(
            $Name,
            $Times = 1
        )

        if( $Times -lt 1 )
        {
            $qualifier = 'not '
        }

        $expectedPipelineName = $Name
        Should -Invoke 'Invoke-WhiskeyPipeline' `
                -ModuleName 'Whiskey' `
                -Times $Times `
                -ParameterFilter { $Name -eq $expectedPipelineName }
        if( $Times )
        {
            ThenContextPassedTo 'Invoke-WhiskeyPipeline' -Times $Times
        }
    }

    function ThenBuildPipelineRan
    {
        param(
            $Times = 1
        )

        ThenPipelineRan $script:buildPipelineName -Times $Times
    }

    function ThenBuildOutputNotRemoved
    {
        Join-Path -Path $script:testDirPath -ChildPath '.output\file.txt' | Should -Exist
    }

    function ThenBuildOutputRemoved
    {
        Join-Path -Path $script:testDirPath -ChildPath '.output' | Should -Not -Exist
    }

    function ThenBuildRunInMode
    {
        param(
            $ExpectedRunMode
        )

        $script:context.RunMode | Should -Be $ExpectedRunMode
    }

    function ThenBuildStatusSetTo
    {
        param(
            [String]$ExpectedStatus
        )

        Should -Invoke 'Set-WhiskeyBuildStatus' `
                -ModuleName 'Whiskey' `
                -Times 1 `
                -ParameterFilter { $Status -eq $ExpectedStatus }
        ThenContextPassedTo 'Set-WhiskeyBuildStatus'
    }

    function ThenBuildStatusMarkedAsCompleted
    {
        ThenBuildStatusSetTo 'Started'
        ThenBuildStatusSetTo 'Completed'
    }

    function ThenBuildStatusMarkedAsFailed
    {
        ThenBuildStatusSetTo 'Started'
        ThenBuildStatusSetTo 'Failed'
    }

    function ThenContextPassedWhenSettingBuildStatus
    {
        ThenMockCalled 'Set-WhiskeyBuildStatus' -Times 2
    }

    function ThenPublishPipelineRan
    {
        ThenPipelineRan -Name $script:publishPipelineName -Times 1
    }

    function ThenPublishPipelineNotRun
    {
        ThenPipelineRan -Name $script:publishPipelineName -Times 0
    }

    function WhenRunningBuild
    {
        [CmdletBinding()]
        param(
            [String[]]$PipelineName,

            [switch]$WithCleanSwitch,

            [switch]$WithInitializeSwitch,

            [hashtable]$WithParameter = @{}
        )

        $startedAt = Get-Date
        Start-Sleep -Milliseconds 1

        Mock -CommandName 'Set-WhiskeyBuildStatus' -ModuleName 'Whiskey'

        $whiskeyYmlPath = Join-Path -Path $script:testDirPath -ChildPath 'whiskey.yml'
        if( (Test-Path -Path $whiskeyYmlPath) )
        {
            $forParam = @{}
            if( $script:runByDeveloper )
            {
                $forParam['ForDeveloper'] = $true
            }
            else
            {
                $forParam['ForBuildServer'] = $true
            }
            $script:context = New-WhiskeyTestContext -ForBuildRoot $script:testDirPath `
                                                    -ConfigurationPath $whiskeyYmlPath `
                                                    @forParam
        }
        else
        {
            Mock -CommandName 'Invoke-WhiskeyPipeline' -ModuleName 'Whiskey' -MockWith ([scriptblock]::Create(@"
                #`$DebugPreference = 'Continue'

                `$script:buildPipelineFails = `$$($script:buildPipelineFails)
                `$script:publishPipelineFails = `$$($script:publishPipelineFails)

                Write-WhiskeyDebug ('Name  {0}' -f `$Name)
                Write-WhiskeyDebug `$script:buildPipelineFails
                Write-WhiskeyDebug `$script:publishPipelineFails

                if( `$Name -eq "$script:buildPipelineName" -and `$script:buildPipelineFails )
                {
                    throw ('Build pipeline fails!')
                }

                if( `$Name -eq "$script:publishPipelineName" -and `$script:publishPipelineFails )
                {
                    throw ('Publish pipeline fails!')
                }
"@))
            $config = @{
                $script:buildPipelineName = @();
            }

            if( $script:publishingTasks )
            {
                $config[$script:publishPipelineName] = $script:publishingTasks
            }

            $script:context = Invoke-WhiskeyPrivateCommand -Name 'New-WhiskeyContextObject'
            $script:context.BuildRoot = $script:testDirPath
            $script:context.Configuration = $config
            $script:context.OutputDirectory = (Join-Path -Path $script:testDirPath -ChildPath '.output');
            if( $script:runByDeveloper )
            {
                $script:context.RunBy = [Whiskey.RunBy]::Developer
            }
            if( $script:runByBuildServer )
            {
                $script:context.RunBy = [Whiskey.RunBy]::BuildServer
            }
            $script:context.Publish = $script:publish;
            $script:context.RunMode = [Whiskey.RunMode]::Build
        }

        $Global:Error.Clear()
        $script:threwException = $false
        try
        {
            $optionalParams = @{}
            if( $WithCleanSwitch )
            {
                $optionalParams['Clean'] = $true
            }
            elseif( $WithInitializeSwitch )
            {
                $optionalParams['Initialize'] = $true
            }

            if( $PipelineName )
            {
                $optionalParams['PipelineName'] = $PipelineName
            }
            $script:context.StartBuild()
            $modulePath = $env:PSModulePath
            Invoke-WhiskeyBuild -Context $script:context @optionalParams @WithParameter
            $script:context.StartedAt | Should -BeGreaterThan $startedAt
            $env:PSModulePath | Should -Be $modulePath
        }
        catch
        {
            $script:threwException = $true
            Write-Error $_
        }
    }

    function WhenRunningBuildFromBuildPs1
    {
        [CmdletBinding()]
        param(
        )

        $script:threwException = $false
        $buildPs1Path = Join-Path $script:testDirPath -ChildPath 'build.ps1'
        @"
            Set-Location -Path "$($script:testDirPath)"
            Import-Module -Name "$(Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey' -Resolve)"
            Import-Module -Name "$(Join-Path -Path $PSScriptRoot -ChildPath 'WhiskeyTestTasks.psm1' -Resolve)"
            `$script:context = New-WhiskeyContext -Environment Verification -ConfigurationPath '.\whiskey.yml'
            Invoke-WhiskeyBuild -Context `$script:context
            New-Item -Path 'passed'
"@ | Set-Content -Path $buildPs1Path

        # PowerShell's error handling is very different between starting a build from a build.ps1 script vs. a Pester test
        # calling Invoke-WhiskeyBuild.
        Start-Job -ScriptBlock {
            & $using:buildPs1Path
        } | Receive-Job -Wait -AutoRemoveJob

        if( -not (Test-Path -Path (Join-Path -Path $script:testDirPath -ChildPath 'passed') ) )
        {
            $script:threwException = $true
        }
    }
        }

Describe 'Invoke-WhiskeyBuild' {
    BeforeEach {
        $Global:Error.Clear()

        [Whiskey.Context]$script:context = $null
        $script:runByDeveloper = $false
        $script:runByBuildServer = $false
        $script:publish = $false
        $script:publishingTasks = $null
        $script:buildPipelineFails = $false
        $script:buildPipelineName = 'Build'
        $script:publishPipelineFails = $false
        $script:publishPipelineName = 'Publish'
        $script:testDirPath = New-WhiskeyTestRoot
    }

    It 'runs a build as a developer' {
        GivenRunByDeveloper
        GivenBuildPipelinePasses
        GivenThereArePublishingTasks
        GivenPublishing
        GivenPublishingPipelineSucceeds
        WhenRunningBuild
        ThenBuildPipelineRan
        ThenPublishPipelineRan
        ThenBuildStatusMarkedAsCompleted
    }

    It 'runs a build as a build server' {
        GivenRunByBuildServer
        GivenBuildPipelinePasses
        GivenPublishing
        GivenThereArePublishingTasks
        WhenRunningBuild
        ThenBuildPipelineRan
        ThenPublishPipelineRan
        ThenBuildStatusMarkedAsCompleted
    }

    It 'fails a build as a developer' {
        GivenRunByDeveloper
        GivenBuildPipelineFails
        GivenPublishingPipelineSucceeds
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRan
        ThenPublishPipelineNotRun
        ThenBuildStatusMarkedAsFailed
    }

    It 'fails a build as a build server' {
        GivenRunByBuildServer
        GivenBuildPipelineFails
        GivenPublishingPipelineSucceeds
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRan
        ThenPublishPipelineNotRun
        ThenBuildStatusMarkedAsFailed
    }

    It 'fails publishing as a developer' {
        GivenRunByDeveloper
        GivenPublishing
        GivenBuildPipelinePasses
        GivenThereArePublishingTasks
        GivenPublishingPipelineFails
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRan
        ThenPublishPipelineRan
        ThenBuildStatusMarkedAsFailed
    }

    It 'fails publishing as a build server' {
        GivenRunByBuildServer
        GivenPublishing
        GivenBuildPipelinePasses
        GivenThereArePublishingTasks
        GivenPublishingPipelineFails
        WhenRunningBuild -ErrorAction SilentlyContinue
        ThenBuildPipelineRan
        ThenPublishPipelineRan
        ThenBuildStatusMarkedAsFailed
    }

    It 'knows how to clean cleans' {
        GivenRunByDeveloper
        GivenBuildPipelinePasses
        GivenNotPublishing
        GivenPreviousBuildOutput
        WhenRunningBuild -WithCleanSwitch
        ThenBuildOutputRemoved
        ThenBuildRunInMode 'Clean'
    }

    It 'knows how initializes' {
        GivenRunByDeveloper
        GivenBuildPipelinePasses
        GivenNotPublishing
        GivenPreviousBuildOutput
        WhenRunningBuild -WithInitializeSwitch
        ThenBuildRunInMode 'Initialize'
    }

    It 'knows to build by default' {
        GivenRunByDeveloper
        GivenBuildPipelinePasses
        GivenNotPublishing
        GivenPreviousBuildOutput
        WhenRunningBuild
        ThenBuildOutputNotRemoved
        ThenBuildRunInMode 'Build'
    }

    It 'knows when not to publish' {
        GivenRunByBuildServer
        GivenNotPublishing
        GivenThereArePublishingTasks
        GivenPublishingPipelineSucceeds
        WhenRunningBuild
        ThenPublishPipelineNotRun
    }

    It 'allows no publishing tasks' {
        GivenRunByBuildServer
        GivenPublishing
        GivenThereAreNoPublishingTasks
        GivenPublishingPipelineSucceeds
        WhenRunningBuild
        ThenPublishPipelineNotRun
    }

    It 'can run specific pipelines' {
        GivenRunByBuildServer
        GivenPublishing
        WhenRunningBuild -PipelineName 'Fubar','snafu'
        ThenPublishPipelineNotRun
        ThenPipelineRan 'Fubar'
        ThenPipelineRan 'Snafu'
        ThenBuildPipelineRan -Times 0
    }

    It 'runs legacy BuildTasks pipeline' {
        GivenRunByBuildServer
        GivenBuildPipelineName 'BuildTasks'
        GivenPublishing
        GivenThereArePublishingTasks
        WhenRunningBuild
        ThenBuildPipelineRan
        ThenPublishPipelineRan
        ThenBuildStatusMarkedAsCompleted
    }

    It 'shows information output' {
        GivenRunByDeveloper
        GivenWhiskeyYml @'
Build:
- Log:
    Message: InformationPreference enabled!
'@
        $InformationPreference = 'Ignore'
        $infos = $null
        WhenRunningBuild -InformationVariable 'infos'
        $infos | Where-Object { $_ -match 'InformationPreference\ enabled!' } | Should -Not -BeNullOrEmpty
    }


    It 'allows silencing information output ' {
        GivenRunByDeveloper
        GivenWhiskeyYml @'
Build:
- Log:
    Message: InformationPreference enabled!
'@
        $InformationPreference = 'Continue'
        $infos = $null
        WhenRunningBuild -InformationVariable 'infos' -WithParameter @{ 'InformationAction' = 'Ignore' }
        $infos | Where-Object { $_ -match 'InformationPreference\ enabled!' } | Should -BeNullOrEmpty
    }

    It 'allows tasks to set strict mode' {
        GivenWhiskeyYml @'
Build:
- SetStrictModeViolationTask
'@
        WhenRunningBuildFromBuildPs1 -ErrorAction SilentlyContinue
        ThenBuildFailed -WithErrorMessage 'Build\ failed\.'
        $Global:Error[1] | Should -Match 'has\ not\ been\ set'
    }

    It 'fails build when task runs command that does not exist' {
        GivenWhiskeyYml @'
Build:
- CommandNotFoundTask
'@
        WhenRunningBuildFromBuildPs1 -ErrorAction SilentlyContinue
        ThenBuildFailed -WithErrorMessage 'Build\ failed\.'
        $Global:Error[1] | Should -Match 'is\ not\ recognized'
    }

    It 'fails the build when a task fails' {
        GivenWhiskeyYml @'
Build:
- FailingTask:
    Message: Some custom message to ensure it gets thrown correctly.
'@
        WhenRunningBuildFromBuildPs1 -ErrorAction SilentlyContinue
        ThenBuildFailed -WithErrorMessage 'Some\ custom\ message\ to\ ensure\ it\ gets\ thrown\ correctly\.'
        $Global:Error | Should -Not -Match 'Build\ failed\.'
    }

    It 'fails the build when task''s error action preference is stop and it writes an error' {
        GivenWhiskeyYml @'
Build:
- CmdletErrorActionStopTask:
    Path: PathThatDoesNotExist
'@
        WhenRunningBuildFromBuildPs1 -ErrorAction SilentlyContinue
        ThenBuildFailed -WithErrorMessage '\bPathThatDoesNotExist\b'
        $Global:Error | Should -Not -Match 'Build\ failed\.'
    }
}
