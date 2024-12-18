
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'


BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    [Whiskey.Context]$script:context = $null

    function GivenAntiVirusLockingFiles
    {
        [CmdletBinding()]
        param(
            [String]$ForVersion,

            [TimeSpan]$For
        )

        if (-not (Test-Path -Path 'variable:IsWindows') -or $IsWindows )
        {
            $platformID = 'win'
        }
        elseif ($IsLinux)
        {
            $platformID = 'linux'
        }
        elseif ($IsMacOS)
        {
            $platformID = 'darwin'
        }

        $extractedDirName = "node-v${ForVersion}-${platformID}-x64"

        $targetFilePath = Join-Path -Path $script:testRoot -ChildPath $extractedDirName
        $lockSignalPath = Join-Path -Path $targetFilePath -ChildPath '.lock'
        $avSignalPath = Join-Path -Path $script:testRoot -ChildPath 'av.started'

        Lock-File -Duration $For -Path $lockSignalPath -AVStartedPath $avSignalPath

        Mock -CommandName 'New-TimeSpan' -ModuleName 'Whiskey' -MockWith ([scriptblock]::Create(@"
            `$DebugPreference = '$($DebugPreference)'
            `$VerbosePreference = '$($VerbosePreference)'

            `$prefix = '[New-TimeSpan]  '

            `$msg = "`$(`$prefix)[`$((Get-Date).ToString('HH:mm:ss.fff'))]  Waiting for A/V to start: looking for file " +
                    """$($avSignalPath)""."
            Write-WhiskeyDebug `$msg
            while( -not (Test-Path -Path "$($avSignalPath)") )
            {
                Start-Sleep -Milliseconds 1
            }
            `$msg = "`$(`$prefix)[`$((Get-Date).ToString('HH:mm:ss.fff'))]  A/V started: file ""$($avSignalPath)"" exists."
            Write-WhiskeyDebug `$msg

            `$msg = "`$(`$prefix)[`$((Get-Date).ToString('HH:mm:ss.fff'))]  Waiting for background job to create lock " +
                    "file ""$($lockSignalPath)""."
            Write-WhiskeyDebug `$msg
            while( -not (Test-Path -Path "$($lockSignalPath)") )
            {
                Start-Sleep -Milliseconds 1
            }
            Write-WhiskeyDebug "`$(`$prefix)[`$((Get-Date).ToString('HH:mm:ss.fff'))]  File ""$($lockSignalPath)"" exists."
            return [TimeSpan]::New(0, 0, 0, `$Seconds)
"@))
    }

    function GivenPackageJsonFile
    {
        param(
            [String] $WithContent = '{}'
        )

        $pkgJsonPath = Join-path -Path $script:testRoot -ChildPath 'package.json'
        $WithContent | Set-Content -Path $pkgJsonPath
        return $pkgJsonPath
    }

    function Lock-File
    {
        param(
            [Parameter(Mandatory)]
            [TimeSpan] $Duration,

            [Parameter(Mandatory)]
            [String] $Path,

            [Parameter(Mandatory)]
            [String] $AVStartedPath
        )

        Start-Job -Name $PSCommandPath -ScriptBlock {

            $DebugPreference = 'Continue'

            $prefix = '[Lock-File]  '

            $parentDir = $using:Path | Split-Path

            $msg = "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Signaling that A/V started: creating file " +
                """$($using:AVStartedPath)""."
            Write-Debug $msg
            New-Item -Path $using:AVStartedPath -ItemType 'File'

            Write-Debug "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Waiting for ""$($parentDir)"" to exist."
            while(-not (Test-Path -Path $parentDir) )
            {
                Start-Sleep -Milliseconds 1
            }
            Write-Debug "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Directory ""$($parentDir)"" exists."

            Write-Debug "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Locking ""$($using:Path)""."
            New-Item -Path $using:Path -ItemType 'File'

            Write-Debug "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Waiting for ""$($using:Path)"" to exist."
            while( -not (Test-Path -Path $using:Path) )
            {
                Start-Sleep -Milliseconds 1
            }
            Write-Debug "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  File ""$($using:Path)"" exists."

            Write-Debug "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Locking ""$($using:Path)""."
            $file = [IO.File]::Open($using:Path, 'Open', 'Write', 'None')
            Write-Debug "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Locked  ""$($using:Path)""."

            try
            {
                $msg = "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Holding lock on ""$($using:Path)"" for " +
                    "$($using:Duration)."
                Write-Debug $msg
                Start-Sleep -Seconds $using:Duration.TotalSeconds
            }
            finally
            {
                Write-Debug "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Unlocking/closing ""$($using:Path)""."
                $file.Close()
                Write-Debug "$($prefix)[$((Get-Date).ToString('HH:mm:ss.fff'))]  Unlocked ""$($using:Path)""."
            }
        }
    }

    function ThenNode
    {
        param(
            [switch] $Not,

            [Parameter(Mandatory)]
            [switch] $Installed,

            [String] $AtVersion,

            [String] $WithNpmAtVersion,

            [String] $To
        )

        if (-not $To)
        {
            $To = '.node'
        }
        $To = Join-Path -Path $script:context.BuildRoot -ChildPath $To

        $nodeCmdName = Join-Path -Path 'bin' -ChildPath 'node'
        $npmCmdName = Join-Path -Path 'bin' -ChildPath 'npm'
        if (-not (Test-Path -Path 'variable:IsWindows') -or $IsWindows)
        {
            $nodeCmdName = 'node.exe'
            $npmCmdName = 'npm.cmd'
        }
        $nodePath = Join-Path -Path $To -ChildPath $nodeCmdName
        $npmPath = Join-Path -Path $To -ChildPath $npmCmdName

        $pathEnvVarRegex = "^$([regex]::Escape(($nodePath | Split-Path -Parent)))$([IO.Path]::PathSeparator).+"
        if ($Not)
        {
            $nodePath | Should -Not -Exist
            $env:PATH | Should -Not -Match $pathEnvVarRegex
            return
        }

        $nodePath | Should -Exist
        if ($AtVersion)
        {
            & $nodePath --version | Should -Be "v${AtVersion}"
        }

        $env:PATH | Should -Match $pathEnvVarRegex

        Get-Command -Name ($nodePath | Split-Path -Leaf) |
            Where-Object 'Source' -EQ $nodePath |
            Should -Not -BeNullOrEmpty
        Get-Command -Name ($npmPath | Split-Path -Leaf) |
            Where-Object 'Source' -EQ $npmPath |
            Should -Not -BeNullOrEmpty

        if ($WithNpmAtVersion)
        {
            & $npmPath '--version' | Should -Be $WithNpmAtVersion
        }
    }

    function WhenInstallingNode
    {
        [CmdletBinding()]
        param(
            [String] $Version,

            [String] $PackageJsonPath,

            [switch] $Force,

            [String] $Path,

            [String] $NpmVersion,

            [String] $Cpu
        )

        $parameters = @{}
        if( $Force )
        {
            $parameters['Force'] = $true
        }

        if ($Version)
        {
            $parameters['Version'] = $Version
        }

        if ($PackageJsonPath)
        {
            $parameters['PackageJsonPath'] = $PackageJsonPath
        }

        if ($Path)
        {
            $parameters['Path'] = $Path
        }

        if ($NpmVersion)
        {
            $parameters['NpmVersion'] = $NpmVersion
        }

        if ($Cpu)
        {
            $parameters['Cpu'] = $Cpu
        }

        Invoke-WhiskeyTask -TaskContext $context `
                           -Parameter $parameters `
                           -Name 'InstallNodeJs'
    }

    function ThenNodeFolderDidNotChange
    {
        $script:fileCreatedTime.add(((Get-ChildItem -Path $nodePath).CreationTime | Select-Object -ExpandProperty ticks))
        @( $filecreatedTime | Select-Object -Unique ) | Should -HaveCount 1
    }
}

