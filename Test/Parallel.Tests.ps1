
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false

function File
{
    param(
        $Path,
        $ContentShouldBe
    )

    $fullPath = Join-Path -Path $TestDrive.FullName -ChildPath $Path
    $fullPath | Should -Exist
    Get-Content -Path $fullPath -Raw | Should -Be $ContentShouldBe
}

function GivenFile
{
    param(
        $Path,
        $Content
    )

    $Content | Set-Content -Path (Join-Path -Path $TestDrive.FullName -ChildPath $Path)
}

function Init
{
}

function WhenRunningTask
{
    [CmdletBinding()]
    param(
        $Parameter
    )

    $context = New-WhiskeyTestContext -ForBuildServer

    $Global:Error.Clear()
    $script:failed = $false
    $jobCount = Get-Job | Measure-Object | Select-Object -ExpandProperty 'Count'
    try
    {
        Invoke-WhiskeyTask -TaskContext $context -Name 'Parallel' -Parameter $Parameter
    }
    catch
    {
        $script:failed = $true
        Write-Error $_
    }

    It ('should cleanup jobs') {
        Get-Job | Measure-Object | Select-Object -ExpandProperty 'Count' | Should -Be $jobCount
    }
}

function ThenCompleted
{
    It ('should complete') {
        $failed | Should -Be $false
    }
}

function ThenErrorIs
{
    param(
        $Regex
    )
    It ('should write error') {
        $Global:Error[0] | Should -Match $Regex
    }
}

function ThenFailed
{
    It ('should fail') {
        $failed | Should -Be $true
    }
}

Describe 'Parallel.when running multiple tasks' {
    Init
    GivenFile 'one.ps1' '1 | sc one.txt'
    GivenFile 'two.ps1' '2 | sc two.txt'
    GivenFile 'three.ps1' '3 | sc three.txt'
    WhenRunningTask @{ 'Task' = @( @{ 'PowerShell' = @{ 'Path' = 'one.ps1' } }, @{ 'PowerShell' = @{ 'Path' = 'two.ps1' } }, @{ 'PowerShell' = @{ 'Path' = 'three.ps1' } } ) }
    It ('should run each task') {
        File 'one.txt' -ContentShouldBe   "1`r`n"
        File 'two.txt' -ContentShouldBe   "2`r`n"
        File 'three.txt' -ContentShouldBe "3`r`n"
    }
}

Describe 'Parallel.when no tasks' {
    Init
    WhenRunningTask @{ } -ErrorAction SilentlyContinue
    ThenFailed
    ThenErrorIs 'Property\ "Task"\ is\ mandatory'
}

Describe 'Parallel.when one task fails' {
    Init
    GivenFile 'one.ps1' 'throw "fubar!"'
    GivenFile 'two.ps1' 'Start-Sleep -Seconds 10'
    WhenRunningTask @{ 'Task' = @( @{ 'PowerShell' = @{ 'Path' = 'two.ps1' } }, @{ 'PowerShell' = @{ 'Path' = 'one.ps1' } } ) } -ErrorAction SilentlyContinue
    ThenFailed
    ThenErrorIs 'Task\ "PowerShell"\ failed\.'
}


Describe 'Parallel.when one task writes an error' {
    Init
    GivenFile 'one.ps1' 'Write-Error "fubar!" ; 1 | sc "one.txt"'
    GivenFile 'two.ps1' '2 | sc "two.txt"'
    WhenRunningTask @{ 'Task' = @( @{ 'PowerShell' = @{ 'Path' = 'one.ps1' } }, @{ 'PowerShell' = @{ 'Path' = 'two.ps1' } } ) } -ErrorAction SilentlyContinue
    ThenCompleted
    It ('should run both tasks') {
        File 'one.txt' -ContentShouldBe "1`r`n"
        File 'two.txt' -ContentShouldBe "2`r`n"
    }
}

