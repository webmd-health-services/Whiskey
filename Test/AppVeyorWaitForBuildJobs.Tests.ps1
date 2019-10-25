
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false
$secret = $null
$secretID = $null
$whiskeyYml = $null
[Object[]]$jobs = $null
$nextID = 10000000
$currentJobID = $null
$runByAppVeyor = $null

function Get-NextID
{
    $ID = $nextID
    $script:nextID++
    return $ID
}

function GivenJob
{
    param(
        [int]$WithID,

        [Parameter(Mandatory,ParameterSetName='ForNotCurrentJob')]
        [String]$WithStatus,

        [Parameter(Mandatory,ParameterSetName='ForNotCurrentJob')]
        [int]$ThatFinishesAtCheck,

        [Parameter(Mandatory,ParameterSetName='CurrentJob')]
        [switch]$Current,

        [Parameter(Mandatory,ParameterSetName='ForNotCurrentJob')]
        [String]$WithFinalStatus,

        [Parameter(ParameterSetName='ForNotCurrentJob')]
        [switch]$ThatHasFinishedProperty
    )

    $script:jobs = & {
        if( $jobs )
        {
            Write-Output $jobs
        }

        if( $WithID )
        {
            $jobID = $WithID
        }
        else
        {
            $jobID = Get-NextID
        }

        if( $Current )
        {
            $script:currentJobID = $jobID
        }

        $job = [pscustomobject]@{ 
            'name' = ('job{0}' -f $jobID)
            'jobId' = $jobID
            'status' = $WithStatus
            'checks' = $ThatFinishesAtCheck
            'finalStatus' = $WithFinalStatus
        } 

        if( $ThatHasFinishedProperty )
        {
            $job | Add-Member -Name 'finished' -MemberType 'NoteProperty' -Value $null
        }
        Write-Output $job
    }
}

function GivenRunBy
{
    param(
        [Parameter(Mandatory,ParameterSetName='Developer')]
        [switch]$Developer,

        [Parameter(Mandatory,ParameterSetName='AppVeyor')]
        [switch]$AppVeyor
    )

    $script:runByAppVeyor = $AppVeyor
}

function GivenSecret
{
    param(
        [Parameter(Mandatory)]
        [String]$Secret,

        [Parameter(Mandatory)]
        [String]$WithID
    )

    $script:secret = $Secret
    $script:secretID = $WithID
}

function GivenWhiskeyYml
{
    param(
        $Value
    )

    $script:whiskeyYml = $Value 
}

function Init
{
    $script:failed = $false
    $script:testRoot = New-WhiskeyTestRoot
    $script:secret = $null
    $script:secretID = $null
    $script:whiskeyYml = $null
    $script:jobs = $null
    $script:currentJobID = $null
    $script:runByAppVeyor = $null
    Remove-Item -Path (Join-Path -Path $testRoot -ChildPath 'whiskey.yml') -ErrorAction Ignore
}

