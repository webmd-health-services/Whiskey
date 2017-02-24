
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$mockPackage = [pscustomobject]@{ }
$mockRelease = [pscustomobject]@{ }
$mockDeploy = [pscustomobject]@{ }

function GivenAnApplication
{
    [CmdletBinding()]
    param(
    )

    $release = $mockRelease
    $package = $mockPackage
    $deploy = $mockDeploy

    Mock -CommandName 'Get-BMRelease' -ModuleName 'WhsCI' -MockWith { return $release }.GetNewClosure()
    Mock -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -MockWith { return $package }.GetNewClosure()
    Mock -CommandName 'Publish-BMReleasePackage' -ModuleName 'WhsCI' -MockWith { return $deploy }.GetNewClosure()

    New-WhsCITestContext -ForApplicationName 'app name' -ForReleaseName 'release name'
}

function WhenCreatingPackage
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context
    )

    process
    {
        New-WhsCIBuildMasterPackage -TaskContext $Context | Out-Null
        return $Context
    }
}

function ThenPackageCreated
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline=$true)]
        [object]
        $Context
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
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter { $PackageNumber -eq ('{0}.{1}.{2}' -f $Context.SemanticVersion.Major,$Context.SemanticVersion.Minor,$Context.SemanticVersion.Patch) }
        }

        It 'should set package variable for package version' {
            Assert-MockCalled -CommandName 'New-BMReleasePackage' -ModuleName 'WhsCI' -ParameterFilter { 
                #$DebugPreference = 'Continue'
                Write-Debug $Variable['ProGetPackageName']
                Write-Debug $Context.SemanticVersion.ToString()
                $Variable.ContainsKey('ProGetPackageName') -and $Variable['ProGetPackageName'] -eq $Context.SemanticVersion.ToString() 
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

Describe 'New-WhsCIBuildMasterPackage.when called by build server' {
    GivenAnApplication |
        WhenCreatingPackage |
        ThenPackageCreated
}