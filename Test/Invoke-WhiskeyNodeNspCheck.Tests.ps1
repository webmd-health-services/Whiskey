
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$dependency = $null
$devDependency = $null
$failed = $false
$output = $null
$version = $null

function Init
{
    param(
        [Switch]
        $NoNsp
    )

    $script:dependency = $null
    $script:devDependency = $null
    $Global:Error.Clear()
    $script:failed = $false
    $script:output = $null
    $script:version = $null
    $withModule = @{ WithModule = 'nsp' }
    if( $NoNsp )
    {
        $withModule = @{ }
    }
    Install-Node @withModule
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

    @"
{
    "name": "NPM-Test-App",
    "version": "0.0.1",
    "lockfileVersion": 1,
    "requires": true,
    "dependencies": {
    }
}
"@ | Set-Content -Path ($packageJsonPath -replace '\bpackage\.json','package-lock.json') -Force
}

function MockNsp
{
    param(
        [switch]
        $Failing
    )

    if (-not $Failing)
    {
        Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'check' } -MockWith { & cmd /c 'ECHO [] && exit 0' }
    }
    else
    {
        Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'check' } -MockWith { & cmd /c 'ECHO An error has occured && exit 1' }
    }
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

function GivenVersion
{
    param(
        $WithVersion
    )

    $script:version = $WithVersion
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
    )

    $Global:Error.Clear()

    $taskContext = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $TestDrive.FullName

    $taskParameter = @{ }

    if ($version)
    {
        $taskParameter['Version'] = $version
    }

    try
    {
        CreatePackageJson

        Invoke-WhiskeyTask -TaskContext $taskContext -Parameter $taskParameter -Name 'NodeNspCheck'
    }
    catch
    {
        $script:failed = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenNspInstalled
{
    param(
        $WithVersion
    )

    $nspRoot = Join-Path -Path $TestDrive.FullName -ChildPath '.node\node_modules\nsp'
    It 'should install NSP module' {
        $nspRoot | Should -Exist
    }

    if( $WithVersion )
    {
        It ('should install NSP version ''{0}''' -f $WithVersion) {
            Get-Content -Path (Join-Path -Path $nspRoot -ChildPath 'package.json') -Raw |
                ConvertFrom-Json |
                Select-Object -ExpandProperty 'Version' |
                Should -Be $WithVersion
        }
    }
}

function ThenNspNotRun
{
    It 'should not run ''nsp check''' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'check' } -Times 0
    }
}

function ThenNspRan
{
    param(
        $WithVersion
    )

    It 'should run ''nsp check''' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'check' } -Times 1
    }

    if( $WithVersion )
    {
        if( $WithVersion -ge (ConvertTo-WhiskeySemanticVersion -InputObject '3.0.0') )
        {
            It 'should run ''nsp check'' with ''--reporter'' json formatting argument' {
                Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $argumentList -eq '--reporter' } -Times 1
            }
        }
        else
        {
            It 'should run ''nsp check'' with ''--output'' json formatting argument' {
                Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $argumentList -eq '--output' } -Times 1
            }
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
        $Global:Error[0] | Should -Match $Message
    }
}

function ThenTaskSucceeded
{
    for( $i = $Global:Error.Count - 1; $i -ge 0; $i-- )
    {
        $errorMessage = $Global:Error[$i]
        if( $errorMessage -match 'npm notice created a lockfile as package-lock.json. You should commit this file.' )
        {
            $Global:Error.RemoveAt($i)
        }
        elseif( $errorMessage -match ([regex]::Escape('The Node Security Platform service is shutting down 9/30')) )
        {
            $Global:Error.RemoveAt($i)
        }
    }

    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'should not fail' {
        $failed | Should -Be $false
    }
}

Describe 'NodeNspCheck.when running nsp check' {
    try
    {
        Init
        MockNsp
        WhenRunningTask
        ThenNspInstalled
        ThenNspRan
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NodeNspCheck.when module has a security vulnerability' {
    try
    {
        Init
        GivenDependency '"minimatch": "3.0.0"'
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'found the following security vulnerabilities'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NodeNspCheck.when nsp does not return valid JSON' {
    try
    {
        Init
        MockNsp -Failing
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailedWithMessage 'did not return valid JSON'
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NodeNspCheck.when running nsp check specifically with v2.7.0' {
    try
    {
        Init -NoNsp
        GivenVersion '2.7.0'
        MockNsp
        WhenRunningTask
        ThenNspInstalled -WithVersion '2.7.0'
        ThenNspRan -WithVersion '2.7.0'
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}

Describe 'NodeNspCheck.when running nsp check specifically with v3.1.0' {
    try
    {
        Init -NoNsp
        GivenVersion '3.1.0'
        MockNsp
        WhenRunningTask
        ThenNspInstalled -WithVersion '3.1.0'
        ThenNspRan -WithVersion '3.1.0'
        ThenTaskSucceeded
    }
    finally
    {
        Remove-Node
    }
}
