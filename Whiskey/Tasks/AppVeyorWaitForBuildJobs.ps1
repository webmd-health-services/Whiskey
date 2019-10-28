
function Wait-WhiskeyAppVeyorBuildJob
{
    [CmdletBinding()]
    [Whiskey.Task('AppVeyorWaitForBuildJobs')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [String]$ApiKeyID,

        [TimeSpan]$CheckInterval = '00:00:10',

        [TimeSpan]$ReportInterval = '00:01:00',

        [String[]]$InProgressStatus = @('running','queued'),

        [String[]]$SuccessStatus = @('success')
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
    if( -not (Test-Path -Path 'env:APPVEYOR') )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Not running under AppVeyor.')
        return
    }

    $bearerToken = Get-WhiskeyApiKey -Context $TaskContext -ID $ApiKeyID -PropertyName 'ApiKeyID'

    $headers = @{
        'Authorization' = ('Bearer {0}' -f $bearerToken);
        'Content-Type' = 'application/json';
    }

    $accountName = (Get-Item -Path 'env:APPVEYOR_ACCOUNT_NAME').Value
    $slug = (Get-Item -Path 'env:APPVEYOR_PROJECT_SLUG').Value
    $myBuildId = (Get-Item -Path 'env:APPVEYOR_BUILD_ID').Value
    $buildUri = 'https://ci.appveyor.com/api/projects/{0}/{1}/builds/{2}' -f $accountName,$slug,$myBuildId

    $myJobId =  (Get-Item -Path 'env:APPVEYOR_JOB_ID').Value

    $nextOutput = [Diagnostics.StopWatch]::new()
    # Eventually AppVeyor will time us out.
    while( $true )
    {
        $result = Invoke-RestMethod -Uri $buildUri -Method Get -Headers $headers -Verbose:$false
        $result | ConvertTo-Json -Depth 100 | Write-Debug

        if( -not $result -or -not $result.build )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Failed to retrieve current build status from {0}: the request returned no build information:{1} {1}{2}.' -f $buildUri,[Environment]::NewLine,($result | ConvertTo-Json -Depth 100))
            return
        }

        $build = $result.build

        # Skip this job.
        $jobsToCheck = 
            $build.jobs | 
            Where-Object { $_ } |
            Where-Object { $_.jobId -ne $myJobId }

        $unfinishedJobs = 
            $jobsToCheck |
            # Jobs currently running don't have a 'finished' member. Just in case that changes in the future, also check status.
            Where-Object { -not ($_ | Get-Member 'finished') -or $_.status -in $InProgressStatus } |
            ForEach-Object {
                if( -not $nextOutput.IsRunning -or $ReportInterval -lt $nextOutput.Elapsed )
                {
                    Write-WhiskeyInfo -Context $TaskContext -Message ('"{0}" job is {1}.' -f $_.name,$_.status)
                    $nextOutput.Restart()
                }
                $_
            }
        
        if( $unfinishedJobs )
        {
            Start-Sleep -Milliseconds $CheckInterval.TotalMilliseconds
            continue
        }

        $failedJobs = $jobsToCheck | Where-Object { $_.status -notin $SuccessStatus }

        if( $failedJobs )
        {
            $suffix = ''
            if( ($failedJobs | Measure-Object).Count -gt 1 )
            {
                $suffix = 's'
            }
            $jobDescriptions = $failedJobs | ForEach-Object { '{0} (status: {1})' -f $_.name,$_.status}
            $jobDescriptions = $jobDescriptions -join ('{0} * ' -f [Environment]::NewLine)
            $errorMsg = 'This build''s other job{0} did not succeed.{1} {1} * {2} {1} ' -f $suffix, [Environment]::NewLine, $jobDescriptions
            Stop-WhiskeyTask -TaskContext $TaskContext -Message $errorMsg
            return
        }

        break
    }
}
