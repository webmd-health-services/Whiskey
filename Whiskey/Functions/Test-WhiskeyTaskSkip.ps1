
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

    if ($Properties['OnlyBy'] -and $Properties['ExceptBy'])
    {
        $msg = 'This task defines both "OnlyBy" and "ExceptBy" properties. Only one of these can be used. Please ' +
               'remove one or both of these properties and re-run your build.'
        Stop-WhiskeyTask -TaskContext $Context -Message $msg
        return
    }
    elseif ($Properties['OnlyBy'])
    {
        [Whiskey.RunBy]$onlyBy = [Whiskey.RunBy]::Developer
        if (-not ([Enum]::TryParse($Properties['OnlyBy'], [ref]$onlyBy)))
        {
            $msg = "invalid value: ""$($Properties['OnlyBy'])"". Valid values are " +
                  """$([Enum]::GetValues([Whiskey.RunBy]) -join '", "')"")."
            Stop-WhiskeyTask -TaskContext $Context -PropertyName 'OnlyBy' -Message $msg
            return
        }

        if ($onlyBy -ne $Context.RunBy)
        {
            $msg = "OnlyBy.${onlyBy} -ne Build.RunBy.$($Context.RunBy)"
            Write-WhiskeyVerbose -Context $Context -Message $msg
            return $true
        }
    }
    elseif ($Properties['ExceptBy'])
    {
        [Whiskey.RunBy]$exceptBy = [Whiskey.RunBy]::Developer
        if (-not ([Enum]::TryParse($Properties['ExceptBy'], [ref]$exceptBy)))
        {
            $runByValuesList = [Enum]::GetValues([Whiskey.RunBy]) -join '", "'
            $msg = "invalid value: ""$($Properties['ExceptBy'])"". Valid values are ""${runByValuesList}""."
            Stop-WhiskeyTask -TaskContext $Context -PropertyName 'ExceptBy' -Message $msg
            return
        }

        if ($exceptBy -eq $Context.RunBy)
        {
            Write-WhiskeyVerbose -Context $Context -Message "ExceptBy.${exceptBy} -eq Build.RunBy.$($Context.RunBy)"
            return $true
        }
    }

    $branch = $Context.BuildMetadata.ScmBranch

    if ($Properties['OnlyOnBranch'] -and $Properties['ExceptOnBranch'])
    {
        $msg = 'This task defines both OnlyOnBranch and ExceptOnBranch properties. Only one of these can be used. ' +
               'Please remove one or both of these properties and re-run your build.'
        Stop-WhiskeyTask -TaskContext $Context -Message $msg
        return
    }

    if ($Properties['OnlyOnBranch'])
    {
        $runTask = $false
        Write-WhiskeyVerbose -Context $Context -Message ('OnlyOnBranch')
        foreach( $wildcard in $Properties['OnlyOnBranch'] )
        {
            if( $branch -like $wildcard )
            {
                $runTask = $true
                Write-WhiskeyVerbose -Context $Context -Message "              ${branch}     -like  ${wildcard}"
                break
            }

            Write-WhiskeyVerbose -Context $Context -Message     "              ${branch}  -notlike  ${wildcard}"
        }

        if( -not $runTask )
        {
            return $true
        }
    }

    if( $Properties['ExceptOnBranch'] )
    {
        $runTask = $true
        Write-WhiskeyVerbose -Context $Context -Message ('ExceptOnBranch')
        foreach( $wildcard in $Properties['ExceptOnBranch'] )
        {
            if( $branch -like $wildcard )
            {
                $runTask = $false
                Write-WhiskeyVerbose -Context $Context -Message "                ${branch}     -like  ${wildcard}"
                break
            }

            Write-WhiskeyVerbose -Context $Context -Message     "                ${branch}  -notlike  ${wildcard}"
        }
        if( -not $runTask )
        {
            return $true
        }
    }

    $modes = @( 'Clean', 'Initialize', 'Build' )
    $modesDisplayList = $modes -join '", "'

    $onlyDuring = $Properties['OnlyDuring']
    $exceptDuring = $Properties['ExceptDuring']

    $validPlatformValues = [Enum]::GetValues([Whiskey.Platform]) | Where-Object { $_ -notin @( 'Unknown', 'All' ) }
    $platformsDisplayList = $validPlatformValues -join '", "'

    if ($onlyDuring -and $exceptDuring)
    {
        $msg = 'Both ''OnlyDuring'' and ''ExceptDuring'' properties are used. These properties are mutually ' +
               'exclusive, i.e. you may only specify one or the other.'
        Stop-WhiskeyTask -TaskContext $Context -Message $msg
        return
    }
    elseif ($onlyDuring -and ($onlyDuring -notin $modes))
    {
        $msg = "Property ""OnlyDuring"" has an invalid value: ""${onlyDuring}"". Valid values are: " +
               """${modesDisplayList}""."
        Stop-WhiskeyTask -TaskContext $Context -Message $msg
        return
    }
    elseif ($exceptDuring -and ($exceptDuring -notin $modes))
    {
        $msg = "Property ""ExceptDuring"" has an invalid value: ""${exceptDuring}"". Valid values are: " +
               """${modesDisplayList}""."
        Stop-WhiskeyTask -TaskContext $Context -Message $msg
        return
    }

    if ($onlyDuring -and ($Context.RunMode -ne $onlyDuring))
    {
        $msg = "OnlyDuring.${onlyDuring} -ne Build.RunMode.$($Context.RunMode)"
        Write-WhiskeyVerbose -Context $Context -Message $msg
        return $true
    }
    elseif ($exceptDuring -and ($Context.RunMode -eq $exceptDuring))
    {
        $msg = "ExceptDuring.${exceptDuring} -ne Build.RunMode.$($Context.RunMode)"
        Write-WhiskeyVerbose -Context $Context -Message $msg
        return $true
    }

    if ($Properties['IfExists'])
    {
        $exists = Test-Path -Path $Properties['IfExists']
        if( -not $exists )
        {
            Write-WhiskeyVerbose -Context $Context -Message "IfExists  $($Properties['IfExists'])  not exists"
            return $true
        }
        Write-WhiskeyVerbose -Context $Context -Message     "IfExists  $($Properties['IfExists'])      exists"
    }

    if ($Properties['UnlessExists'])
    {
        $exists = Test-Path -Path $Properties['UnlessExists']
        if( $exists )
        {
            Write-WhiskeyVerbose -Context $Context -Message "UnlessExists  $($Properties['UnlessExists'])      exists"
            return $true
        }
        Write-WhiskeyVerbose -Context $Context -Message     "UnlessExists  $($Properties['UnlessExists'])  not exists"
    }

    if ($Properties['OnlyIfBuild'])
    {
        [Whiskey.BuildStatus] $buildStatus = [Whiskey.BuildStatus]::Succeeded
        if (-not ([Enum]::TryParse($Properties['OnlyIfBuild'], [ref]$buildStatus)))
        {
            $buildStatusDisplayList = [Enum]::GetValues([Whiskey.BuildStatus]) -join '", "'
            $msg = "invalid value: ""$($Properties['OnlyIfBuild'])"". Valid values are ""${buildStatusDisplayList}""."
            Stop-WhiskeyTask -TaskContext $Context -PropertyName 'OnlyIfBuild' -Message $msg
            return
        }

        if ($buildStatus -ne $Context.BuildStatus)
        {
            $msg = "OnlyIfBuild.${buildStatus} -ne Build.BuildStatus.$($Context.BuildStatus)"
            Write-WhiskeyVerbose -Context $Context -Message $msg
            return $true
        }
    }

    if ($Properties['OnlyOnPlatform'])
    {
        $shouldSkip = $true
        [Whiskey.Platform] $platform = [Whiskey.Platform]::Unknown
        foreach( $item in $Properties['OnlyOnPlatform'] )
        {
            if (-not [Enum]::TryParse($item,[ref]$platform))
            {
                $msg = "Invalid platform ""${item}"". Valid values are ""${platformsDisplayList}""."
                Stop-WhiskeyTask -TaskContext $Context -PropertyName 'OnlyOnPlatform' -Message
                return
            }

            $platform = [Whiskey.Platform]$item
            if ($CurrentPlatform.HasFlag($platform))
            {
                Write-WhiskeyVerbose -Context $Context -Message "OnlyOnPlatform    ${platform} -eq ${currentPlatform}"
                $shouldSkip = $false
                break
            }
            else
            {
                Write-WhiskeyVerbose -Context $Context -Message "OnlyOnPlatform  ! ${platform} -ne ${currentPlatform}"
            }
        }
        return $shouldSkip
    }


    if ($Properties['ExceptOnPlatform'])
    {
        $shouldSkip = $false
        [Whiskey.Platform]$platform = [Whiskey.Platform]::Unknown
        foreach ($item in $Properties['ExceptOnPlatform'])
        {
            if (-not [Enum]::TryParse($item, [ref]$platform))
            {
                $msg = "Invalid platform ""${item}"". Valid values are ""${validPlatformValues}".""
                Stop-WhiskeyTask -TaskContext $Context -PropertyName 'ExceptOnPlatform' -Message $msg
                return
            }

            $platform = [Whiskey.Platform]$item
            if ($CurrentPlatform.HasFlag($platform))
            {
                Write-WhiskeyVerbose -Context $Context -Message "ExceptOnPlatform  ! ${plaform} -eq ${currentPlatform}"
                $shouldSkip = $true
                break
            }
            else
            {
                Write-WhiskeyVerbose -Context $Context -Message "ExceptOnPlatform    ${plaform} -ne ${currentPlatform}"
            }
        }
        return $shouldSkip
    }

    return $false
}
