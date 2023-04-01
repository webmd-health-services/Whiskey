
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:credential = $null
    $script:context = $null
    $script:packageJsonPath = $null
    $script:prerelease = $null
    $script:testRoot = $null
    $script:threwException = $false

    function GivenPackageJson
    {
        param(
            $Content
        )

        $script:packageJsonPath = Join-Path -Path $script:testRoot -ChildPath 'package.json'
        New-Item -Path $script:packageJsonPath -ItemType File -Value $Content -Force | Out-Null
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
                            -Times 1 `
                            -Exactly `
                            -ParameterFilter {
                                if( $Name -ne 'publish' )
                                {
                                    return $false
                                }

                                $PesterBoundParameters['ErrorAction'] |
                                    Should -Be 'Stop' -Because 'Invoke-NpmCommand "publish" should throw a terminating error if it fails'
                                return $true
                            }
    }

    function ThenNodeModuleIsNotPublished
    {
        Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                            -ModuleName 'Whiskey' `
                            -Times 0 `
                            -Exactly `
                            -ParameterFilter { $Name -eq 'publish' }
    }

    function ThenNodeModuleVersionUpdated
    {
        param(
            [Alias('To')]
            $Version
        )

        Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                            -ModuleName 'Whiskey' `
                            -Times 1 `
                            -Exactly `
                            -ParameterFilter {
                                if( $Name -ne 'version')
                                {
                                    return $false
                                }

                                $Version | Should -BeIn $ArgumentList -Because 'Invoke-NpmCommand "version" should be called with expected version'
                                '--no-git-tag-version' | Should -BeIn $ArgumentList -Because 'Invoke-NpmCommand "version" should not create a new git commit and tag'
                                '--allow-same-version' | Should -BeIn $ArgumentList -Because 'Invoke-NpmCommand "version" should not fail when version in package.json matches given version'
                                $ArgumentList | Should -HaveCount 3 -Because 'Invoke-NpmCommand "version" shouldn''t be called with extra arguments'
                                $PesterBoundParameters['ErrorAction'] |
                                    Should -Be 'Stop' -Because 'Invoke-NpmCommand "version" should throw a terminating error if it fails'

                                return $true
                            }
    }

    function ThenNpmPackagesPruned
    {
        Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                            -ModuleName 'Whiskey' `
                            -Times 1 `
                            -Exactly `
                            -ParameterFilter {
                                if( $Name -ne 'prune')
                                {
                                    return $false
                                }

                                $ArgumentList | Should -HaveCount 1 -Because 'Invoke-NpmCommand "prune" shouldn''t be called with extra arguments'
                                $PesterBoundParameters['ErrorAction'] |
                                    Should -Be 'Stop' -Because 'Invoke-NpmCommand "prune" should throw a terminating error if it fails'

                                return $true
                            }
    }

    function ThenNpmrcCreated
    {
        param(
            [String]$WithEmail,
            [Uri]$WithRegistry
        )

        $buildRoot = $script:context.BuildRoot

        $npmRcPath = Join-Path -Path $buildRoot -ChildPath '.npmrc'
        $npmRcPath | Should -Exist

        $npmUserName = $script:credential.UserName
        $npmCredPassword = $script:credential.GetNetworkCredential().Password
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

        Assert-MockCalled   -CommandName 'Remove-Item' `
                            -ModuleName 'Whiskey' `
                            -Times 1 `
                            -Exactly `
                            -ParameterFilter {
                                $Path | Should -Be $npmRcPath -Because 'it should remove the temporary local .npmrc file'
                                return $true
                            }
    }

    function ThenPackageJsonVersion
    {
        param(
            [Alias('Is')]
            $ExpectedVersion
        )

        $packageJson = Get-Content -Path $script:packageJsonPath -Raw | ConvertFrom-Json
        $packageJson | Select-Object -ExpandProperty 'version' | Should -Be $ExpectedVersion
    }

    function ThenPublishedWithTag
    {
        [CmdletBinding(DefaultParameterSetName='ExpectedTag')]
        param(
            [Parameter(Mandatory,Position=0,ParameterSetName='ExpectedTag')]
            [String]$ExpectedTag,

            [Parameter(ParameterSetName='None')]
            [switch]$None
        )

        $parameterFilter = {
            if( $Name -ne 'publish')
            {
                return $false
            }

            if( $ExpectedTag )
            {
                '--tag' |
                    Should -BeIn $ArgumentList -Because 'Invoke-NpmCommand "publish" missing "--tag" argument'
                $ExpectedTag |
                    Should -BeIn $ArgumentList -Because 'Invoke-NpmCommand "publish" unexpected tag argument'
                $ArgumentList |
                    Should -HaveCount 2 -Because 'Invoke-NpmCommand "publish" shouldn''t be called with extra arguments'
            }
            elseif( $None )
            {
                $ArgumentList |
                    Should -HaveCount 0 -Because 'Invoke-NpmCommand "publish" has tag arguments'
            }

            $PesterBoundParameters['ErrorAction'] |
                Should -Be 'Stop' -Because 'Invoke-NpmCommand "publish" should throw a terminating error if it fails'

            return $true
        }

        Assert-MockCalled   -CommandName 'Invoke-WhiskeyNpmCommand' `
                            -ModuleName 'Whiskey' `
                            -Times 1 `
                            -Exactly `
                            -ParameterFilter $parameterFilter
    }

    function ThenTaskFailed
    {
        param(
            $ExpectedErrorMessagePattern
        )

        $script:threwException | Should -BeTrue

        $Global:Error | Should -Match $ExpectedErrorMessagePattern
    }

    function WhenPublishingNodeModule
    {
        [CmdletBinding()]
        param(
            [String]$WithCredentialID,
            [String]$WithEmailAddress,
            [String]$WithNpmRegistryUri,
            [String]$WithTag
        )

        Mock -CommandName 'Invoke-WhiskeyNpmCommand' -ModuleName 'Whiskey' -ParameterFilter { $Name -ne 'version' }
        Mock -CommandName 'Remove-Item' -ModuleName 'Whiskey' -ParameterFilter { $Path -match '\.npmrc' }

        $version =
            Get-Content -Path $script:packageJsonPath -Raw | ConvertFrom-Json | Select-Object -ExpandProperty 'version'
        if( $script:prerelease )
        {
            $version = '{0}-{1}' -f $version, $script:prerelease
        }

        $script:context = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $script:testRoot -ForVersion $version

        $parameter = @{ }
        if( $WithCredentialID )
        {
            $parameter['CredentialID'] = $WithCredentialID
            Add-WhiskeyCredential -Context $script:context -ID $WithCredentialID -Credential $script:credential
        }

        if( $WithEmailAddress )
        {
            $parameter['EmailAddress'] = $WithEmailAddress
        }

        if( $WithNpmRegistryUri )
        {
            $parameter['NpmRegistryUri'] = $WithNpmRegistryuri
        }

        if( $WithTag )
        {
            $parameter['Tag'] = $WithTag
        }

        $script:threwException = $false
        $Global:Error.Clear()

        try
        {
            Invoke-WhiskeyTask -TaskContext $script:context -Name 'PublishNodeModule' -Parameter $parameter
        }
        catch
        {
            $script:threwException = $true
            Write-Error -ErrorRecord $_
        }
    }
}

Describe 'PublishNodeModule' {
    BeforeEach {
        $script:credential =
            [pscredential]::New('npmusername',(ConvertTo-SecureString -String 'npmpassword' -AsPlainText -Force))
        $script:context = $null
        $script:packageJsonPath = $null
        $script:prerelease = $null
        $script:testRoot = New-WhiskeyTestRoot
        $script:threwException = $false

        Install-Node -BuildRoot $script:testRoot
    }

    AfterEach {
        Remove-Node -BuildRoot $script:testRoot
    }

    It 'should publish the module' {
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
        ThenPublishedWithTag -None
    }

    It 'should validate NPM registry URI property' {
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

    It 'should validate credential ID property' {
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

    It 'should validate email address' {
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

    Context 'mocked "npm version" command' {
        It 'should publish module with the prerelease version' {
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
            ThenPublishedWithTag 'alpha'
        }
    }

    Context 'un-mocked "npm version" command' {
        It 'should restore non-prerelease version in package.json after publishing' {
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

    It 'should publish the module with tag' {
        GivenPackageJson @"
        {
            "name": "publishnodemodule_test",
            "version": "1.2.0"
        }
"@
        WhenPublishingNodeModule -WithCredentialID 'NpmCred' `
                                 -WithEmailAddress 'somebody@example.com' `
                                 -WithNpmRegistryUri 'http://registry@example.com' `
                                 -WithTag 'mytag'
        ThenNodeModulePublished
        ThenPublishedWithTag 'mytag'
    }

    It 'should publish the module with prerelease version and a tag' {
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
                                 -WithNpmRegistryUri 'http://registry@example.com' `
                                 -WithTag 'mytag'
        ThenNodeModuleVersionUpdated -To '1.2.0-alpha.1'
        ThenNpmPackagesPruned
        ThenNodeModulePublished
        ThenPublishedWithTag 'mytag'
    }
}
