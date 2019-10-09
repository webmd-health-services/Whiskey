
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$credential = $null
$context = $null
$packageJsonPath = $null
$prerelease = $null
$threwException = $false

function Init
{
    $script:credential = New-Object 'pscredential' 'npmusername',(ConvertTo-SecureString -String 'npmpassword' -AsPlainText -Force)
    $script:context = $null
    $script:packageJsonPath = $null
    $script:prerelease = $null
    $script:threwException = $false

    Install-Node
}

function GivenPackageJson
{
    param(
        $Content
    )

    $script:packageJsonPath = Join-Path -Path $TestDrive.Fullname -ChildPath 'package.json'
    New-Item -Path $packageJsonPath -ItemType File -Value $Content -Force | Out-Null
}

function GivenPrerelease
{
    param(
        $Prerelease
    )

    $script:prerelease = $Prerelease
}

function ThenNodeModulePublished
{
    Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $Name -eq 'publish' -and $ErrorActionPreference -eq 'Stop' } `
                        -Times 1 -Exactly
}

function ThenNodeModuleIsNotPublished
{
    Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter { $Name -eq 'publish' } `
                        -Times 0 -Exactly
}

function ThenNodeModuleVersionUpdated
{
    param(
        [Alias('To')]
        $Version
    )

    Assert-MockCalled -CommandName 'Invoke-WhiskeyNpmCommand' `
                      -ModuleName 'Whiskey' `
                      -Times 1 -Exactly `
                      -ParameterFilter {
                          if( $Name -ne 'version')
                          {
                              return $false
                          }

                          # $DebugPreference = 'Continue'
                          Write-Debug -Message ('NPM Command Name: "{0}"' -f $Name)

                          $expectedArguments = @($Version, '--no-git-tag-version', '--allow-same-version')
                          Write-Debug -Message ('ArgumentList expected "{0}"' -f ($expectedArguments -join '", "'))
                          Write-Debug -Message ('ArgumentList actual   "{0}"' -f ($ArgumentList -join '", "'))

                          foreach ($argument in $expectedArguments)
                          {
                              if( $argument -notin $ArgumentList )
                              {
                                  return $false
                              }
                          }

                          return $true
                      }
}

function ThenNpmPackagesPruned
{
    Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                        -ModuleName 'Whiskey' `
                        -ParameterFilter {
                            $Name -eq 'prune' -and
                            $ArgumentList[0] -eq '--production' -and
                            $ErrorActionPreference -eq 'Stop'
                        } `
                        -Times 1 -Exactly
}

function ThenNpmrcCreated
{
    param(
        [string]$WithEmail,
        [uri]$WithRegistry
    )

    $buildRoot = $context.BuildRoot

    $npmRcPath = Join-Path -Path $buildRoot -ChildPath '.npmrc'
    $npmRcPath | Should -Exist

    $npmUserName = $credential.UserName
    $npmCredPassword = $credential.GetNetworkCredential().Password
    $npmBytesPassword  = [System.Text.Encoding]::UTF8.GetBytes($npmCredPassword)
    $npmPassword = [System.Convert]::ToBase64String($npmBytesPassword)
    $npmConfigPrefix = '//{0}{1}:' -f $WithRegistry.Authority,$WithRegistry.LocalPath
    $npmrcFileLine2 = ('{0}_password="{1}"' -f $npmConfigPrefix, $npmPassword)
    $npmrcFileLine3 = ('{0}username={1}' -f $npmConfigPrefix, $npmUserName)
    $npmrcFileLine4 = ('{0}email={1}' -f $npmConfigPrefix, $WithEmail)
    $npmrcFileLine5 = ('registry={0}' -f $WithRegistry)
    $npmrcFileContents = "$npmrcFileLine2{0}$npmrcFileLine3{0}$npmrcFileLine4{0}$npmrcFileLine5{0}" -f [Environment]::NewLine

    # should populate the .npmrc file with the appropriate configuration values' {
    $actualFileContents = Get-Content -Raw -Path $npmrcPath
    $actualFileContents.Trim() | Should -Be $npmrcFileContents.Trim()

    Assert-MockCalled -CommandName 'Remove-Item' -ModuleName 'Whiskey' `
                        -ParameterFilter {$Path -eq $npmRcPath} -Times 1 -Exactly
}

function ThenPackageJsonVersion
{
    param(
        [Alias('Is')]
        $ExpectedVersion
    )

    $packageJson = Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json
    $packageJson | Select-Object -ExpandProperty 'version' | Should -Be $ExpectedVersion
}

function ThenTaskFailed
{
    param(
        $ExpectedErrorMessagePattern
    )

    $threwException | Should -BeTrue

    $Global:Error | Should -Match $ExpectedErrorMessagePattern
}

