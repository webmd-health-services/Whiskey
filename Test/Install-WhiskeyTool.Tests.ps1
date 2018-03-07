
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function Invoke-PowershellInstall
{
    param(
        $ForModule,
        $Version,
        $ActualVersion,

        [Parameter(Mandatory=$true,ParameterSetName='ForRealsies')]
        [Switch]
        # Really do the install. Don't fake it out.
        $ForRealsies,

        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell5')]
        [Switch]
        $LikePowerShell5,

        [Parameter(Mandatory=$true,ParameterSetName='LikePowerShell4')]
        [Switch]
        $LikePowerShell4
    )

    if( -not $ActualVersion )
    {
        $ActualVersion = $Version
    }

    if( -not ($PSCmdlet.ParameterSetName -eq 'ForRealsies') )
    {
        $ForRealsies = $false
    }

    if( -not $ForRealsies )
    {
        if( $PSCmdlet.ParameterSetName -eq 'LikePowerShell5' )
        {
            $LikePowerShell4 = $false
        }
        if( $PSCmdlet.ParameterSetName -eq 'LikePowerShell4' )
        {
            $LikePowerShell5 = $false
        }

        Mock -CommandName 'Find-Module' -ModuleName 'Whiskey' -MockWith {
            return $module = @(
                                 [pscustomobject]@{
                                                Version = [Version]$Version
                                                Repository = 'Repository'
                                            }
                                 [pscustomobject]@{
                                                Version = '0.1.1'
                                                Repository = 'Repository'
                                            }
                              )
        }

        Mock -CommandName 'Save-Module' -ModuleName 'Whiskey' -MockWith {
            $moduleRoot = Join-Path -Path (Get-Item -Path 'TestDrive:').FullName -ChildPath 'Modules'
            if( $LikePowerShell4 )
            {
                $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $ForModule
            }
            elseif( $LikePowerShell5 )
            {
                $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $ForModule
                $moduleRoot = Join-Path -Path $moduleRoot -ChildPath $ActualVersion
            }
            New-Item -Path $moduleRoot -ItemType 'Directory' | Out-Null
            $moduleManifestPath = Join-Path -Path $moduleRoot -ChildPath ('{0}.psd1' -f $ForModule)
            New-ModuleManifest -Path $moduleManifestPath -ModuleVersion $ActualVersion
        }.GetNewClosure()
    }

    $optionalParams = @{ }
    $Global:Error.Clear()
    $result = Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName $ForModule -Version $Version

    if( -not $ForRealsies )
    {
        It 'should download the module' {
            Assert-MockCalled -CommandName 'Save-Module' -ModuleName 'Whiskey' -Times 1 -ParameterFilter {
                #$DebugPreference = 'Continue';
                Write-Debug -Message ('Name             expected  {0}' -f $ForModule)
                Write-Debug -Message ('                 actual    {0}' -f $Name)
                Write-Debug -Message ('RequiredVersion  expected  {0}' -f $ActualVersion)
                Write-Debug -Message ('                 actual    {0}' -f $RequiredVersion)
                Write-Debug -Message ('Repository       expected  {0}' -f 'Repository')
                Write-Debug -Message ('                 actual    {0}' -f $Repository)
                $Name -eq $ForModule -and `
                $RequiredVersion -eq $ActualVersion -and `
                $Repository -eq 'Repository'
            }
        }

        It 'should put the modules in $DownloadRoot\Modules' {
            Assert-MockCalled -CommandName 'Save-Module' -ModuleName 'Whiskey' -ParameterFilter {
                $Path -eq (Join-Path -Path $TestDrive.FullName -ChildPath 'Modules')
            }
        }
        return
    }

    Context 'the module' {
        It 'should exist' {
            $result | Should Exist
        }

        It 'should be importable' {
            $errors = @()
            Import-Module -Name $result -PassThru -ErrorVariable 'errors' | Remove-Module
            $errors | Should BeNullOrEmpty
        }

        It 'should put it in the right place' {
            $expectedRegex = 'Modules\\{0}$' -f [regex]::Escape($ForModule)
            $result | Should Match $expectedRegex
        }
    }
}

