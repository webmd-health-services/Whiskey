
function New-WhsCIAppPackage
{
    <#
    .SYNOPSIS
    Creates a WHS application deployment package.

    .DESCRIPTION
    The `New-WhsCIAppPackage` function creates a universal ProGet package for a WHS application and optionally uploads it to ProGet. The package should contain everything the application needs to install itself and run on any server it is deployed to, with minimal/no pre-requisites installed. To upload to ProGet, provide the packages's ProGet URI and credentials with the `ProGetPackageUri` and `ProGetCredential` parameters, respectively.

    It returns an `IO.FileInfo` object for the created package.

    Packages are only allowed to have whitelisted files, i.e. you can't include all files by default. You must supply a value for the `Include` parameter that lists the file names or wildcards that match the files you want in your application.

    If the whitelist includes files that you want to exclude, or you want to omit certain directories, use the `Exclude` parameter. `New-WhsCIAppPackage` *always* excludes directories named:

     * `obj`
     * `.git`
     * `.hg`
    #>
    [CmdletBinding(DefaultParameterSetName='NoUpload')]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        # The path to the root of the repository the application lives in.
        $RepositoryRoot,

        [Parameter(Mandatory=$true)]
        [string]
        # The name of the package being created.
        $Name,

        [Parameter(Mandatory=$true)]
        [string]
        # A description of the package.
        $Description,

        [Parameter(Mandatory=$true)]
        [string]
        # The package's version.
        $Version,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The paths to include in the artifact. All items under directories are included.
        $Path,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The whitelist of files to include in the artifact. Wildcards supported. Only files that match entries in this list are included in the package.
        $Include,

        [Parameter(Mandatory=$true,ParameterSetName='WithUpload')]
        [string]
        # The URI to the package's feed in ProGet. The package will be uploaded to this feed.
        $ProGetPackageUri,

        [Parameter(Mandatory=$true,ParameterSetName='WithUpload')]
        [pscredential]
        # The credential to use to upload the package to ProGet.
        $ProGetCredential,
        
        [string[]]
        # A list of files and/or directories to exclude. Wildcards supported. If any file or directory that would match a pattern in the `Include` list matches an item in this list, it is not included in the package.
        # 
        # `New-WhsCIAppPackage` will *always* exclude directories named:
        #
        # * .git
        # * .hg
        # * obj
        $Exclude
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    $resolveErrors = @()
    $Path = $Path | Resolve-Path -ErrorVariable 'resolveErrors' | Select-Object -ExpandProperty 'ProviderPath'
    if( $resolveErrors )
    {
        throw ('Unable to create ''{0}'' package. One or more of the paths to include in the package don''t exist.'-f $Name)
        return
    }

    $arcPath = Join-Path -Path $RepositoryRoot -ChildPath 'Arc'
    if( -not (Test-Path -Path $arcPath -PathType Container) )
    {
        throw ('Unable to create ''{0}'' package because the Arc platform ''{1}'' does not exist. Arc is required when using the WhsCI module to package your application. See https://confluence.webmd.net/display/WHS/Arc for instructions on how to integrate Arc into your repository.' -f $Name,$arcPath)
        return
    }

    $fileName = '{0}.{1}.upack' -f $Name,$Version
    $outDirectory = Get-WhsCIOutputDirectory -WorkingDirectory $RepositoryRoot

    $outFile = Join-Path -Path $outDirectory -ChildPath $fileName

    $tempRoot = [IO.Path]::GetRandomFileName()
    $tempBaseName = 'WhsCI+New-WhsCIAppPackage+{0}' -f $Name
    $tempRoot = '{0}+{1}' -f $tempBaseName,$tempRoot
    $tempRoot = Join-Path -Path $env:TEMP -ChildPath $tempRoot
    New-Item -Path $tempRoot -ItemType 'Directory' | Out-String | Write-Verbose
    $tempPackageRoot = Join-Path -Path $tempRoot -ChildPath 'package'
    New-Item -Path $tempPackageRoot -ItemType 'Directory' | Out-String | Write-Verbose

    try
    {
        $ciComponents = @(
                            'BitbucketServerAutomation', 
                            'Blade', 
                            'LibGit2', 
                            'LibGit2Adapter', 
                            'MSBuild',
                            'Pester', 
                            'PsHg',
                            'ReleaseTrain',
                            'WhsArtifacts',
                            'WhsHg',
                            'WhsPipeline'
                        )
        $arcDestination = Join-Path -Path $tempPackageRoot -ChildPath 'Arc'
        $excludedFiles = Get-ChildItem -Path $arcPath -File | 
                            ForEach-Object { '/XF'; $_.FullName }
        $excludedCIComponents = $ciComponents | ForEach-Object { '/XD' ; Join-Path -Path $arcPath -ChildPath $_ }
        robocopy $arcPath $arcDestination '/MIR' $excludedFiles $excludedCIComponents | Write-Debug

        $upackJsonPath = Join-Path -Path $tempRoot -ChildPath 'upack.json'
        @{
            name = $Name;
            version = $Version;
            title = $Name;
            description = $Description
        } | ConvertTo-Json | Set-Content -Path $upackJsonPath

        foreach( $item in $Path )
        {
            $itemName = $item | Split-Path -Leaf
            $destination = Join-Path -Path $tempPackageRoot -ChildPath $itemName
            $excludeParams = $Exclude | ForEach-Object { '/XF' ; $_ ; '/XD' ; $_ }
            robocopy $item $destination /MIR $Include 'upack.json' $excludeParams '/XD' '.git' '/XD' '.hg' '/XD' 'obj' | Write-Debug
        }

        Get-ChildItem -Path $tempRoot | Compress-Item -OutFile $outFile

        # Upload to ProGet
        if( $PSCmdlet.ParameterSetName -eq 'WithUpload' )
        {
            $headers = @{ }
            $bytes = [Text.Encoding]::UTF8.GetBytes(('{0}:{1}' -f $ProGetCredential.UserName,$ProGetCredential.GetNetworkCredential().Password))
            $creds = 'Basic ' + [Convert]::ToBase64String($bytes)
            $headers.Add('Authorization', $creds)
    
            $result = Invoke-RestMethod -Method Put `
                                        -Uri $ProGetPackageUri `
                                        -ContentType 'application/octet-stream' `
                                        -Body ([IO.File]::ReadAllBytes($outFile)) `
                                        -Headers $headers

            if( -not $? -or ($result -and $result.StatusCode -ne 201) )
            {
                throw ('Failed to upload ''{0}'' package to {1}:{2}{3}' -f ($outFile | Split-Path -Leaf),$ProGetPackageUri,[Environment]::NewLine,($result | Format-List * -Force | Out-String))
            }
        }

        $outFile
    }
    finally
    {
        Get-ChildItem -Path $env:TEMP -Filter ('{0}+*' -f $tempBaseName) |
            Remove-Item -Recurse -Force 
    }
}