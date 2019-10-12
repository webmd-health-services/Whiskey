
$credentialKey = New-Object 'byte[]' (256/8)
$rng = New-Object 'Security.Cryptography.RNGCryptoServiceProvider'
$rng.GetBytes($credentialKey)

$serializableCredential = [pscustomobject]@{ 
                                                UserName = $credential.UserName;
                                                Password = ConvertFrom-SecureString -SecureString $credential.Password -Key $credentialKey
                                            }

$job = Start-Job {
    param(
        [Parameter(Mandatory)]
        [byte[]]
        $Key
    )
    $serializedCredential = $using:serializableCredential

    $password = ConvertTo-SecureString -String $serializedCredential.Password -Key $Key
    $credential = New-Object 'PSCredential' ($serializedCredential.UserName,$password)
    [Array]::Clear($Key,0,$Key.Length)
} -ArgumentList (,$credentialKey) | Wait-Job | Receive-Job

[Array]::Clear($credentialKey,0,$credentialKey.Length)
