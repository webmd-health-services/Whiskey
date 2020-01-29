<#
.SYNOPSIS
Generates a report of Pester tests.

.DESCRIPTION
The `Format-PesterResult.ps1` script reads a set of Pester output XML files and converts them to a table output report. The report shows all test fixtures, from longest-running to shortest-running.

It can also show a suggested Whiskey queue structure for the tests to optimize them to run across multiple concurrent processes as quickly as possible. Pass the desired background processes to the `QueueCount` parameter or the maximum duration/runtime of each background queue to the `QueueDuration` parameter. When you do, the output will include a third `Queue` column that shows what queue that test should be in.

If you don't want the output formatted as a table for you, use the `PassThru` switch to return the objects instead.

.EXAMPLE
.\Format-PesterResult.ps1 -Path .\.output\pester*.xml

Demonstrates how to call this script when running under Whiskey.
#>
[CmdletBinding(DefaultParameterSetName='Default')]
param(
    [Parameter(Mandatory,Position=0)]
    # The list of Pester output XML files to read for test results.
    [String[]]$Path,

    [Parameter(Mandatory,ParameterSetName='QueueCount')]
    # The maximum number of queues you want to distribute your tests across. The script adds up the total time of all the tests and divides them into a number of queues equal to this paramter's value that should run in approximately an equal amount of time.
    [int]$QueueCount,

    [Parameter(Mandatory,ParameterSetName='QueueDuration')]
    # The maximum duration of each queue if you distribute your tests across queues. The script takes this duration and tries to assign tests to a number of queues so that each queue takes this much time.
    [TimeSpan]$QueueDuration,

    # Instead of showing a report, return objects for each test case.
    [switch]$PassThru
)

Set-StrictMode -Version 'Latest'

$results = 
    Get-Item -Path $Path |
    Get-Content -Raw |
    ForEach-Object { ([xml]$_).SelectNodes('/test-results/test-suite/results/test-suite') } |
    ForEach-Object { [pscustomobject]@{ name = ($_.name | Split-Path -Leaf); duration = ([TimeSpan]::FromSeconds( $_.time )) } } |
    Sort-Object -Descending -Property 'duration' 
    
$results =
    & {
        if( -not $QueueDuration -and -not $QueueCount )
        {
            Write-Output $results
            return
        }

        if( $QueueCount )
        {
            $totalDuration = [TimeSpan]::Zero
            foreach( $item in $results )
            {
                $totalDuration = $totalDuration.Add($item.duration)
            }

            Write-Verbose -Message ('Total Duration  {0}' -f $totalDuration) -Verbose

            $perQueueDuration = $totalDuration.Ticks / $QueueCount
            $QueueDuration = [TimeSpan]::FromTicks($perQueueDuration)

            Write-Verbose -Message ('Queue Duration  {0}' -f $QueueDuration) -Verbose
        }

        [TimeSpan]$currentDuration = [TimeSpan]::Zero
        $queueNum = 0
        foreach( $item in $results )
        {
            $newDuration = $currentDuration.Add($item.duration)
            if( $newDuration -gt $QueueDuration )
            {
                $currentDuration = $item.duration
                $queueNum++
            }
            else
            {
                $currentDuration = $newDuration
            }
            $item | Add-Member -MemberType NoteProperty -Name 'Queue' -Value $queueNum
            Write-Output $item
        }
    } 
    
if( $PassThru )
{
    Write-Output $results
    return
}

$results | Format-Table -Auto
