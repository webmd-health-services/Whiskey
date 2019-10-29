
Set-StrictMode -Version 'Latest'
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$testRoot = $null
$context = $null
$configurationPath = $null
$force = $false
$propertyName = $null
$taskName = $null
$threwException = $false
$value = $null

function Init
{
    $Global:Error.Clear()
    $script:context = $null
    $script:configurationPath = $null
    $script:force = $false
    $script:propertyName = $null
    $script:taskName= $null
    $script:threwException = $false
    $script:value = $null

    $script:testRoot = New-WhiskeyTestRoot
}

function GivenContext
{
    param(
        $ContextObject
    )

    if ($script:configurationPath)
    {
        $script:context = New-WhiskeyContext -Environment 'Dev' `
                                             -ConfigurationPath $script:configurationPath `
                                             -ForBuildRoot $testRoot
    }
    elseif ($ContextObject)
    {
        $script:context = $ContextObject
    }
    else
    {
        $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $testRoot
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

function GivenPropertyName
{
    param(
        $Name
    )

    $script:propertyName = $Name
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

    $script:configurationPath = Join-Path -Path $testRoot -ChildPath 'whiskey.yml'
    $Yaml | Set-Content -Path $script:configurationPath
}

function WhenAddingTaskDefault
{
    [CmdletBinding()]
    param()

    $forceParam = @{ 'Force' = $script:force }

    try
    {
        Add-WhiskeyTaskDefault -Context $context -TaskName $taskName -PropertyName $propertyName -Value $value @forceParam
    }
    catch
    {
        $script:threwException = $true
        Write-Error -ErrorRecord $_
    }
}

function ThenNoErrors
{
    $Global:Error | Should -BeNullOrEmpty
}

function ThenFailedWithError
{
    param(
        $ErrorMessage
    )

    $threwException | Should -BeTrue
    $Global:Error[0] | Should -Match $ErrorMessage
}

function ThenTaskDefaultsContains
{
    param(
        $TaskName,
        $Property,
        $Value
    )

    $script:context.TaskDefaults.ContainsKey($TaskName) | Should -BeTrue
    $script:context.TaskDefaults[$TaskName].ContainsKey($Property) | Should -BeTrue
    $script:context.TaskDefaults[$TaskName][$Property] | Should -Be $Value
}

Describe 'Add-WhiskeyTaskDefault.when given an invalid task name' {
    It 'should fail' {
        Init
        GivenContext
        GiventaskName 'NotARealTask'
        GivenPropertyName 'Version'
        GivenValue 12.0
        WhenAddingTaskDefault -ErrorAction SilentlyContinue
        ThenFailedWithError 'Task ''NotARealTask'' does not exist.'
    }
}

Describe 'Add-WhiskeyTaskDefault.when setting MSBuild "Version" property to 12.0 and then trying to set it again' {
    It 'should fail' {
        Init
        GivenContext
        GiventaskName 'MSBuild'
        GivenPropertyName 'Version'
        GivenValue 12.0
        WhenAddingTaskDefault
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 12.0
        ThenNoErrors
        WhenAddingTaskDefault -ErrorAction SilentlyContinue
        ThenFailedWithError 'task already contains a default value for the property'
    }
}

Describe 'Add-WhiskeyTaskDefault.when a task property already contains a default value but "Force" was used' {
    It 'should set defaults' {
        Init
        GivenContext
        GiventaskName 'MSBuild'
        GivenPropertyName 'Version'
        GivenValue 12.0
        WhenAddingTaskDefault

        GiventaskName 'MSBuild'
        GivenPropertyName 'Version'
        GivenValue 15.0
        GivenForce
        WhenAddingTaskDefault
        ThenTaskDefaultsContains -Task 'MSBuild' -Property 'Version' -Value 15.0
        ThenNoErrors
    }
}