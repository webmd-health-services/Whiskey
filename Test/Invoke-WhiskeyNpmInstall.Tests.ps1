
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dependency = $null
$devDependency = $null
$failed = $false
$package = @()

function Init
{
    $Global:Error.Clear()
    $script:dependency = $null
    $script:devDependency = $null
    $script:failed = $false
    $script:package = @()
    Install-Node
}

function CreatePackageJson
{
    $packageJsonPath = Join-Path -Path $TestDrive.FullName -ChildPath 'package.json'

    @"
{
    "name": "NPM-Test-App",
    "version": "0.0.1",
    "description": "test",
    "repository": "bitbucket:example/repo",
    "private": true,
    "license": "MIT",
    "dependencies": {
        $($script:dependency -join ',')
    },
    "devDependencies": {
        $($script:devDependency -join ',')
    }
} 
"@ | Set-Content -Path $packageJsonPath -Force

    # If there is no package-lock.json file, npm install writes a notice to STDERR which the ISE interprets as an error, so it bails.
    @'
{
    "name": "NPM-Test-App",
    "version": "0.0.1",
    "lockfileVersion": 1,
    "requires": true,
    "dependencies": {
    }
}
'@ | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath 'package-lock.json')
}

function GivenDependency 
{
    param(
        [object[]]
        $Dependency 
    )
    $script:dependency = $Dependency
}

function GivenDevDependency 
{
    param(
        [object[]]
        $DevDependency 
    )
    $script:devDependency = $DevDependency
}

function GivenFailingNpmInstall
{
    param(
        [string]
        $ErrorMessage
    )

    Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { if( $ErrorActionPreference -ne 'Stop' ) { throw 'You must pass -ErrorAction Stop parameter.' } return true }
}

function GivenPackage
{
    param(
        $Package
    )
    $script:package += $Package
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        [Switch]
        $Global
    )

    $taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $TestDrive.FullName

    $taskParameter = @{ }

    if( $package )
    {
        $taskParameter['Package'] = $package
    }

    if( $Global )
    {
        $taskParameter['Global'] = 'true'
    }

    try
    {
        CreatePackageJson
        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NpmInstall'
    }
    catch
    {
        if( $_ -notmatch '\bnpm\ (notice|warn)\b' )
        {
            $script:failed = $true
            Write-Error -ErrorRecord $_
        }
    }
}

function ThenPackage
{
    param(
        [Parameter(Position=0)]
        [string]
        $PackageName,

        [Parameter(Mandatory=$false,ParameterSetName='Exists')]
        [string]
        $Version,
        
        [Parameter(Mandatory=$true,ParameterSetName='Exists')]
        [switch]
        $Exists,

        [Parameter(Mandatory=$true,ParameterSetName='DoesNotExist')]
        [switch]
        $DoesNotExist,

        [Switch]
        $Global
    )

    $nodeRoot = $TestDrive.FullName 
    if( $Global )
    {
        $nodeRoot = Join-Path -Path $nodeRoot -ChildPath '.node'
    }

    $packagePath = Join-Path -Path $nodeRoot -ChildPath ('node_modules\{0}' -f $PackageName)


    If ($Exists)
    {
        It ('should install package ''{0}''' -f $PackageName) {
            $packagePath | Should -Exist
        }

        if ($Version)
        {
            $packageVersion = Get-Content -Path (Join-Path -Path $packagePath -ChildPath 'package.json') -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'Version'
            It ('''{0}'' should be version ''{1}''' -f $PackageName,$Version) {
                $packageVersion | Should -Be $Version
            }
        }
    }
    else
    {
        It ('should remove package ''{0}''' -f $PackageName) {
            $packagePath | Should -Not -Exist
        }
    }
}

function ThenTaskFailedWithMessage
{
    param(
        $Message
    )

    It 'task should fail' {
        $failed | Should -Be $true
    }

    It ('error message should match [{0}]' -f $Message) {
        $Global:Error | Where-Object { $_ -match $Message } | Should -Not -BeNullOrEmpty
    }
}

function ThenUninstalledModule
{
    param(
        $ModuleName
    )

    It ('should uninstall the ''{0}'' module' -f $ModuleName) {
        Assert-MockCalled -CommandName 'Uninstall-WhiskeyNodeModule' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $ModuleName } -Times 1
    }
}

function ThenTaskSucceeded
{
    It 'should not write any errors' {
        $Global:Error | Where-Object { $_ -notmatch ('\bnpm\ (notice|warn)\b') } | Should -BeNullOrEmpty
    }

    It 'should not fail' {
        $failed | Should -Be $false
    }
}

Describe 'NpmInstall.when ''npm install'' fails' {
    try
    {
        Init
        GivenDependency ('"{0}": "0.0.0"' -f [IO.Path]::GetRandomFileName())
        WhenRunningTask -ErrorAction SilentlyContinue
        $errorMsg = 'npm\ install\b.*\bfailed\ with\ exit\ code\ 1'
        if( $host.Name -eq 'Windows PowerShell ISE Host' )
        {
            $errorMsg = 'npm\ ERR!\ code\ E404'
        }
        ThenTaskFailedWithMessage $errorMsg
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NpmInstall.when installing packages from package.json' {
    try
    {
        Init
        GivenDependency '"wrappy": "^1.0.2"'
        GivenDevDependency '"pify": "^3.0.0"'
        WhenRunningTask
        ThenPackage 'wrappy' -Exists
        ThenPackage 'pify' -Exists
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NpmInstall.when given package' {
    try
    {
        Init
        GivenPackage 'rimraf'
        GivenPackage 'pify'
        GivenDependency '"wrappy": "^1.0.2"'
        WhenRunningTask
        ThenPackage 'rimraf' -Exists
        ThenPackage 'pify' -Exists
        ThenPackage 'wrappy' -DoesNotExist
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NpmInstall.when given package with version number' {
    try
    {
        Init
        GivenPackage 'pify'
        GivenPackage @{ 'wrappy' = '1.0.2' }
        WhenRunningTask
        ThenPackage 'pify' -Exists
        ThenPackage 'wrappy' -Version '1.0.2' -Exists
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NpmInstall.when installing module globally' {
    try
    {
        Init
        GivenPackage 'pify'
        WhenRunningTask -Global
        ThenPackage 'pify' -Exists -Global
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}
