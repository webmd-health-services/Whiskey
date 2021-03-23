
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

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
            $verbose | Should -Be 'Verbose!'
            $debug | Should -Be 'Debug!'
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
                    $verbose | Should -Be "Verbose!"
                    $debug | Should -Be "Debug!"
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
            Assert-MockCalled 'Write-Error' -ModuleName 'Whiskey' -Times 0
        }

        It 'should not output at warning level when warning action is turned off' {
            $WarningPreference = 'Ignore'
            Mock -CommandName 'Write-Warning' -ModuleName 'Whiskey'
            $output = Write-WhiskeyWarning -Message 'Nada'
            $output | Should -BeNullOrEmpty
            Assert-MockCalled 'Write-Warning' -ModuleName 'Whiskey' -Times 0
        }

        It 'should not output at information level when information action is turned off' {
            $InformationPreference = 'Ignore'
            Mock -CommandName 'Write-Information' -ModuleName 'Whiskey'
            $output = Write-WhiskeyInfo -Message 'Nada'
            $output | Should -BeNullOrEmpty
            Assert-MockCalled 'Write-Information' -ModuleName 'Whiskey' -Times 0
        }

        It 'should not output at verbose level when verbose action is turned off' {
            $VerbosePreference = 'Ignore'
            Mock -CommandName 'Write-Verbose' -ModuleName 'Whiskey'
            $output = Write-WhiskeyVerbose -Message 'Nada'
            $output | Should -BeNullOrEmpty
            Assert-MockCalled 'Write-Verbose' -ModuleName 'Whiskey' -Times 0
        }

        It 'should not output at debug level when debug action is turned off' {
            $DebugPreference = 'Ignore'
            Mock -CommandName 'Write-Debug' -ModuleName 'Whiskey'
            $output = Write-WhiskeyDebug -Message 'Nada'
            $output | Should -BeNullOrEmpty
            Assert-MockCalled 'Write-Debug' -ModuleName 'Whiskey' -Times 0
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
}

foreach( $level in @('Error','Warning','Info','Verbose','Debug') )
{
    Describe ('Write-Whiskey{0}.when piped messages' -f $level) {
        It ('should bookend all messages and indent each message') {
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
                & ('Write-Whiskey{0}' -f $level) -Context $context `
                                                 -ErrorVariable 'errors' `
                                                 -WarningVariable 'warnings' `
                                                 -InformationVariable 'info' `
                                                 4>&1 5>&1
            switch( $Level )
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
                    ThenOutputAsGroup $output -NoDuration -NoIndent
                }
                'Debug'
                {
                    $errors | Should -BeNullOrEmpty
                    $warnings | Should -BeNullOrEmpty
                    $info | Should -BeNullOrEmpty
                    ThenOutputAsGroup $output -NoDuration -NoIndent
                }
            }
        }
    }

    foreach( $preferenceValue in [Enum]::GetValues([Management.Automation.ActionPreference]) )
    {
        if( $preferenceValue -eq [Management.Automation.ActionPreference]::Inquire )
        {
            continue
        }

        Describe ('Write-Whiskey{0}.when preference is {1} and not piping messages' -f $level,$preferenceValue) {
            It ('should only write if necessary') {
                $ErrorActionPreference = $WarningPreference = $InformationPreference = $VerbosePreference  = 
                    $DebugPreference = $preferenceValue

                if( $level -eq 'Info' )
                { 
                    $mockedCmdName = 'Write-Information'
                }
                else
                {
                    $mockedCmdName = 'Write-WhiskeyInfo'
                }

                Mock -CommandName $mockedCmdName -ModuleName 'Whiskey' 
                & ('Write-Whiskey{0}' -f $level) -Message $level 

                $prefsThatSkipWriting = & {
                    [Management.Automation.ActionPreference]::Ignore
                    if( $level -in @('Verbose','Debug') )
                    {
                        [Management.Automation.ActionPreference]::SilentlyContinue
                    }
                }
                if( $preferenceValue -in $prefsThatSkipWriting )
                {
                    Assert-MockCalled -CommandName $mockedCmdName -ModuleName 'Whiskey' -Times 0 -Exactly
                }
                else
                {
                    Assert-MockCalled -CommandName $mockedCmdName `
                                      -ModuleName 'Whiskey' `
                                      -Times 1 `
                                      -Exactly 
                }
            }
        }

        Describe ('Write-WhiskeyInfo.when preference is {1}' -f $level,$preferenceValue) {
            It ('should only write when necessary') {
                $ErrorActionPreference = $WarningPreference = $InformationPreference = $VerbosePreference  = 
                    $DebugPreference = $preferenceValue

                $mockedCmdName = 'Write-{0}' -f $level
                if( $level -eq 'Info' )
                { 
                    $mockedCmdName = 'Write-Information'
                }

                Mock -CommandName $mockedCmdName -ModuleName 'Whiskey' 
                Write-WhiskeyInfo -Level $level -Message $level 

                $prefsThatSkipWriting = & {
                    [Management.Automation.ActionPreference]::Ignore
                    if( $level -in @('Verbose','Debug') )
                    {
                        [Management.Automation.ActionPreference]::SilentlyContinue
                    }
                }
                if( $preferenceValue -in $prefsThatSkipWriting )
                {
                    Assert-MockCalled -CommandName $mockedCmdName -ModuleName 'Whiskey' -Times 0 -Exactly
                }
                else
                {
                    Assert-MockCalled -CommandName $mockedCmdName `
                                      -ModuleName 'Whiskey' `
                                      -Times 1 `
                                      -Exactly 
                }
            }
        }
    }
}
