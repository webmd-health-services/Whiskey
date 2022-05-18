
function Invoke-WhiskeyNodeTask
{
    [Whiskey.Task('Node',SupportsClean,SupportsInitialize,Obsolete,ObsoleteMessage='The "Node" task is obsolete and will be removed in a future version of Whiskey. It''s functionality has been broken up into the "Npm" and "NodeLicenseChecker" tasks.')]
    [Whiskey.RequiresTool('Node',PathParameterName='NodePath')]
    [Whiskey.RequiresNodeModule('license-checker', PathParameterName='LicenseCheckerPath',
        VersionParameterName='LicenseCheckerVersion')]
    [Whiskey.RequiresNodeModule('nsp', PathParameterName='NspPath', VersionParameterName='PINNED_TO_NSP_2_7_0', 
        Version='2.7.0')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        # The context the task is running under.
        [Whiskey.Context]$TaskContext,

        [Parameter(Mandatory)]
        # The task parameters, which are:
        #
        # * `NpmScript`: a list of one or more NPM scripts to run, e.g. `npm run $SCRIPT_NAME`. Each script is run indepently.
        # * `WorkingDirectory`: the directory where all the build commands should be run. Defaults to the directory where the build's `whiskey.yml` file was found. Must be relative to the `whiskey.yml` file.
        [hashtable]$TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $TaskContext.ShouldClean )
    {
        Write-WhiskeyDebug -Context $TaskContext -Message 'Cleaning'
        $nodeModulesPath = Join-Path -Path $TaskContext.BuildRoot -ChildPath 'node_modules'
        Remove-WhiskeyFileSystemItem -Path $nodeModulesPath
        Write-WhiskeyDebug -Context $TaskContext -Message 'COMPLETE'
        return
    }

    $npmScripts = $TaskParameter['NpmScript']
    $npmScriptCount = $npmScripts | Measure-Object | Select-Object -ExpandProperty 'Count'
    $numSteps = 4 + $npmScriptCount
    $stepNum = 0

    $activity = 'Running Node Task'

    function Update-Progress
    {
        param(
            [Parameter(Mandatory)]
            [String]$Status,

            [int]$Step
        )

        Write-Progress -Activity $activity -Status $Status.TrimEnd('.') -PercentComplete ($Step/$numSteps*100)
    }

    $workingDirectory = (Get-Location).ProviderPath
    $originalPath = $env:PATH

    try
    {
	$nodePath = Resolve-WhiskeyNodePath -BuildRoot $TaskContext.BuildRoot
	
        Set-Item -Path 'env:PATH' -Value ('{0}{1}{2}' -f ($nodePath | Split-Path),[IO.Path]::PathSeparator,$env:PATH)

        Update-Progress -Status ('Installing NPM packages') -Step ($stepNum++)
        Write-WhiskeyDebug -Context $TaskContext -Message ('npm install')
        Invoke-WhiskeyNpmCommand -Name 'install' -ArgumentList '--production=false' -BuildRootPath $TaskContext.BuildRoot -ForDeveloper:$TaskContext.ByDeveloper -ErrorAction Stop
        Write-WhiskeyDebug -Context $TaskContext -Message ('COMPLETE')

        if( $TaskContext.ShouldInitialize )
        {
            Write-WhiskeyDebug -Context $TaskContext -Message 'Initialization complete.'
            return
        }

        if( -not $npmScripts )
        {
            Write-WhiskeyWarning -Context $TaskContext -Message (@'
Property 'NpmScript' is missing or empty. Your build isn''t *doing* anything. The 'NpmScript' property should be a list of one or more npm scripts to run during your build, e.g.

Build:
- Node:
  NpmScript:
  - build
  - test
'@)
        }

        foreach( $script in $npmScripts )
        {
            Update-Progress -Status ('npm run {0}' -f $script) -Step ($stepNum++)
            Write-WhiskeyDebug -Context $TaskContext -Message ('Running script ''{0}''.' -f $script)
            Invoke-WhiskeyNpmCommand -Name 'run-script' -ArgumentList $script -BuildRootPath $TaskContext.BuildRoot -ForDeveloper:$TaskContext.ByDeveloper -ErrorAction Stop
            Write-WhiskeyDebug -Context $TaskContext -Message ('COMPLETE')
        }

        $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $TaskContext.BuildRoot

        Update-Progress -Status ('nsp check') -Step ($stepNum++)
        Write-WhiskeyDebug -Context $TaskContext -Message ('Running NSP security check.')
        $nspPath = Assert-WhiskeyNodeModulePath -Path $TaskParameter['NspPath'] -CommandPath 'bin\nsp' -ErrorAction Stop
        $output = & $nodePath $nspPath 'check' '--output' 'json' 2>&1 |
                        ForEach-Object { if( $_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_ } }
        Write-WhiskeyDebug -Context $TaskContext -Message ('COMPLETE')
        $results = ($output -join [Environment]::NewLine) | ConvertFrom-Json
        if( $LASTEXITCODE )
        {
            $summary = $results | Format-List | Out-String
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NSP, the Node Security Platform, found the following security vulnerabilities in your dependencies (exit code: {0}):{1}{2}' -f $LASTEXITCODE,[Environment]::NewLine,$summary)
            return
        }

        Update-Progress -Status ('license-checker') -Step ($stepNum++)
        Write-WhiskeyDebug -Context $TaskContext -Message ('Generating license report.')

        $licenseCheckerPath = Assert-WhiskeyNodeModulePath -Path $TaskParameter['LicenseCheckerPath'] -CommandPath 'bin\license-checker' -ErrorAction Stop

        $reportJson = & $nodePath $licenseCheckerPath '--json'
        Write-WhiskeyDebug -Context $TaskContext -Message ('COMPLETE')
        $report = ($reportJson -join [Environment]::NewLine) | ConvertFrom-Json
        if( -not $report )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('License Checker failed to output a valid JSON report.')
            return
        }

        Write-WhiskeyDebug -Context $TaskContext -Message ('Converting license report.')
        # The default license checker report has a crazy format. It is an object with properties for each module.
        # Let's transform it to a more sane format: an array of objects.
        [Object[]]$newReport = 
            $report |
            Get-Member -MemberType NoteProperty |
            Select-Object -ExpandProperty 'Name' |
            ForEach-Object { $report.$_ | Add-Member -MemberType NoteProperty -Name 'name' -Value $_ -PassThru }

        # show the report
        $newReport | Sort-Object -Property 'licenses','name' | Format-Table -Property 'licenses','name' -AutoSize | Out-String | Write-WhiskeyVerbose -Context $TaskContext

        $licensePath = 'node-license-checker-report.json'
        $licensePath = Join-Path -Path $TaskContext.OutputDirectory -ChildPath $licensePath
        ConvertTo-Json -InputObject $newReport -Depth 100 | Set-Content -Path $licensePath
        Write-WhiskeyDebug -Context $TaskContext -Message ('COMPLETE')
    }
    finally
    {
        Set-Item -Path 'env:PATH' -Value $originalPath
        Write-Progress -Activity $activity -Completed -PercentComplete 100
    }
}
