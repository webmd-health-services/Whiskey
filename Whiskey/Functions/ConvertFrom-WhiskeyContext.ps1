
function ConvertFrom-WhiskeyContext
{
    <#
    .SYNOPSIS
    Converts a `Whiskey.Context` into a generic object that can be serialized across platforms.
    
    .DESCRIPTION
    Some tasks need to run in background jobs and need access to Whiskey's context. This function converts a `Whiskey.Context` object into an object that can be serialized by PowerShell across platforms. The object returned by this function can be passed to a `Start-Job` script block. Inside that script block you should import Whiskey and pass the serialized context to `ConvertTo-WhiskeyContext`.

        $serializableContext = $TaskContext | ConvertFrom-WhiskeyContext
        $job = Start-Job {
                    Invoke-Command -ScriptBlock {
                                            $VerbosePreference = 'SilentlyContinue';
                                            # Or wherever your project keeps Whiskey relative to your task definition.
                                            Import-Module -Name (Join-Path -Path $using:PSScriptRoot -ChildPath '..\Whiskey' -Resolve -ErrorAction Stop)
                                        }
                    $context = $using:serializableContext | ConvertTo-WhiskeyContext 
                    # Run your task
              }

    You should create a new serializable context for each job you are running. Whiskey generates a temporary encryption key so it can encrypt/decrypt credentials. Once it decrypts the credentials, it deletes the key from memory. If you use the same context object between jobs, one job will clear the key and other jobs will fail because the key will be gone.

    .EXAMPLE
    $TaskContext | ConvertFrom-WhiskeyContext

    Demonstrates how to call `ConvertFrom-WhiskeyContext`. See the description for a full example.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline)]
        [Whiskey.Context]
        # The context to convert. You can pass an existing context via the pipeline.
        $Context
    )

    begin 
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

        $key = New-Object 'byte[]' (256/8)
        $rng = New-Object 'Security.Cryptography.RNGCryptoServiceProvider'
        $rng.GetBytes($key)
    }

    process 
    {
        # PowerShell on Linux/MacOS can't serialize SecureStrings. So, we have to encrypt and serialize them.
        $serializableCredentials = @{ }
        foreach( $credentialID in $Context.Credentials.Keys )
        {
            [pscredential]$credential = $Context.Credentials[$credentialID]
            $serializableCredential = [pscustomobject]@{ 
                                                            UserName = $credential.UserName;
                                                            Password = ConvertFrom-SecureString -SecureString $credential.Password -Key $key
                                                        }
            $serializableCredentials[$credentialID] = $serializableCredential
        }

        $serializableApiKeys = @{ }
        foreach( $apiKeyID in $Context.ApiKeys.Keys )
        {
            [securestring]$apiKey = $Context.ApiKeys[$apiKeyID]
            $serializableApiKey = ConvertFrom-SecureString -SecureString $apiKey -Key $key
            $serializableApiKeys[$apiKeyID] = $serializableApiKey
        }

        $Context | 
            Select-Object -Property '*' -ExcludeProperty 'Credentials','ApiKeys' | 
            Add-Member -MemberType NoteProperty -Name 'Credentials' -Value $serializableCredentials -PassThru |
            Add-Member -MemberType NoteProperty -Name 'ApiKeys' -Value $serializableApiKeys -PassThru |
            Add-Member -MemberType NoteProperty -Name 'CredentialKey' -Value $key.Clone() -PassThru
    }

    end
    {
        [Array]::Clear($key,0,$key.Length)
    }
}