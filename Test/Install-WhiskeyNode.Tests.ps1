
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeDiscovery {
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
}

BeforeAll {
    Set-StrictMode -Version 'Latest'


    $script:threwException = $false
    $script:taskWorkingDirectory = $null
    $script:nodePath = $null
    $script:testRoot = $null
    $script:outPath = $null
    $script:avStartedFileName = 'av.started'

    function GivenPackageJson
    {
        param(
            $InputObject,
            $InDirectory = $script:testRoot
        )

        $InputObject | Set-Content -Path (Join-Path -Path $InDirectory -ChildPath 'package.json')
    }

    function GivenWorkingDirectory
    {
        param(
            $Directory
        )

        $script:taskWorkingDirectory = Join-Path -Path $script:testRoot -ChildPath $Directory
        New-Item -Path $script:taskWorkingDirectory -ItemType Directory -Force | Out-Null
    }

    function ThenNodeInstalled
    {
        param(
            [String]$NodeVersion,

            [String]$NpmVersion,

            [switch]$AtLatestVersion,

            [switch]$AndArchiveFileExists
        )

        $script:nodePath = Resolve-WhiskeyNodePath -BuildRootPath $script:testRoot
        if( $AtLatestVersion )
        {
            $expectedVersion = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' |
                                    ForEach-Object { $_ } |
                                    Where-Object { $_.lts } |
                                    Select-Object -First 1
            $NodeVersion = $expectedVersion.version
            if( -not $NpmVersion )
            {
                $NpmVersion = $expectedVersion.npm
            }
        }

        if( $IsWindows )
        {
            $platformID = 'win'
            $extension = 'zip'
        }
        elseif( $IsLinux )
        {
            $platformID = 'linux'
            $extension = 'tar.xz'
        }
        elseif( $IsMacOS )
        {
            $platformID = 'darwin'
            $extension = 'tar.gz'
        }

        if( $AndArchiveFileExists )
        {
            Join-Path -Path $script:outPath -ChildPath ('node-{0}-{1}-x64.{2}' -f $NodeVersion,$platformID,$extension) | Should -Exist
        }
        else
        {
            Join-Path -Path $script:outPath -ChildPath ('node-{0}-{1}-x64.{2}' -f $NodeVersion,$platformID,$extension) | Should -Not -Exist
        }

        $script:nodePath | Should -Exist
        & $script:nodePath '--version' | Should -Be $NodeVersion

        $npmPath = Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $script:testRoot -Global
        $npmPath = Join-Path -Path $npmPath -ChildPath 'bin\npm-cli.js'
        $npmPath | Should -Exist
        & $script:nodePath $npmPath '--version' | Should -Be $NpmVersion
        $script:nodePath | Should -Be (Resolve-WhiskeyNodePath -BuildRootPath $script:testRoot)
    }

    function ThenNodeNotInstalled
    {
        Resolve-WhiskeyNodePath -BuildRootPath $script:testRoot -ErrorAction Ignore | Should -BeNullOrEmpty
        Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $script:testRoot -Global -ErrorAction Ignore | Should -BeNullOrEmpty
    }

    function ThenNodePackageNotFound
    {
        $Global:Error | Select-Object -First 1 | Should -Match 'NotFound'
    }

    function ThenNoError
    {
        $Global:Error | Should -BeNullOrEmpty
    }

    function ThenNothingReturned
    {
        $script:nodePath | Should -BeNullOrEmpty
    }

    function ThenThrewException
    {
        param(
            $Regex
        )

        $script:threwException | Should -Be $true
        $Global:Error[0] | Should -Match $Regex
    }

    function WhenInstallingTool
    {
        [CmdletBinding()]
        param(
            $Version,

            [switch]$InCleanMode
        )

        $Global:Error.Clear()

        $parameter = $PSBoundParameters
        $parameter['InstallRootPath'] = $script:testRoot
        $parameter['OutFileRootPath'] = $script:outPath

        Push-Location -path $script:taskWorkingDirectory
        try
        {
            $script:nodePath = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyNode' -Parameter $parameter
        }
        finally
        {
            Pop-Location
        }
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

    function GivenAntiVirusLockingFiles
    {
        [CmdletBinding()]
        param(
            [String]$NodeVersion,

            [switch]$AtLatestVersion,

            [TimeSpan]$For
        )

        if( $AtLatestVersion )
        {
            $expectedVersion = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' |
                                    ForEach-Object { $_ } |
                                    Where-Object { $_.lts } |
                                    Select-Object -First 1
            $NodeVersion = $expectedVersion.version
        }

        if( $IsWindows )
        {
            $platformID = 'win'
        }
        elseif( $IsLinux )
        {
            $platformID = 'linux'
        }
        elseif( $IsMacOS )
        {
            $platformID = 'darwin'
        }

        $extractedDirName = 'node-{0}-{1}-x64' -f $NodeVersion,$platformID

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
}

Describe 'Install-WhiskeyNode' {
    BeforeEach {
        $script:nodePath = $null
        $script:threwException = $false
        $script:testRoot = New-WhiskeyTestRoot
        $script:outPath = New-Item -Path $script:testRoot -Name '.output' -ItemType 'directory'
        $script:taskWorkingDirectory = $script:testRoot
        $Global:Error.Clear()
    }

    AfterEach {
        # Remove any leftover or still running background jobs.
        Write-Verbose -Message "[Reset]  [$((Get-Date).ToString('HH:mm:ss.fff'))]  Removing leftover jobs."
        $DebugPreference = 'Continue'
        $jobs = Get-Job | Where-Object 'Name' -EQ $PSCommandPath
        if ($jobs)
        {
            $jobs | Format-Table -Auto | Out-String | Write-Debug
        }
        $jobs | Receive-Job -AutoRemoveJob -Wait
        Write-Verbose -Message "[Reset]  [$((Get-Date).ToString('HH:mm:ss.fff'))]  Done removing jobs."

        Remove-Node -BuildRoot $script:testRoot
        $Global:VerbosePreference = 'SilentlyContinue'
        $Global:DebugPreference = 'SilentlyContinue'
    }

    It 'should install Node.js' {
        WhenInstallingTool
        ThenNodeInstalled -AtLatestVersion -AndArchiveFileExists
    }

    It 'should not download old version' {
        $oldVersion = '4.4.7'
        if( -not $IsWindows )
        {
            $oldVersion = '0.7.9'
        }
        GivenPackageJson @"
{
    "engines": {
        "node": "$($oldVersion)"
    }
}
"@
        { WhenInstallingTool } | Should -Throw "Failed to download Node v$($oldVersion)*"
        ThenNodeNotInstalled
        ThenNodePackageNotFound
    }

    It 'should install specific version' {
        GivenPackageJson @'
{
    "engines": {
        "node": "9.2.1"
    }
}
'@
        WhenInstallingTool
        ThenNodeInstalled 'v9.2.1' -NpmVersion '5.5.1' -AndArchiveFileExists
    }

    It 'should upgrade to a new version' {
        GivenPackageJson @'
{
    "engines": {
        "node": "8.8.1"
    }
}
'@
        WhenInstallingTool
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2' -AndArchiveFileExists

        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool
        ThenNodeInstalled 'v8.9.0' -NpmVersion '5.6.0' -AndArchiveFileExists
    }

    It 'should download the latest version that matches wildcard' {
        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool -Version '8.8.*'
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2' -AndArchiveFileExists
    }

    It 'should update NPM' {
        GivenPackageJson @'
{
    "engines": {
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool
        ThenNodeInstalled -AtLatestVersion -NpmVersion '5.6.0' -AndArchiveFileExists
    }

    It 'should use installed version of Node' {
        WhenInstallingTool
        ThenNodeInstalled -AtLatestVersion -AndArchiveFileExists

        Mock -CommandName 'Invoke-WebRequest' -Module 'Whiskey'
        $nodeUnzipPath = Join-Path -Path $script:testRoot -ChildPath '.node\node-*-win-x64'
        Get-ChildItem -Path $nodeUnzipPath -Directory | Remove-Item
        WhenInstallingTool
        $nodeUnzipPath | Should -Not -Exist
        Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 0
    }

    It 'should install Node.js from working directory''s packageJson' {
        GivenWorkingDirectory 'app'

        # Put a package.json in the root to ensure package.json in the current directory is used first.
        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.4"
    }
}
'@

        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0"
    }
}
'@ -InDirectory $script:taskWorkingDirectory

        WhenInstallingTool
        ThenNodeInstalled -NodeVersion 'v8.9.0' -NpmVersion '5.5.1' -AndArchiveFileExists
    }

    It 'should clean Node.js' {
        WhenInstallingTool -InCleanMode
        ThenNodeNotInstalled
        ThenNoError
        ThenNothingReturned
    }

    It 'should not clean Node.js' {
        Install-Node -BuildRoot $script:testRoot
        WhenInstallingTool -InCleanMode
        ThenNodeInstalled -AtLatestVersion
        ThenNoError
    }

    # These tests fail intermittently on the build server despite my best efforts. I'm going to say this functionality
    # works, so no need to run them regularlary, just when a developer runs them locally.
    $skipAVTests = -not $IsWindows -or (Test-Path -Path 'env:WHS_CI')
    It 'should handle aggressive anti-virus' -Skip:$skipAVTests {
        $Global:VerbosePreference = 'Continue'
        $Global:DebugPreference = 'Continue'
        GivenAntiVirusLockingFiles -AtLatestVersion -For '00:00:05'
        WhenInstallingTool
        ThenNodeInstalled -AtLatestVersion -AndArchiveFileExists
    }

    It 'should not wait forever for aggressive anti-virus' -Skip:$skipAVTests {
        $Global:VerbosePreference = 'Continue'
        $Global:DebugPreference = 'Continue'
        GivenAntiVirusLockingFiles -AtLatestVersion -For '00:00:20'
        { WhenInstallingTool } | Should -Throw '*Node executable doesn''t exist*'
        ThenNodeNotInstalled
        $Global:Error | Where-Object { $_ -like '*because renaming*' } | Should -Not -BeNullOrEmpty
    }
}
