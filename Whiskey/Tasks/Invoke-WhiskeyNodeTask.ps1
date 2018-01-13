
function Invoke-WhiskeyNodeTask
{
    <#
    .SYNOPSIS
    ** OBSOLETE ** Use the `NpmInstall`, `NpmRunScript`, `NspCheck`, and `NodeLicenseChecker` tasks instead.
    
    .DESCRIPTION
    ** OBSOLETE ** Use the `NpmInstall`, `NpmRunScript`, `NspCheck`, and `NodeLicenseChecker` tasks instead.
    #>
    [Whiskey.Task('Node',SupportsClean=$true,SupportsInitialize=$true)]
    [Whiskey.RequiresTool('Node','NodePath')]
    [Whiskey.RequiresTool('NodeModule::license-checker','LicenseCheckerPath',VersionParameterName='LicenseCheckerVersion')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        # The context the task is running under.
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        # The task parameters, which are:
        #
        # * `NpmScript`: a list of one or more NPM scripts to run, e.g. `npm run $SCRIPT_NAME`. Each script is run indepently.
        # * `WorkingDirectory`: the directory where all the build commands should be run. Defaults to the directory where the build's `whiskey.yml` file was found. Must be relative to the `whiskey.yml` file.
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    Write-Warning -Message ('The ''Node'' task has been deprecated and will be removed in a future version of Whiskey. It''s functionality has been broken up into individual smaller tasks, ''NpmInstall'', ''NpmRunScript'', ''NspCheck'', and ''NodeLicenseChecker''. Update the build configuration in ''{0}'' to use the new tasks.' -f $TaskContext.ConfigurationPath)

    $startedAt = Get-Date
    function Write-Timing
    {
        param(
            $Message
        )

        $now = Get-Date
        Write-Debug -Message ('[{0}]  [{1}]  {2}' -f $now,($now - $startedAt),$Message)
    }

    if( $TaskContext.ShouldClean() )
    {
        Write-Timing -Message 'Cleaning'
        $nodeModulesPath = (Join-Path -path $TaskContext.BuildRoot -ChildPath 'node_modules')
        if( Test-Path $nodeModulesPath -PathType Container )
        {
            $outputDirectory = Join-Path -path $TaskContext.BuildRoot -ChildPath '.output' 
            $emptyDir = New-Item -Name 'TempEmptyDir' -Path $outputDirectory -ItemType 'Directory'
            Write-Timing -Message ('Emptying {0}' -f $nodeModulesPath)
            Invoke-WhiskeyRobocopy -Source $emptyDir -Destination $nodeModulesPath | Write-Debug
            Write-Timing -Message ('COMPLETE')
            Remove-Item -Path $emptyDir
            Remove-Item -Path $nodeModulesPath
        }
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
            [Parameter(Mandatory=$true)]
            [string]
            $Status,

            [int]
            $Step
        )

        Write-Progress -Activity $activity -Status $Status.TrimEnd('.') -PercentComplete ($Step/$numSteps*100)
    }

    $workingDirectory = (Get-Location).ProviderPath
    $originalPath = $env:PATH

    try
    {
        $nodePath = $TaskParameter['NodePath']
        if( -not $nodePath -or -not (Test-Path -Path $nodePath -PathType Leaf) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Whiskey didn''t install Node. Something pretty serious has gone wrong.')
        }

        $nodeRoot = $nodePath | Split-Path

        Set-Item -Path 'env:PATH' -Value ('{0};{1}' -f $nodeRoot,$env:Path)

        Update-Progress -Status ('Installing NPM packages') -Step ($stepNum++)
        Write-Timing -Message ('npm install')
        Invoke-WhiskeyNpmCommand -Name 'install' -ArgumentList '--production=false' -NodePath $nodePath -ForDeveloper:$TaskContext.ByDeveloper
        Write-Timing -Message ('COMPLETE')
        if( $LASTEXITCODE )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('npm install returned exit code {0}. Please see previous output for details.' -f $LASTEXITCODE)
        }

        Update-Progress -Status ('npm install nsp@2.7.0') -Step ($stepNum++)
        Write-Timing -Message ('npm install nsp@2.7.0')
        $nspRoot = Install-WhiskeyNodeModule -Name 'nsp' -Version '2.7.0' -NodePath $nodePath -ApplicationRoot (Get-Location).ProviderPath -ForDeveloper:$TaskContext.ByDeveloper -Global
        Write-Timing -Message ('COMPLETE')
        if( -not $nspRoot -or -not (Test-Path -Path $nspRoot -PathType Container) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Whiskey failed to install node module nsp@2.7.0. Something pretty serious has gone wrong.')
        }

        $nspPath = Join-Path -Path $nspRoot -ChildPath 'bin\nsp' -Resolve
        if( -not $nspPath -or -not (Test-Path -Path $nspPath -PathType Leaf) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Whiskey failed to install node module nsp@2.7.0. Something pretty serious has gone wrong.')
        }

        if( $TaskContext.ShouldInitialize() )
        {
            Write-Timing -Message 'Initialization complete.'
            return
        }

        if( -not $npmScripts )
        {
            Write-WhiskeyWarning -TaskContext $TaskContext -Message (@'
Property 'NpmScript' is missing or empty. Your build isn''t *doing* anything. The 'NpmScript' property should be a list of one or more npm scripts to run during your build, e.g.

BuildTasks:
- Node:
  NpmScript:
  - build
  - test           
'@)
        }

        foreach( $script in $npmScripts )
        {
            Update-Progress -Status ('npm run {0}' -f $script) -Step ($stepNum++)
            Write-Timing -Message ('Running script ''{0}''.' -f $script)
            Invoke-WhiskeyNpmCommand -Name 'run-script' -ArgumentList $script -NodePath $nodePath -ForDeveloper:$TaskContext.ByDeveloper -ErrorAction Stop
            Write-Timing -Message ('COMPLETE')
        }

        Update-Progress -Status ('nsp check') -Step ($stepNum++)
        Write-Timing -Message ('Running NSP security check.')
        $output = & $nodePath $nspPath 'check' '--output' 'json'
        Write-Timing -Message ('COMPLETE')
        $results = ($output -join [Environment]::NewLine) | ConvertFrom-Json
        if( $LASTEXITCODE )
        {
            $summary = $results | Format-List | Out-String
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('NSP, the Node Security Platform, found the following security vulnerabilities in your dependencies (exit code: {0}):{1}{2}' -f $LASTEXITCODE,[Environment]::NewLine,$summary)
        }

        Update-Progress -Status ('license-checker') -Step ($stepNum++)
        $licenseCheckerRoot = $TaskParameter['LicenseCheckerPath']
        if( -not $licenseCheckerRoot -or -not (Test-Path -Path $licenseCheckerRoot -PathType Container) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Whiskey failed to install node module license-checker. Something pretty serious has gone wrong.')
        }

        $licenseCheckerPath = Join-Path -Path $licenseCheckerRoot -ChildPath 'bin\license-checker' -Resolve
        if( -not $licenseCheckerPath -or -not (Test-Path -Path $licenseCheckerPath -PathType Leaf) )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('Node module ''{0}\bin\license-checker'' does not exist. Looks like the latest version of the license checker no longer works with Whiskey. Please migrate away from this task.' -f $licenseCheckerRoot)
        }

        Write-Timing -Message ('Generating license report.')
        $reportJson = & $nodePath $licenseCheckerPath '--json'
        Write-Timing -Message ('COMPLETE')
        $report = ($reportJson -join [Environment]::NewLine) | ConvertFrom-Json
        if( -not $report )
        {
            Stop-WhiskeyTask -TaskContext $TaskContext -Message ('License Checker failed to output a valid JSON report.')
        }

        Write-Timing -Message ('Converting license report.')
        # The default license checker report has a crazy format. It is an object with properties for each module.
        # Let's transform it to a more sane format: an array of objects.
        [object[]]$newReport = $report | 
                                    Get-Member -MemberType NoteProperty | 
                                    Select-Object -ExpandProperty 'Name' | 
                                    ForEach-Object { $report.$_ | Add-Member -MemberType NoteProperty -Name 'name' -Value $_ -PassThru }

        # show the report
        $newReport | Sort-Object -Property 'licenses','name' | Format-Table -Property 'licenses','name' -AutoSize | Out-String | Write-Verbose

        $licensePath = 'node-license-checker-report.json'
        $licensePath = Join-Path -Path $TaskContext.OutputDirectory -ChildPath $licensePath
        ConvertTo-Json -InputObject $newReport -Depth 100 | Set-Content -Path $licensePath
        Write-Timing -Message ('COMPLETE')
    }
    finally
    {
        Set-Item -Path 'env:PATH' -Value $originalPath
        Write-Progress -Activity $activity -Completed -PercentComplete 100
    }
}
