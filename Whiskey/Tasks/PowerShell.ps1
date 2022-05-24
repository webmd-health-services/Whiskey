
function Invoke-WhiskeyPowerShell
{
    [Whiskey.Task('PowerShell',SupportsClean,SupportsInitialize)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Whiskey.Tasks.ValidatePath(PathType='File')]
        [String[]]$Path,

        [String]$ScriptBlock,

        [Object]$Argument = @()
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $scriptBlockGiven = $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('ScriptBlock')

    if( -not $Path -and -not $scriptBlockGiven )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Missing required property. Task must use one of "Path" or "ScriptBlock".'
        return
    }
    elseif( $Path -and $scriptBlockGiven )
    {
        Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Task uses both "Path" and "ScriptBlocK" properties. Only one of these properties is allowed.'
        return
    }

    if( $scriptBlockGiven )
    {
        $Path = Join-Path -Path $TaskContext.Temp.FullName -ChildPath 'scriptblock.ps1'
        Set-Content -Path $Path -Value $ScriptBlock -Force
    }

    $workingDirectory = (Get-Location).ProviderPath

    foreach( $scriptPath in $Path )
    {
        $mediumAndPath = "script `"$($scriptPath)`""
        if( $scriptBlockGiven )
        {
            $mediumAndPath = 'script block'
        }

        $scriptCommand = Get-Command -Name $scriptPath -ErrorAction Ignore
        if( -not $scriptCommand )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message "Can't run PowerShell $($mediumAndPath): it has a syntax error."
            continue
        }

        $passTaskContext = $scriptCommand.Parameters.ContainsKey('TaskContext')

        if( (Get-Member -InputObject $argument -Name 'Keys') )
        {
            $scriptCommand.Parameters.Values |
                Where-Object { $_.ParameterType -eq [switch] } |
                Where-Object { $argument.ContainsKey($_.Name) } |
                ForEach-Object { $argument[$_.Name] = $argument[$_.Name] | ConvertFrom-WhiskeyYamlScalar }
        }

        $resultPath = Join-Path -Path $TaskContext.OutputDirectory -ChildPath ('PowerShell-{0}-RunResult-{1}' -f ($scriptPath | Split-Path -Leaf),([IO.Path]::GetRandomFileName()))
        $serializableContext = $TaskContext | ConvertFrom-WhiskeyContext
        $job = Start-Job -ScriptBlock {

            Set-StrictMode -Version 'Latest'

            $VerbosePreference = $using:VerbosePreference
            $DebugPreference = $using:DebugPreference
            $ProgressPreference = $using:ProgressPreference
            $WarningPreference = $using:WarningPreference
            $ErrorActionPreference = $using:ErrorActionPreference
            $InformationPreference = $using:InformationPreference

            $workingDirectory = $using:WorkingDirectory
            $scriptPath = $using:ScriptPath
            $argument = $using:argument
            $serializedContext = $using:serializableContext
            $whiskeyScriptRoot = $using:whiskeyScriptRoot
            $resultPath = $using:resultPath
            $passTaskContext = $using:passTaskContext
            $scriptBlockGiven = $using:scriptBlockGiven

            Invoke-Command -ScriptBlock {
                                            $VerbosePreference = 'SilentlyContinue';
                                            & (Join-Path -Path $whiskeyScriptRoot -ChildPath 'Import-Whiskey.ps1' -Resolve -ErrorAction Stop)
                                        }
            [Whiskey.Context]$context = $serializedContext | ConvertTo-WhiskeyContext

            Set-Location $workingDirectory

            $scriptPath = Resolve-Path -Path $scriptPath -Relative

            if( $scriptBlockGiven )
            {
                $message = ''
                $lines = Get-Content -Path $scriptPath
                if( ($lines | Measure-Object).Count -le 1 )
                {
                    Write-WhiskeyInfo -Context $context -Message ($lines | Select-Object -First 1)
                }
                else
                {
                    & {
                        '' | Write-Output
                        $lines | Write-Output
                        '' | Write-Output
                    } | Write-WhiskeyInfo -NoTiming
                }
            }
            else
            {
                $message = $scriptPath
                if( $message.Contains(' ') )
                {
                    $message = '& "{0}"' -f $message
                }
            }

            $contextArgument = @{ }
            if( $passTaskContext )
            {
                $contextArgument['TaskContext'] = $context
                if( $message )
                {
                    $message = '{0} -TaskContext $context' -f $message
                }
            }

            if( $argument )
            {
                $argumentDesc =
                    & {
                        if( ($argument | Get-Member -Name 'Keys') )
                        {
                            foreach( $parameterName in $argument.Keys )
                            {
                                Write-Output ('-{0}' -f $parameterName)
                                Write-Output $argument[$parameterName]
                            }
                        }
                        else
                        {
                            Write-Output $argument
                        }
                    } |
                    ForEach-Object {
                        if( $_.ToString().Contains(' ') )
                        {
                            Write-Output ("{0}" -f $_)
                            return
                        }
                        Write-Output $_
                    }
                if( $message )
                {
                    $message = '{0} {1}' -f $message,($argumentDesc -join ' ')
                }
            }

            if( $message )
            {
                Write-WhiskeyInfo -Context $context -Message $message
            }

            $Global:LASTEXITCODE = 0

            $result = [pscustomobject]@{
                'ExitCode'   = $Global:LASTEXITCODE
                'Successful' = $false
            }
            $result | ConvertTo-Json | Set-Content -Path $resultPath

            try
            {
                Set-StrictMode -Off
                & $scriptPath @contextArgument @argument
                $result.ExitCode = $Global:LASTEXITCODE
                $result.Successful = $?
            }
            catch
            {
                $_ | Out-String | Write-WhiskeyError
            }

            Set-StrictMode -Version 'Latest'

            Write-WhiskeyVerbose -Context $context -Message ('Exit Code  {0}' -f $result.ExitCode)
            Write-WhiskeyVerbose -Context $context -Message ('$?         {0}' -f $result.Successful)
            $result | ConvertTo-Json | Set-Content -Path $resultPath
        }

        do
        {
            # There's a bug where Write-Host output gets duplicated by Receive-Job if $InformationPreference is set to "Continue".
            # Since some things use Write-Host, this is a workaround to avoid seeing duplicate host output.
            $job | Receive-Job -InformationAction SilentlyContinue
        }
        while( -not ($job | Wait-Job -Timeout 1) )

        $job | Receive-Job -InformationAction SilentlyContinue

        if( (Test-Path -Path $resultPath -PathType Leaf) )
        {
            $runResult = Get-Content -Path $resultPath -Raw | ConvertFrom-Json
        }
        else
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message "PowerShell $($mediumAndPath) threw a terminating exception."
            return
        }

        if( $runResult.ExitCode -ne 0 )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message "PowerShell $($mediumAndPath) failed, exited with code $($runResult.ExitCode)."
            return
        }
        elseif( -not $runResult.Successful )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message "PowerShell $($mediumAndPath) threw a terminating exception."
            return
        }
    }
}
