
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

InModuleScope 'Whiskey' {
    function MyWhiskeyFunction
    {
        param(
            # Named this way on purpose so we can ensure that Get-WhiskeyContext isn't dependent on what a parameter is 
            # named.
            $InputObject
        )

        Get-WhiskeyContext
    }

    function MyOtherWhiskeyFunction
    {
        param(
            $InputObject2
        )

        MyWhiskeyFunction
    }

    Describe 'Get-WhiskeyContext.when called inside Whiskey.' {
        It 'should get context from call stack' {
            $fubar = New-Object 'Whiskey.Context'
            $context = MyOtherWhiskeyFunction -InputObject $fubar
            [object]::ReferenceEquals($fubar,$context) | Should -BeTrue
        }
    }

    Describe 'Get-WhiskeyContext.when called outside Whiskey' {
        It 'should get no context ' {
            $Global:Error.Clear()
            Get-WhiskeyContext | Should -BeNullOrEmpty
            $Global:Error | Should -BeNullOrEmpty
        }
    }
}