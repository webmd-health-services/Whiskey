
$cred = New-Object 'pscredential' 'username',(ConvertTo-SecureString -String 'password' -AsPlainText -Force)

#$password = ConvertFrom-SecureString -SecureString $cred.Password -Key ([byte[]]@( '1', '1', '1', '1','1', '1', '1', '1','1', '1', '1', '1','1', '1', '1', '1' ))
$job = Start-Job { 
    param(
        $UserName,
        [securestring]
        $Password
    )
    
    $Credential = New-Object 'pscredential' $UserName,$Password
    '{0}:{1}' -f $Credential.UserName,($Credential.GetNetworkCredential().Password)
} -ArgumentList $cred.UserName,$cred.Password

$job | Wait-Job | Receive-Job 
$job | Remove-Job