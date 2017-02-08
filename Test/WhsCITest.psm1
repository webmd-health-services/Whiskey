
function New-WhsCITestContext
{
    param(
        [Switch]
        $WithMockToolData
    )

    [pscustomobject]@{
                        TaskPathRoot = $TestDrive.FullName;
                        Version = [semversion.SemanticVersion]'1.2.3-rc.1+build';
                        ProGetAppFeedUri = 'http://proget.example.com/';
                        ProGetCredential = New-Credential -UserName 'fubar' -Password 'snafu';
                        BuildMasterSession = 'buildmaster session'
                     }
}

Export-ModuleMember -Function '*'