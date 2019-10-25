
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

function Invoke-ImportWhiskeyYaml
{
    param(
        [string]$Yaml
    )

    Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyYaml' -Parameter @{ 'Yaml' = $Yaml }
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
        Invoke-WhiskeyTask -TaskContext $context -Name 'Parallel' -Parameter $Parameter -ErrorAction Continue
    }
    catch
    {
        $script:failed = $true
    }

    Get-Job | Measure-Object | Select-Object -ExpandProperty 'Count' | Should -Be $jobCount
}

function ThenCompleted
{
    $failed | Should -Be $false
}

function ThenErrorIs
{
    param(
        $Regex
    )

    $Global:Error[0] | Should -Match $Regex
}

function ThenFailed
{
    $failed | Should -Be $true
}

function ThenNoErrors
{
    $Global:Error | Should -BeNullOrEmpty
}

Describe 'Parallel.when running multiple queues' {
    It 'should run tasks in each queue' {
        Init
        GivenFile 'one.ps1' '1 | Set-Content one.txt'
        GivenFile 'two.ps1' '2 | Set-Content two.txt'
        GivenFile 'three.ps1' '3 | Set-Content three.txt'
        $task = Invoke-ImportWhiskeyYaml -Yaml @'
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
        File 'one.txt' -ContentShouldBe   ('1{0}' -f [Environment]::NewLine)
        File 'two.txt' -ContentShouldBe   ('2{0}' -f [Environment]::NewLine)
        File 'three.txt' -ContentShouldBe ('3{0}' -f [Environment]::NewLine)
    }
}

Describe 'Parallel.when no queues' {
    It 'should fail' {
        Init
        WhenRunningTask @{ } -ErrorAction SilentlyContinue
        ThenFailed
        ThenErrorIs 'Property\ "Queues"\ is\ mandatory'
    }
}

Describe 'Parallel.when queue missing task' {
    It 'should fail' {
        Init
        GivenFile 'one.ps1' 'Start-Sleep -Seconds 1 ; 1'
        $task = Invoke-ImportWhiskeyYaml -Yaml @'
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
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Parallel.when one queue fails' {
    It 'should fail' {
        Init
        GivenFile 'one.ps1' 'throw "fubar!"'
        GivenFile 'two.ps1' 'Start-Sleep -Seconds 10'
        $task = Invoke-ImportWhiskeyYaml -Yaml @'
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
}


Describe 'Parallel.when one queue writes an error' {
    It 'should run other tasks' {
        Init
        GivenFile 'one.ps1' 'Write-Error "fubar!" ; 1 | Set-Content "one.txt"'
        GivenFile 'two.ps1' '2 | Set-Content "two.txt"'
        $task = Invoke-ImportWhiskeyYaml -Yaml @'
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
        File 'one.txt' -ContentShouldBe ('1{0}' -f [Environment]::NewLine)
        File 'two.txt' -ContentShouldBe ('2{0}' -f [Environment]::NewLine)
    }
}

Describe 'Parallel.when second queue finishes before first queue' {
    It 'should wait for all queues to finish' {
        Init
        GivenFile 'one.ps1' 'Write-Host ("1" * 80) ; Write-Host (Get-Date) ; Start-Sleep -Seconds 12 ; 1 ; Write-Host (Get-Date) ; $Global:Error | Format-List * -Force | Out-String | Write-Host'
        GivenFile 'two.ps1' 'Write-Host ("2" * 80) ; Write-Host (Get-Date) ; 2 ; Write-Host (Get-Date) ; $Global:Error | Format-List * -Force | Out-String | Write-Host'
        $task = Invoke-ImportWhiskeyYaml -Yaml @'
Queues:
- Tasks:
    - PowerShell:
        Path: one.ps1
- Tasks:
    - PowerShell:
        Path: two.ps1
'@
        [object[]]$output = WhenRunningTask $task #-ErrorAction SilentlyContinue
        ThenCompleted
        $output.Count | Should -Be 2
        $output[0] | Should -Be 2
        $output[1] | Should -Be 1
        ThenNoErrors
    }
}

Describe 'Parallel.when multiple tasks per queue' {
    It 'should run all the tasks in each queue' {
        Init
        GivenFile 'one.ps1' '1'
        GivenFile 'two.ps1' '2'
        GivenFile 'three.ps1' '3'
        $task = Invoke-ImportWhiskeyYaml -Yaml @'
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
        $output.Count | Should -Be 3
        $output -contains 1 | Should -Be $true
        $output -contains 2 | Should -Be $true
        $output -contains 3 | Should -Be $true
        ThenNoErrors
    }
}

Describe 'Parallel.when a task definition is invalid' {
    It 'should fail' {
        Init
        $task = Invoke-ImportWhiskeyYaml -Yaml @'
Queues:
- Tasks:
    - 
'@
        WhenRunningTask $task -ErrorAction SilentlyContinue
        ThenFailed
        $Global:Error[0] | Should -Match 'Invalid\ task\ YAML'
    }
}

Describe 'Parallel.when API keys, variables, credentials, and task defaults are defined' {
    It 'should preserve everything to parallel tasks' {
        Init
        GivenFile 'one.ps1' -Content @'
param(
    [object]$TaskContext
)

if( $TaskContext.Variables['Fubar'] -ne 'Snafu' )
{
    throw ('Fubar variable value is not "Snafu".')
}

$apiKey = Get-WhiskeyApiKey -Context $TaskContext -ID 'ApiKey' -PropertyName 'ID' -ErrorAction Stop
if( $apiKey -cne 'ApiKey' )
{
    throw ('API key "ApiKey" doesn''t have its expected value of "ApiKey".')
}

$cred = Get-WhiskeyCredential -Context $TaskContext -ID 'Credential' -PropertyName 'Whatevs' -ErrorAction Stop
if( -not $cred )
{
    throw ('Credential "Credential" is missing.')
}

if( $cred.UserName -ne 'cred' )
{
    throw ('Credential''s UserName isn''t "cred".')
}

if( $cred.GetNetworkCredential().Password -ne 'cred' )
{
    throw ('Credential''s Password isn''t "cred".')
}

exit 0
'@
        $yaml = @'
Build:
- TaskDefaults:
    PowerShell:
        Path: one.ps1
- SetVariable:
    Fubar: Snafu
- Parallel:
    Queues:
    - Tasks:
        - PowerShell:
            Argument:
                VariableValue: $(Fubar)
'@
        $context = New-WhiskeyTestContext -ForBuildServer -ForYaml $yaml
        Add-WhiskeyApiKey -Context $context -ID 'ApiKey' -Value 'ApiKey'
        Add-WhiskeyCredential -Context $context -ID 'Credential' -Credential (New-Object 'PsCredential' ('cred',(ConvertTo-SecureString -String 'cred' -AsPlainText -Force)))
        $Global:Error.Clear()
        Invoke-WhiskeyBuild -Context $context
        $Global:Error | Should -BeNullOrEmpty
    }
}

Describe 'Parallel.when running pipeline task' {
    It 'should run the pipeline tasks correctly' {
        Init
        GivenFile 'one.ps1' '1 | Set-Content one.txt'
        GivenFile 'whiskey.yml' @'
Build:
- Parallel:
    Queues:
    - Tasks:
        - Pipeline:
            Name: PowerShell

PowerShell:
- PowerShell:
    Path: one.ps1
'@
        $context = New-WhiskeyContext -Environment 'Verification' -ConfigurationPath (Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml')
        Invoke-WhiskeyBuild -Context $context
        File 'one.txt' -ContentShouldBe ('1{0}' -f [Environment]::NewLine)
    }
}
