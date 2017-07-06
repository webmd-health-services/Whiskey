
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$mockPackage = [pscustomobject]@{ }
$mockRelease = [pscustomobject]@{ }
$mockDeploy = [pscustomobject]@{ }
$packageVersion = 'version'
$context = $null

function GivenAnApplication
{
    [CmdletBinding()]
    param(
    )

    $release = $mockRelease
    $package = $mockPackage
    $deploy = $mockDeploy

    $version = [SemVersion.SemanticVersion]'9.8.7-rc.1+build'
    Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -MockWith { return $release }.GetNewClosure()
    Mock -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -MockWith { return $package }.GetNewClosure()
    Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -MockWith { return $deploy }.GetNewClosure()
    Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return $version }.GetNewClosure()
    
    $script:context = New-WhiskeyTestContext -ForApplicationName 'app name' -ForReleaseName 'release name' -ForBuildServer -ForVersion $version
    
}

function GivenNoApplication
{
    $version = [SemVersion.SemanticVersion]'9.8.7-rc.1+build'
    Mock -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' 
    Mock -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' 
    Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' 
    Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith { return $version }.GetNewClosure()

    $script:context = New-WhiskeyTestContext -ForApplicationName 'app name' -ForReleaseName 'release name' -ForBuildServer -ForVersion $version
}

function WhenCreatingPackage
{
    [CmdletBinding()]
    param(
        [hashtable]
        $WithVariables = @{ },

        [Switch]
        $WithNoPackageVersionVariable,
        
        [Switch]
        $ThenPackageNotCreated,

        [string]
        $WithErrorMessage,

        [Switch]
        $ForDeveloper,

        [Switch]
        $ThatDoesNotGetDeployed
    )

    process
    {
        if( -not $WithNoPackageVersionVariable )
        {
            $context.PackageVariables['ProGetPackageVersion'] = $packageVersion
            $context.PackageVariables['ProGetPackageName'] = $packageVersion
        }

        if( $WithVariables )
        {
            foreach( $key in $WithVariables.Keys )
            {
                $Context.PackageVariables[$key] = $WithVariables[$key]
            }
        }
        if( $ForDeveloper )
        {
            $Context.ByDeveloper = $True
        }

        if( $ThatDoesNotGetDeployed )
        {
            $Context.Configuration['DeployPackage'] = $false
        }

        $threwException = $false
        try
        {
            $Global:Error.Clear()
            Publish-WhiskeyBuildMasterPackage -TaskContext $context 
        }
        catch
        {
            $threwException = $true
            Write-Error $_
        }

        if( $ThenPackageNotCreated )
        {
            It 'should throw an exception' {
                $threwException | Should Be $true
            }

            It 'should write an errors' {
                $Global:Error | Should Match $WithErrorMessage
            }
        }
        else
        {
            It 'should not throw an exception' {
                $threwException | Should Be $false
            }

            It 'should not write any errors' {
                $Global:Error | Should BeNullOrEmpty
            }
        }

        return $Context
    }
}

function ThenItFails
{
    It 'should not create release package' {
        Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -Times 0
    }

    It 'should not start deploy' {
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -Times 0
    }
}

function ThenPackageCreated
{
    [CmdletBinding()]
    param(
        [hashtable]
        $WithVariables = @{}
    )

    process
    {
        It 'should get the release' {
            Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey'
        }

        It 'should get the release using the context''s session' {
            Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { [object]::ReferenceEquals($Context.BuildMasterSession,$Session) }
        }

        It 'should get the release using the context''s release name' {
            Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -ParameterFilter { $Name -eq $Context.ReleaseName }
        }

        It 'should create release package' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey'
        }

        It 'should create release package using the context''s session' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { [object]::ReferenceEquals($Context.BuildMasterSession,$Session) }
        }

        It 'should create release package for the release' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { [object]::ReferenceEquals($mockRelease, $Release) }
        }

        It 'should create release package with package number' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { $PackageNumber -eq ('{0}.{1}.{2}' -f $Context.Version.SemVer2.Major,$Context.Version.SemVer2.Minor,$Context.Version.SemVer2.Patch) }
        }

        $expectedVariables = @{
                                    'ProGetPackageVersion' = $packageVersion;
                                    'ProGetPackageName' = $packageVersion;
                              }
        foreach( $key in $WithVariables.Keys )
        {
            $expectedVariables[$key] = $WithVariables[$key]
        }

        foreach( $variableName in $expectedVariables.Keys )
        {
            $variableValue = $expectedVariables[$variableName]
            It ('should create {0} package variable' -f $variableName) {
                Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { 
                    #$DebugPreference = 'Continue'
                    Write-Debug ('Expected  {0}' -f $variableValue)
                    Write-Debug ('Actual    {0}' -f $Variable[$variableName])
                    $Variable.ContainsKey($variableName) -and $Variable[$variableName] -eq $variableValue
                }
            }
        }

        It 'should start the package''s release pipeline' {
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey'
        }

        It 'should start the package''s release pipeline using the context''s session' {
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { [object]::ReferenceEquals($Context.BuildMasterSession,$Session) }
        }

        It 'should start the package''s release pipeline using the newly created package' {
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -ParameterFilter { [object]::ReferenceEquals($mockPackage,$Package) }
        }
    }
}

function ThenPackageNotCreated
{
    [CmdletBinding()]
    param(
    )

    process
    {
        It 'should not get releases' {
            Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'Whiskey' -Times 0
        }
        It 'should not create release package' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'Whiskey' -Times 0
        }
        It 'should not start deploy' {
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'Whiskey' -Times 0
        }
    }
}

Describe 'Publish-WhiskeyBuildMasterPackage.when called by build server' {
    GivenAnApplication
    WhenCreatingPackage
    ThenPackageCreated
}

Describe 'Publish-WhiskeyBuildMasterPackage.when using custom package variables' {
    $variables = @{ 
                        'Fubar' = 'Snafu';
                        'Snafu' = 'Fubuar';
                   }
    GivenAnApplication
    WhenCreatingPackage -WithVariables $variables
    ThenPackageCreated -WithVariables $variables
}

Describe 'Publish-WhiskeyBuildMasterPackage.when using custom package variables' {
    GivenAnApplication
    WhenCreatingPackage -WithNoPackageVersionVariable
    ThenPackageNotCreated
}

Describe 'Publish-WhiskeyBuildMasterPackage.when called by a developer' {
    GivenAnApplication
    WhenCreatingPackage -ForDeveloper
    ThenPackageNotCreated
}

Describe 'Publish-WhiskeyBuildMasterPackage.when called by a developer' {
    GivenAnApplication
    WhenCreatingPackage -ThatDoesNotGetDeployed
    ThenPackageNotCreated
}

Describe 'Publish-WhiskeyBuildMasterPackage.when application doesn''t exist in BuildMaster' {
    GivenNoApplication
    WhenCreatingPackage -WithErrorMessage 'unable to create and deploy a release package' -ThenPackageNotCreated -ErrorAction SilentlyContinue
    ThenItFails
}
