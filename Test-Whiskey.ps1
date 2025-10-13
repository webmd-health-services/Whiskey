[CmdletBinding()]
param(
    [int] $RunnerCount,

    [TimeSpan] $WaitInterval,

    # For local testing/debugging, set this to show all test output, not just output from failed tests. On build
    # servers, set the WHISKEY_CI_RECEIVE_ALL_TEST_OUTPUT env var to True.
    [switch] $ReceiveAll
)

Set-StrictMode -Version 'Latest'

$script:testsFailed = $false

function Complete-Job
{
    param(
        [int] $RunnerID,
        [Object] $Job
    )

    $duration = $Job.PSEndtime - $Job.PSBeginTime
    $totalSeconds = [int]$duration.TotalSeconds
    Write-Information "Runner [${idx}] $($Job.Name) $($Job.State) in ${totalSeconds}s."
    # Test fixtures that have failing tests that don't fail the build.
    $failed = $Job.State -eq 'Failed'
    if ($failed -or $ReceiveAll)
    {
        # Receiving jobs is very expensive and makes builds take longer so only receive jobs that failed.
        $Job | Receive-Job -InformationAction SilentlyContinue
    }

    if ($failed)
    {
        $script:testsFailed = $true
    }

    $Job | Remove-Job -Force
}

