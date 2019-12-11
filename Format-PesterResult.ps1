[CmdletBinding(DefaultParameterSetName='Default')]
param(
    [Parameter(Mandatory,Position=0)]
    [String[]]$Path,

    [Parameter(Mandatory,ParameterSetName='QueueCount')]
    [int]$QueueCount,

    [Parameter(Mandatory,ParameterSetName='QueueDuration')]
    [TimeSpan]$QueueDuration,

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
        if( -not $QueueDuration -and -not $QueueDuration )
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

            $QueueDuration = $totalDuration.Ticks / $QueueCount
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
