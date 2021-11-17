
function Format-Stopwatch
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)]
        [Diagnostics.Stopwatch]$Stopwatch
    )

    process
    {
        $duration = $Stopwatch.Elapsed
        "{0,2}m{1:00}s" -f $duration.TotalMinutes.ToUInt32($null), $duration.Seconds
    }
}
