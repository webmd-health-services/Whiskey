
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$mockPackage = [pscustomobject]@{ }
$mockRelease = [pscustomobject]@{ }
$mockDeploy = [pscustomobject]@{ }
$packageVersion = 'version'

function GivenAnApplication
{
    [CmdletBinding()]
    param(
    )

    $release = $mockRelease
    $package = $mockPackage
    $deploy = $mockDeploy

    $version = [SemVersion.SemanticVersion]'9.8.7-rc.1+build'
    Mock -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' -MockWith { return $release }.GetNewClosure()
    Mock -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -MockWith { return $package }.GetNewClosure()
    Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -MockWith { return $deploy }.GetNewClosure()
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return $version }.GetNewClosure()
    
    New-WhsCITestContext -ForApplicationName 'app name' -ForReleaseName 'release name' -ForBuildServer -ForVersion $version
    
}

function GivenNoApplication
{
    $version = [SemVersion.SemanticVersion]'9.8.7-rc.1+build'
    Mock -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' 
    Mock -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' 
    Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' 
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith { return $version }.GetNewClosure()

    New-WhsCITestContext -ForApplicationName 'app name' -ForReleaseName 'release name' -ForBuildServer -ForVersion $version
}

function WhenCreatingPackage
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context,

        [hashtable]
        $WithVariables = @{ },

        [Switch]
        $WithNoPackageVersionVariable,
        
        [Switch]
        $ThenPackageNotCreated,

        [string]
        $WithErrorMessage,

        [Switch]
        $ForDeveloper
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
        $threwException = $false
        try
        {
            $Global:Error.Clear()
            New-WhsCIBuildMasterPackage -TaskContext $Context | Out-Null
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
        Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -Times 0
    }

    It 'should not start deploy' {
        Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -Times 0
    }
}

function ThenPackageCreated
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context,

        [hashtable]
        $WithVariables
    )

    process
    {
        It 'should get the release' {
            Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'WhsCI'
        }

        It 'should get the release using the context''s session' {
            Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' -ParameterFilter { [object]::ReferenceEquals($Context.BuildMasterSession,$Session) }
        }

        It 'should get the release using the context''s release name' {
            Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' -ParameterFilter { $Name -eq $Context.ReleaseName }
        }

        It 'should create release package' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI'
        }

        It 'should create release package using the context''s session' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter { [object]::ReferenceEquals($Context.BuildMasterSession,$Session) }
        }

        It 'should create release package for the release' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter { [object]::ReferenceEquals($mockRelease, $Release) }
        }

        It 'should create release package with package number' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter { $PackageNumber -eq ('{0}.{1}.{2}' -f $Context.Version.Major,$Context.Version.Minor,$Context.Version.Patch) }
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
                Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter { 
                    #$DebugPreference = 'Continue'
                    Write-Debug ('Expected  {0}' -f $variableValue)
                    Write-Debug ('Actual    {0}' -f $Variable[$variableName])
                    $Variable.ContainsKey($variableName) -and $Variable[$variableName] -eq $variableValue
                }
            }
        }

        It 'should start the package''s release pipeline' {
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI'
        }

        It 'should start the package''s release pipeline using the context''s session' {
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter { [object]::ReferenceEquals($Context.BuildMasterSession,$Session) }
        }

        It 'should start the package''s release pipeline using the newly created package' {
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter { [object]::ReferenceEquals($mockPackage,$Package) }
        }
    }
}

function ThenPackageNotCreated
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context
    )

    process
    {
        It 'should not get releases' {
            Assert-MockCalled -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' -Times 0
        }
        It 'should not create release package' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -Times 0
        }
        It 'should not start deploy' {
            Assert-MockCalled -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -Times 0
        }
    }
}

Describe 'New-WhsCIBuildMasterPackage.when called by build server' {
    GivenAnApplication |
        WhenCreatingPackage |
        ThenPackageCreated
}

Describe 'New-WhsCIBuildMasterPackage.when using custom package variables' {
    $variables = @{ 
                        'Fubar' = 'Snafu';
                        'Snafu' = 'Fubuar';
                   }
    GivenAnApplication |
        WhenCreatingPackage -WithVariables $variables |
        ThenPackageCreated -WithVariables $variables
}

Describe 'New-WhsCIBuildMasterPackage.when using custom package variables' {
    GivenAnApplication |
        WhenCreatingPackage -WithNoPackageVersionVariable |
        ThenPackageNotCreated
}

Describe 'New-WhsCIBuildMasterPackage.when called by a developer' {
    GivenAnApplication |
        WhenCreatingPackage -ForDeveloper |
        ThenPackageNotCreated
}

Describe 'New-WhsCIBuildMasterPackage.when application doesn''t exist in BuildMaster' {
    GivenNoApplication |
        WhenCreatingPackage -WithErrorMessage 'unable to create and deploy a release package' -ThenPackageNotCreated -ErrorAction SilentlyContinue |
        ThenItFails
}