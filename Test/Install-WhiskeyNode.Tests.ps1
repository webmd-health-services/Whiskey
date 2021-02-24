
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$threwException = $false
$taskWorkingDirectory = $null
$nodePath = $null
$testRoot = $null
$outPath = $null

function GivenPackageJson
{
    param(
        $InputObject,
        $InDirectory = $testRoot
    )

    $InputObject | Set-Content -Path (Join-Path -Path $InDirectory -ChildPath 'package.json')
}

function GivenWorkingDirectory
{
    param(
        $Directory
    )

    $script:taskWorkingDirectory = Join-Path -Path $testRoot -ChildPath $Directory
    New-Item -Path $taskWorkingDirectory -ItemType Directory -Force | Out-Null
}

function Init
{
    $script:nodePath = $null
    $script:threwException = $false
    $script:testRoot = New-WhiskeyTestRoot
    $script:outPath = New-Item -Path $testRoot -Name '.output' -ItemType 'directory'
    $script:taskWorkingDirectory = $testRoot
}

function Reset 
{
    Remove-Node -BuildRoot $testRoot
}

function ThenNodeInstalled
{
    param(
        [String]$NodeVersion,

        [String]$NpmVersion,

        [switch]$AtLatestVersion,

        [switch]$NodeZipFileCheck
    )

    $nodePath = Resolve-WhiskeyNodePath -BuildRootPath $testRoot
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

    if($NodeZipFileCheck)
    {
        Join-Path -Path $outPath -ChildPath ('node-{0}-{1}-x64.{2}' -f $NodeVersion,$platformID,$extension) | Should -Exist
    }
    else
    {
        Join-Path -Path $outPath -ChildPath ('node-{0}-{1}-x64.{2}' -f $NodeVersion,$platformID,$extension) | Should -Not -Exist
    }

    $nodePath | Should -Exist
    & $nodePath '--version' | Should -Be $NodeVersion

    $npmPath = Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $testRoot -Global
    $npmPath = Join-Path -Path $npmPath -ChildPath 'bin\npm-cli.js'
    $npmPath | Should -Exist
    & $nodePath $npmPath '--version' | Should -Be $NpmVersion
    $nodePath | Should -Be (Resolve-WhiskeyNodePath -BuildRootPath $testRoot)
}

function ThenNodeNotInstalled
{
    Resolve-WhiskeyNodePath -BuildRootPath $testRoot -ErrorAction Ignore | Should -BeNullOrEmpty
    Resolve-WhiskeyNodeModulePath -Name 'npm' -BuildRootPath $testRoot -Global -ErrorAction Ignore | Should -BeNullOrEmpty
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
    $nodePath | Should -BeNullOrEmpty
}

function ThenThrewException
{
    param(
        $Regex
    )

    $threwException | Should -Be $true
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
    $parameter['InstallRoot'] = $testRoot
    $parameter['OutputPath'] = $outPath 

    Push-Location -path $taskWorkingDirectory
    try
    {
        $script:nodePath = Invoke-WhiskeyPrivateCommand -Name 'Install-WhiskeyNode' -Parameter $parameter
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }
    finally
    {
        Pop-Location
    }
}

function Lock-File {
    param(
        $Seconds,
        $File
    )
    Start-Job -ScriptBlock {                                     
        $file = [IO.File]::Open($using:File, 'Open', 'Write', 'None')

        try
        {
            Start-Sleep -Seconds $using:Seconds
        }

        finally
        {
           $file.Close()
        }
    }

    # Wait for file to get locked
    do
    {
        Start-Sleep -Milliseconds 100
        Write-Debug -Message ('Waiting for hosts file to get locked.')
    }
    while( (Get-Content -Path $File -ErrorAction SilentlyContinue ) )

    $Global:Error.Clear()
}

