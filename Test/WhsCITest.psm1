
function New-WhsCITestContext
{
    param(
        [Switch]
        $WithMockToolData,

        [string]
        $ForRepositoryRoot
    )

    Set-StrictMode -Version 'Latest'

    if( -not $ForRepositoryRoot )
    {
        $ForRepositoryRoot = $TestDrive.FullName
    }

    if( -not [IO.Path]::IsPathRooted($ForRepositoryRoot) )
    {
        $ForRepositoryRoot = Join-Path -Path $TestDrive.FullName -ChildPath $ForRepositoryRoot
    }

    $context = [pscustomobject]@{
                                    TaskPathRoot = $TestDrive.FullName;
                                    RepositoryRoot = $ForRepositoryRoot;
                                    OutputDirectory = (Join-Path -Path $ForRepositoryRoot -ChildPath '.output');
                                    Version = [semversion.SemanticVersion]'1.2.3-rc.1+build';
                                    ProGetAppFeedUri = 'http://proget.example.com/';
                                    ProGetCredential = New-Credential -UserName 'fubar' -Password 'snafu';
                                    BuildMasterSession = 'buildmaster session'
                                 }
    New-Item -Path $context.OutputDirectory -ItemType 'Directory' -Force -ErrorAction Ignore | Out-String | Write-Debug
    return $context
}

Export-ModuleMember -Function '*'