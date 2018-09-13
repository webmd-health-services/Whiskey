
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1')

Describe ('Documentation') {
    $tasksMissingDocs = Get-WhiskeyTask |
                            Select-Object -ExpandProperty 'Name'|
                            Where-Object { $_ -notin @( 'NodeNspCheck', 'Node', 'NpmConfig', 'NpmInstall', 'NpmPrune', 'NpmRunScript', 'PublishNuGetLibrary', 'PublishNuGetPackage' ) } |
                            Where-Object { 
                                -not (Get-Help -Name ('about_Whiskey_{0}_Task' -f $_))
                            } 
    It ('should have about_Whiskey_*_Task help topic for every task') {
        $tasksMissingDocs | Should -BeNullOrEmpty
    }
    
}