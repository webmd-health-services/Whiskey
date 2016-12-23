
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function Assert-ThatTheTask
{
    [CmdletBinding()]
    param(
        [string]
        $ForScript,

        [Switch]
        $ForAPassingScript,

        [Switch]
        $ForAFailingScript,

        [Switch]
        $Passes,

        [Switch]
        $Fails,

        [Switch]
        $WhenNotGivenAWorkingDirectory,

        [String]
        $InWorkingDirectory = $TestDrive.FullName,

        [Switch]
        $DoesNotRun
    )

    $scriptPath = Join-Path -Path $TestDrive.FullName -ChildPath 'myscript.ps1'
        @'
New-Item -Path 'run' -ItemType 'File'
'@ | Set-Content -Path $scriptPath

    if( $ForAFailingScript )
    {
        'exit 1' | Add-Content -Path $scriptPath
    }

    if( $ForScript )
    {
        $ForScript | Add-Content -Path $scriptPath
    }

    $workingDirParam = @{ WorkingDirectory = $InWorkingDirectory }
    if( $WhenNotGivenAWorkingDirectory )
    {
        $workingDirParam = @{}
    }

    $failed = $false
    try
    {
        Invoke-WhsCIPowerShellTask -ScriptPath $scriptPath @workingDirParam
    }
    catch
    {
        Write-Error -ErrorRecord $_
        $failed = $true
    }

    if( $Passes )
    {
        It 'should pass' {
            $failed | Should Be $false
        }
    }

    if( $Fails )
    {
        It 'should fail' {
            $failed | Should Be $true
        }
    }

    $itRanPath = Join-Path -Path $TestDrive.FullName -ChildPath 'run'
    if( $DoesNotRun )
    {
        It 'should not run' {
            $itRanPath | Should Not Exist
        }
    }
    else
    {
        It 'should not run' {
            $itRanPath | Should Exist
        }
    }
}

Describe 'Invoke-WhsCIPowerShellTask.when script passes' {
    Assert-ThatTheTask -ForAPassingScript -Passes
}

Describe 'Invoke-WhsCIPowerShellTask.when script fails' {
    Assert-ThatTheTask -ForAFailingScript -Fails -ErrorAction SilentlyContinue
}

Describe 'Invoke-WhsCIPowerShellTask.when script passes after a previous command fails' {
    $Global:LASTEXITCODE = 1
    Assert-ThatTheTask -ForAPassingScript -Passes
}

Describe 'Invoke-WhsCIPowerShellTask.when script throws a terminating exception' {
    $script = @'
throw 'fubar!'
'@ 
    Assert-ThatTheTask -ForScript $script -Fails -ErrorAction SilentlyContinue

    It 'should handle the script''s error' {
        $Global:Error[0] | Should Match 'fubar'
    }
}

Describe 'Invoke-WhsCIPowerShellTask.when script''s error action preference is Stop' {
    $script = @'
$ErrorActionPreference = 'Stop'
Write-Error 'snafu!'
'@ 
    Assert-ThatTheTask -ForScript $script -Fails -ErrorAction SilentlyContinue

    It 'should handle the script''s error' {
        $Global:Error[0] | Should Match 'snafu'
    }
}

Describe 'Invoke-WhsCIPowerShellTask.when not given a working directory' {
    Push-Location $TestDrive.FullName
    try
    {
        Assert-ThatTheTask -ForAPassingScript -Passes -WhenNotGivenAWorkingDirectory
    }
    finally
    {
        Pop-Location
    }
}

Describe 'Invoke-WhsCIPowerShellTask.when working directory does not exist' {
    Assert-ThatTheTask -ForAPassingScript -InWorkingDirectory 'C:\I\Do\Not\Exist' -Fails -DoesNotRun -ErrorAction SilentlyContinue
}