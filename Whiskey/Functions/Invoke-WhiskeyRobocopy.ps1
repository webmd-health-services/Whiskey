
function Invoke-WhiskeyRobocopy
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String] $Source,

        [Parameter(Mandatory)]
        [String] $Destination,

        [String[]] $WhiteList,

        [String[]] $Exclude
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $numRobocopyThreads = [Environment]::ProcessorCount * 2

    $logPathFileName = "robocopy-$([IO.Path]::GetRandomFileName() -replace '\.','').log"
    $logPath = Join-Path -Path (Get-WhiskeyTempPath) -ChildPath $logPathFileName

    $excludeParam = $Exclude | ForEach-Object { '/XF' ; $_ ; '/XD' ; $_ }
    robocopy $Source `
             $Destination `
             '/PURGE' `
             '/S' `
             '/R:0' `
             "/LOG:${logPath}" `
             "/MT:${numRobocopyThreads}" `
             $WhiteList `
             $excludeParam

    try
    {
        if ($LASTEXITCODE -ge 8)
        {
            Get-Content -Path $logPath
            $msg = "The command ""robocopy.exe '${Source}' '${Destination}'"" failed with exit code ${LASTEXITCODE}."
            Write-WhiskeyError $msg
            return
        }

        # Make sure one of Robocopy's success exit codes doesn't fail the build.
        $Global:LASTEXITCODE = $LASTEXITCODE = 0
    }
    finally
    {
        if (Test-Path -Path $logPath)
        {
            Remove-Item -Path $logPath -Force
        }
    }
}
