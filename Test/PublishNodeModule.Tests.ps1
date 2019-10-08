
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$npmRegistryUri = $null
$defaultCredID = 'NpmCredentialID'
$defaultUserName = 'npm'
$defaultPassword = 'npm1'
$defaultEmailAddress = 'publishnodemodule@example.com'
$credID = $null
$credential = $null
$parameter = $null
$context = $null
$threwException = $false
$email = $null

function GivenNoCredentialID
{
    $script:credID = $null
}

function GivenNoEmailAddress
{
    $script:email = $null
}

function GivenNoNpmRegistryUri
{
    $script:npmRegistryUri = $null
}

function Init
{
    $script:credID = $defaultCredID
    $script:credential = New-Object 'pscredential' $defaultUserName,(ConvertTo-SecureString -String $defaultPassword -AsPlainText -Force)
    $script:parameter = @{ }
    $script:context = $null
    $script:npmRegistryUri = 'http://registry.npmjs.org/'
    $script:email = $defaultEmailAddress
    Install-Node
}

function New-PublishNodeModuleStructure
{
    param(
    )

    Mock -CommandName 'Remove-Item' -ModuleName 'Whiskey' -ParameterFilter {$Path -match '\.npmrc'}

    $context = New-WhiskeyTestContext -ForBuildServer

    $taskParameter = @{}
    if( $npmRegistryUri )
    {
        $taskParameter['NpmRegistryUri'] = $npmRegistryUri
    }

    $testPackageJsonChildPath = 'package.json'

    $testPackageJsonPath = Join-Path -Path $context.BuildRoot -ChildPath $testPackageJsonChildPath
    $testPackageJson = @"
{
  "name": "publishnodemodule_test",
  "version": "1.2.0",
  "main": "index.js"
}
"@

    $testPackageJsonPath = New-Item -Path $testPackageJsonPath -ItemType File -Value $testPackageJson

    $returnContextParams = @{}
    $returnContextParams.TaskContext = $context
    $returnContextParams.TaskParameter = $taskParameter
    $script:parameter = $taskParameter
    $script:context = $context

    return $returnContextParams
}

function ThenNodeModulePublished
{
    Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $Name -eq 'publish' } -Times 1 -Exactly
}

function ThenNodeModuleIsNotPublished
{
    Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $Name -eq 'publish' } -Times 0 -Exactly
}

function ThenNpmPackagesPruned
{
    Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $Name -eq 'prune' -and $ArgumentList[0] -eq '--production' } -Times 1 -Exactly
}

function ThenNpmrcCreated
{
    param(
        $In
    )

    $buildRoot = $context.BuildRoot
    if( $In )
    {
        $buildRoot = Join-Path -Path $context.BuildRoot -ChildPath $In
    }

    $npmRcPath = Join-Path -Path $buildRoot -ChildPath '.npmrc'

    Test-Path -Path $npmrcPath | Should be $true

    $npmRegistryUri = [uri]$script:npmRegistryUri
    $npmUserName = $credential.UserName
    $npmCredPassword = $credential.GetNetworkCredential().Password
    $npmBytesPassword  = [System.Text.Encoding]::UTF8.GetBytes($npmCredPassword)
    $npmPassword = [System.Convert]::ToBase64String($npmBytesPassword)
    $npmConfigPrefix = '//{0}{1}:' -f $npmRegistryUri.Authority,$npmRegistryUri.LocalPath
    $npmrcFileLine2 = ('{0}_password="{1}"' -f $npmConfigPrefix, $npmPassword)
    $npmrcFileLine3 = ('{0}username={1}' -f $npmConfigPrefix, $npmUserName)
    $npmrcFileLine4 = ('{0}email={1}' -f $npmConfigPrefix, $email)
    $npmrcFileLine5 = ('registry={0}' -f $npmRegistryUri)
    $npmrcFileContents = "$npmrcFileLine2{0}$npmrcFileLine3{0}$npmrcFileLine4{0}$npmrcFileLine5{0}" -f [Environment]::NewLine

    # should populate the .npmrc file with the appropriate configuration values' {
    $actualFileContents = Get-Content -Raw -Path $npmrcPath
    $actualFileContents.Trim() | Should Be $npmrcFileContents.Trim()

    Assert-MockCalled -CommandName 'Remove-Item' -ModuleName 'Whiskey' `
                        -ParameterFilter {$Path -eq $npmRcPath} -Times 1 -Exactly
}

function ThenTaskFailed
{
    param(
        $ExpectedErrorMessagePattern
    )

    $threwException | Should -Be $true

    $Global:Error | Should -Match $ExpectedErrorMessagePattern
}

function WhenPublishingNodeModule
{
    [CmdletBinding()]
    param(
    )

    Mock -CommandName 'Invoke-WhiskeyNpmCommand' `
         -ModuleName 'Whiskey' `
         -ParameterFilter {
            if( $ErrorActionPreference -ne 'Stop' )
            {
                throw 'Invoke-WhiskeyNpmCommand must be called with `-ErrorAction Stop`.'
            }
            return $true
        }

    if( $credID )
    {
        $parameter['CredentialID'] = $credID
    }

    if( $credID -and $credential )
    {
        Add-WhiskeyCredential -Context $context -ID $credID -Credential $credential
    }

    if( $email )
    {
        $parameter['EmailAddress'] = $email
    }
    $script:threwException = $false
    try
    {
        $Global:Error.Clear()
        Invoke-WhiskeyTask -TaskContext $context -Name 'PublishNodeModule' -Parameter $parameter
    }
    catch
    {
        $script:threwException = $true
        $_ | Write-Error
    }
}

Describe 'PublishNodeModule.when publishing node module' {
    It 'should publish the module' {
        try
        {
            Init
            New-PublishNodeModuleStructure
            WhenPublishingNodeModule
            ThenNpmrcCreated
            ThenNpmPackagesPruned
            ThenNodeModulePublished
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'PublishNodeModule.when NPM registry URI property is missing' {
    It 'should fail' {
        try
        {
            Init
            GivenNoNpmRegistryUri
            New-PublishNodeModuleStructure
            WhenPublishingNodeModule -ErrorAction SilentlyContinue
            ThenTaskFailed '\bNpmRegistryUri\b.*\bmandatory\b'
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'PublishNodeModule.when credential ID property missing' {
    It 'should fail' {
        try
        {
            Init
            GivenNoCredentialID
            New-PublishNodeModuleStructure
            WhenPublishingNodeModule -ErrorAction SilentlyContinue
            ThenTaskFailed '\bCredentialID\b.*\bmandatory\b'
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'PublishNodeModule.when email address property missing' {
    It 'should fail' {
        try
        {
            Init
            GivenNoEmailAddress
            New-PublishNodeModuleStructure
            WhenPublishingNodeModule -ErrorAction SilentlyContinue
            ThenTaskFailed '\bEmailAddress\b.*\bmandatory\b'
        }
        finally
        {
            Remove-Node
        }
    }
}