function Invoke-NuGetInstall
{
    [CmdletBinding()]
    param(
        $Package,
        $Version,

        [switch]
        $invalidPackage
    )

    $result = Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -NugetPackageName $Package -Version $Version
    if( -not $invalidPackage)
    {
        Context 'the NuGet Package' {
            It 'should exist' {
                $result | Should -Exist
            }
            It 'should get installed into $DownloadRoot\packages' {
                $result | Should -BeLike ('{0}\packages\*' -f $TestDrive.FullName)
            }
        }
    }
    else
    {
        Context 'the Invalid NuGet Package' {
            It 'should NOT exist' {
                $result | Should Not Exist
            }
            it 'should write errors' {
                $Global:Error | Should NOT BeNullOrEmpty
            }
        }
    }
}

Describe 'Install-WhiskeyTool.when given a NuGet Package' {
    Invoke-NuGetInstall -package 'NUnit.Runners' -version '2.6.4'
}

Describe 'Install-WhiskeyTool.when NuGet Pack is bad' {
    Invoke-NuGetInstall -package 'BadPackage' -version '1.0.1' -invalidPackage -ErrorAction silentlyContinue
}

Describe 'Install-WhiskeyTool.when NuGet pack Version is bad' {
    Invoke-NugetInstall -package 'Nunit.Runners' -version '0.0.0' -invalidPackage -ErrorAction silentlyContinue
}

Describe 'Install-WhiskeyTool.when given a NuGet Package with an empty version string' {
    Invoke-NuGetInstall -package 'NUnit.Runners' -version ''
}

Describe 'Install-WhiskeyTool.when installing an already installed NuGet package' {

    $Global:Error.Clear()

    Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'
    Invoke-NuGetInstall -package 'Nunit.Runners' -version '2.6.4'

    it 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyTool.when run by developer/build server' {
    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.15.0' -ForRealsies
}

Describe 'Install-WhiskeyTool.when installing an already installed module' {
    $Global:Error.Clear()

    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.15.0' -ForRealsies
    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.15.0' -ForRealsies

    it 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }
}

Describe 'Install-WhiskeyTool.when omitting BUILD number' {
    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.15' -ActualVersion '0.15.0' -ForRealsies
}

Describe 'Install-WhiskeyTool.when omitting Version' {
    $bladeModule = Resolve-WhiskeyPowerShellModule -Version '' -Name 'Blade'
    Invoke-PowershellInstall -ForModule 'Blade' -Version '' -ActualVersion $bladeModule.Version -ForRealsies
}

Describe 'Install-WhiskeyTool.when using wildcard version' {
    $bladeModule = Resolve-WhiskeyPowerShellModule -Version '0.*' -Name 'Blade'
    Invoke-PowershellInstall -ForModule 'Blade' -Version '0.*' -ActualVersion $bladeModule.Version -ForRealsies
}

Describe 'Install-WhiskeyTool.when installing a module under PowerShell 4' {
    Invoke-PowershellInstall -ForModule 'Fubar' -Version '1.3.3' -LikePowerShell4
}

Describe 'Install-WhiskeyTool.when installing a module under PowerShell 5' {
    Invoke-PowershellInstall -ForModule 'Fubar' -Version '1.3.3' -LikePowerShell5
}

Describe 'Install-WhiskeyTool.when version of module doesn''t exist' {
    $Global:Error.Clear()

    $result = Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName 'Pester' -Version '3.0.0' -ErrorAction SilentlyContinue

    It 'shouldn''t return anything' {
        $result | Should BeNullOrEmpty
    }

    It 'should write an error' {
        $Global:Error.Count | Should Be 1
        $Global:Error[0] | Should Match 'failed to find module'
    }
}

Describe 'Install-WhiskeyTool.for non-existent module when version parameter is empty' {
    $Global:Error.Clear()

    $result = Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName 'Fubar' -Version '' -ErrorAction SilentlyContinue

    It 'shouldn''t return anything' {
        $result | Should BeNullOrEmpty
    }

    It 'should write an error' {
        $Global:Error.Count | Should Be 1
        $Global:Error[0] | Should Match 'Failed to find module'
    }
}

