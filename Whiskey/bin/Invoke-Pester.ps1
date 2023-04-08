[CmdletBinding()]
param(
    [String] $ParameterBase64
)

#Requires -Version 5.1
Set-StrictMode -Version 'Latest'
$ErrorActionPreference = 'Stop'

function Convert-ArrayList
{
    param(
        [Parameter(Mandatory)]
        [Collections.ICollection] $InputObject
    )

    foreach( $entry in @($InputObject.GetEnumerator()) )
    {
        if( $entry.Value -is [Collections.ICollection] -and $entry.Value.PSobject.Properties.Name -contains 'Values' )
        {
            Convert-ArrayList $entry.Value
            continue
        }

        # PesterConfiguration only wants arrays for its lists. It doesn't handle any other list object.
        if( $entry.Value -is [Collections.IList] -and  $entry.Value -isnot [Array] )
        {
            $InputObject[$entry.Key] = ($entry.Value.GetEnumerator() | ForEach-Object { $_ }) -as [Array]
            continue
        }
    }
}

function Convert-Boolean
{
    param(
        [Parameter(Mandatory)]
        [Collections.ICollection] $InputObject
    )

    foreach( $entry in @($InputObject.GetEnumerator()) )
    {
        if( $entry.Value -is [Collections.ICollection] -and $entry.Value.PSobject.Properties.Name -contains 'Values' )
        {
            Convert-Boolean $entry.Value
            continue
        }

        # PesterConfiguration does not accept strings for boolean values. True has to be $true
        if( $entry.Value -is [String] -and  $entry.Value -eq 'True' -or $entry.Value -eq 'False' )
        {
            $InputObject[$entry.Key] = [System.Convert]::ToBoolean($entry.Value)
            continue
        }
    }
}

function Get-PesterContainer
{
    param(
        [Parameter(Mandatory)]
        [hashtable] $Container
    )

    if( $Container.ContainsKey('Path') )
    {
        return New-PesterContainer -Path $Container['Path'] -Data $Container['Data']
    }
    if( $Container.ContainsKey('ScriptBlock') )
    {
        if( $Container['ScriptBlock'] -isnot [scriptblock] )
        {
            $Container['ScriptBlock'] = [scriptblock]::Create($Container['ScriptBlock'])
        }
        return New-PesterContainer -ScriptBlock $Container['ScriptBlock'] -Data $Container['Data']
    }
}

function ConvertTo-Hashtable
{
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object] $InputObject
    )

    $Destination = @{}

    foreach ($memberName in ($InputObject | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty 'Name'))
    {
        $memberValue = $InputObject.$memberName
        if ($memberValue -is [psobject])
        {
            $memberValue = $memberValue | ConvertTo-Hashtable
        }
        $Destination[$memberName] = $memberValue
    }

    return $Destination
}

$parameterBytes = [Convert]::FromBase64String($ParameterBase64)
$ParameterJson = [Text.Encoding]::Unicode.GetString($parameterBytes)

$Parameter = $ParameterJson | ConvertFrom-Json | ConvertTo-Hashtable

$WorkingDirectory = $Parameter['WorkingDirectory']
$PesterManifestPath = $Parameter['PesterManifestPath']
$Configuration = $Parameter['Configuration']
$Container = $Parameter['Container']
$ExitCodePath = $Parameter['ExitCodePath']
$Preference = $Parameter['Preference']

Set-Location -Path $WorkingDirectory

$VerbosePreference = 'SilentlyContinue'
Import-Module -Name $PesterManifestPath -Verbose:$false -WarningAction Ignore

$ProgressPreference = $Preference['ProgressPreference']
$WarningPreference = $Preference['WarningPreference']
$InformationPreference = $Preference['InformationPreference']
$VerbosePreference = $Preference['VerbosePreference']
$DebugPreference = $Preference['DebugPreference']

Convert-ArrayList -InputObject $Configuration
Convert-Boolean -InputObject $Configuration

# New Pester5 Invoke-Pester with Configuration
$pesterConfiguration = New-PesterConfiguration -Hashtable $Configuration

# If there is test data we have to set up a Pester Container
if( $Container )
{
    $pesterConfiguration.Run.Container = Get-PesterContainer -Container $Container
}

try
{
    $LASTEXITCODE = 0
    Invoke-Pester -Configuration $pesterConfiguration
}
finally
{
    Write-Debug "Pester  LASTEXITCODE  $($LASTEXITCODE)"
    $LASTEXITCODE | Set-Content -Path $ExitCodePath
}
