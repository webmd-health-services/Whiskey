
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
              }

foreach( $key in $testCases.Keys )
{
    Describe ('ConvertTo-SemanticVersion.when converting ''[{0}]{1}''' -f $key.GetType().Name.ToLowerInvariant(),$key) {
        $expectedValue = [SemVersion.SemanticVersion]$testCases[$key]
        It ('should be ''{0}''' -f $expectedValue) {
            $key | ConvertTo-SemanticVersion | Should Be $expectedValue
        }
    }
}