
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
$workingDirectory = $null
$threwException = $false
$email = $null
$npmVersion = $null

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

function GivenNpmVersion
{
    param(
        $Version
    )

    $script:npmVersion = ('"npm": "{0}",' -f $Version)
}

function GivenNpmReturnsNonZeroExitCode
{
    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter {$ScriptBlock -match 'publish'} -MockWith { & cmd /c exit 1 }
}

function GivenWorkingDirectory
{
    param(
        $Path
    )

    $script:workingDirectory = $Path
    New-Item -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Path) -ItemType 'Directory' -Force
}

function Init
{
    $script:credID = $defaultCredID
    $script:credential = New-Object 'pscredential' $defaultUserName,(ConvertTo-SecureString -String $defaultPassword -AsPlainText -Force)
    $script:parameter = @{ }
    $script:context = $null
    $script:workingDirectory = $null
    $script:npmRegistryUri = 'http://registry.npmjs.org/'
    $script:email = $defaultEmailAddress
    $script:npmVersion = $null
}

function GivenWithInitilizeFlag
{
    $script:context.RunMode = 'initialize'
    $nvmPath = Join-Path $context.BuildRoot -ChildPath '\nvm\v4.4.7\node.exe'
    Mock -CommandName 'Install-WhiskeyNodeJs' -ModuleName 'Whiskey' {$nvmPath}.GetNewClosure()
}
function New-PublishNodeModuleStructure
{
    param(
    )

    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter {$ScriptBlock -match 'publish'}
    Mock -CommandName 'Remove-Item' -ModuleName 'Whiskey' -ParameterFilter {$Path -match '\.npmrc'}

    $context = New-WhiskeyTestContext -ForBuildServer
    
    $taskParameter = @{}
    if( $npmRegistryUri )
    {
        $taskParameter['NpmRegistryUri'] = $npmRegistryUri
    }

    $testPackageJsonChildPath = 'package.json'

    if ($workingDirectory)
    {
        $taskParameter['WorkingDirectory'] = $workingDirectory
        $testPackageJsonChildPath = (Join-Path -Path $workingDirectory -ChildPath 'package.json')
    }

    $testPackageJsonPath = Join-Path -Path $context.BuildRoot -ChildPath $testPackageJsonChildPath
    $testPackageJson = @"
{
  "name": "publishnodemodule_test",
  "version": "1.2.0",
  "main": "index.js",
  "engines": {
    $($script:npmVersion)
    "node": "^4.4.7"
  }
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

function ThenNodeShouldExist
{
    It 'should have a nodejs installed' {
        Assert-MockCalled   -CommandName 'Install-WhiskeyNodeJs' `
                            -ModuleName 'Whiskey' `
                            -Times 1 -Exactly
    }
}

function ThenNodeModulePublished
{
    It ('should publish the module') {
        Assert-MockCalled   -CommandName 'Invoke-Command' -ModuleName 'Whiskey' `
                            -ParameterFilter {$ScriptBlock -match 'publish'} -Times 1 -Exactly
    }
}

function ThenNodeModuleIsNotPublished
{
    It 'should not publish the module' {
        Assert-MockCalled   -CommandName 'Invoke-Command' -ModuleName 'Whiskey' `
                            -ParameterFilter {$ScriptBlock -match 'publish'} -Times 0 -Exactly
    }
}

function ThenLocalNpmCleanedUp
{
    $npmPath = (Join-Path -Path $context.BuildRoot -ChildPath 'node_modules\npm\bin\npm-cli.js')

    It 'should remove the local version of npm after publishing' {
        $npmPath | Should -Not -Exist
    }
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

    It ('should create a temporary .npmrc file in {0}' -f $buildRoot) {
        Test-Path -Path $npmrcPath | Should be $true
    }

    $npmRegistryUri = [uri]$script:npmRegistryUri
    $npmUserName = $credential.UserName
    $npmCredPassword = $credential.GetNetworkCredential().Password
    $npmBytesPassword  = [System.Text.Encoding]::UTF8.GetBytes($npmCredPassword)
    $npmPassword = [System.Convert]::ToBase64String($npmBytesPassword)
    $npmConfigPrefix = '//{0}{1}:' -f $npmRegistryUri.Authority,$npmRegistryUri.LocalPath
    $npmrcFileLine2 = ('{0}_password="{1}"' -f $npmConfigPrefix, $npmPassword)
    $npmrcFileLine3 = ('{0}username={1}' -f $npmConfigPrefix, $npmUserName)
    $npmrcFileLine4 = ('{0}email={1}' -f $npmConfigPrefix, $email)
    $npmrcFileContents = @"
$npmrcFileLine2
$npmrcFileLine3
$npmrcFileLine4
"@

    It ('.npmrc file should be{0}{1}' -f [Environment]::newLine,$npmrcFileLine2){
        # should populate the .npmrc file with the appropriate configuration values' {
        $actualFileContents = Get-Content -Raw -Path $npmrcPath
        $actualFileContents.Trim() | Should Be $npmrcFileContents.Trim()
    }

    It ('should remove {0}' -f $npmRcPath) {
        Assert-MockCalled -CommandName 'Remove-Item' -ModuleName 'Whiskey' `
                          -ParameterFilter {$Path -eq $npmRcPath} -Times 1 -Exactly
    }
}

function ThenTaskFailed
{
    param(
        $ExpectedErrorMessagePattern
    )

    It ('the task should throw an exception') {
        $threwException | Should -Be $true
    }

    It ('should fail with error message /{0}/' -f $ExpectedErrorMessagePattern) {
        $Global:Error | Should -Match $ExpectedErrorMessagePattern
    }
}

function WhenPublishingNodeModule
{
    [CmdletBinding()]
    param(
    )

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
    Init
    New-PublishNodeModuleStructure
    WhenPublishingNodeModule
    ThenNpmrcCreated
    ThenNodeModulePublished
}

Describe 'PublishNodeModule.when publishing node module from custom working directory' {
    Init
    GivenWorkingDirectory 'App'
    New-PublishNodeModuleStructure
    WhenPublishingNodeModule
    ThenNpmrcCreated -In 'App'
    ThenNodeModulePublished    
}

Describe 'PublishNodeModule.when NPM registry URI property is missing' {
    Init
    GivenNoNpmRegistryUri
    New-PublishNodeModuleStructure
    WhenPublishingNodeModule -ErrorAction SilentlyContinue
    ThenTaskFailed '\bNpmRegistryUri\b.*\bmandatory\b'
}

Describe 'PublishNodeModule.when credential ID property missing' {
    Init
    GivenNoCredentialID
    New-PublishNodeModuleStructure
    WhenPublishingNodeModule -ErrorAction SilentlyContinue
    ThenTaskFailed '\bCredentialID\b.*\bmandatory\b'
}

Describe 'PublishNodeModule.when email address property missing' {
    Init
    GivenNoEmailAddress
    New-PublishNodeModuleStructure
    WhenPublishingNodeModule -ErrorAction SilentlyContinue
    ThenTaskFailed '\bEmailAddress\b.*\bmandatory\b'
}

Describe 'PublishNodeModule.when publishing node module with initialization mode' {
    Init
    New-PublishNodeModuleStructure
    GivenWithInitilizeFlag
    WhenPublishingNodeModule
    ThenNodeShouldExist
    ThenNodeModuleIsNotPublished
}
Describe 'PublishNodeModule.when publishing node module using specific version of npm' {
    Init
    GivenNPMVersion '~4.6.1'
    New-PublishNodeModuleStructure
    WhenPublishingNodeModule
    ThenNpmrcCreated
    ThenLocalNpmCleanedUp
}

Describe 'PublishNodeModule.when npm publish returns non-zero exit code' {
    Init
    New-PublishNodeModuleStructure
    GivenNpmReturnsNonZeroExitCode
    WhenPublishingNodeModule -ErrorAction SilentlyContinue
    ThenNpmrcCreated
    ThenTaskFailed 'NPM command ''npm publish'' failed with exit code ''1'''
}
