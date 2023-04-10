
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
}

Describe 'Write-WhiskeyInfo' {
    Context 'no context' {
        It 'should write at different levels without a context' {
            Mock -CommandName 'Get-Date' -ModuleName 'Whiskey' -MockWith { return [DateTime]::MaxValue }
            $ErrorActionPreference = $WarningPreference = $InformationPreference =  'SilentlyContinue'
            Write-WhiskeyError 'Error!' -ErrorVariable 'errors'
            Write-WhiskeyWarning 'Warning!' -WarningVariable 'warnings'
            Write-WhiskeyInfo 'Info!' -InformationVariable 'info'
            $verbose = Write-WhiskeyVerbose 'Verbose!' -Verbose 4>&1
            $DebugPreference = 'Continue'
            $debug = Write-WhiskeyDebug 'Debug!' 5>&1

            $errors | Should -Be 'Error!'
            $warnings | Should -Be 'Warning!'
            $info | Should -CMatch '^\[23:59:59\]    Info!$'
            $verbose | Should -Be '[23:59:59]  Verbose!'
            $debug | Should -Be '[23:59:59]  Debug!'
        }
    }

    Context 'context' {
        It 'should write task information and duration' {
            InModuleScope 'Whiskey' {
                function Invoke-Write
                {
                    [CmdletBinding()]
                    param(
                        [Parameter(Mandatory)]
                        [Whiskey.Context]$Context
                    )
                    $ErrorActionPreference = $WarningPreference = $InformationPreference = 'SilentlyContinue'
                    Write-WhiskeyError 'Error!' -ErrorVariable 'errors'
                    Write-WhiskeyWarning 'Warning!' -WarningVariable 'warnings'
                    Write-WhiskeyInfo 'Info!' -InformationVariable 'info'
                    $verbose = Write-WhiskeyVerbose 'Verbose!' -Verbose 4>&1
                    $DebugPreference = 'Continue'
                    $debug = Write-WhiskeyDebug 'Debug!' 5>&1

                    $errors | Should -Be 'Error!'
                    $warnings | Should -Be 'Warning!'
                    $durationRegex = '\[ \dm\d\ds\]  \[ \dm\d\ds\]'
                    $info | Should -CMatch "^$($durationRegex)    Info!$"
                    $verbose | Should -CMatch "^$($durationRegex)  Verbose!"
                    $debug | Should -CMatch "^$($durationRegex)  Debug!"
                }

                $context = New-Object 'Whiskey.Context'
                $context.StartBuild()
                $context.StartTask('WriteLog')

                Invoke-Write -Context $context -InformationVariable 'output'
            }
        }
    }

    Context 'preference variables set to ignore' {
        It 'should not output at error level when error action is turned off' {
            $ErrorActionPreference = 'Ignore'
            Mock -CommandName 'Write-Error' -ModuleName 'Whiskey'
            $output = Write-WhiskeyError -Message 'Nada'
            $output | Should -BeNullOrEmpty
            Should -Invoke 'Write-Error' -ModuleName 'Whiskey' -Times 0
        }

        It 'should not output at warning level when warning action is turned off' {
            $WarningPreference = 'Ignore'
            Mock -CommandName 'Write-Warning' -ModuleName 'Whiskey'
            $output = Write-WhiskeyWarning -Message 'Nada'
            $output | Should -BeNullOrEmpty
            Should -Invoke 'Write-Warning' -ModuleName 'Whiskey' -Times 0
        }

        It 'should not output at information level when information action is turned off' {
            $InformationPreference = 'Ignore'
            Mock -CommandName 'Write-Information' -ModuleName 'Whiskey'
            $output = Write-WhiskeyInfo -Message 'Nada'
            $output | Should -BeNullOrEmpty
            Should -Invoke 'Write-Information' -ModuleName 'Whiskey' -Times 0
        }

        It 'should not output at verbose level when verbose action is turned off' {
            $VerbosePreference = 'Ignore'
            Mock -CommandName 'Write-Verbose' -ModuleName 'Whiskey'
            $output = Write-WhiskeyVerbose -Message 'Nada'
            $output | Should -BeNullOrEmpty
            Should -Invoke 'Write-Verbose' -ModuleName 'Whiskey' -Times 0
        }

        It 'should not output at debug level when debug action is turned off' {
            $DebugPreference = 'Ignore'
            Mock -CommandName 'Write-Debug' -ModuleName 'Whiskey'
            $output = Write-WhiskeyDebug -Message 'Nada'
            $output | Should -BeNullOrEmpty
            Should -Invoke 'Write-Debug' -ModuleName 'Whiskey' -Times 0
        }
    }

    It 'should still write when passed null message' {
        $InformationPreference = 'Continue'
        Write-WhiskeyInfo -Message @($null) -InformationVariable 'output'
        $output | Should -Match '^\[\d{2}:\d{2}:\d{2}\]\ *$'
    }

    It 'should still write when passed empty message' {
        $InformationPreference = 'Continue'
        Write-WhiskeyInfo -Message '' -InformationVariable 'output'
        $output | Should -Match '^\[\d{2}:\d{2}:\d{2}\]\ *$'
    }

    It ('should write all messages when passed multiple messages with no context') {
        $InformationPreference = 'Continue'
        Write-WhiskeyInfo -Message @('One','Two','Three') -InformationVariable 'output'
        $output | Should -HaveCount 3
        $output[0] | Should -CMatch ('^\[\d\d:\d\d:\d\d\]\ {4}One$')
        $output[1] | Should -CMatch ('^\[\d\d:\d\d:\d\d\]\ {4}Two$')
        $output[2] | Should -CMatch ('^\[\d\d:\d\d:\d\d\]\ {4}Three$')
    }

    It ('should write all messages when passed multiple messages and a context') {
        $InformationPreference = 'Continue'
        $context = [Whiskey.Context]::new()
        $context.StartBuild()
        $context.StartTask('Snafu')
        Write-WhiskeyInfo -Context $context -Message @('One','Two','Three') -InformationVariable 'output'
        $output | Should -HaveCount 3
        $output[0] | Should -CMatch ('^(\[ \dm\d\ds\]  ){2}  One$')
        $output[1] | Should -CMatch ('^(\[ \dm\d\ds\]  ){2}  Two$')
        $output[2] | Should -CMatch ('^(\[ \dm\d\ds\]  ){2}  Three$')
    }

    Context 'Write-Whiskey<_>' -ForEach @('Error','Warning','Info','Verbose','Debug') {
        It 'should bookend all piped messages and indent each piped message' -TestCases $_ {
            $script:level = $_

            $context = [Whiskey.Context]::New()
            $context.StartBuild()
            $context.StartTask('Fubar')
            $ErrorActionPreference = $WarningPreference = $InformationPreference = $VerbosePreference  =
                $DebugPreference = 'Continue'

            function ThenOutputAsGroup
            {
                param(
                    [String[]]$Output,
                    [switch]$NoIndent,
                    [switch]$NoDuration
                )

                $indentRegex = '\ \ '
                if( $NoIndent )
                {
                    $indentRegex = ''
                }

                $durationRegex = '(\[ \dm\d\ds\]\ \ ){2}'
                if( $NoDuration )
                {
                    $durationRegex = ''
                }

                $output[0] | Should -CMatch "^$($durationRegex)$($indentRegex)1$"
                $output[1] | Should -CMatch "^$($durationRegex)$($indentRegex)2$"
                $output[2] | Should -CMatch "^$($durationRegex)$($indentRegex)3$"
            }

            $output =
                @(1,2,3) |
                & ('Write-Whiskey{0}' -f $script:level) -Context $context `
                                                    -ErrorVariable 'errors' `
                                                    -WarningVariable 'warnings' `
                                                    -InformationVariable 'info' `
                                                    4>&1 5>&1
            switch( $script:level )
            {
                'Error'
                {
                    $errors | Should -Match ([regex]::Escape('1{0}2{0}3' -f [Environment]::NewLine))
                    $warnings | Should -BeNullOrEmpty
                    $info | Should -BeNullOrEmpty
                    $output | Should -BeNullOrEmpty
                }
                'Warning'
                {
                    $errors | Should -BeNullOrEmpty
                    ThenOutputAsGroup $warnings -NoDuration -NoIndent
                    $info | Should -BeNullOrEmpty
                    $output | Should -BeNullOrEmpty
                }
                'Info'
                {
                    $errors | Should -BeNullOrEmpty
                    $warnings | Should -BeNullOrEmpty
                    ThenOutputAsGroup $info
                    $output | Should -BeNullOrEmpty
                }
                'Verbose'
                {
                    $errors | Should -BeNullOrEmpty
                    $warnings | Should -BeNullOrEmpty
                    $info | Should -BeNullOrEmpty
                    ThenOutputAsGroup $output -NoIndent
                }
                'Debug'
                {
                    $errors | Should -BeNullOrEmpty
                    $warnings | Should -BeNullOrEmpty
                    $info | Should -BeNullOrEmpty
                    ThenOutputAsGroup $output -NoIndent
                }
            }
        }

        Context '<_>' -ForEach ([Enum]::GetValues([Management.Automation.ActionPreference]) |
                                    Where-Object { $_ -notin @('Inquire', 'Break', 'Suspend')}) {
            It 'should only write if necessary' -TestCases $_ {
                $preferenceValue = $_
                $ErrorActionPreference = $WarningPreference = $InformationPreference = $VerbosePreference  =
                    $DebugPreference = $preferenceValue

                if( $script:level -eq 'Info' )
                {
                    $mockedCmdName = 'Write-Information'
                }
                else
                {
                    $mockedCmdName = 'Write-WhiskeyInfo'
                }

                Mock -CommandName $mockedCmdName -ModuleName 'Whiskey'
                & ('Write-Whiskey{0}' -f $script:level) -Message $script:level

                $prefsThatSkipWriting = & {
                    [Management.Automation.ActionPreference]::Ignore
                    if( $script:level -in @('Verbose','Debug') )
                    {
                        [Management.Automation.ActionPreference]::SilentlyContinue
                    }
                }
                if( $preferenceValue -in $prefsThatSkipWriting )
                {
                    Should -Invoke -CommandName $mockedCmdName -ModuleName 'Whiskey' -Times 0 -Exactly
                }
                else
                {
                    Should -Invoke -CommandName $mockedCmdName `
                                      -ModuleName 'Whiskey' `
                                      -Times 1 `
                                      -Exactly
                }
            }

            It 'should only write when necessary' -TestCases $_ {
                $preferenceValue = $_
                $ErrorActionPreference = $WarningPreference = $InformationPreference = $VerbosePreference  =
                    $DebugPreference = $preferenceValue

                $mockedCmdName = 'Write-{0}' -f $script:level
                if( $script:level -eq 'Info' )
                {
                    $mockedCmdName = 'Write-Information'
                }

                Mock -CommandName $mockedCmdName -ModuleName 'Whiskey'
                Write-WhiskeyInfo -Level $script:level -Message $script:level

                $prefsThatSkipWriting = & {
                    [Management.Automation.ActionPreference]::Ignore
                    if( $script:level -in @('Verbose','Debug') )
                    {
                        [Management.Automation.ActionPreference]::SilentlyContinue
                    }
                }
                if( $preferenceValue -in $prefsThatSkipWriting )
                {
                    Should -Invoke -CommandName $mockedCmdName -ModuleName 'Whiskey' -Times 0 -Exactly
                }
                else
                {
                    Should -Invoke -CommandName $mockedCmdName `
                                      -ModuleName 'Whiskey' `
                                      -Times 1 `
                                      -Exactly
                }
            }
        }
    }
}
