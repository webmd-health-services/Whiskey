
if( (Get-Module -Name 'BitbucketServerAutomation') )
{
    Remove-Module -Name 'BitbucketServerAutomation' -Force
}

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath 'BitbucketServerAutomation.psd1' -Resolve)
