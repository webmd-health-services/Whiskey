
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testCases = @(      
                @{
                    Name = 'int';
                    Result = 685230;
                    Values = @( 
                                '685230',
                                '685_230',
                                '02472256',
                                '0x_0A_74_AE',
                                '0b1010_0111_0100_1010_1110' #,
                                #'190:20:30'  co-ordinates/base-60. Don't know how to parse.
                            )
                },
                @{
                    Name = 'int';
                    Result = 9223372036854775807;
                    Values = @(
                                '9223372036854775807',
                                '9_223_372_036_854_775_807',
                                '0x7FFFFFFFFFFFFFFF',
                                '0b111111111111111111111111111111111111111111111111111111111111111',
                                '0777777777777777777777'
                            )
                },
                @{
                    Name = 'bool';
                    Result = $true;
                    Values = @(
                                'on',
                                'true',
                                'y',
                                'yes'
                            )
                },
                @{
                    Name = 'bool';
                    Result = $false;
                    Values = @(
                                'off',
                                'false',
                                'n',
                                'no'
                            )
                },
                @{
                    Name = 'null';
                    Result = $null;
                    Values = @(
                                '~',
                                'null',
                                ''
                            )
                },
                @{
                    Name = 'datetime';
                    Result = [DateTime]'2001-12-15T02:59:43.1Z';
                    Values = @(
                        '2001-12-15T02:59:43.1Z'
                        '2001-12-15 02:59:43.1Z'
                    )
                },
                @{
                    Name = 'datetime';
                    Result = [DateTime]'2001-12-14t21:59:43.10-05:00';
                    Values = @(
                        '2001-12-14t21:59:43.10-05:00',
                        '2001-12-14t21:59:43.10 -5'
                        '2001-12-14 21:59:43.10-05:00',
                        '2001-12-14 21:59:43.10 -5'
                    )
                },
                @{
                    Name = 'datetime';
                    Result = [DateTime]'2001-12-15 2:59:43.10';
                    Values = @(
                        '2001-12-15T2:59:43.10',
                        '2001-12-15 02:59:43.10'
                    )
                },
                @{
                    Name = 'datetime';
                    Result = [DateTime]'2002-12-14';
                    Values = @(
                        '2002-12-14'
                    )
                },
                @{
                    Name = 'double';
                    Result = 685230.15
                    Values = @(
                                    '6.8523015e+5',
                                    '685_230.15' #,
                                    # 190:20:30.15  Co-ordinates/sexagesimal/base-60. Don't know how to parse this.
                    )
                },
                @{
                    Name = 'double';
                    Result = 685230.15
                    Values = @(
                                    '685.230_15e+03'
                    )
                },
                @{
                    Name = 'double';
                    Result = [Double]::NegativeInfinity
                    Values = @(
                                    '-.Inf'
                                )
                },
                @{
                    Name = 'double';
                    Result = [Double]::PositiveInfinity
                    Values = @(
                                    '.Inf'
                                )
                }
            )

foreach( $testCase in $testCases )
{
    foreach( $value in $testCase['Values'] )
    {
        Describe ('ConvertFrom-WhiskeyYamlScalar.when converting ''{0}''' -f $value) {
            It ('should return [{0}]{1}' -f $testCase.Name,$testCase.Result) {
                $value | ConvertFrom-WhiskeyYamlScalar | Should -Be $testCase.Result
            }
        }
    }
}

Describe ('ConvertFrom-WhiskeyYamlScalar.when converting ''NaN''') {
    It ('should return [Double]NaN') {
        '.NaN' | ConvertFrom-WhiskeyYamlScalar | ForEach-Object { [Double]::IsNaN($_) } | Should -Be $true
    }
}

$strings = @(
                '-.Inf .NaN 2001-12-15T02:59:43.1Z 459.3434'
            )
foreach( $string in $strings )
{
    Describe ('ConvertFrom-WhiskeyYamlScalar.when converting a string that contains types') {
        It ('should return nothing') {
            $string | ConvertFrom-WhiskeyYamlScalar -ErrorAction Ignore | Should -BeNullOrEmpty
        }
    }
}