function ThenCheckedStatus
{
    param(
        [Parameter(Mandatory)]
        [int]$Times
    )

    # Start-Sleep should always get called one time fewer than Invoke-RestMethod
    $sleptNumTimes = $Times - 1
    if( $sleptNumTimes -lt 0 )
    {
        $sleptNumTimes = 0
    }
    Assert-MockCalled -CommandName 'Start-Sleep' -ModuleName 'Whiskey' -Times $sleptNumTimes -Exactly
    Assert-MockCalled -CommandName 'Invoke-RestMethod' -ModuleName 'Whiskey' -Times $Times -Exactly

    $secret = $script:secret
    Assert-MockCalled -CommandName 'Invoke-RestMethod' `
                      -ModuleName 'Whiskey' `
                      -ParameterFilter { 
                            $Headers['Authorization'] | 
                                Should -Be ('Bearer {0}' -f $secret) `
                                       -Because 'Invoke-RestMethod should be passed authorization header' 
                            $PSBoundParameters['Verbose'] | 
                                Should -Not -BeNullOrEmpty -Because 'should not show Invoke-RestMethod verbose output'
                            $PSBoundParameters['Verbose'] | 
                                Should -BeFalse -Because 'should not show Invoke-RestMethod verbose output'
                            $expectedUri = '^https://ci\.appveyor\.com/api/projects/.*/.*/builds/\d+$' 
                            $Uri.ToString() | 
                                Should -Match $expectedUri -Because 'should use api/projects/builds endpoint'
                            return $true
                        } `
                      -Times $Times `
                      -Exactly
}

function ThenFails
{
    $failed | Should -BeTrue
}

function ThenSucceeds
{
    $failed | Should -BeFalse
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [switch]$AndNothingReturned,
        [switch]$AndNoBuildReturned
    )

    $Global:Error.Clear()
    $context = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $testRoot -ForYaml $whiskeyYml
    if( $secretID -and $secret )
    {
        Add-WhiskeyApiKey -Context $context -ID $secretID -Value $secret
    }

    $runByAppVeyor = $script:runByAppVeyor
    Mock -CommandName 'Test-Path' `
         -ModuleName 'Whiskey' `
         -Parameter { $Path -eq 'env:APPVEYOR' } `
         -MockWith { $runByAppVeyor }.GetNewClosure()

    Mock -CommandName 'Get-Item' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $Path -eq 'env:APPVEYOR_ACCOUNT_NAME' } `
         -MockWith { [pscustomobject]@{ Value = 'Fubar-Snafu' } }

    Mock -CommandName 'Get-Item' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $Path -eq 'env:APPVEYOR_PROJECT_SLUG' } `
         -MockWith { [pscustomobject]@{ Value = 'Ewwwww' } }
    
    $buildID = Get-NextID
    Mock -CommandName 'Get-Item' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $Path -eq 'env:APPVEYOR_BUILD_ID' } `
         -MockWith { [pscustomobject]@{ Value = $buildID } }.GetNewClosure()

    $currentJobID = $script:currentJobID
    Mock -CommandName 'Get-Item' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $Path -eq 'env:APPVEYOR_JOB_ID' } `
         -MockWith { [pscustomobject]@{ Value = $currentJobID } }.GetNewClosure()

    $project = [pscustomobject]@{
        'project' = [pscustomobject]@{};
        'build' = [pscustomobject]@{
            'buildId' = $buildID;
            'buildNumber' = (Get-NextID);
            'status' = 'running';
            'jobs' = $jobs;
        }
    }

    if( $AndNothingReturned )
    {
        $project = $null
    }
    elseif( $AndNoBuildReturned )
    {
        $project.build = $null
    }

    Mock -CommandName 'Invoke-RestMethod' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { $Uri -eq ('https://ci.appveyor.com/api/projects/Fubar-Snafu/Ewwwww/builds/{0}' -f $buildID) } `
         -MockWith { 

             function Write-Timing
             {
                param(
                    $Message
                )
                #$DebugPreference = 'Continue'
                $now = (Get-Date).ToString('HH:mm:ss.ff')
                Write-Debug ('[{0,2}]  [{1}]  {2}' -f $CheckNum,$now,$Message)
             }

             Write-Timing ('Invoke-RestMethod')

             foreach( $job in $project.build.jobs )
             {
                if( $job.jobID -eq $currentJobID )
                {
                    continue
                }

                if( $CheckNum -lt $job.checks )
                {
                    Write-Timing ('[{0}]  < {1}' -f $job.name,$job.checks)
                    continue
                }

                if( -not ($job | Get-Member 'finished') )
                {
                    Write-Timing ('[{0}]  Adding "finished" property.' -f $job.name)
                    Add-Member -InputObject $job -Name 'finished' -MemberType 'NoteProperty' -Value ((Get-Date).ToString('s'))
                }

                if( $job.status -ne $job.finalStatus )
                {
                    Write-Timing ('[{0}]  Setting final status to "{1}".' -f $job.name,$job.finalStatus)
                    $job.status = $job.finalStatus
                }
            }
            return $project
        }.GetNewClosure()

    $parameter = @{}
    $task = $context.Configuration['Build'][0]
    $checkInterval = [TimeSpan]'00:00:10'
    if( $task -isnot [String] )
    {
        $parameter = $task['AppVeyorWaitForBuildJobs']
        if( $parameter.ContainsKey('CheckInterval') )
        {
            $checkInterval = [TimeSpan]$parameter['CheckInterval']
        }
    }
    
    $Global:CheckNum = $null
    Mock -CommandName 'Start-Sleep' `
         -ModuleName 'Whiskey' `
         -ParameterFilter { 
            #$DebugPreference = 'Continue'
            Write-Debug ('{0} -eq {1}' -f $Milliseconds,$checkInterval.TotalMilliseconds)
            $Milliseconds -eq $checkInterval.TotalMilliseconds } `
         -MockWith { $Global:CheckNum++ }

    $script:failed = $false
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name 'AppVeyorWaitForBuildJobs' -Parameter $parameter
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
    finally
    {
        Remove-Variable -Name 'CheckNum' -Scope 'Global'
    }
}

Describe 'AppVeyorWaitForBuildJobs.when there is only one job' {
    It 'should immediately finish' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.1
'@
        GivenJob -Current 
        WhenRunningTask
        ThenSucceeds
        ThenCheckedStatus -Times 1
    }
}

Describe 'AppVeyorWaitForBuildJobs.when there are two jobs' {
    It 'should wait for second job to finish' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.1
'@
        GivenJob -WithStatus 'running' -ThatFinishesAtCheck 2 -WithFinalStatus 'success'
        GivenJob -Current 
        WhenRunningTask
        ThenSucceeds
        ThenCheckedStatus -Times 3
    }
}

Describe 'AppVeyorWaitForBuildJobs.when there are two jobs and not customizing check interval' {
    It 'should wait for second job to finish' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
'@
        GivenJob -WithStatus 'running' -ThatFinishesAtCheck 2 -WithFinalStatus 'success'
        GivenJob -Current 
        WhenRunningTask
        ThenSucceeds
        ThenCheckedStatus -Times 3
    }
}