Describe 'Install-WhiskeyTool.when set EnableNuGetPackageRestore' {
    Mock -CommandName 'Set-Item' -ModuleName 'Whiskey'
    Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -NugetPackageName 'NUnit.Runners' -version '2.6.4'
    It 'should enable NuGet package restore' {
        Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Path -eq 'env:EnableNuGetPackageRestore'}
        Assert-MockCalled 'Set-Item' -ModuleName 'Whiskey' -parameterFilter {$Value -eq 'true'}
    }
}

Describe 'Install-WhiskeyTool.when PowerShell module is already installed' {
    Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName 'Pester' -Version '4.0.6'
    $info = Get-ChildItem -Path $TestDrive.FullName -Filter 'Pester.psd1' -Recurse
    $manifest = Test-ModuleManifest -Path $info.FullName
    Start-Sleep -Milliseconds 333
    Install-WhiskeyTool -DownloadRoot $TestDrive.FullName -ModuleName 'Pester' -Version '4.0.7'
    $newInfo = Get-ChildItem -Path $TestDrive.FullName -Filter 'Pester.psd1' -Recurse
    $newManifest = Test-ModuleManifest -Path $newInfo.FullName
    It 'should not redownload module' {
        $newManifest.Version | Should -Be $manifest.Version
    }
}

$context = $null
$globalDotnetDirectory = $null
$threwException = $false
$originalPath = $env:Path
$pathParameterName = 'ToolPath'
$versionParameterName = $null
$taskParameter = $null
$workingDirectory = $null

function Get-DotnetLatestLTSVersion
{
    Invoke-RestMethod -Uri 'https://dotnetcli.blob.core.windows.net/dotnet/Sdk/LTS/latest.version' | Where-Object { $_ -match '(\d+\.\d+\.\d+)'} | Out-Null
    return $Matches[1]
}

function GivenGlobalDotnetInstalled
{
    param(
        $Version
    )

    New-Item -Path (Join-Path -Path $globalDotnetDirectory -ChildPath 'dotnet.exe') -ItemType File -Force | Out-Null
    New-Item -Path (Join-Path -Path $globalDotnetDirectory -ChildPath ('sdk\{0}\dotnet.dll' -f $Version)) -ItemType File -Force | Out-Null
    $env:Path += (';{0}' -f $globalDotnetDirectory)
}


function GivenGlobalJsonSdkVersion
{
    param(
        $Version,
        $Directory = $TestDrive.FullName
    )

    @{
        'sdk' = @{
            'version' = $Version
        }
    } | ConvertTo-Json -Depth 100 | Set-Content -Path (Join-Path -Path $Directory -Child 'global.json') -Force
}

function GivenPackageJson
{
    param(
        $InputObject,
        $InDirectory = $TestDrive.FullName
    )

    $InputObject | Set-Content -Path (Join-Path -Path $InDirectory -ChildPath 'package.json')
}

function GivenVersionParameterName
{
    param(
        $Name
    )

    $script:versionParameterName = $Name
}

function GivenWorkingDirectory
{
    param(
        $Directory
    )

    $script:workingDirectory = Join-Path -Path $TestDrive.FullName -ChildPath $Directory
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
}

function Init
{
    $script:context = $null
    $script:globalDotnetDirectory = Join-Path -Path $TestDrive.FullName -ChildPath 'GlobalDotnetSDK'
    $script:threwException = $false
    $script:taskParameter = $null
    $script:versionParameterName = $null
    $script:workingDirectory = $TestDrive.FullName
}

function Remove-DotnetInstallsFromPath
{
    $dotnetInstalls = Get-Command -Name 'dotnet.exe' -All -ErrorAction Ignore | Select-Object -ExpandProperty 'Source' -ErrorAction Ignore
    foreach ($path in $dotnetInstalls)
    {
        $dotnetDirectory = [regex]::Escape(($path | Split-Path -Parent))
        $dotnetDirectory = ('{0}\\?' -f $dotnetDirectory)
        $env:Path = $env:Path -replace $dotnetDirectory,''
    }
}

