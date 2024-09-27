
function Test-WhiskeyTaskSkip
{
    <#
    .SYNOPSIS
    Determines if the current Whiskey task should be skipped.

    .DESCRIPTION
    The `Test-WhiskeyTaskSkip` function returns `$true` or `$false` indicating whether the current Whiskey task should
    be skipped. It determines if the task should be skipped by comparing values in the Whiskey context and common task
    properties.
    #>
    [CmdletBinding()]
    param(
        # The context for the build.
        [Parameter(Mandatory)]
        [Whiskey.Context] $Context,

        # The common task properties defined for the current task.
        [Parameter(Mandatory)]
        [hashtable] $Properties
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if ($Properties.Count -eq 0)
    {
        return $false
    }

    function Test-RunBy
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $DesiredValue,

            [Parameter(Mandatory)]
            [String] $PropertyName
        )

        [Whiskey.RunBy] $runBy = [Whiskey.RunBy]::Developer
        if (-not ([Enum]::TryParse($DesiredValue, [ref]$runBy)))
        {
            $valuesList = [Enum]::GetValues([Whiskey.RunBy]) -join '", "'
            $msg = "invalid value ""${DesiredValue}"". Valid values are ""${valuesList}""."
            Stop-WhiskeyTask -TaskContext $Context -PropertyName $PropertyName -Message $msg
            return
        }

        return $runBy -eq $Context.RunBy
    }

    function Test-RunMode
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $DesiredValue,

            [Parameter(Mandatory)]
            [String] $PropertyName
        )

        [Whiskey.RunMode] $runMode = [Whiskey.RunMode]::Initialize
        if (-not ([Enum]::TryParse($DesiredValue, [ref]$runMode)))
        {
            $valuesList = [Enum]::GetValues([Whiskey.RunMode]) -join '", "'
            $msg = "invalid value ""${DesiredValue}"". Valid values are ""${valuesList}""."
            Stop-WhiskeyTask -TaskContext $Context -PropertyName $PropertyName -Message $msg
            return
        }

        return $runMode -eq $Context.RunMode
    }

    function Test-Platform
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $DesiredValue,

            [Parameter(Mandatory)]
            [String] $PropertyName
        )

        [Whiskey.Platform] $platform = [Whiskey.Platform]::Unknown
        if (-not ([Enum]::TryParse($DesiredValue, [ref]$platform)))
        {
            $validValues = [Enum]::GetValues([Whiskey.Platform]) | Where-Object { $_ -notin @( 'Unknown', 'All' ) }
            $valuesList = $validValues -join '", "'
            $msg = "invalid platform ""${DesiredValue}"". Valid values are ""${valuesList}""."
            Stop-WhiskeyTask -TaskContext $Context -PropertyName $PropertyName -Message $msg
            return
        }

        return $platform -eq $script:currentPlatform
    }

    function Assert-MutuallyExclusiveProperty
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String[]] $PropertyName
        )

        foreach ($_propertyName in $PropertyName)
        {
            if (-not $Properties.ContainsKey($_propertyName))
            {
                return $false
            }
        }

        $propertyNamesMsg = ($PropertyName | Select-Object -SkipLast 1) -join '", "'
        $lastPropertyName = $PropertyName | Select-Object -Last 1

        $msg = "Uses ""${propertyNamesMsg}"" and ""${lastPropertyName}"" properties. Only one of these can be used. " +
               'Please remove one or both of these properties and re-run your build.'
        Stop-WhiskeyTask -TaskContext $Context -Message $msg
        return $true
    }

    if ((Assert-MutuallyExclusiveProperty -PropertyName $script:exceptByPropertyName,$script:onlyByPropertyName) -or `
        (Assert-MutuallyExclusiveProperty -PropertyName $script:exceptDuringPropertyName,$script:onlyDuringPropertyName) -or `
        (Assert-MutuallyExclusiveProperty -PropertyName $script:exceptOnBranchPropertyName,$script:onlyOnBranchPropertyName) -or `
        (Assert-MutuallyExclusiveProperty -PropertyName $script:exceptOnPlatformPropertyName,$script:onlyOnPlatformPropertyName))
    {
        return
    }

    $results = [Collections.ArrayList]::New()

    try
    {
        foreach ($propertyName in $script:skipPropertyNames)
        {
            if (-not $Properties.ContainsKey($propertyName))
            {
                continue
            }

            $conditions = $Properties[$propertyName]

            $conditionInfo = [pscustomobject]@{
                Name = $propertyName;
                Condition = $conditions
                State = $null;
                RunTask = $true;
            }

            [void]$results.Add($conditionInfo)

            $conditionValue = $null
            $runTask = $true

            switch ($propertyName)
            {
                $script:exceptByPropertyName
                {
                    $conditionValue = $Context.RunBy
                    $runTask = -not (Test-RunBy -DesiredValue $conditions -PropertyName $propertyName)
                }

                $script:exceptDuringPropertyName
                {
                    $conditionValue = $Context.RunMode

                    $foundMatch = $false
                    foreach ($condition in $conditions)
                    {
                        if (Test-RunMode -DesiredValue $condition -PropertyName $propertyName)
                        {
                            $foundMatch = $true
                            break
                        }
                    }

                    $runTask = -not $foundMatch
                }

                $script:exceptOnBranchPropertyName
                {
                    $branchName = $conditionValue = $Context.BuildMetadata.ScmBranch

                    $foundMatch = $false
                    foreach ($condition in $conditions)
                    {
                        if ($branchName -like $condition)
                        {
                            $foundMatch = $true
                            break
                        }
                    }
                    $runTask = -not $foundMatch
                }

                $script:exceptOnPlatformPropertyName
                {
                    $conditionValue = $script:currentPlatform

                    $foundMatch = $false
                    foreach ($condition in $conditions)
                    {
                        if (Test-Platform -DesiredValue $condition -PropertyName $propertyName)
                        {
                            $foundMatch = $true
                            break
                        }
                    }

                    $runTask = -not $foundMatch
                }

                $script:ifExistsPropertyName
                {
                    $pathExists = Test-Path -Path $conditions

                    $conditionValue = $pathExists

                    $runTask = $pathExists
                }

                $script:onlyByPropertyName
                {
                    $conditionValue = $Context.RunBy
                    $runTask = (Test-RunBy -DesiredValue $conditions -PropertyName $propertyName)
                }

                $script:onlyDuringPropertyName
                {
                    $conditionValue = $Context.RunMode

                    $foundMatch = $false
                    foreach ($condition in $conditions)
                    {
                        if (Test-RunMode -DesiredValue $condition -PropertyName $propertyName)
                        {
                            $foundMatch = $true
                            break
                        }
                    }

                    $runTask = $foundMatch
                }

                $script:onlyOnBranchPropertyName
                {
                    $branchName = $conditionValue = $Context.BuildMetadata.ScmBranch

                    $foundMatch = $false
                    foreach ($condition in $conditions)
                    {
                        if ($branchName -like $condition)
                        {
                            $foundMatch = $true
                            break
                        }
                    }
                    $runTask = $foundMatch
                }

                $script:onlyOnPlatformPropertyName
                {
                    $conditionValue = $script:currentPlatform

                    $foundMatch = $false
                    foreach ($condition in $conditions)
                    {
                        if (Test-Platform -DesiredValue $condition -PropertyName $propertyName)
                        {
                            $foundMatch = $true
                            break
                        }
                    }

                    $runTask = $foundMatch
                }

                $script:unlessExistsPropertyName
                {
                    $pathExists = Test-Path -Path $conditions

                    $conditionValue = $pathExists

                    $runTask = -not $pathExists
                }

            }

            $conditionInfo.State = $conditionValue
            $conditionInfo.RunTask = $runTask
            if (-not $runTask)
            {
                # This function should indicate if the task should be *skipped*.
                return $true
            }
        }
    }
    finally
    {
        $msg = $results | Format-Table -AutoSize | Out-String
        $msg -split '\r?\n' | Write-WhiskeyVerbose -Context $Context
    }

    return $false
}
