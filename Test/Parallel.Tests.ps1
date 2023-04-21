
#Requires -Version 4
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'
    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:failed = $false
    $script:testDir = $null

    function File
    {
        param(
            $Path,
            $ContentShouldBe
        )

        $fullPath = Join-Path -Path $script:testDir -ChildPath $Path
        $fullPath | Should -Exist
        Get-Content -Path $fullPath -Raw | Should -Be $ContentShouldBe
    }

    function GivenFile
    {
        param(
            $Path,
            $Content
        )

        Write-Debug $Path
        Write-Debug $Content
        $Content | Set-Content -Path (Join-Path -Path $script:testDir -ChildPath $Path)
    }

    function Invoke-ImportWhiskeyYaml
    {
        param(
            [String]$Yaml
        )

        Invoke-WhiskeyPrivateCommand -Name 'Import-WhiskeyYaml' -Parameter @{ 'Yaml' = $Yaml }
    }

    function WhenRunningTask
    {
        [CmdletBinding()]
        param(
            $Parameter
        )

        $context = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $script:testDir

        $script:failed = $false
        $jobCount = Get-Job | Measure-Object | Select-Object -ExpandProperty 'Count'
        Mock -CommandName 'Start-Sleep' -ModuleName 'Whiskey' # So tests don't take extra time.
        try
        {
            $Global:Error.Clear()
            Invoke-WhiskeyTask -TaskContext $context -Name 'Parallel' -Parameter $Parameter #-ErrorAction Continue
        }
        catch
        {
            $_ | Write-Error
            $script:failed = $true
        }

        Get-Job | Measure-Object | Select-Object -ExpandProperty 'Count' | Should -Be $jobCount
    }

    function ThenCompleted
    {
        $script:failed | Should -BeFalse
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
        $script:failed | Should -BeTrue
    }

    function ThenNoErrors
    {
        $Global:Error | Format-List * -Force | Out-String | Write-Verbose
        $Global:Error | Should -BeNullOrEmpty
    }
}

Describe 'Parallel' {
    BeforeEach {
        $script:testDir = New-WhiskeyTestRoot
        $Global:Error.Clear()
    }

    AfterEach {
        $stopwatch = [Diagnostics.Stopwatch]::StartNew()
        while ($stopwatch.Elapsed -lt [TimeSpan]'00:00:10')
        {
            try
            {
                $newName = ".$($script:testDir | Split-Path -Leaf)"
                Rename-Item -Path $script:testDir -NewName $newName -ErrorAction Ignore
            }
            catch
            {
                Write-Warning "Failed to rename ""$($script:testDir)"": $($_)."
            }

            if (-not (Test-Path -Path $script:testDir))
            {
                break
            }
            Start-Sleep -Seconds 1
        }
    }

    It 'should run multiple queues' {
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

    It 'should reject no queues' {
        WhenRunningTask @{ } -ErrorAction SilentlyContinue
        ThenFailed
        ThenErrorIs 'Property\ "Queues"\ is\ mandatory'
    }

    It 'should validate queue has at least one task' {
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
        [Object[]]$result = WhenRunningTask $task -ErrorAction SilentlyContinue
        ThenFailed
        ThenErrorIs 'Queue\[1\]:\ Property\ "Tasks"\ is\ mandatory'
        $result | Should -BeNullOrEmpty
    }

    It 'should fail when one queue fails' {
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
        ThenErrorIs 'didn''t finish successfully'
    }

    It 'should ignore errors written by other queues' {
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

    It 'should run all the tasks in each queue' {
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
        [Object[]]$output = WhenRunningTask $task
        ThenCompleted
        $output.Count | Should -Be 3
        $output -contains 1 | Should -BeTrue
        $output -contains 2 | Should -BeTrue
        $output -contains 3 | Should -BeTrue
        ThenNoErrors
    }

    It 'should validate task definition' {
        $task = Invoke-ImportWhiskeyYaml -Yaml @'
Queues:
- Tasks:
    -
'@
        WhenRunningTask $task -ErrorAction SilentlyContinue
        ThenFailed
        $Global:Error[0] | Should -Match 'Invalid\ task\ YAML'
    }

    It 'should preserve Whiskey context in tasks' {
        GivenFile 'one.ps1' -Content @'
param(
    [Object]$TaskContext
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
        $context = New-WhiskeyTestContext -ForBuildServer -ForYaml $yaml -ForBuildRoot $script:testDir
        Add-WhiskeyApiKey -Context $context -ID 'ApiKey' -Value 'ApiKey'
        Add-WhiskeyCredential -Context $context -ID 'Credential' -Credential (New-Object 'PsCredential' ('cred',(ConvertTo-SecureString -String 'cred' -AsPlainText -Force)))
        $Global:Error.Clear()
        Invoke-WhiskeyBuild -Context $context
        $Global:Error | Should -BeNullOrEmpty
    }

    It 'should pipeline task' {
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
        $context = New-WhiskeyContext -Environment 'Verification' `
                                      -ConfigurationPath (Join-Path -Path $script:testDir -ChildPath 'whiskey.yml')
        Invoke-WhiskeyBuild -Context $context
        File 'one.txt' -ContentShouldBe ('1{0}' -f [Environment]::NewLine)
    }

    It 'should run custom tasks from a module' {
        Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'WhiskeyTestTasks.psm1')
        try
        {
            GivenFile 'whiskey.yml' @'
Build:
- Parallel:
    Queues:
    - Tasks:
        - WrapsNoOpTask
'@
            $context = New-WhiskeyContext -Environment 'Verification' `
                                          -ConfigurationPath (Join-Path -Path $script:testDir -ChildPath 'whiskey.yml')
            Invoke-WhiskeyBuild -Context $context
            $Global:Error | Should -BeNullOrEmpty
        }
        finally
        {
            Remove-Module 'WhiskeyTestTasks'
        }
    }

    It 'should cancel and stop long-running tasks' {
        $task = Invoke-ImportWhiskeyYaml -Yaml @'
Timeout: 00:00:00.1
Queues:
- Tasks:
    - PowerShell:
        ScriptBlock: "Start-Sleep -Seconds 10 ; throw 'Fubar'"
- Tasks:
    - PowerShell:
        ScriptBlock: Start-Sleep -Seconds 10 ; throw 'Snafu'"
'@
        WhenRunningTask $task -ErrorAction SilentlyContinue
        ThenFailed
        ThenErrorIs 'background jobs timed out'
    }
}