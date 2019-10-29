
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

function GivenAnError
{
    function Write-MeAnError
    {
        Write-MeAnErrorUnder
    }

    function Write-MeAnErrorUnder
    {
        Write-Error -Message 'ZOMG! Terrible things!' -ErrorAction SilentlyContinue
    }

    Write-MeAnError -ErrorVariable 'myError'
}

function Init
{
    $Global:Error.Clear()
}

function New-Context
{

    $context = [Whiskey.Context]::new()
    $context.TaskName = 'MyTask'
    $context.StartedAt = (Get-Date)
    return $context
}

function ShouldBeBookended
{
    param(
        [Parameter(ValueFromPipeline)]
        [String]$Output,

        [String]$WithTaskName
    )

    begin
    {
        $lastMessage = $null
        if( $WithTaskName )
        {
            $WithTaskName = '  \[{0}\]' -f [regex]::escape($WithTaskName)
        }
        $pattern = '^\[\d\d:\d\d:\d\d.\d\d\]  \[ERROR  \]{0}$' -f $WithTaskName
    }
    process
    {
        if( -not $lastMessage )
        {
            $Output | Should -CMatch $pattern
        }
        $lastMessage = $Output
    }
    end
    {
        $lastMessage | Should -CMatch $pattern
    }
}

function ShouldHaveMessage
{
    param(
        [Parameter(Mandatory,ValueFromPipeline)]
        [String]$Output,

        [Parameter(Mandatory,Position=0)]
        [String]$Message
    )

    begin
    {
        $lineCount = 0
    }

    process
    {
        if( $lineCount++ -gt 2 )
        {
            continue
        }

        if( $lineCount -eq 2 )
        {
            $Output | Should -Match ('^    {0}$' -f [regex]::Escape($Message))
        }
    }
}

function ShouldHaveStackTrace
{
    param(
        [Parameter(ValueFromPipeline)]
        [String]$Output
    )

    begin
    {
        $lines = [Collections.ArrayList]::new()
    }

    process
    {
        [Void]$lines.Add($Output)
    }

    end
    {
        $stackTraceSize = (Get-PSCallStack | Measure-Object).Count + 2
        $lines[2..$stackTraceSize] | Should -Match ('^      at\ [^,]+,\ .+:\ line\ \d+$')
    }
}

Describe 'Write-WhiskeyError' {
    Context 'No Context' {
        It 'should use Write-Error' {
            Init
            Write-WhiskeyError -Message 'Something bad happened' -ErrorVariable 'errors' -ErrorAction SilentlyContinue
            $errors | Should -HaveCount 1
            $errors | Should -Match '^Something bad happened$'
        }
    }

    Context 'Context' {
        It 'should use Write-Error' {
            Init
            $context = New-Context
            Write-WhiskeyError -Context $context `
                               -Message 'Something bad happened' `
                               -ErrorVariable 'errors' `
                               -ErrorAction SilentlyContinue
            $errors | Should -HaveCount 1
            $errors | Should -Match '^Something bad happened$'
        }
    }
}

Describe 'Write-WhiskeyError.when error action is stop' {
    It 'should use Write-Error and stop the build' {
        Init
        $failed = $false
        try
        {
            Write-WhiskeyError -Message 'Blarg!' -ErrorAction Stop
        }
        catch
        {
            $failed = $true
        }
        $failed | Should -BeTrue
    }
}
