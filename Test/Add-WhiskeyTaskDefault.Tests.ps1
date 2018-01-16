
Set-StrictMode -Version 'Latest'
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$context = $null
$configurationPath = $null
$force = $false
$parameterName = $null
$taskName = $null
$threwException = $false
$value = $null

function Init
{
    $Global:Error.Clear()
    $script:context = $null
    $script:configurationPath = $null
    $script:force = $false
    $script:parameterName = $null
    $script:taskName = $null
    $script:threwException = $false
    $script:value = $null
}

function GivenContext
{
    param(
        $ContextObject
    )

    if ($script:configurationPath)
    {
        $script:context = New-WhiskeyContext -Environment 'Dev' -ConfigurationPath $script:configurationPath
    }
    elseif ($ContextObject)
    {
        $script:context = $ContextObject
    }
    else
    {
        $script:context = New-WhiskeyTestContext -ForDeveloper
    }
}

function GivenForce
{
    $script:force = $true
}

function GivenTaskName
{
    param(
        $Name
    )
    
    $script:taskName = $Name
}

function GivenParameterName
{
    param(
        $Name
    )

    $script:parameterName = $Name
}

function GivenValue
{
    param(
        $Value
    )

    $script:value = $Value
}

function GivenWhiskeyYml
{
    param(
        $Yaml
    )

    $script:configurationPath = Join-Path -Path $TestDrive.FullName -ChildPath 'whiskey.yml'
    $Yaml | Set-Content -Path $script:configurationPath
}

function WhenAddingTaskDefault
{
    [CmdletBinding()]
    param()

    $forceParam = @{ 'Force' = $script:force }

    try
    {
        Add-WhiskeyTaskDefault -Context $context -TaskName $taskName -ParameterName $parameterName -Value $value @forceParam
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenNoErrors
{
    It 'should not write any errors' {
        $Global:Error | Should -BeNullOrEmpty
    }
}

function ThenFailedWithError
{
    param(
        $ErrorMessage
    )

    It 'should throw a terminating exception' {
        $threwException | Should -Be $true
    }

    It ('should write error message matching /{0}/' -f $ErrorMessage) {
        $Global:Error[0] | Should -Match $ErrorMessage
    }
}

function ThenTaskDefaultsContains
{
    param(
        $Task,
        $Property,
        $Value
    )

    It ('should set ''{0}'' property ''{1}'' to ''{2}''' -f $Task,$Property,($Value -join ', ')) {
        $script:context.TaskDefaults.ContainsKey($Task) | Should -Be $true
        $script:context.TaskDefaults[$Task].ContainsKey($Property) | Should -Be $true
        $script:context.TaskDefaults[$Task][$Property] | Should -Be $Value
    }
}

Describe 'Add-WhiskeyTaskDefault.when context object is missing TaskDefaults property' {
    Init
    GivenContext [pscustomobject]@{ RunMode = 'Build' }
    GivenTaskName 'MSBuild'
    GivenParameterName 'Version'
    GivenValue 12.0
    WhenAddingTaskDefault -ErrorAction SilentlyContinue
    ThenFailedWithError 'does not contain a ''TaskDefaults'' property'
}

Describe 'Add-WhiskeyTaskDefault.when given an invalid TaskName' {
    Init
    GivenContext
    GivenTaskName 'NotARealTask'
    GivenParameterName 'Version'
    GivenValue 12.0
    WhenAddingTaskDefault -ErrorAction SilentlyContinue
    ThenFailedWithError 'The TaskName ''NotARealTask'' is not a valid Whiskey task'
}

Describe 'Add-WhiskeyTaskDefault.when setting MSBuild ''Version'' property to 12.0 and then trying to set it again' {
    Init
    GivenContext
    GivenTaskName 'MSBuild'
    GivenParameterName 'Version'
    GivenValue 12.0
    WhenAddingTaskDefault
    ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
    ThenNoErrors

    Context 'MSBuild ''Version'' already set' {
        WhenAddingTaskDefault -ErrorAction SilentlyContinue
        ThenFailedWithError 'task already contains a default value for the parameter'
    }
}

Describe 'Add-WhiskeyTaskDefault.when a task parameter already contains a default value but ''Force'' was used' {
    Init
    GivenWhiskeyYml @'
TaskDefaults:
    MSBuild:
        Version: 12.0
    Exec:
        SuccessExitCode:
        - 1
        - 2
        - 3
'@
    GivenContext
    GivenTaskName 'MSBuild'
    GivenParameterName 'Version'
    GivenValue 15.0
    GivenForce
    WhenAddingTaskDefault
    ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 15.0
    ThenTaskDefaultsContains -Task 'Exec' -Property 'SuccessExitCode' -Value @(1, 2, 3)
    ThenNoErrors
}
Describe 'Add-WhiskeyTaskDefault.when adding task default after existing defaults defined from whiskey.yml' {
    Init
    GivenWhiskeyYml @'
TaskDefaults:
    MSBuild:
        Version: 12.0
    NuGetPack:
        Symbols: Yes
'@
    GivenContext
    GivenTaskName 'MSBuild'
    GivenParameterName 'Verbosity'
    GivenValue 'd'
    WhenAddingTaskDefault

    ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
    ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Verbosity' -Value 'd'
    ThenTaskDefaultsContains -Task 'NuGetPack' -Property 'Symbols' -Value $true
    ThenNoErrors
}