Describe 'AppVeyorWaitForBuildJobs.when there are three jobs and one job takes awhile' {
    It 'should wait for all jobs to finish' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.1
    ReportInterval: 00:00:00.1
'@
        GivenJob -WithStatus 'running' -ThatFinishesAtCheck 2 -WithFinalStatus 'success'
        GivenJob -Current 
        GivenJob -WithStatus 'running' -ThatFinishesAtCheck 10 -WithFinalStatus 'success'
        WhenRunningTask
        ThenSucceeds
        ThenCheckedStatus -Times 11
    }
}

Describe 'AppVeyorWaitForBuildJobs.when AppVeyor eventually always includes a finished property even when job is not finished' {
    It 'should pass' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.1
'@
        GivenJob -WithStatus 'running' -ThatFinishesAtCheck 2 -WithFinalStatus 'success' -ThatHasFinishedProperty
        GivenJob -Current 
        WhenRunningTask
        ThenSucceeds
        ThenCheckedStatus -Times 3
    }
}

Describe 'AppVeyorWaitForBuildJobs.when other job fails' {
    It 'should fail' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.01
'@
        GivenJob -WithID 4380 -WithStatus 'running' -ThatFinishesAtCheck 2 -WithFinalStatus 'failed' -ThatHasFinishedProperty
        GivenJob -Current 
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenFails
        $Global:Error | Where-Object { $_ -match '\bother job\b' } | Should -Not -BeNullOrEmpty
        $Global:Error | Where-Object { $_ -match '\ \* job4380 \(status: failed\)' } | Should -Not -BeNullOrEmpty
        ThenCheckedStatus -Times 3
    }
}

Describe 'AppVeyorWaitForBuildJobs.when other jobs fail' {
    It 'should fail' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.1
'@
        GivenJob -WithID 4380 -WithStatus 'running' -ThatFinishesAtCheck 2 -WithFinalStatus 'failed' -ThatHasFinishedProperty
        GivenJob -WithID 4381 -WithStatus 'running' -ThatFinishesAtCheck 2 -WithFinalStatus 'failed' -ThatHasFinishedProperty
        GivenJob -Current 
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenFails
        $Global:Error | Where-Object { $_ -match '\bother jobs\b' } | Should -Not -BeNullOrEmpty
        $Global:Error | Where-Object { $_ -match '\ \* job4380 \(status: failed\)' } | Should -Not -BeNullOrEmpty
        $Global:Error | Where-Object { $_ -match '\ \* job4381 \(status: failed\)' } | Should -Not -BeNullOrEmpty
        ThenCheckedStatus -Times 3
    }
}

Describe 'AppVeyorWaitForBuildJobs.when not running under AppVeyor' {
    It 'should fail' {
        Init
        GivenRunBy -Developer
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
'@
        GivenJob -Current 
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenFails
        $Global:Error | Should -Match 'Not\ running\ under\ AppVeyor'
        ThenCheckedStatus -Times 0
    }
}

Describe 'AppVeyorWaitForBuildJobs.when customizing in-progress status indicators' {
    It 'should continue checking while job has custom status' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.1
    InProgressStatus: nerfherder
'@
        GivenJob -WithStatus 'nerfherder' -ThatFinishesAtCheck 2 -WithFinalStatus 'success' -ThatHasFinishedProperty
        GivenJob -Current 
        WhenRunningTask
        ThenSucceeds
        ThenCheckedStatus -Times 3
    }
}

Describe 'AppVeyorWaitForBuildJobs.when customizing success status indicators' {
    It 'should continue checking while job has custom status' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.1
    SuccessStatus: failed
'@
        GivenJob -WithStatus 'queued' -ThatFinishesAtCheck 2 -WithFinalStatus 'failed' -ThatHasFinishedProperty
        GivenJob -Current 
        WhenRunningTask
        ThenSucceeds
        ThenCheckedStatus -Times 3
    }
}

Describe 'AppVeyorWaitForBuilds.when nothing is returned' {
    It 'should fail' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.01
'@
        WhenRunningTask -AndNothingReturned -ErrorAction SilentlyContinue
        ThenFails
        $Global:Error | Should -Match 'request returned no build information'
    }
}

Describe 'AppVeyorWaitForBuilds.when no builds are returned' {
    It 'should fail' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.01
'@
        WhenRunningTask -AndNoBuildReturned -ErrorAction SilentlyContinue
        ThenFails
        $Global:Error | Should -Match 'request returned no build information'
    }
}

Describe 'AppVeyorWaitForBuilds.when no jobs are returned' {
    It 'should fail' {
        Init
        GivenRunBy -AppVeyor
        GivenSecret 'fubarsnafu' -WithID 'AppVeyor'
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00.01
'@
        WhenRunningTask 
        ThenSucceeds
        $Global:Error | Should -BeNullOrEmpty
    }
}

Describe 'AppVeyorWaitForBuilds.when no API key given' {
    It 'should fail' {
        Init
        GivenRunBy -AppVeyor
        GivenWhiskeyYml @'
Build:
- AppVeyorWaitForBuildJobs:
    ApiKeyID: AppVeyor
    CheckInterval: 00:00:00:01
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenFails
        $Global:Error | Should -Match 'API Key ''AppVeyor'' does not exist'
    }
}
