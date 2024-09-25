
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:testRoot = $null
    $script:argument = $null
    $script:failed = $false
    $script:path = $null
    $script:successExitCode = $null
    $script:workingDirectory = $null
    $script:defaultProperty = $null
    $script:context = $null

    function Get-BuildRoot
    {
        $buildRoot = (Join-Path -Path $script:testRoot -ChildPath 'BuildRoot')
        New-Item -Path $buildRoot -ItemType 'Directory' -Force | Out-Null

        return $buildRoot
    }

    function GivenArgument
    {
        param(
            $Argument
        )

        $script:argument = $Argument
    }

    function GivenADirectory
    {
        param(
            $DirectoryPath
        )

        New-Item -Path (Join-Path -Path (Get-BuildRoot) -ChildPath $DirectoryPath) -ItemType 'Directory' -Force | Out-Null
    }

    function GivenPowerShellFile
    {
        param(
            $Path,
            $ExitCode
        )

        $parentPath = $Path | Split-Path
        if ($parentPath)
        {
            GivenADirectory $parentPath
        }

        $Content = @"
#`$DebugPreference = 'Continue'
Write-WhiskeyDebug `$PWD.Path
Write-WhiskeyDebug ([IO.Directory]::GetCurrentDirectory())
'ItRan' | Set-Content 'ItRan.txt'
`$args | Set-Content 'Arguments.txt'
`$PWD.Path | Set-Content 'WorkingDirectory.txt'
exit $ExitCode
"@

        Set-Content -Path (Join-Path -Path (Get-BuildRoot) -ChildPath $Path) -Value $Content
    }

    function GivenPath
    {
        param(
            $Path
        )

        $script:path = $Path
    }

    function GivenWorkingDirectory
    {
        param(
            $WorkingDirectory
        )

        $script:workingDirectory = $WorkingDirectory
    }

    function GivenSuccessExitCode
    {
        param(
            $SuccessExitCode
        )

        $script:successExitCode = $SuccessExitCode
    }

    function GivenTaskDefaultProperty
    {
        param(
            $Property
        )

        $script:defaultProperty = $Property
    }

    function WhenRunningExecTask
    {
        [CmdletBinding()]
        param(
            [switch] $InCleanMode,

            [switch] $InInitMode,

            [hashtable] $WithProperties = @{}
        )

        if( $script:path )
        {
            $WithProperties['Path'] = $script:path
        }

        if ( $script:argument )
        {
            $WithProperties['Argument'] = $script:argument
        }

        if ( $script:workingDirectory )
        {
            $WithProperties['WorkingDirectory'] = $script:workingDirectory
        }

        if ( $script:successExitCode )
        {
            $WithProperties['SuccessExitCode'] = $script:successExitCode
        }

        if ( $script:defaultProperty )
        {
            $WithProperties[''] = $script:defaultProperty
        }

        if ($InCleanMode -or $InInitMode)
        {
            $script:context = New-WhiskeyTestContext -ForDeveloper `
                                                     -ForBuildRoot $script:context.BuildRoot `
                                                     -InCleanMode:$InCleanMode `
                                                     -InInitMode:$InInitMode
        }

        try
        {
            Invoke-WhiskeyTask -TaskContext $context -Parameter $WithProperties -Name 'Exec'
        }
        catch
        {
            Write-Error -ErrorRecord $_
            $script:failed = $true
        }
    }

    function ThenExecutableRan
    {
        $taskDir = Get-BuildRoot
        if( $script:workingDirectory )
        {
            $taskDir = Join-Path -Path $taskDir -ChildPath $script:workingDirectory
        }

        $executableRanResult = Get-ChildItem -Path $taskDir -Filter 'ItRan.txt' -Recurse

        $executableRanResult | Should -Not -BeNullOrEmpty
    }

    function ThenSpecifiedArgumentsWerePassed
    {
        param(
            [String[]]$script:arguments = @()
        )

        [String[]]$script:argumentsResult = Get-ChildItem -Path (Get-BuildRoot) -Filter 'Arguments.txt' -Recurse | Get-Content
        if( -not $script:argumentsResult )
        {
            $script:argumentsResult = @()
        }

        if ( -not $script:arguments )
        {
            $script:argumentsResult | Should -BeNullOrEmpty
        }
        else
        {
            $argCount = $script:argumentsResult.Length
            $argCount | Should -Be $script:arguments.Length
            for( $idx = 0; $idx -lt $argCount; ++$idx )
            {
                $script:argumentsResult[$idx] | Should -Be $script:arguments[$idx]
            }
        }
    }

    function ThenRanInWorkingDirectory
    {
        param(
            $WorkingDirectory = $script:workingDirectory
        )

        $WorkingDirectory = Join-Path -Path (Get-BuildRoot) -ChildPath $WorkingDirectory -Resolve
        $workDirPath = Join-Path -Path $WorkingDirectory -ChildPath 'WorkingDirectory.txt'

        $workDirPath | Should -Exist
        Get-Content -Path $workDirPath | Should -Be $WorkingDirectory
    }

    function ThenTaskSuccess
    {
        $script:failed | Should -BeFalse
    }

    function ThenTaskFailedWithMessage
    {
        param(
            $Message
        )

        $script:failed | Should -BeTrue
        $Global:Error[0] | Should -Match $Message
    }
    }

