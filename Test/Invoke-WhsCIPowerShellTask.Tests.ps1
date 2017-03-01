
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
        $DoesNotRun,

        [Switch]
        $WhenGivenADirectoryThatDoesNotExist,

        [Switch]
        $WhenGivenARelativePath

    )
    $script = 'myscript.ps1'
    $scriptPath = Join-Path -Path $InWorkingDirectory -ChildPath $script
        
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

    if( $WhenNotGivenAWorkingDirectory )
    {
        $taskParameter = @{
                            Path = @(
                                    $script
                                )
                      }
        $context = New-WhsCITestContext -ForDeveloper
    }
    elseif( $WhenGivenADirectoryThatDoesNotExist )
    {
        $taskParameter = @{
                            WorkingDirectory = 'C:\I\DO\NOT\EXIST'
                            Path = @(
                                    $script
                                )
                        }
        $context = New-WhsCITestContext -ForDeveloper
    }
    elseif( $WhenGivenARelativePath )
    {
        $relativePath = 'relative'
        $contentPath = Join-Path -Path $TestDrive.FullName -ChildPath $relativePath
        New-Item -Path $contentPath -ItemType 'Directory'
        $contentPath = Join-Path -Path $contentPath -ChildPath $script
        @'
New-Item -Path 'run' -ItemType 'File'
'@ | Set-Content -Path $contentPath
        $taskParameter = @{
                            WorkingDirectory = $relativePath
                            Path = @(
                                    $script
                                )
                        }
        $context = New-WhsCITestContext -ForDeveloper


    }
    else
    {
        $taskParameter = @{
                            WorkingDirectory = $InWorkingDirectory
                            Path = @(
                                    $script
                                )
                        }
        $context = New-WhsCITestContext -ForBuildRoot $InWorkingDirectory  -ForDeveloper
    }
    
    $failed = $false
    try
    {
        Invoke-WhsCIPowerShellTask -TaskContext $context -TaskParameter $taskParameter
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
    if ( $WhenGivenARelativePath )
    {
        $itRanPath = Join-Path -Path (Join-Path -Path $InWorkingDirectory -ChildPath $relativePath) -ChildPath 'run'
    }
    else
    {
        $itRanPath = Join-Path -Path $InWorkingDirectory -ChildPath 'run'
    }    
    if( $DoesNotRun )
    {
        It 'should not run' {
            $itRanPath | Should Not Exist
        }
    }
    else
    {
        It 'should run' {
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

Describe 'Invoke-WhsCIBuild.when PowerShell task defined with an absolute working directory' {
    $absolutePath = Join-Path -path $TestDrive.FullName -ChildPath 'bin'
    New-Item -Path $absolutePath -ItemType 'Directory' 
    Assert-ThatTheTask -ForAPassingScript -Passes -InWorkingDirectory $absolutePath 
}

Describe 'Invoke-WhsCIBuild.when PowerShell task defined with a relative working directory' {
    Assert-ThatTheTask -ForAPassingScript -Passes -whenGivenARelativePath
    return
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
    Assert-ThatTheTask -ForAPassingScript -WhenGivenADirectoryThatDoesNotExist -Fails -DoesNotRun -ErrorAction SilentlyContinue
}