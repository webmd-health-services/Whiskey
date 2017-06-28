
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$buildID = '80'
$branch = 'origin/feature/fubar'
$commitID = 'deadbeefdeadbeefdeadbeefdeadbeef'
$appBuildMetadata = 'feature-fubar.deadbee'
$libraryBuildMetadata = '80.feature-fubar.deadbee'
$developerBuildMetadata = '{0}.{1}' -f $env:USERNAME,$env:COMPUTERNAME

function Assert-ConvertsTo
{
    param(
        [Parameter(ValueFromPipeline=$true)]
        $InputObject,

        [string]
        $ByBuildServer,

        [string]
        $ByDeveloper,

        [Switch]
        $WithAppBuildMetadata,

        [Switch]
        $WithLibraryBuildMetadata,

        [Switch]
        $WithDevelopBuildMetadata,

        [Switch]
        $PreserveBuildMetadata
    )

    process
    {
        $preserveBuildMetadataArg = @{}
        $preserveDesc = ''
        if( $PreserveBuildMetadata )
        {
            $preserveBuildMetadataArg['PreserveBuildMetadata'] = $true
            $preserveDesc = ' and preserving build metadata'
        }

        $inputDesc = 'nothing'
        if( $InputObject )
        {
            $inputDesc = '[{0}]{1}' -f $InputObject.GetType().Name.ToLowerInvariant(),$InputObject
        }
        Describe ('ConvertTo-WhiskeySemanticVersion.when passed {0}{1}' -f $inputDesc,$preserveDesc) {
            Context 'by build server' {
                New-MockBuildServerEnvironment
                $expectedVersion = $ByBuildServer

                if( $WithAppBuildMetadata )
                {
                    $expectedVersion = '{0}.{1}+{2}' -f $ByBuildServer,$buildID,$appBuildMetadata
                }

                if( $WithLibraryBuildMetadata )
                {
                    $expectedVersion = '{0}+{1}' -f $ByBuildServer,$libraryBuildMetadata
                }

                It ('should convert to {0}' -f $expectedVersion) {
                    $InputObject | ConvertTo-WhiskeySemanticVersion @preserveBuildMetadataArg | Should Be $expectedVersion
                }
            }
            Context 'by developer' {
                New-MockDeveloperEnvironment
                $expectedVersion = $ByDeveloper
                if( -not $PreserveBuildMetadata )
                {
                    $expectedVersion = '{0}+{1}' -f $ByDeveloper,$developerBuildMetadata
                }
                It ('should convert to {0}' -f $expectedVersion) {
                    $InputObject | ConvertTo-WhiskeySemanticVersion @preserveBuildMetadataArg | Should Be $expectedVersion
                }
            }
        }
    }
}

function New-MockBuildServerEnvironment
{
    param(
    )

    Mock -CommandName 'Test-WhiskeyRunByBuildServer' -ModuleName 'Whiskey' -MockWith { return $true }
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { return $true } -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = '80' } }.GetNewClosure() -ParameterFilter { $Path -eq 'env:BUILD_ID' }
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { return $true } -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = 'origin/feature/fubar' } }.GetNewClosure() -ParameterFilter { $Path -eq 'env:GIT_BRANCH' }
    Mock -CommandName 'Test-Path' -ModuleName 'Whiskey' -MockWith { return $true } -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }
    Mock -CommandName 'Get-Item' -ModuleName 'Whiskey' -MockWith { [pscustomobject]@{ Value = 'deadbeefdeadbeefdeadbeefdeadbeef' } }.GetNewClosure() -ParameterFilter { $Path -eq 'env:GIT_COMMIT' }
}

function New-MockDeveloperEnvironment
{
    Mock -CommandName 'Test-WhiskeyRunByBuildServer' -ModuleName 'Whiskey' -MockWith { return $false }
}

$testCases = @{
                '3.2.1+build.info' = '3.2.1';
              }


[datetime]'1/2/3'  | Assert-ConvertsTo -ByBuildServer '1.2.3' -ByDeveloper '1.2.3'  -WithLibraryBuildMetadata
[datetime]'1/2/99' | Assert-ConvertsTo -ByBuildServer '1.2.99' -ByDeveloper '1.2.99'  -WithLibraryBuildMetadata
'3.2.1+build.info' | Assert-ConvertsTo -ByBuildServer '3.2.1' -ByDeveloper '3.2.1' -WithLibraryBuildMetadata
'3.2.1+build.info' | Assert-ConvertsTo -ByBuildServer '3.2.1+build.info' -ByDeveloper '3.2.1+build.info' -PreserveBuildMetadata
2.0                | Assert-ConvertsTo -ByBuildServer '2.0' -ByDeveloper '2.0.0' -WithAppBuildMetadata
2.01               | Assert-ConvertsTo -ByBuildServer '2.1' -ByDeveloper '2.1.0' -WithAppBuildMetadata
2.001              | Assert-ConvertsTo -ByBuildServer '2.1' -ByDeveloper '2.1.0' -WithAppBuildMetadata
3                  | Assert-ConvertsTo -ByBuildServer '3.0' -ByDeveloper '3.0.0' -WithAppBuildMetadata
$dateBasedVersion = (Get-Date).ToString('yyyy.Mdd')
(@{})['Version']   | Assert-ConvertsTo -ByBuildServer $dateBasedVersion -ByDeveloper ('{0}.0' -f $dateBasedVersion) -WithAppBuildMetadata
'5.6.7-rc.3'       | Assert-ConvertsTo -ByBuildServer '5.6.7-rc.3' -ByDeveloper '5.6.7-rc.3' -WithLibraryBuildMetadata
'1'                | Assert-ConvertsTo -ByBuildServer '1.0' -ByDeveloper '1.0.0' -WithAppBuildMetadata
'1.32'             | Assert-ConvertsTo -ByBuildServer '1.32' -ByDeveloper '1.32.0' -WithAppBuildMetadata
'1.32.4'           | Assert-ConvertsTo -ByBuildServer '1.32.4' -ByDeveloper '1.32.4' -WithLibraryBuildMetadata
'1.0130'           | Assert-ConvertsTo -ByBuildServer '1.130' -ByDeveloper '1.130.0' -WithAppBuildMetadata
