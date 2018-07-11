
function Test-WhiskeyTaskSkip
{
    <#
    .SYNOPSIS
    Determines if the current Whiskey task should be skipped.

    .DESCRIPTION
    The `Test-WhiskeyTaskSkip` function returns `$true` or `$false` indicating whether the current Whiskey task should be skipped. It determines if the task should be skipped by comparing values in the Whiskey context and common task properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Whiskey.Context]
        # The context for the build.
        $Context,

        [Parameter(Mandatory=$true)]
        [hashtable]
        # The common task properties defined for the current task.
        $Properties
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    if( $Properties['OnlyBy'] -and $Properties['ExceptBy'] )
    {
        Stop-WhiskeyTask -TaskContext $Context -Message ('This task defines both "OnlyBy" and "ExceptBy" properties. Only one of these can be used. Please remove one or both of these properties and re-run your build.')
        return
    }
    elseif( $Properties['OnlyBy'] )
    {
        [Whiskey.RunBy]$onlyBy = [Whiskey.RunBy]::Developer
        if( -not ([enum]::TryParse($Properties['OnlyBy'], [ref]$onlyBy)) )
        {
            Stop-WhiskeyTask -TaskContext $Context -PropertyName 'OnlyBy' -Message ('invalid value: ''{0}''. Valid values are ''{1}''.' -f $Properties['OnlyBy'],([enum]::GetValues([Whiskey.RunBy]) -join ''', '''))
            return
        }

        if( $onlyBy -ne $Context.RunBy )
        {
            Write-WhiskeyVerbose -Context $Context -Message ('OnlyBy.{0} -ne Build.RunBy.{1}' -f $onlyBy,$Context.RunBy)
            return $true
        }
    }
    elseif( $Properties['ExceptBy'] )
    {
        [Whiskey.RunBy]$exceptBy = [Whiskey.RunBy]::Developer
        if( -not ([enum]::TryParse($Properties['ExceptBy'], [ref]$exceptBy)) )
        {
            Stop-WhiskeyTask -TaskContext $Context -PropertyName 'ExceptBy' -Message ('invalid value: ''{0}''. Valid values are ''{1}''.' -f $Properties['ExceptBy'],([enum]::GetValues([Whiskey.RunBy]) -join ''', '''))
            return
        }

        if( $exceptBy -eq $Context.RunBy )
        {
            Write-WhiskeyVerbose -Context $Context -Message ('ExceptBy.{0} -eq Build.RunBy.{1}' -f $exceptBy,$Context.RunBy)
            return $true
        }
    }

    $branch = $Context.BuildMetadata.ScmBranch

    if( $Properties['OnlyOnBranch'] -and $Properties['ExceptOnBranch'] )
    {
        Stop-WhiskeyTask -TaskContext $Context -Message ('This task defines both OnlyOnBranch and ExceptOnBranch properties. Only one of these can be used. Please remove one or both of these properties and re-run your build.')
        return
    }

    if( $Properties['OnlyOnBranch'] )
    {
        $runTask = $false
        Write-WhiskeyVerbose -Context $Context -Message ('OnlyOnBranch')
        foreach( $wildcard in $Properties['OnlyOnBranch'] )
        {
            if( $branch -like $wildcard )
            {
                $runTask = $true
                Write-WhiskeyVerbose -Context $Context -Message ('              {0}     -like  {1}' -f $branch, $wildcard)
                break
            }

            Write-WhiskeyVerbose -Context $Context -Message     ('              {0}  -notlike  {1}' -f $branch, $wildcard)
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
                Write-WhiskeyVerbose -Context $Context -Message ('                {0}     -like  {1}' -f $branch, $wildcard)
                break
            }

            Write-WhiskeyVerbose -Context $Context -Message     ('                {0}  -notlike  {1}' -f $branch, $wildcard)
        }
        if( -not $runTask )
        {
            return $true
        }
    }

    $modes = @( 'Clean', 'Initialize', 'Build' )
    $onlyDuring = $Properties['OnlyDuring']
    $exceptDuring = $Properties['ExceptDuring']

    if ($onlyDuring -and $exceptDuring)
    {
        Stop-WhiskeyTask -TaskContext $Context -Message 'Both ''OnlyDuring'' and ''ExceptDuring'' properties are used. These properties are mutually exclusive, i.e. you may only specify one or the other.'
        return
    }
    elseif ($onlyDuring -and ($onlyDuring -notin $modes))
    {
        Stop-WhiskeyTask -TaskContext $Context -Message ('Property ''OnlyDuring'' has an invalid value: ''{0}''. Valid values are: ''{1}''.' -f $onlyDuring,($modes -join "', '"))
        return
    }
    elseif ($exceptDuring -and ($exceptDuring -notin $modes))
    {
        Stop-WhiskeyTask -TaskContext $Context -Message ('Property ''ExceptDuring'' has an invalid value: ''{0}''. Valid values are: ''{1}''.' -f $exceptDuring,($modes -join "', '"))
        return
    }

    if ($onlyDuring -and ($Context.RunMode -ne $onlyDuring))
    {
        Write-WhiskeyVerbose -Context $Context -Message ('OnlyDuring.{0} -ne Build.RunMode.{1}' -f $onlyDuring,$Context.RunMode)
        return $true
    }
    elseif ($exceptDuring -and ($Context.RunMode -eq $exceptDuring))
    {
        Write-WhiskeyVerbose -Context $Context -Message ('ExceptDuring.{0} -ne Build.RunMode.{1}' -f $exceptDuring,$Context.RunMode)
        return $true
    }

    if( $Properties['IfExists'] )
    {
        $exists = Test-Path -Path $Properties['IfExists']
        if( -not $exists )
        {
            Write-WhiskeyVerbose -Context $Context -Message ('IfExists  {0}  not exists' -f $Properties['IfExists']) -Verbose
            return $true
        }
        Write-WhiskeyVerbose -Context $Context -Message     ('IfExists  {0}      exists' -f $Properties['IfExists']) -Verbose
    }

    if( $Properties['UnlessExists'] )
    {
        $exists = Test-Path -Path $Properties['UnlessExists']
        if( $exists )
        {
            Write-WhiskeyVerbose -Context $Context -Message ('UnlessExists  {0}      exists' -f $Properties['UnlessExists']) -Verbose
            return $true
        }
        Write-WhiskeyVerbose -Context $Context -Message     ('UnlessExists  {0}  not exists' -f $Properties['UnlessExists']) -Verbose
    }

    if( $Properties['OnlyIfBuild'] )
    {
        [Whiskey.BuildStatus]$buildStatus = [Whiskey.BuildStatus]::Succeeded
        if( -not ([enum]::TryParse($Properties['OnlyIfBuild'], [ref]$buildStatus)) )
        {
            Stop-WhiskeyTask -TaskContext $Context -PropertyName 'OnlyIfBuild' -Message ('invalid value: ''{0}''. Valid values are ''{1}''.' -f $Properties['OnlyIfBuild'],([enum]::GetValues([Whiskey.BuildStatus]) -join ''', '''))
            return
        }

        if( $buildStatus -ne $Context.BuildStatus )
        {
            Write-WhiskeyVerbose -Context $Context -Message ('OnlyIfBuild.{0} -ne Build.BuildStatus.{1}' -f $buildStatus,$Context.BuildStatus)
            return $true
        }
    }

    return $false
}
