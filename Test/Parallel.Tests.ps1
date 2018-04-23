
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

function ThenNoErrors
{
    It ('should write no errors') {
        $Global:Error | Should -BeNullOrEmpty
    }
}

Describe 'Parallel.when running multiple queues' {
    Init
    GivenFile 'one.ps1' '1 | sc one.txt'
    GivenFile 'two.ps1' '2 | sc two.txt'
    GivenFile 'three.ps1' '3 | sc three.txt'
    $task = Import-WhiskeyYaml -Yaml @'
Queues:
- Tasks:
    - PowerShell:
        Path: one.ps1
- Tasks:
    - PowerShell:
        Path: two.ps1
- Tasks:
    - PowerShell:
        Path: three.ps1
'@
    WhenRunningTask $task
    It ('should run each task') {
        File 'one.txt' -ContentShouldBe   "1`r`n"
        File 'two.txt' -ContentShouldBe   "2`r`n"
        File 'three.txt' -ContentShouldBe "3`r`n"
    }
}

Describe 'Parallel.when no queues' {
    Init
    WhenRunningTask @{ } -ErrorAction SilentlyContinue
    ThenFailed
    ThenErrorIs 'Property\ "Queues"\ is\ mandatory'
}

Describe 'Parallel.when queue missing task' {
    Init
    GivenFile 'one.ps1' 'Start-Sleep -Seconds 1 ; 1'
    $task = Import-WhiskeyYaml -Yaml @'
Queues:
- Tasks:
    - PowerShell:
        Path: one.ps1
- 
    - PowerShell:
        Path: two.ps1
'@
    [object[]]$result = WhenRunningTask $task -ErrorAction SilentlyContinue
    ThenFailed
    ThenErrorIs 'Queue\[1\]:\ Property\ "Tasks"\ is\ mandatory'
    It ('should cancel other queues') {
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Parallel.when one queue fails' {
    Init
    GivenFile 'one.ps1' 'throw "fubar!"'
    GivenFile 'two.ps1' 'Start-Sleep -Seconds 10'
    $task = Import-WhiskeyYaml -Yaml @'
Queues:
- Tasks:
    - PowerShell:
        Path: two.ps1
- Tasks:
    - PowerShell:
        Path: one.ps1
'@
    WhenRunningTask $task -ErrorAction SilentlyContinue
    ThenFailed
    ThenErrorIs 'Queue\[1\]\ failed\.'
}


Describe 'Parallel.when one queue writes an error' {
    Init
    GivenFile 'one.ps1' 'Write-Error "fubar!" ; 1 | sc "one.txt"'
    GivenFile 'two.ps1' '2 | sc "two.txt"'
    $task = Import-WhiskeyYaml -Yaml @'
Queues:
- Tasks:
    - PowerShell:
        Path: one.ps1
- Tasks:
    - PowerShell:
        Path: two.ps1
'@
    WhenRunningTask $task -ErrorAction SilentlyContinue
    ThenCompleted
    It ('should run both tasks') {
        File 'one.txt' -ContentShouldBe "1`r`n"
        File 'two.txt' -ContentShouldBe "2`r`n"
    }
}

Describe 'Parallel.when second queue finishes before first queue' {
    Init
    GivenFile 'one.ps1' 'Start-Sleep -Second 3 ; 1'
    GivenFile 'two.ps1' '2'
    $task = Import-WhiskeyYaml -Yaml @'
Queues:
- Tasks:
    - PowerShell:
        Path: one.ps1
- Tasks:
    - PowerShell:
        Path: two.ps1
'@
    [object[]]$output = WhenRunningTask $task -ErrorAction SilentlyContinue
    ThenCompleted
    It ('should finish tasks as the complete') {
        $output.Count | Should -Be 2
        $output[0] | Should -Be 2
        $output[1] | Should -Be 1
    }
    ThenNoErrors
}

Describe 'Parallel.when multiple tasks per queue' {
    Init
    GivenFile 'one.ps1' '1'
    GivenFile 'two.ps1' '2'
    GivenFile 'three.ps1' '3'
    $task = Import-WhiskeyYaml -Yaml @'
Queues:
- Tasks:
    - PowerShell:
        Path: one.ps1
    - PowerShell:
        Path: two.ps1
- Tasks:
    - PowerShell:
        Path: three.ps1
'@
    [object[]]$output = WhenRunningTask $task
    ThenCompleted
    It ('should finish tasks as the complete') {
        $output.Count | Should -Be 3
        $output -contains 1 | Should -Be $true
        $output -contains 2 | Should -Be $true
        $output -contains 3 | Should -Be $true
    }
    ThenNoErrors
}