if (-not $PSBoundParameters.ContainsKey('ReceiveAll'))
{
    $ReceiveAll = (Test-Path -Path 'env:WHISKEY_CI_RECEIVE_ALL_TEST_OUTPUT') -and `
                  $env:WHISKEY_CI_RECEIVE_ALL_TEST_OUTPUT -eq 'True'
}

$pester4Tests = @(
    'Add-WhiskeyApiKey.Tests.ps1',
    'AppVeyorWaitForBuildJobs.Tests.ps1',
    'Convert-WhiskeyPathDirectorySeparator.Tests.ps1',
    'ConvertFrom-WhiskeyContext.Tests.ps1',
    'CopyFile.Tests.ps1',
    'Delete.Tests.ps1',
    'Find-WhiskeyPowerShellModule.Tests.ps1',
    'Get-WhiskeyApiKey.Tests.ps1',
    'Get-WhiskeyBuildMetadata.Tests.ps1',
    'Get-WhiskeyContext.Tests.ps1',
    'Get-WhiskeyCredential.Tests.ps1',
    'Get-WhiskeyMSBuildConfiguration.Tests.ps1',
    'GetPowerShellModule.Tests.ps1',
    'GitHubRelease.Tests.ps1',
    'Import-Whiskey.ps1.Tests.ps1',
    'Import-WhiskeyPowerShellModule.Tests.ps1',
    'Import-WhiskeyYaml.Tests.ps1',
    'Install-WhiskeyDotNetSdk.Tests.ps1',
    'Invoke-WhiskeyDotNetCommand.Tests.ps1',
    'Invoke-WhiskeyPipelineTask.Tests.ps1',
    'LoadTask.Tests.ps1',
    'New-WhiskeyContext.Tests.ps1',
    'PublishPowerShellModule.Tests.ps1',
    'Resolve-WhiskeyDotnetSdkVersion.Tests.ps1',
    'Resolve-WhiskeyNodeModulePath.Tests.ps1',
    'Resolve-WhiskeyNodePath.Tests.ps1',
    'Resolve-WhiskeyRelativePath.Tests.ps1',
    'Set-WhiskeyBuildStatus.Tests.ps1',
    'Set-WhiskeyMSBuildConfiguration.Tests.ps1',
    'SetVariable.Tests.ps1',
    'SetVariableFromPowerShellDataFile.Tests.ps1',
    'SetVariableFromXml.Tests.ps1',
    'Uninstall-WhiskeyNodeModule.Tests.ps1',
    'Uninstall-WhiskeyPowerShellModule.Tests.ps1'
)

if (-not $RunnerCount -or $RunnerCount -le 0)
{
    $RunnerCount = [Environment]::ProcessorCount - 1
}

if ($RunnerCount -eq 1)
{
    $RunnerCount = 4
}

if (-not $WaitInterval)
{
    $WaitInterval = New-TimeSpan -Seconds 9
}

Write-Verbose "Running Whiskey tests with ${RunnerCount} test runners."

$testJobs = [Collections.Generic.List[Object]]::New($RunnerCount)

# Hydrate the list so that it is at capacity.
for ($idx = 0; $idx -lt $RunnerCount; ++$idx)
{
    $testJobs.Add($null)
}

$testFiles =
    Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Test') -Filter '*.Tests.ps1' |
    Sort-Object {
        # These tests take the longest so start them first.
        if ($_.Name -eq 'InstallNodeJs.Tests.ps1')
        {
            return '001'
        }
        if ($_.Name -eq 'MSBuild.Tests.ps1')
        {
            return '002'
        }
        return $_.Name
    }

foreach ($testFile in $testFiles)
{
    $testFileName = $testFile.Name

    $pesterVersion = '5'
    if ($testFile.Name -in $pester4Tests)
    {
        $pesterVersion = '4'
    }

    $runnerIdx = -1
    for ($idx = 0; $idx -lt $testJobs.Count; ++$idx)
    {
        if ($null -eq $testJobs[$idx])
        {
            $runnerIdx = $idx
            break
        }
    }

    # Maxed out on runners. Watch previous runners until one is finished.
    if ($runnerIdx -eq -1)
    {
        Write-Verbose "Unable to assign ${testFileName} because all runners are active."
        do
        {
            for ($idx = 0; $idx -lt $testJobs.Count; ++$idx)
            {
                $job = $testJobs[$idx]
                if ($job -and $job.State -eq 'Running')
                {
                    Write-Verbose "Runner [${idx}] $($job.Name) is $($job.State)."
                    continue
                }

                # Found one!
                Complete-Job -RunnerID $idx -Job $job

                $testJobs[$idx] = $null
                $runnerIdx = $idx
                break
            }

            if ($runnerIdx -ne -1)
            {
                break
            }

            # Wait a second for any of the running jobs to complete.
            $msg = "All runners active. Sleeping for $([int]$WaitInterval.TotalSeconds) seconds before checking again."
            Write-Verbose $msg
            Start-Sleep -Seconds $WaitInterval.TotalSeconds
        }
        while ($true)
    }

    Write-Verbose "Runner [${runnerIdx}] ${testFileName} is starting."
    $testJobs[$runnerIdx] = Start-Job -Name $testFileName {
        $repoRoot = $using:PSScriptRoot
        $pesterVersion = $using:pesterVersion
        $testFile = $using:testFile

        $pwshCmd = 'powershell'
        if ($PSVersionTable['PSEdition'] -eq 'Core')
        {
            $pwshCmd = 'pwsh'
        }

        # PowerShell background jobs have a 400x smaller call depth than a normal PowerShell process, which causes some
        # tests to fail. So, in the background job we actually spin up a separate PowerShell process that doesn't have
        # this constraint.
        $invokePath = Join-Path -Path $repoRoot -ChildPath 'Invoke-WhiskeyTestFile.ps1'
        & $pwshCmd -NoProfile `
                   -NonInteractive `
                   -Command "${invokePath} -Path '$($testFile.FullName)' -PesterVersion '${pesterVersion}'"
        if ($LASTEXITCODE)
        {
            Write-Error -Message "Tests $($testFile.Name) failed." -ErrorAction Stop
            exit 1
        }
    }
}

# All test files are running or have finished running, now let's wait for them to finish.

$idx = 0
foreach ($job in $testJobs)
{
    $idx += 1
    $job | Wait-Job | Out-Null
    Complete-Job -RunnerID $idx -Job $job
}

# Make sure we fail the build if any tests failed.
if ($script:testsFailed)
{
    Write-Error -Message "Tests failed." -ErrorAction Stop
    exit 1
}
