
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$result = $null
$context = $null

function GivenVariable
{
    param(
        $Name,
        $Value
    )

    Add-WhiskeyVariable -Context $context -Name $Name -Value $Value
}

function Init
{
    $script:result = $null
    $script:context = New-WhiskeyTestContext -ForDeveloper
}

function ThenErrorIs
{
    param(
        $Pattern
    )

    It 'should write an error' {
        $Global:Error | Should -Match $Pattern
    }
}

function ThenNoErrors
{
    param(
    )

    It 'should write no errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenValueIs
{
    param(
        $ExpectedValue,
        $Actual
    )

    function Test-Hashtable
    {
        param(
            $Expected,
            $Actual
        )

        It ('should return a hashtable') {
            $Actual | Get-Member -Name 'Keys' | Should -Not -BeNullOrEmpty
        }

        It ('should not add extra values') {
            $Actual.Count | Should -Be $Expected.Count
        }

        foreach( $key in $Expected.Keys )
        {
            if( (Get-Member 'Keys' -InputObject $Expected[$key] ) )
            {
                Test-Hashtable -Expected $Expected[$key] -Actual $Actual[$key]
            }
            else
            {
                It ('should replace variables in keys') {
                    $Actual[$key] | Should -Be $Expected[$key]
                }
            }
        }
    }

    if( -not $Actual )
    {
        $Actual = $result
    }

    $expectedType = $ExpectedValue.GetType()
    if( (Get-Member 'Keys' -InputObject $ExpectedValue) )
    {
        Test-Hashtable $ExpectedValue $Actual
        return
    }

    if( (Get-Member -Name 'Count' -InputObject $ExpectedValue) )
    {
        It( 'should return same size array' ) {
            Get-Member -Name 'Count' -InputObject $Actual | Should -Not -BeNullOrEmpty
            $Actual.Count | Should -Be $ExpectedValue.Count
        }

        for( $idx = 0; $idx -lt $ExpectedValue.Count; ++$idx )
        {
            ThenValueIs $ExpectedValue[$idx] $Actual[$idx]
        }
        return
    }

    It ('should replace variables in {0}' -f $expectedType.Name) {
        $Actual | Should -Be $ExpectedValue
        ,$Actual | Should -BeOfType $expectedType
    }

    It ('should not add extra items') {
        $Actual | Measure-Object | Select-Object -ExpandProperty 'Count' | Should -Be ($ExpectedValue | Measure-Object).Count
    }
}

function WhenResolving
{
    [CmdletBinding()]
    param(
        $Value
    )

    $Global:Error.Clear()
    $script:result = $Value | Resolve-WhiskeyVariable -Context $context
}

Describe 'Resolve-WhiskeyVariable.when passed a string with no variable' {
    Init
    WhenResolving 'no variable'
    ThenValueIs 'no variable'
}

Describe 'Resolve-WhiskeyVariable.when passed a string with an environment variable' {
    Init
    WhenResolving '$(COMPUTERNAME)'
    ThenValueIs $env:COMPUTERNAME
}

Describe 'Resolve-WhiskeyVariable.when passed a string with multiple variables' {
    Init
    WhenResolving '$(USERNAME)$(COMPUTERNAME)'
    ThenValueIs ('{0}{1}' -F $env:USERNAME,$env:COMPUTERNAME)
}
    
Describe 'Resolve-WhiskeyVariable.when passed a non-string' {
    Init
    WhenResolving 4
    ThenValueIs 4
}

Describe 'Resolve-WhiskeyVariable.when passed an array' {
    Init
    WhenResolving @( '$(COMPUTERNAME)', 'no variable', 4 )
    ThenValueIs @( $env:COMPUTERNAME, 'no variable', 4 )
}

Describe 'Resolve-WhiskeyVariable.when passed a hashtable' {
    Init
    WhenResolving @{ 'Key1' = '$(COMPUTERNAME)'; 'Key2' = 'no variable'; 'Key3' = 4 }
    ThenValueIs @{ 'Key1' = $env:COMPUTERNAME; 'Key2' = 'no variable'; 'Key3' = 4 }
}

Describe 'Resolve-WhiskeyVariable.when passed a hashtable with an array and hashtable in it' {
    Init
    WhenResolving @{ 'Key1' = @{ 'SubKey1' = '$(COMPUTERNAME)'; }; 'Key2' = @( '$(USERNAME)', 4 ) }
    ThenValueIs @{ 'Key1' = @{ 'SubKey1' = $env:COMPUTERNAME; }; 'Key2' = @( $env:USERNAME, 4 ) }
}

Describe 'Resolve-WhiskeyVariable.when passed an array with an array and hashtable in it' {
    Init
    WhenResolving @( @{ 'SubKey1' = '$(COMPUTERNAME)'; }, @( '$(USERNAME)', 4 ) )
    ThenValueIs @( @{ 'SubKey1' = $env:COMPUTERNAME; }, @( $env:USERNAME, 4 ) )
}

Describe 'Resolve-WhiskeyVariable.when passed a List object' {
    Init
    $list = New-Object 'Collections.Generic.List[string]'
    $list.Add( '$(COMPUTERNAME)' )
    $list.Add( 'fubar' )
    $list.Add( 'snafu' )
    WhenResolving @( $list )
    ThenValueIs @( @( $env:COMPUTERNAME, 'fubar', 'snafu' ) )
}

Describe 'Resolve-WhiskeyVariable.when passed a Dictionary' {
    Init
    $dictionary = New-Object 'Collections.Generic.Dictionary[string,string]'
    $dictionary.Add( 'Key1', '$(COMPUTERNAME)' )
    $dictionary.Add( 'Key2', 'fubar' )
    $dictionary.Add( 'Key3', 'snafu' )
    WhenResolving @( $dictionary, 4 )
    ThenValueIs @( @{ 'Key1' =  $env:COMPUTERNAME; 'Key2' = 'fubar'; 'Key3' = 'snafu' }, 4 )
}

Describe 'Resolve-WhiskeyVariable.when using a custom variable' {
    Init
    GivenVariable 'fubar' 'snafu'
    WhenResolving '$(fubar)'
    ThenValueIs 'snafu'
}

Describe 'Resolve-WhiskeyVariable.when using a variable with the same name as an environment variable' {
    Init
    GivenVariable 'COMPUTERNAME' 'snafu'
    WhenResolving '$(COMPUTERNAME)'
    ThenValueIs 'snafu'
}

Describe 'Resolve-WhiskeyVariable.when using a variable that doesn''t exist' {
    Init
    WhenResolving '$(i do not exist)' -ErrorAction SilentlyContinue
    ThenValueIs '$(i do not exist)'
    ThenErrorIs ('''i\ do\ not\ exist'' does not exist.')
}

Describe 'Resolve-WhiskeyVariable.when ignoring errors' {
    Init
    WhenResolving '$(i do not exist)' -ErrorAction Ignore
    ThenValueIs '$(i do not exist)'
    ThenNoErrors
}