
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$buildID = '80'
$branch = 'origin/feature/fubar'
$commitID = 'deadbeefdeadbeefdeadbeefdeadbeef'
$appBuildMetadata = 'feature-fubar.deadbee'
$libraryBuildMetadata = '80.feature-fubar.deadbee'
$developerBuildMetadata = '{0}.{1}' -f [Environment]::UserName,[Environment]::MachineName

function Assert-ConvertsTo
{
    param(
        [Parameter(ValueFromPipeline=$true)]
        $InputObject,

        [Parameter(Mandatory=$true,Position=0)]
        [SemVersion.SemanticVersion]
        $ExpectedVersion
    )

    process
    {
        $inputDesc = 'nothing'
        if( $InputObject )
        {
            $inputDesc = '[{0}]{1}' -f $InputObject.GetType().Name.ToLowerInvariant(),$InputObject
        }
        Describe ('ConvertTo-WhiskeySemanticVersion.when passed {0}' -f $inputDesc) {
            It ('should convert to {0}' -f $expectedVersion) {
                $InputObject | ConvertTo-WhiskeySemanticVersion | Should Be $expectedVersion
            }
        }
    }
}

[datetime]'1/2/3'  | Assert-ConvertsTo '1.2.2003'
[datetime]'1/2/99' | Assert-ConvertsTo '1.2.1999'
'3.2.1+build.info' | Assert-ConvertsTo '3.2.1'
'3.2.1+build.info' | Assert-ConvertsTo '3.2.1+build.info'
2.0                | Assert-ConvertsTo '2.0.0'
2.01               | Assert-ConvertsTo '2.1.0'
2.001              | Assert-ConvertsTo '2.1.0'
3                  | Assert-ConvertsTo '3.0.0'
'5.6.7-rc.3'       | Assert-ConvertsTo '5.6.7-rc.3'
'1'                | Assert-ConvertsTo '1.0.0'
'1.32'             | Assert-ConvertsTo '1.32.0'
'1.32.4'           | Assert-ConvertsTo '1.32.4'
'1.0130'           | Assert-ConvertsTo '1.130.0'
[version]'1.2.3'   | Assert-ConvertsTo '1.2.3'
[SemVersion.SemanticVersion]'1.2.3-rc.4+build' | Assert-ConvertsTo '1.2.3-rc.4+build'
