
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'about_Whiskey_Tasks' {
    It ('should include all known tasks') {
        $helpTopic = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Whiskey\en-US\about_Whiskey_Tasks.help.txt' -Resolve) -Raw

        $missingTasks = Get-WhiskeyTask |
                            Select-Object -ExpandProperty 'Name' |
                            Where-Object { @( 'DotNetBuild', 'DotNetPack', 'DotNetPublish', 'DotNetTest', 'Node', 'NodeNspCheck', 'NpmConfig', 'NpmInstall', 'NpmPrune', 'NpmRunScript', 'PublishNuGetPackage', 'PublishNuGetLibrary' ) -notcontains $_ } |
                            Where-Object { $helpTopic -notmatch [regex]::Escape('`{0}`' -f $_) }

        $missingTasks | Should -BeNullOrEmpty
    }
}