function Restore-OriginalPathEnvironment
{
    $env:Path = $originalPath
}

function ThenDotnetSdkVersion
{
    param(
        [string]
        $Version
    )

    Push-Location -Path $workingDirectory
    try
    {
        It 'should install correct .NET Core SDK version' {
            & $taskParameter[$pathParameterName] --version | Should -Be $Version
        }
    }
    finally
    {
        Pop-Location
    }
}

function ThenDotnetNotLocallyInstalled
{
    param(
        $Version
    )

    $dotnetSdkPath = Join-Path -Path $TestDrive.FullName -ChildPath ('.dotnet\sdk\{0}' -f $Version)
    It 'should not install .NET Core SDK locally' {
        $dotnetSdkPath | Should -Not -Exist
    }
}

function ThenDotnetPathAddedToTaskParameter
{
    It ('should set path to the dotnet.exe') {
        $taskParameter[$pathParameterName] | Should -BeLike '*\dotnet.exe'
    }
}

function ThenGlobalJsonVersion
{
    param(
        $Version,
        $Directory = $TestDrive.FullName
    )

    $globalJsonVersion = Get-Content -Path (Join-Path -Path $Directory -ChildPath 'global.json') -Raw |
                         ConvertFrom-Json |
                         Select-Object -ExpandProperty 'sdk' -ErrorAction Ignore |
                         Select-Object -ExpandProperty 'version' -ErrorAction Ignore

    It ('should update global.json sdk version to ''{0}''' -f $Version) {
        $globalJsonVersion | Should -Be $Version
    }
}

function ThenNodeInstalled
{
    param(
        [string]
        $NodeVersion,

        [string]
        $NpmVersion,

        [Switch]
        $AtLatestVersion
    )

    $nodePath = Join-Path -Path $TestDrive.FullName -ChildPath '.node\node.exe'
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

    It ('should download Node ZIP file') {
        Join-Path -Path $TestDrive.FullName -ChildPath ('.node\node-{0}-win-x64.zip' -f $NodeVersion) | Should -Exist
    }

    It ('should install Node') {
        $nodePath | Should -Exist
        & $nodePath '--version' | Should -Be $NodeVersion
    }


    $npmPath = Join-Path -Path $TestDRive.FullName -ChildPath '.node\node_modules\npm\bin\npm-cli.js'
    It ('should install NPM') {
        $npmPath | Should -Exist
        & $nodePath $npmPath '--version' | Should -Be $NpmVersion
    }

    It ('should set path to node.exe') {
        $taskParameter[$pathParameterName] | Should -Be (Join-Path -Path $TestDrive.FullName -ChildPath '.node\node.exe')
    }
}

function ThenNodeModuleInstalled
{
    param(
        $Name,
        $AtVersion
    )

    It ('should install the node module') {
        $expectedPath = Join-Path -Path $TestDrive.FullName -ChildPath ('.node\node_modules\{0}' -f $Name)
        $expectedPath | Should -Exist
        $taskParameter[$pathParameterName] | Should -Be $expectedPath

        if( $AtVersion )
        {
            Get-Content -Path (Join-Path -Path $expectedPath -ChildPath 'package.json') -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'version' | Should -Be $AtVersion
        }
    }
}

function ThenNodeModuleNotInstalled
{
    param(
        $Name
    )

    It ('should not install the node module') {
        $expectedPath = Join-Path -Path $TestDrive.FullName -ChildPath ('.node\node_modules\{0}' -f $Name)
        $expectedPath | Should -Not -Exist
        $taskParameter.ContainsKey($pathParameterName) | Should -Be $false
    }
}

