 
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'ConvertFrom-WhiskeyContext.when has API keys' {
    $context = New-Object 'Whiskey.Context'
    Add-WhiskeyApiKey -Context $context -ID 'Fubar' -Value 'Snafu'

    $serializableContext = ConvertFrom-WhiskeyContext -Context $context
    It ('should encrypt API keys') {
        $serializableContext.ApiKeys['Fubar'] | Should -BeOfType 'string'
        $serializableContext.ApiKeys['Fubar'] | Should -Not -Be 'Snafu'
    }

    It ('should save encryption key') {
        $serializableContext.CredentialKey | Should -Not -BeNullOrEmpty
    }

    $deserializedContext = $serializableContext | ConvertTo-WhiskeyContext
    It ('should decrypt API keys') {
        $deserializedContext | Should -BeOfType 'Whiskey.Context'
        $deserializedContext.ApiKeys['Fubar'] | Should -BeOfType 'securestring'
        Get-WhiskeyApiKey -Context $deserializedContext -ID 'Fubar' -PropertyName 'Fubar' | Should -BeExactly 'Snafu'
    }

}