function GivenAntiVirusLockingFiles
{
    param(
    [String]$NodeVersion,

    [switch]$AtLatestVersion,

    [int]$Seconds
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

    $extractedDirName = 'node-{0}-{1}-x64' -f $NodeVersion,$platformID
    $filename = '{0}.{1}' -f $extractedDirName,$extension
    $nodeZipFile = Join-Path -Path $outPath -ChildPath $filename 

    $uri = 'https://nodejs.org/dist/{0}/{1}' -f $NodeVersion,$filename
    Invoke-WebRequest -Uri $uri -OutFile $nodeZipFile
    $nodeZipFile | Should -Exist

    $archive = [io.compression.zipfile]::OpenRead($nodeZipFile)
    $outputDirectoryName = $archive.Entries[0].FullName
    $archive.Dispose()
    $outputDirectoryName = $outputDirectoryName.Substring(0, $outputDirectoryName.Length - 1)
    $outputDirectoryName = New-Item -Path $testRoot -Name $outputDirectoryName -ItemType 'Directory'
    $outputDirectoryName | Should -Exist

    Remove-Item -Force $nodeZipFile
    
    $targetFile = Join-Path -Path $outputDirectoryName -ChildPath 'lock.txt'
    New-Item -Path $targetFile -ItemType 'File'
    $targetFile | Should -Exist

    $job = Lock-File -Seconds $Seconds -File $targetFile -log_msg log_msg

    try {

        WhenInstallingTool
	}
    finally {

        $job | Wait-Job | Receive-Job
    }      
}


Describe 'Install-WhiskeyNode.when installing' {
    AfterEach { Reset }
    It 'should install Node.js' {
        Init
        WhenInstallingTool
        ThenNodeInstalled -AtLatestVersion -NodeZipFileCheck 
    }
}

Describe 'Install-WhiskeyNode.when installing old version' {
    AfterEach { Reset }
    It 'should fail' {
        $oldVersion = '4.4.7'
        if( -not $IsWindows )
        {
            $oldVersion = '0.7.9'
        }
        Init
        GivenPackageJson @"
{
    "engines": {
        "node": "$($oldVersion)"
    }
}
"@
        WhenInstallingTool -ErrorAction SilentlyContinue
        ThenThrewException ([regex]::Escape(('Failed to download Node v{0}' -f $oldVersion)))
        ThenNodeNotInstalled
        ThenNodePackageNotFound
    }
}

Describe 'Install-WhiskeyNode.when installing specific version' {
    AfterEach { Reset }
    It 'should install that version' {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "9.2.1"
    }
}
'@
        WhenInstallingTool
        ThenNodeInstalled 'v9.2.1' -NpmVersion '5.5.1' -NodeZipFileCheck 
    }
}

Describe 'Install-WhiskeyNode.when upgrading to a new version' {
    AfterEach { Reset }
    It 'should upgrade to the new version' {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "8.8.1"
    }
}
'@
        WhenInstallingTool
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2' -NodeZipFileCheck 

        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool
        ThenNodeInstalled 'v8.9.0' -NpmVersion '5.6.0' -NodeZipFileCheck 
    }
}

Describe 'Install-WhiskeyNode.when user specifies version in whiskey.yml and uses wildcard' {
    AfterEach { Reset }
    It 'should download the latest version that matches the wildcard' {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool -Version '8.8.*'
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2' -NodeZipFileCheck 
    }
}

Describe 'Install-WhiskeyNode.when using custom version of NPM' {
    AfterEach { Reset }
    It 'should update NPM' {
        Init
        GivenPackageJson @'
{
    "engines": {
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool
        ThenNodeInstalled -AtLatestVersion -NpmVersion '5.6.0' -NodeZipFileCheck 
    }
}

Describe 'Install-WhiskeyNode.when already installed' {
    AfterEach { Reset }
    It 'should use version of Node already there' {
        Init
        WhenInstallingTool
        ThenNodeInstalled -AtLatestVersion -NodeZipFileCheck 

        Mock -CommandName 'Invoke-WebRequest' -Module 'Whiskey'
        $nodeUnzipPath = Join-Path -Path $testRoot -ChildPath '.node\node-*-win-x64'
        Get-ChildItem -Path $nodeUnzipPath -Directory | Remove-Item
        WhenInstallingTool
        $nodeUnzipPath | Should -Not -Exist
        Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 0
    }
}

Describe 'Install-WhiskeyNode.when packageJson is in working directory' {
    AfterEach { Reset }
    It 'should install Node.js' {
        Init
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
'@ -InDirectory $taskWorkingDirectory

        WhenInstallingTool
        ThenNodeInstalled -NodeVersion 'v8.9.0' -NpmVersion '5.5.1' -NodeZipFileCheck 
    }
}

Describe 'Install-WhiskeyNode.when run in clean mode' {
    AfterEach { Reset }
    It 'should remove Node.js' {
        Init
        WhenInstallingTool -InCleanMode
        ThenNodeNotInstalled
        ThenNoError
        ThenNothingReturned
    }
}

Describe 'Install-WhiskeyNode.when run in clean mode and Node is installed' {
    AfterEach { Reset }
    It 'should uninstall Node.js' {
        Init
        Install-Node -BuildRoot $testRoot
        WhenInstallingTool -InCleanMode
        ThenNodeInstalled -AtLatestVersion
        ThenNoError
    }
}

if($IsWindows)
{
    Describe 'Install-WhiskeyNode.when anti-virus locks file in uncompressed package' {
        AfterEach { Reset }
        It 'should still install Node.js' {
            Init
            GivenAntiVirusLockingFiles -AtLatestVersion -Seconds 40
            ThenNodeInstalled -AtLatestVersion -NodeZipFileCheck
        }

        It 'should fail' {
            Init
            GivenAntiVirusLockingFiles -AtLatestVersion -Seconds 120
            ThenNodeNotInstalled
        }
    }
}