function ThenNodeNotInstalled
{
    $nodePath = Join-Path -Path $TestDrive.FullName -ChildPath '.node\node.exe'
    It ('should not install Node') {
        $nodePath | Should -Not -Exist
    }

    $npmPath = Join-Path -Path $TestDRive.FullName -ChildPath '.node\node_modules\npm\bin\npm-cli.js'
    It ('should not install NPM') {
        $npmPath | Should -Not -Exist
    }

    It ('should not set path to node') {
        $taskParameter.ContainsKey($pathParameterName) | Should -Be $false
    }
}

function ThenNodePackageNotFound
{
    It ('should report failure to download') {
        $Error[0] | Should -Match 'NotFound'
    }
}

function ThenThrewException
{
    param(
        $Regex
    )

    It ('should throw an exception') {
        $threwException | Should -Be $true
        $Global:Error[0] | Should -Match $Regex
    }
}

function WhenInstallingTool
{
    [CmdletBinding()]
    param(
        $Name,
        $Parameter = @{ },
        $Version
    )

    $Global:Error.Clear()

    $toolAttribute = New-Object 'Whiskey.RequiresToolAttribute' $Name,$pathParameterName

    if( $versionParameterName )
    {
        $toolAttribute.VersionParameterName = $versionParameterName
    }

    if( $Version )
    {
        $toolAttribute.Version = $Version
    }

    $script:taskParameter = $Parameter

    Push-Location -path $workingDirectory
    try
    {
        Install-WhiskeyTool -ToolInfo $toolAttribute -InstallRoot $TestDrive.FullName -TaskParameter $Parameter
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

Describe 'Install-WhiskeyTool.when installing Node' {
    try
    {
        Init
        WhenInstallingTool 'Node'
        ThenNodeInstalled -AtLatestVersion
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing old version of Node' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "4.4.7"
    }
}
'@
        WhenInstallingTool 'Node' -ErrorAction SilentlyContinue
        ThenThrewException 'Failed to download Node v4\.4\.7'
        ThenNodeNotInstalled
        ThenNodePackageNotFound
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing specific version of Node' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "9.2.1"
    }
}
'@
        WhenInstallingTool 'Node'
        ThenNodeInstalled 'v9.2.1' -NpmVersion '5.5.1'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when upgrading to a new version of Node' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "8.8.1"
    }
}
'@
        WhenInstallingTool 'Node'
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2'

        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool 'Node'
        ThenNodeInstalled 'v8.9.0' -NpmVersion '5.6.0'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when user specifies version of Node in whiskey.yml and uses wildcard' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        GivenVersionParameterName 'Fubar'
        WhenInstallingTool 'Node' @{ 'Fubar' = '8.8.*' }
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when task author specifies version of Node' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "node": "8.9.0",
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool 'Node' @{  } -Version '8.8.*'
        ThenNodeInstalled 'v8.8.1' -NpmVersion '5.4.2'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when using custom version of NPM' {
    try
    {
        Init
        GivenPackageJson @'
{
    "engines": {
        "npm": "5.6.0"
    }
}
'@
        WhenInstallingTool 'Node'
        ThenNodeInstalled -AtLatestVersion -NpmVersion '5.6.0'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when already installed' {
    try
    {
        Init
        WhenInstallingTool 'Node'
        ThenNodeInstalled -AtLatestVersion

        Mock -CommandName 'Invoke-WebRequest' -Module 'Whiskey'
        $nodeUnzipPath = Join-Path -Path $TestDrive.FullName -ChildPath '.node\node-*-win-x64'
        Get-ChildItem -Path $nodeUnzipPath -Directory | Remove-Item
        WhenInstallingTool 'Node'
        It ('should not re-unzip ZIP file') {
            $nodeUnzipPath | Should -Not -Exist
        }
        It 'should not re-download Node' {
            Assert-MockCalled -CommandName 'Invoke-WebRequest' -ModuleName 'Whiskey' -Times 0
        }
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when package.json is in working directory' {
    try
    {
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
'@ -InDirectory $workingDirectory

        WhenInstallingTool 'Node'
        ThenNodeInstalled -NodeVersion 'v8.9.0' -NpmVersion '5.5.1'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing Node module' {
    try
    {
        Init
        WhenInstallingTool 'Node'
        ThenNodeInstalled -AtLatestVersion
        WhenInstallingTool 'NodeModule::license-checker'
        ThenNodeModuleInstalled 'license-checker'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing Node module and Node isn''t installed' {
    try
    {
        Init
        WhenInstallingTool 'NodeModule::license-checker' -ErrorAction SilentlyContinue
        ThenThrewException 'Whiskey\ maybe\ failed\ to\ install\ Node\ correctly'
        ThenNodeModuleNotInstalled 'license-checker'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing specific version of a Node module via version parameter' {
    try
    {
        Init
        Install-Node
        GivenVersionParameterName 'Fubar'
        WhenInstallingTool 'NodeModule::license-checker' @{ 'Fubar' = '13.1.0' } -Version '16.0.0'
        ThenNodeModuleInstalled 'license-checker' -AtVersion '13.1.0'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing specific version of a Node module via RequiresTool attribute''s Version property' {
    try
    {
        Init
        Install-Node
        WhenInstallingTool 'NodeModule::nsp' @{ } -Version '2.7.0'
        ThenNodeModuleInstalled 'nsp' -AtVersion '2.7.0'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'Install-WhiskeyTool.when installing Dotnet and no version specified' {
    Init
    WhenInstallingTool -Name 'Dotnet'
    ThenDotnetPathAddedToTaskParameter
    ThenGlobalJsonVersion (Get-DotnetLatestLTSVersion)
    ThenDotnetSdkVersion (Get-DotnetLatestLTSVersion)
}

Describe 'Install-WhiskeyTool.when installing specific version of Dotnet from whiskey.yml' {
    Init
    GivenGlobalJsonSdkVersion '1.1.5'
    GivenVersionParameterName 'SDKVersion'
    WhenInstallingTool -Name 'Dotnet' -Parameter @{ 'SDKVersion' = '2.1.4' }
    ThenDotnetPathAddedToTaskParameter
    ThenGlobalJsonVersion '2.1.4'
    ThenDotnetSdkVersion '2.1.4'
}

Describe 'Install-WhiskeyTool.when installing specific version of Dotnet from global.json' {
    Init
    GivenGlobalJsonSdkVersion '2.1.4'
    WhenInstallingTool -Name 'Dotnet'
    ThenDotnetPathAddedToTaskParameter
    ThenGlobalJsonVersion '2.1.4'
    ThenDotnetSdkVersion '2.1.4'
}

Describe 'Install-WhiskeyTool.when specified version of dotnet exists globally' {
    Remove-DotnetInstallsFromPath
    try
    {
        Init
        GivenGlobalDotnetInstalled '2.1.4'
        GivenVersionParameterName 'SDKVersion'
        WhenInstallingTool -Name 'Dotnet' -Parameter @{ 'SDKVersion' = '2.1.4' }
        ThenDotnetPathAddedToTaskParameter
        ThenGlobalJsonVersion '2.1.4'
        ThenDotnetNotLocallyInstalled '2.1.4'
    }
    finally
    {
        Restore-OriginalPathEnvironment
    }
}

Describe 'Install-WhiskeyTool.when installing Dotnet and global.json exists in both build root and working directory' {
    Remove-DotnetInstallsFromPath
    try
    {
        Init
        GivenGlobalDotnetInstalled '1.1.5'
        GivenWorkingDirectory 'app'
        GivenGlobalJsonSdkVersion '1.0.1' -Directory $workingDirectory
        GivenGlobalJsonSdkVersion '2.1.4' -Directory $TestDrive.FullName
        GivenVersionParameterName 'SDKVersion'
        WhenInstallingTool -Name 'Dotnet' -Parameter @{ 'SDKVersion' = '1.1.5' }
        ThenGlobalJsonVersion '1.1.5' -Directory $workingDirectory
        ThenGlobalJsonVersion '2.1.4' -Directory $TestDrive.FullName
    }
    finally
    {
        Restore-OriginalPathEnvironment
    }
}
