
function Invoke-WhiskeyPowerShell
{
    [Whiskey.Task('PowerShell',SupportsClean,SupportsInitialize)]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Whiskey.Context]$TaskContext,

        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String[]]$Path,

        [Object]$Argument = @()
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $workingDirectory = (Get-Location).ProviderPath

    foreach( $scriptPath in $path )
    {

        $scriptCommand = Get-Command -Name $scriptPath -ErrorAction Ignore
        if( -not $scriptCommand )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Can''t run PowerShell script "{0}": it has a syntax error.' -f $scriptPath)
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

            Invoke-Command -ScriptBlock {
                                            $VerbosePreference = 'SilentlyContinue';
                                            & (Join-Path -Path $whiskeyScriptRoot -ChildPath 'Import-Whiskey.ps1' -Resolve -ErrorAction Stop)
                                        }
            [Whiskey.Context]$context = $serializedContext | ConvertTo-WhiskeyContext

            Set-Location $workingDirectory

            $message = Resolve-Path -Path $scriptPath -Relative
            if( $message.Contains(' ') )
            {
                $message = '& "{0}"' -f $message
            }

            $contextArgument = @{ }
            if( $passTaskContext )
            {
                $contextArgument['TaskContext'] = $context
                $message = '{0} -TaskContext $context' -f $message
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
                $message = '{0} {1}' -f $message,($argumentDesc -join ' ')
            }

            Write-WhiskeyInfo -Context $context -Message $message

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
            $job | Receive-Job
        }
        while( -not ($job | Wait-Job -Timeout 1) )

        $job | Receive-Job

        if( (Test-Path -Path $resultPath -PathType Leaf) )
        {
            $runResult = Get-Content -Path $resultPath -Raw | ConvertFrom-Json
        }
        else
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('PowerShell script "{0}" threw a terminating exception.' -F $scriptPath)
            return
        }

        if( $runResult.ExitCode -ne 0 )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('PowerShell script "{0}" failed, exited with code {1}.' -F $scriptPath,$runResult.ExitCode)
            return
        }
        elseif( -not $runResult.Successful )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('PowerShell script "{0}" threw a terminating exception.' -F $scriptPath)
            return
        }

    }
}