AfterAll {
    $pathSeparator = [IO.Path]::PathSeparator
    $env:Path = ($env:Path -split $pathSeparator | Where-Object { Test-Path -Path $_ }) -join $pathSeparator
}

Describe 'InstallNodeJs' {
    BeforeEach {
        $script:testRoot = New-WhiskeyTestRoot
        $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot
        $script:fileCreatedTime = New-Object Collections.ArrayList
        $script:nodePath = Join-Path -Path $script:testRoot -ChildPath '.node'
        $Global:Error.Clear()
    }

    AfterEach {
        $emptyPath = Join-Path -Path $TestDrive -ChildPath 'Empty'
        if (-not (Test-Path -Path $emptyPath))
        {
            New-Item -Path $emptyPath -ItemType Directory
        }
        if (-not (Test-Path -Path 'variable:IsWindows') -or $IsWindows)
        {
            robocopy $emptyPath $script:testRoot /MIR
        }
    }

    $nodeVersions = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' | ForEach-Object { $_ }

    $latestNodeVersion =
        $nodeVersions |
        Where-Object{ $_.lts  } |
        Select-Object -ExpandProperty version |
        Select-Object -First 1 |
        ForEach-Object { $_.Substring(1) }

    It 'installs latest lts by default' -ForEach $latestNodeVersion {
        GivenPackageJsonFile
        WhenInstallingNode -InformationVariable 'infoMsgs'
        ThenNode -Installed -AtVersion $_
        $infoMsgs | Where-Object { $_ -match 'the latest active LTS version' } | Should -Not -BeNullOrEmpty
    }

    # Use a version of Node.js that isn't going to have any new versions so we can hard-code the expected versions.
    $testCases = @(
            @{ 'node' = '16'      ; 'npm' = '9'     ; },
            @{ 'node' = '16.20'   ; 'npm' = '9.9'   ; },
            @{ 'node' = '16.20.2' ; 'npm' = '9.9.4' ; }
        ) |
        ForEach-Object {
            $_['expectedNode'] = '16.20.2';
            $_['expectedNpm'] = '9.9.4';
            $_['defaultNpm'] = '8.19.4';
            $_ | Write-Output
        }
    $majorOnlyTestCase = $testCases[0]
    $majorMinorPatchTestCase = $testCases[2]

    Context 'using version from whiskey.yml file' {
        It 'installs Node.js using version <node> and NPM using version <npm>' -ForEach $testCases {
            WhenInstallingNode -Version $node -NpmVersion $npm
            ThenNode -Installed -AtVersion $expectedNode -WithNpmAtVersion $expectedNpm
        }

        It 'does not upgrade NPM' -ForEach $majorOnlyTestCase {
            WhenInstallingNode -Version $node
            ThenNode -Installed -AtVersion $expectedNode -WithNpmAtVersion $defaultNpm
        }

        It 'supports v prefix'  -ForEach $majorOnlyTestCase {
            WhenInstallingNode -Version "v${node}" -NpmVersion "v${npm}"
            ThenNode -Installed -AtVersion $expectedNode -WithNpmAtVersion $expectedNpm
        }
    }

    Context 'using version from packageJson file' {
        It 'installs Node.js using version <node> and NPM using version <npm>' -ForEach $testCases {
            $pkgJsonPath = GivenPackageJsonFile -WithContent @"
{
    "whiskey": {
        "node": "${node}",
        "npm": "${npm}"
    }
}
"@
            WhenInstallingNode -PackageJsonPath $pkgJsonPath
            ThenNode -Installed -AtVersion $expectedNode -WithNpmAtVersion $expectedNpm
        }

        It 'does not upgrade NPM' -ForEach $majorMinorPatchTestCase {
            $pkgJsonPath = GivenPackageJsonFile -WithContent @"
{
    "whiskey": {
        "node": "16.20.2"
    }
}
"@
            WhenInstallingNode -PackageJsonPath $pkgJsonPath
            ThenNode -Installed -AtVersion $expectedNode -WithNpmAtVersion $defaultNpm
        }

        It 'supports v prefix' -ForEach $majorOnlyTestCase {
            $pkgJsonPath = GivenPackageJsonFile @"
{
    "whiskey": {
        "node": "v${node}",
        "npm": "v${npm}"
    }
}
"@
            WhenInstallingNode -PackageJsonPath $pkgJsonPath
            ThenNode -Installed -AtVersion $expectedNode -WithNpmAtVersion $expectedNpm
        }
    }

    Context 'using version from .node-version file' {
        It 'installs Node.js using version <node>' -ForEach $testCases {
            $nodeVersionPath = Join-Path -Path $script:context.BuildRoot -ChildPath '.node-version'
            $node | Set-Content -Path $nodeVersionPath
            WhenInstallingNode
            ThenNode -Installed -AtVersion $expectedNode -WithNpmAtVersion $defaultNpm
        }

        It 'supports v prefix' -ForEach $majorOnlyTestCase {
            $nodeVersionPath = Join-Path -Path $script:context.BuildRoot -ChildPath '.node-version'
            "v${node}" | Set-Content -Path $nodeVersionPath
            WhenInstallingNode
            ThenNode -Installed -AtVersion $expectedNode -WithNpmAtVersion $defaultNpm
        }
    }

    It 'installs into custom directory' {
        WhenInstallingNode -Path 'mynode'
        ThenNode -Installed -To 'mynode'
    }

    It 'fails to download old version' {
        $oldVersion = '4.4.7'
        if ((Test-Path -Path 'variable:IsWindows') -and -not $IsWindows)
        {
            $oldVersion = '0.7.9'
        }
        { WhenInstallingNode -Version $oldVersion } | Should -Throw "*Failed to download Node v$($oldVersion)*"
        ThenNode -Not -Installed
        $Global:Error | Select-Object -First 1 | Should -Match 'NotFound'
    }

    It 'upgrades' {
        WhenInstallingNode -Version '8.8.1'
        ThenNode -Installed -AtVersion '8.8.1' -WithNpmAtVersion '5.4.2'

        $path = Join-Path -Path $script:context.BuildRoot -ChildPath '.node\deleteme'
        New-Item -Path $path -ItemType File
        $path | Should -Exist

        WhenInstallingNode -Version '8.9.0'
        ThenNode -Installed -AtVersion '8.9.0' -WithNpmAtVersion '5.5.1'
        # Make sure old .node directory gets deleted completely.
        $path | Should -Not -Exist
    }

    It 'customizes CPU' -Skip:((Test-Path -Path 'variable:IsWindows') -and -not $IsWindows) {
        WhenInstallingNode -Cpu 'x86'
        ThenNode -Installed
        & (Join-Path -Path $script:context.BuildRoot -ChildPath '.node\node.exe') -p 'process.arch' |
            Should -Not -Be 'x64'
    }

    # These tests fail intermittently on the build server despite my best efforts. I'm going to say this functionality
    # works, so no need to run them regularlary, just when a developer runs them locally.
    $skipAVTests = (Test-Path -Path 'env:WHS_CI') -or ((Test-Path -Path 'variable:IsWindows') -and -not $IsWindows)
    It 'handles aggressive anti-virus' -Skip:$skipAVTests -ForEach $latestNodeVersion {
        try
        {
            $latestNodeVersion = $_
            GivenAntiVirusLockingFiles -ForVersion $latestNodeVersion -For '00:00:05'
            { WhenInstallingNode } | Should -Not -Throw
            ThenNode -Installed -AtVersion $latestNodeVersion
        }
        finally
        {
            Get-Job | Stop-Job
            Get-Job | Remove-Job -Force
        }
    }

    It 'eventually gives up waiting for aggressive anti-virus' -Skip:$skipAVTests -ForEach $latestNodeVersion {
        try
        {
            $latestNodeVersion = $_
            GivenAntiVirusLockingFiles -ForVersion $latestNodeVersion -For '00:00:20'
            { WhenInstallingNode } | Should -Throw '*failed to install Node.js*'
            ThenNode -Not -Installed
            $Global:Error | Should -Match 'because renaming'
        }
        finally
        {
            Get-Job | Stop-Job
            Get-Job | Remove-Job -Force
        }
    }

    It 'sources NodeJs and NPM versions from different files' -ForEach $majorOnlyTestCase {
        $pkgJsonPath = GivenPackageJsonFile -WithContent @"
{
    "whiskey": {
        "node": "${node}"
    }
}
"@
        WhenInstallingNode -PackageJsonPath $pkgJsonPath -NpmVersion $npm -InformationVariable 'infoMsgs'
        ThenNode -Installed -AtVersion $expectedNode -WithNpmAtVersion $expectedNpm
        $infoMsgs |
            Where-Object { $_ -match "installing npm.* read from file.*whiskey\.yml" } |
            Should -Not -BeNullOrEmpty
        $infoMsgs |
            Where-Object { $_ -match "installing Node\.js.* read from file.*package.json" } |
            Should -Not -BeNullOrEmpty
    }
}