<#
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    # Path to the root of the wiki repository.
    [string]$Path,

    [Parameter(Mandatory)]
    # The name of the module whose help you're exporting.
    [string]$ModuleName,

    [Parameter(Mandatory)]
    # The path to the root of the module. Used to import the module so we can get at its help topics.
    [string]$ModuleRoot,

    # The help topic to use for your wiki's home page. The default is `about_$ModuleName`.
    [string]$HomeHelpTopic
)

#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

Import-Module -Name $ModuleRoot -Force

if( -not $HomeHelpTopic )
{
    $HomeHelpTopic = 'about_{0}' -f $ModuleName
}

$homeTopic = Get-Help $HomeHelpTopic 
$homePath = Join-Path -Path $Path -ChildPath 'Home.md'

$pageContent = New-Object -TypeName 'Text.StringBuilder'
foreach( $line in $homeTopic )
{
    if( $line -cmatch '^[A-Z][A-Z ]+$' )
    {
        $line = '# {0}' -f $line
    }
    elseif( $line -match '^ +' )
    {
        $line = $line -replace '^    ',''
    }

    [void]$pageContent.AppendLine($line)
}

[IO.File]::WriteAllText($homePath,$pageContent.ToString())
