# A collection of tasks to use in tests.

$lastTaskBoundParameters = $null

function AliasedTask
{
    [Whiskey.Task('AliasedTask',Aliases=('OldAliasedTaskName','AnotherOldAliasedTaskName'))]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function AlternateStandardParameterNamesTask
{
    [Whiskey.Task('AlternateStandardParameterNamesTask')]
    param(
        $Context,
        $Parameter
    )
    $script:lastTaskBoundParameters = $PSBoundParameters
}

function BuildOnlyTask
{
    [Whiskey.Task('BuildOnlyTask')]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function CapturesCommonPreferencesTask
{
    [Whiskey.Task('CapturesCommonPreferencesTask')]
    [CmdletBinding(SupportsShouldProcess)]
    param(
    )

    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $script:lastTaskBoundParameters = $PSBoundParameters
    foreach( $prefName in @( 'VerbosePreference', 'WhatIfPreference', 'DebugPreference', 'InformationPreference', 'ErrorActionPreference' ) )
    {
        $lastTaskBoundParameters[$prefName] = Get-Variable -Name $prefName -ValueOnly
    }
}

function Clear-LastTaskBoundParameter
{
    $script:lastTaskBoundParameters = $null
}
function DuplicateAliasTask1
{
    [Whiskey.Task('DuplicateAliasTask1',Aliases=('DuplicateAliasTask'),WarnWhenUsingAlias)]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function DuplicateAliasTask2
{
    [Whiskey.Task('DuplicateAliasTask2',Aliases=('DuplicateAliasTask'),WarnWhenUsingAlias)]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function DuplicateTask1
{
    [Whiskey.Task('DuplicateTask')]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function DuplicateTask2
{
    [Whiskey.Task('DuplicateTask')]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function FailingTask
{
    [Whiskey.Task('FailingTask')]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )

    Stop-WhiskeyTask -TaskContext $TaskContext -Message 'Failed!'
}

function Get-LastTaskBoundParameter
{
    return $lastTaskBoundParameters
}

function LinuxOnlyTask
{
    [Whiskey.Task('LinuxOnlyTask',Platform='Linux')]
    [CmdletBinding()]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function MacOSOnlyTask
{
    [Whiskey.Task('MacOSOnlyTask',Platform='MacOS')]
    [CmdletBinding()]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function NamedParametersTask
{
    [Whiskey.Task('NamedParametersTask',SupportsClean)]
    [CmdletBinding()]
    param(
        [String]$Yolo,
        [String]$Fubar,
        [switch]$SwitchOne,
        [switch]$SwitchTwo,
        [switch]$SwitchThree,
        [bool]$Bool,
        [int]$Int,
        [bool]$NoBool,
        [int]$NoInt
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function NoOpTask
{
    [CmdletBinding()]
    [Whiskey.Task('NoOpTask')]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ObsoleteAliasTask
{
    [Whiskey.Task('ObsoleteAliasTask',Aliases=('OldObsoleteAliasTaskName'),WarnWhenUsingAlias)]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function ObsoleteTask
{
    [Whiskey.Task('ObsoleteTask',Obsolete)]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function ObsoleteWithCustomMessageTask
{
    [Whiskey.Task('ObsoleteWithCustomMessageTask',Obsolete,ObsoleteMessage='Use the NonObsoleteTask instead.')]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function ParameterValueFromVariableTask
{
    [Whiskey.Task('ParameterValueFromVariableTask')]
    param(
        [Whiskey.Tasks.ParameterValueFromVariable('WHISKEY_ENVIRONMENT')]
        [String]$Environment
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ParameterValueFromVariablePropertyTask
{
    [Whiskey.Task('ParameterValueFromVariablePropertyTask')]
    param(
        [Whiskey.Tasks.ParameterValueFromVariable('WHISKEY_ENVIRONMENT.Length')]
        [String]$Environment
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function RequiresNodeTask
{
    [Whiskey.Task('RequiresNodeTask',SupportsClean)]
    [Whiskey.RequiresTool('Node',PathParameterName='NodePath')]
    [CmdletBinding()]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function RequiresNodeFailingTask
{
    <#
    .SYNOPSIS
    A task that requires a tool to be intalled (Node) but fails when run. Use this to test that tools get installed even
    if a task doesn't run (i.e. during Clean and Initialize modes).
    #>
    [Whiskey.Task('RequiresNodeFailingTask',SupportsClean)]
    [Whiskey.RequiresTool('Node',PathParameterName='NodePath')]
    [CmdletBinding()]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )

    Stop-WhiskeyTask 'Failed!'
}

function SupportsCleanAndInitializeTask
{
    [Whiskey.TaskAttribute('SupportsCleanAndInitializeTask',SupportsClean,SupportsInitialize)]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function SupportsCleanTask 
{
    [Whiskey.TaskAttribute('SupportsCleanTask',SupportsClean)]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function SupportsInitializeTask 
{
    [Whiskey.TaskAttribute('SupportsInitializeTask',SupportsInitialize)]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function ValidateMandatoryDirectoryTask
{
    [Whiskey.Task('ValidateMandatoryDirectoryTask')]
    param(
        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='Directory')]
        [String]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ValidateMandatoryFilesTask
{
    [Whiskey.Task('ValidateMandatoryFilesTask')]
    param(
        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String[]]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ValidateMandatoryFileTask
{
    [Whiskey.Task('ValidateMandatoryFileTask')]
    param(
        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File')]
        [String]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ValidateOptionalFileTask
{
    [Whiskey.Task('ValidateOptionalFileTask')]
    param(
        [Whiskey.Tasks.ValidatePath(PathType='File')]
        [String]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ValidateMandatoryNonexistentFileTask
{
    [Whiskey.Task('ValidateMandatoryNonexistentFileTask')]
    param(
        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',AllowNonexistent)]
        [String]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ValidateMandatoryNonexistentOutsideBuildRootFileTask
{
    [Whiskey.Task('ValidateMandatoryNonexistentOutsideBuildRootFileTask')]
    param(
        [Whiskey.Tasks.ValidatePath(Mandatory,PathType='File',AllowNonexistent,AllowOutsideBuildRoot)]
        [String]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ValidateMandatoryPathTask
{
    [Whiskey.Task('ValidateMandatoryPathTask')]
    param(
        [Whiskey.Tasks.ValidatePath(Mandatory)]
        [String]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ValidateOptionalNonexistentPathTask
{
    [Whiskey.Task('ValidateOptionalNonexistentPathTask')]
    param(
        [Whiskey.Tasks.ValidatePath(AllowNonexistent)]
        [String]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ValidateOptionalPathsTask
{
    [Whiskey.Task('ValidateOptionalPathsTask')]
    param(
        [Whiskey.Tasks.ValidatePath()]
        [String[]]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}

function ValidateOptionalPathTask
{
    [Whiskey.Task('ValidateOptionalPathTask')]
    param(
        [Whiskey.Tasks.ValidatePath()]
        [String]$Path
    )

    $script:lastTaskBoundParameters = $PSBoundParameters
}
        
function WindowsOnlyTask
{
    [Whiskey.Task('WindowsOnlyTask',Platform='Windows')]
    [CmdletBinding()]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function WindowsAndLinuxTask
{
    [Whiskey.Task('WindowsAndLinuxTask',Platform='Windows,Linux')]
    [CmdletBinding()]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )
}

function WrapsNoOpTask
{
    [Whiskey.Task('WrapsNoOpTask')]
    [CmdletBinding()]
    param(
        [Whiskey.Context]$TaskContext,
        [hashtable]$TaskParameter
    )

    Invoke-WhiskeyTask -TaskContext $TaskContext -Parameter $TaskParameter -Name 'NoOpTask'
}
