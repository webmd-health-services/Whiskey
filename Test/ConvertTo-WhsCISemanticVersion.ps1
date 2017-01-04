
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

$testCases = @{
                '1.2.3' = '1.2.3';
                [datetime]'1/2/3' = '1.2.3';
                [datetime]'1/2/99' = '1.2.99';
                2.0 = '2.0.0';
                2.01 = '2.1.0';
                2.001 = '2.1.0';
                3 = '3.0.0';
                '5.6.7-rc.3' = '5.6.7-rc.3';
                '3.2.1+build.info' = '3.2.1';
              }

foreach( $key in $testCases.Keys )
{
    $semanticVersion = [SemVersion.SemanticVersion]$testCases[$key]
    $withBuildMetadata = $semanticVersion
    if( $key -match '\+' )
    {
        $withBuildMetadata = [SemVersion.SemanticVersion]$key
    }

    Describe ('ConvertTo-SemanticVersion.when converting ''[{0}]{1}'' by a developer' -f $key.GetType().Name.ToLowerInvariant(),$key) {
        Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $false }
        $buildInfo = '{0}@{1}' -f $env:USERNAME,$env:COMPUTERNAME
        $expectedSemVer = New-Object 'SemVersion.SemanticVersion' $semanticVersion.Major,$semanticVersion.Minor,$semanticVersion.Patch,$semanticVersion.Prerelease,$buildInfo
        It ('should be ''{0}''' -f $expectedSemVer) {
            $key | ConvertTo-SemanticVersion | Should Be $expectedSemVer
        }

        It 'should include build information' {
            $key | ConvertTo-SemanticVersion | ForEach-Object { $_.ToString() } | Should Be $expectedSemVer.ToString()
        }

        It 'should preserve build information' {
            $key | ConvertTo-SemanticVersion -PreserveBuildMetadata | ForEach-Object { $_.ToString() } | Should Be $withBuildMetadata.ToString()
        }
    }

    Describe ('ConvertTo-SemanticVersion.when converting ''[{0}]{1}'' by build server' -f $key.GetType().Name.ToLowerInvariant(),$key) {
        Mock -CommandName 'Test-WhsCIRunByBuildServer' -ModuleName 'WhsCI' -MockWith { return $true }
        $buildID = '80'
        $branch = 'origin/develop'
        $commitID = 'deadbeefdeadbeefdeadbeefdeadbeef'
        Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = $buildID } }.GetNewClosure() -ParameterFilter { $Path -eq 'env:BUILD_ID' }
        Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = $branch } }.GetNewClosure() -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
        Mock -CommandName 'Get-Item' -ModuleName 'WhsCI' -MockWith { [pscustomobject]@{ Value = $commitID } }.GetNewClosure() -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }
        
        $buildInfo = '{0}.develop.{2}' -f $buildID,'develop',$commitID.Substring(0,7)
        $expectedSemVer = New-Object 'SemVersion.SemanticVersion' $semanticVersion.Major,$semanticVersion.Minor,$semanticVersion.Patch,$semanticVersion.Prerelease,$buildInfo
        It ('should be ''{0}''' -f $expectedSemVer) {
            $key | ConvertTo-SemanticVersion | Should Be $expectedSemVer
        }

        It 'should include build information' {
            $key | ConvertTo-SemanticVersion | ForEach-Object { $_.ToString() } | Should Be $expectedSemVer.ToString()
        }

        It 'should preserve build information' {
            $key | ConvertTo-SemanticVersion -PreserveBuildMetadata | ForEach-Object { $_.ToString() } | Should Be $withBuildMetadata.ToString()
        }
    }
}