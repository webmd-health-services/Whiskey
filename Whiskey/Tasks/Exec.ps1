function Invoke-WhiskeyExec
{
    [CmdletBinding()]
    [Whiskey.Task('Exec', SupportsClean, SupportsInitialize, DefaultParameterName='Command')]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [String] $Path,

        [String[]] $Argument,

        [String] $Command,

        [String[]] $SuccessExitCode
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if ($Command)
    {
        $regExMatches = Select-String -InputObject $Command -Pattern '([^\s"'']+)|("[^"]*")|(''[^'']*'')' -AllMatches
        [String[]]$cmdTokens =
            $regExMatches.Matches.Groups |
            Where-Object 'Name' -NE '0' |
            Where-Object 'Success' -EQ $true |
            Select-Object -ExpandProperty 'Value'

        $Path = $cmdTokens | Select-Object -First 1
        if ($cmdTokens.Count -gt 1)
        {
            $Argument = $cmdTokens | Select-Object -Skip 1 | ForEach-Object { $_.Trim("'",'"') }
        }
    }

    if (-not $Path)
    {
        $msg = 'Property "Command" or "Path" is mandatory. Command should be the command to run, with arguments. ' +
               'Path should be the Path to an executable you want the Exec task to run along with arguments given ' +
               'with the Argument parameter, e.g.

    Build:
    - cmd.exe /c echo ''HELLO WORLD''
    - Exec: cmd.exe /c echo ''HELLO WORLD''
    - Exec:
        Command: cmd.exe /C echo ''HELLO WORLD''
    - Exec:
        Path: cmd.exe
        Argument: [ ''/c'', ''echo "HELLO WORLD"'' ]

    '
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    $resolvedPath = $Path
    $cmd = Get-Command -Name $resolvedPath -CommandType Application -ErrorAction Ignore
    if (-not $cmd)
    {
        $resolvedPath = ''
    }

    if (-not $resolvedPath)
    {
        $resolvedPath =
            & {
                if( [IO.Path]::IsPathRooted($Path) )
                {
                    $Path
                }
                else
                {
                    Join-Path -Path (Get-Location).Path -ChildPath $Path
                    Join-Path -Path $TaskContext.BuildRoot -ChildPath $Path
                }
            } |
            Where-Object { Test-Path -Path $_ -PathType Leaf } |
            Select-Object -First 1 |
            Resolve-Path |
            Select-Object -ExpandProperty 'ProviderPath'
    }

    if (-not $resolvedPath)
    {
        $msg = "Executable ""${Path}"" does not exist. We checked if the executable is at that path on the file " +
                'system and if it is in your PATH environment variable.'
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    if( ($resolvedPath | Measure-Object).Count -gt 1 )
    {
        $msg = "Unable to run executable ""${Path}"": it contains wildcards and resolves to the following files: " +
               """$($Path -join '","')""."
        Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
        return
    }

    Write-WhiskeyVerbose -Context $TaskContext -Message "${Path} -> ${resolvedPath}"

    Write-WhiskeyCommand -Context $TaskContext -Path $resolvedPath -ArgumentList $Argument -NoIndent

    # Don't use Start-Process. If/when a build runs in a background job, when Start-Process finishes, it immediately
    # terminates the build. Full stop.
    & $resolvedPath @Argument
    $exitCode = $LASTEXITCODE

    if (-not $SuccessExitCode)
    {
        $SuccessExitCode = '0'
    }

    foreach ($_successExitCode in $SuccessExitCode )
    {
        if ( $_successExitCode -match '^(\d+)$')
        {
            if ($exitCode -eq [int]$Matches[0])
            {
                Write-WhiskeyVerbose -Context $TaskContext -Message ('Exit Code {0} = {1}' -f $exitCode,$Matches[0])
                return
            }
        }

        if ($_successExitCode -match '^(<|<=|>=|>)\s*(\d+)$')
        {
            $operator = $Matches[1]
            $_successExitCode = [int]$Matches[2]
            switch( $operator )
            {
                '<'
                {
                    if( $exitCode -lt $_successExitCode )
                    {
                        $msg = "Exit Code ${exitCode} < ${_successExitCode}"
                        Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                        return
                    }
                }
                '<='
                {
                    if( $exitCode -le $_successExitCode )
                    {
                        $msg = "Exit Code ${exitCode} <= ${_successExitCode}"
                        Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                        return
                    }
                }
                '>'
                {
                    if( $exitCode -gt $_successExitCode )
                    {
                        $msg = "Exit Code ${exitCode} > ${_successExitCode}"
                        Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                        return
                    }
                }
                '>='
                {
                    if( $exitCode -ge $_successExitCode )
                    {
                        $msg = "Exit Code ${exitCode} >= ${_successExitCode}"
                        Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                        return
                    }
                }
            }
        }

        if ($_successExitCode -match '^(\d+)\.\.(\d+)$')
        {
            if( $exitCode -ge [int]$Matches[1] -and $exitCode -le [int]$Matches[2] )
            {
                $msg = "Exit Code $($Matches[1]) <= ${exitCode} <= $($Matches[2])"
                Write-WhiskeyVerbose -Context $TaskContext -Message $msg
                return
            }
        }
    }

    $msg = """${resolvedPath}"" returned with an exit code of ""${exitCode}"". View the build output to see why the " +
           'executable''s process failed.'
    Stop-WhiskeyTask -TaskContext $TaskContext -Message $msg
}
