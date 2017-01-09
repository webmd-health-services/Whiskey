
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$buildID = '80'

$testCases = @{
                '1.2.3' = '1.2.3';
                [datetime]'1/2/3' = '1.2.3';
                [datetime]'1/2/99' = '1.2.99';
                2.0 = '2.0.{BUILDID}';
                2.01 = '2.1.{BUILDID}';
                2.001 = '2.1.{BUILDID}';
                3 = '3.0.{BUILDID}';
                '5.6.7-rc.3' = '5.6.7-rc.3';
                '3.2.1+build.info' = '3.2.1';
                '4.1' = '4.1.{BUILDID}';
                '5' = '5.0.{BUILDID}';
              }

foreach( $key in $testCases.Keys )
{
    $rawVersion = $testCases[$key] 
    $buildServerSemVer = [SemVersion.SemanticVersion]($rawVersion -replace '\{BUILDID\}','80')
    $developerSemVer = [SemVersion.SemanticVersion]($rawVersion -replace '\{BUILDID\}','0')
    $withBuildServerBuildMetadata = $buildServerSemVer
    $withDeveloperBuildMetadata = $developerSemVer
    if( $key -match '\+' )
    {
        $withBuildServerBuildMetadata = [SemVersion.SemanticVersion]$key
        $withDeveloperBuildMetadata = [SemVersion.SemanticVersion]$key
    }

    Describe ('ConvertTo-WhsCISemanticVersion.when converting ''[{0}]{1}'' by a developer' -f $key.GetType().Name.ToLowerInvariant(),$key) {
        Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $false }
        $buildInfo = '{0}@{1}' -f $env:USERNAME,$env:COMPUTERNAME
        $expectedSemVer = New-Object 'SemVersion.SemanticVersion' $developerSemVer.Major,$developerSemVer.Minor,$developerSemVer.Patch,$developerSemVer.Prerelease,$buildInfo
        It ('should be ''{0}''' -f $expectedSemVer) {
            $key | ConvertTo-WhsCISemanticVersion | Should Be $expectedSemVer
        }

        It 'should include build information' {
            $key | ConvertTo-WhsCISemanticVersion | ForEach-Object { $_.ToString() } | Should Be $expectedSemVer.ToString()
        }

        It 'should preserve build information' {
            $key | ConvertTo-WhsCISemanticVersion -PreserveBuildMetadata | ForEach-Object { $_.ToString() } | Should Be $withDeveloperBuildMetadata.ToString()
        }
    }

    Describe ('ConvertTo-WhsCISemanticVersion.when converting ''[{0}]{1}'' by build server' -f $key.GetType().Name.ToLowerInvariant(),$key) {
        Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $true }
        $branch = 'origin/develop'
        $commitID = 'deadbeefdeadbeefdeadbeefdeadbeef'
        Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = '80' } }.GetNewClosure() -ParameterFilter { $Path -eq 'env:BUILD_ID' }
        Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = $branch } }.GetNewClosure() -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
        Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = $commitID } }.GetNewClosure() -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }
        
        $buildInfo = '{0}.develop.{2}' -f $buildID,'develop',$commitID.Substring(0,7)
        $expectedSemVer = New-Object 'SemVersion.SemanticVersion' $buildServerSemVer.Major,$buildServerSemVer.Minor,$buildServerSemVer.Patch,$buildServerSemVer.Prerelease,$buildInfo
        It ('should be ''{0}''' -f $expectedSemVer) {
            $key | ConvertTo-WhsCISemanticVersion | Should Be $expectedSemVer
        }

        It 'should include build information' {
            $key | ConvertTo-WhsCISemanticVersion | ForEach-Object { $_.ToString() } | Should Be $expectedSemVer.ToString()
        }

        It 'should preserve build information' {
            $key | ConvertTo-WhsCISemanticVersion -PreserveBuildMetadata | ForEach-Object { $_.ToString() } | Should Be $withBuildServerBuildMetadata.ToString()
        }
    }
}