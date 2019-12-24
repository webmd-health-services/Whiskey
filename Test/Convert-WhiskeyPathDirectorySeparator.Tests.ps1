
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'Convert-WhiskeyPathDirectorySeparator' {
    It 'should convert' {
        if( [IO.Path]::DirectorySeparatorChar -eq '\' )
        {
            'fubar/snafu' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'fubar\snafu'
            'fubar/snafu/' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'fubar\snafu'
            'fubar/snafu','snafu/fubar' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'fubar\snafu','snafu\fubar'
            'dir/endswithperiod.' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'dir\endswithperiod.'
            'dir/endswithperiod/.' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'dir\endswithperiod\.'
            'dir/endswithperiod/..' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'dir\endswithperiod\..'
            'C:/full/path' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'C:\full\path'
        }
        else
        {
            'fubar\snafu' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'fubar/snafu'
            'fubar\snafu\' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'fubar/snafu'
            'fubar\snafu','snafu\fubar' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'fubar/snafu','snafu/fubar'
            'dir\endswithperiod.' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'dir/endswithperiod.'
            'dir\endswithperiod\.' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'dir/endswithperiod/.'
            'dir\endswithperiod\..' | Convert-WhiskeyPathDirectorySeparator | Should -Be 'dir/endswithperiod/..'
            '\full\path' | Convert-WhiskeyPathDirectorySeparator | Should -Be '/full/path'
        }
    }
}