function WhenPublishingNodeModule
{
    [CmdletBinding()]
    param(
        [string]$WithCredentialID,
        [string]$WithEmailAddress,
        [string]$WithNpmRegistryUri
    )

    Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $Name -ne 'version' }
    Mock -CommandName 'Remove-Item' -ModuleName 'Whiskey' -ParameterFilter { $Path -match '\.npmrc' }

    $version = Get-Content -Path $packageJsonPath -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'version'
    if( $prerelease )
    {
        $version = '{0}-{1}' -f $version, $prerelease
    }

    $script:context = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $TestDrive.FullName -ForVersion $version

    $parameter = @{ }
    if( $WithCredentialID )
    {
        $parameter['CredentialID'] = $WithCredentialID
        Add-WhiskeyCredential -Context $context -ID $WithCredentialID -Credential $credential
    }

    if( $WithEmailAddress )
    {
        $parameter['EmailAddress'] = $WithEmailAddress
    }

    if( $WithNpmRegistryUri )
    {
        $parameter['NpmRegistryUri'] = $WithNpmRegistryuri
    }

    $script:threwException = $false
    $Global:Error.Clear()

    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name 'PublishNodeModule' -Parameter $parameter
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }
}

Describe 'PublishNodeModule.when publishing node module' {
    It 'should publish the module' {
        try
        {
            Init
            GivenPackageJson @"
            {
                "name": "publishnodemodule_test",
                "version": "1.2.0"
            }
"@
            WhenPublishingNodeModule -WithCredentialID 'NpmCred' `
                                     -WithEmailAddress 'somebody@example.com' `
                                     -WithNpmRegistryUri 'http://registry@example.com'
            ThenNpmrcCreated -WithEmail 'somebody@example.com' -WithRegistry 'http://registry@example.com'
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
            GivenPackageJson @"
            {
                "name": "publishnodemodule_test",
                "version": "1.2.0"
            }
"@
            WhenPublishingNodeModule -WithCredentialID 'NpmCred' `
                                     -WithEmailAddress 'somebody@example.com' `
                                     -ErrorAction SilentlyContinue
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
            GivenPackageJson @"
            {
                "name": "publishnodemodule_test",
                "version": "1.2.0"
            }
"@
            WhenPublishingNodeModule -WithEmailAddress 'somebody@example.com' `
                                     -WithNpmRegistryUri 'http://registry@example.com' `
                                     -ErrorAction SilentlyContinue
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
            GivenPackageJson @"
            {
                "name": "publishnodemodule_test",
                "version": "1.2.0"
            }
"@
            WhenPublishingNodeModule -WithCredentialID 'NpmCred' `
                                     -WithNpmRegistryUri 'http://registry@example.com' `
                                     -ErrorAction SilentlyContinue
            ThenTaskFailed '\bEmailAddress\b.*\bmandatory\b'
        }
        finally
        {
            Remove-Node
        }
    }
}

Describe 'PublishNodeModule.when publishing node module with prerelease version' {
    try
    {
        Context 'mocked "npm version" command' {
            It 'should publish module with the prerelease version' {
                Init
                GivenPackageJson @"
                {
                    "name": "publishnodemodule_test",
                    "version": "1.2.0"
                }
"@
                GivenPrerelease 'alpha.1'
                Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq 'version' }
                WhenPublishingNodeModule -WithCredentialID 'NpmCred' `
                                        -WithEmailAddress 'somebody@example.com' `
                                        -WithNpmRegistryUri 'http://registry@example.com'
                ThenNpmrcCreated -WithEmail 'somebody@example.com' -WithRegistry 'http://registry@example.com'
                ThenNodeModuleVersionUpdated -To '1.2.0-alpha.1'
                ThenNpmPackagesPruned
                ThenNodeModulePublished
            }
        }

        Context 'un-mocked "npm version" command' {
            It 'should restore non-prerelease version in package.json after publishing' {
                Init
                GivenPackageJson @"
                {
                    "name": "publishnodemodule_test",
                    "version": "1.2.0"
                }
"@
                GivenPrerelease 'alpha.1'
                WhenPublishingNodeModule -WithCredentialID 'NpmCred' `
                                        -WithEmailAddress 'somebody@example.com' `
                                        -WithNpmRegistryUri 'http://registry@example.com'
                ThenNpmrcCreated -WithEmail 'somebody@example.com' -WithRegistry 'http://registry@example.com'
                ThenNpmPackagesPruned
                ThenNodeModulePublished
                ThenPackageJsonVersion -Is '1.2.0'
            }
        }
    }
    finally
    {
        Remove-Node
    }
}