Describe 'Exec' {
    BeforeEach {
        $Global:Error.Clear()
        $script:argument = $null
        $script:failed = $false
        $script:path = $null
        $script:successExitCode = $null
        $script:workingDirectory = $null
        $script:defaultProperty = $null

        $script:testRoot = New-WhiskeyTestRoot

        $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot (Get-BuildRoot)

    }

    It 'runs executable without arguments' {
        GivenPowerShellFile 'exec.ps1' '0'
        GivenPath 'exec.ps1'
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskSuccess
    }

    It 'passes arguments to command' {
        GivenPowerShellFile 'exec.ps1' '0'
        GivenPath 'exec.ps1'
        GivenArgument 'Arg1'
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed 'Arg1'
        ThenTaskSuccess
    }

    It 'should pass all the arguments to the command' {
        GivenPowerShellFile 'exec.ps1' '0'
        GivenPath 'exec.ps1'
        GivenArgument 'Arg1','Arg2'
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed 'Arg1','Arg2'
        ThenTaskSuccess
    }

    It 'should use values from default task' {
        GivenPowerShellFile 'exec.ps1' '0'
        GivenTaskDefaultProperty '.\exec.ps1 Arg1 Arg2 "Arg 3" ''Arg 4'''
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed 'Arg1', 'Arg2', 'Arg 3', 'Arg 4'
        ThenTaskSuccess
    }

    It 'should fail' {
        WhenRunningExecTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage '"Path" is mandatory.'
    }

    It 'should fail' {
        GivenPath 'nonexistent.exe'
        WhenRunningExecTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'Executable "nonexistent.exe" does not exist.'
    }

    It 'should still run command' {
        GivenPowerShellFile 'e x e c.ps1' '0'
        GivenPath 'e x e c.ps1'
        WhenRunningExecTask
        ThenExecutableRan
        ThenRanInWorkingDirectory '.'
        ThenTaskSuccess
    }

    It 'should pass' {
        GivenPowerShellFile 'exec.ps1' '123'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '123'
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskSuccess
    }

    It 'should fail build' {
        GivenPowerShellFile 'exec.ps1' '42'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '0','1','123'
        WhenRunningExecTask -ErrorAction SilentlyContinue
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
    }

    It 'should pass build if exit code within that range' {
        GivenPowerShellFile 'exec.ps1' '123'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '120..130'
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskSuccess
    }

    It 'should fail the build' {
        GivenPowerShellFile 'exec.ps1' '133'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '120..130'
        WhenRunningExecTask -ErrorAction SilentlyContinue
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
    }

    It 'uses >= for evaluating success exit codes' {
        GivenPowerShellFile 'exec.ps1' '500'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '>=500'
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskSuccess
    }

    It 'should fail' {
        GivenPowerShellFile 'exec.ps1' '85'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '>=500'
        WhenRunningExecTask -ErrorAction SilentlyContinue
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
    }

    It 'uses <= for evaluating success exit codes' {
        GivenPowerShellFile 'exec.ps1' '9'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '<= 9'
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskSuccess
    }

    It 'should fail build' {
        GivenPowerShellFile 'exec.ps1' '10'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '<= 9'
        WhenRunningExecTask -ErrorAction SilentlyContinue
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
    }

    It 'uses > for evaluating success exit codes' {
        GivenPowerShellFile 'exec.ps1' '91'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '>90'
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskSuccess
    }

    It 'should fail build' {
        GivenPowerShellFile 'exec.ps1' '90'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '>90'
        WhenRunningExecTask -ErrorAction SilentlyContinue
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
    }

    It 'uses < for success exit codes' {
        GivenPowerShellFile 'exec.ps1' '89'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '<90'
        WhenRunningExecTask
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskSuccess
    }

    It 'should fail build' {
        GivenPowerShellFile 'exec.ps1' '90'
        GivenPath 'exec.ps1'
        GivenSuccessExitCode '<90'
        WhenRunningExecTask -ErrorAction SilentlyContinue
        ThenExecutableRan
        ThenSpecifiedArgumentsWerePassed
        ThenTaskFailedWithMessage 'View the build output to see why the executable''s process failed.'
    }

    It 'should run command in that directory' {
        GivenADirectory 'workdir'
        GivenPowerShellFile 'workdir\exec.ps1' '0'
        GivenPath 'exec.ps1'
        GivenWorkingDirectory 'workdir'
        WhenRunningExecTask
        ThenExecutableRan
        ThenRanInWorkingDirectory
        ThenTaskSuccess
    }

    It 'should fail' {
        GivenADirectory 'workdir'
        GivenPowerShellFile 'exec.ps1' '0'
        GivenPath 'exec.ps1'
        GivenWorkingDirectory 'badworkdir'
        WhenRunningExecTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'Build.+WorkingDirectory.+does not exist.'
    }

    It 'should run command' {
        GivenPowerShellFile 'exec.ps1' '0'
        GivenPath 'exec.ps1'
        WhenRunningExecTask -InCleanMode
        ThenTaskSuccess
        ThenExecutableRan
    }

    It 'should run command' {
        GivenPowerShellFile 'exec.ps1' '0'
        GivenPath 'exec.ps1'
        WhenRunningExecTask -InInitMode
        ThenTaskSuccess
        ThenExecutableRan
    }

    It 'validates path resolves to single command' {
        GivenPowerShellFile 'exec1.ps1' '1'
        GivenPowerShellFile 'exec2.ps1' '2'
        GivenPath 'exec*.ps1'
        WhenRunningExecTask #-ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage ([regex]::Escape('contains wildcards and resolves to the following files'))
    }

    It 'allows single-line syntax' {
        GivenPowerShellFile 'exec.ps1' '0'
        GivenTaskDefaultProperty 'exec.ps1 0'
        WhenRunningExecTask
        ThenTaskSuccess
        ThenExecutableRan
    }

    # Discovered in issue where `npm intall rimraf -g` got exeuted as `npm "install rimraf -g"` because PowerShell
    # resolved the npm command to npm.ps1, which got introduced in Node.js 22.
    It 'handles when command is a PowerShell script' {
        Invoke-WhiskeyTask -TaskContext $script:context -Name 'InstallNodeJs' -Parameter @{ Version = '22' }
        $npmCmd = Get-Command -Name 'npm'
        $npmCmd | Should -Not -BeNullOrEmpty
        $npmCmd.Source | Split-Path -Leaf | Should -Be 'npm.ps1'
        WhenRunningExecTask -WithProperties @{ 'Command' = 'npm install rimraf -g' }
        JOin-Path -Path $script:context.BuildRoot -ChildPath '.node\node_modules\rimraf' | Should -Exist
    }
}
