
function New-WhsCITestContext
{
    param(
        [Switch]
        $WithMockToolData,

        [string]
        $ForBuildRoot
    )

    Set-StrictMode -Version 'Latest'

    if( -not $ForBuildRoot )
    {
        $ForBuildRoot = $TestDrive.FullName
    }

    if( -not [IO.Path]::IsPathRooted($ForBuildRoot) )
    {
        $ForBuildRoot = Join-Path -Path $TestDrive.FullName -ChildPath $ForBuildRoot
    }

    $context = [pscustomobject]@{
                                    BuildRoot = $ForBuildRoot;
                                    OutputDirectory = (Join-Path -Path $ForBuildRoot -ChildPath '.output');
                                    Version = [semversion.SemanticVersion]'1.2.3-rc.1+build';
                                    ProGetAppFeedUri = 'http://proget.example.com/';
                                    ProGetCredential = New-Credential -UserName 'fubar' -Password 'snafu';
                                    BuildMasterSession = 'buildmaster session'
                                 }
    New-Item -Path $context.OutputDirectory -ItemType 'Directory' -Force -ErrorAction Ignore | Out-String | Write-Debug
    return $context
}

Export-ModuleMember -Function '*'