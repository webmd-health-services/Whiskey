
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'about_Whiskey_Tasks' {
    $helpTopic = help 'about_Whiskey_Tasks'

    $missingTasks = Get-WhiskeyTask |
                        Select-Object -ExpandProperty 'Name' |
                        Where-Object { @( 'Node', 'PublishNuGetPackage', 'PublishNuGetLibrary' ) -notcontains $_ } |
                        Where-Object { $helpTopic -notmatch [regex]::Escape('`{0}`' -f $_) }

    It ('should include all known tasks') {
        $missingTasks | Should -BeNullOrEmpty
    }
}