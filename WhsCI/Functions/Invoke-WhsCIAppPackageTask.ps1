
function Invoke-WhsCIAppPackageTask
{
    <#
    .SYNOPSIS
    Creates a WHS application deployment package.

    .DESCRIPTION
    The `Invoke-WhsCIAppPackageTask` function creates an universal ProGet package for a WHS application, and optionally uploads it to ProGet and starts a deploy for the package in BuildMaster. The package should contain everything the application needs to install itself and run on any server it is deployed to, with minimal/no pre-requisites installed. To upload to ProGet and start a deploy, provide the packages's ProGet URI and credentials with the `ProGetPackageUri` and `ProGetCredential` parameters, respectively and a session to BuildMaster with the `BuildMasterSession` object.

    It returns an `IO.FileInfo` object for the created package.

    Packages are only allowed to have whitelisted files, i.e. you can't include all files by default. You must supply a value for the `Include` parameter that lists the file names or wildcards that match the files you want in your application.

    If the whitelist includes files that you want to exclude, or you want to omit certain directories, use the `Exclude` parameter. `Invoke-WhsCIAppPackageTask` *always* excludes directories named:

     * `obj`
     * `.git`
     * `.hg`

    Some packages require third-party packages, tools, etc, whose contents are out of our control (e.g. the `node_modules` directory in Node.js applications). Pass paths to these items to the `ThirdPartyPath` parameter. These paths are copied as-is, with no filtering, i.e. the `Include` or `Exclude` parameters are not used to filter its contents.

    If the application doesn't exist exist in ProGet, it is created.

    The application must exist in BuildMaster and must have three releases: `develop` for deploying to Dev, `release` for deploying to Test, and `master` for deploying to Staging and Live. `Invoke-WhsCIAppPackageTask` uses the current Git branch to determine which release to add the package to.
    #>
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName='NoUpload')]
    param(
        [Parameter(Mandatory=$true)]
        [object]
        $TaskContext,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $TaskParameter
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState

    foreach( $mandatoryName in @( 'Name', 'Description', 'Include', 'Path' ) )
    {
        if( -not $TaskParameter.ContainsKey($mandatoryName) )
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('Element ''{0}'' is mandatory.' -f $mandatoryName)
        }
    }

    $version = [semversion.SemanticVersion]$TaskContext.Version
    $name = $TaskParameter['Name']
    $description = $TaskParameter['Description']
    $path = $TaskParameter['Path']
    $include = $TaskParameter['Include']
    $exclude = $TaskParameter['Exclude']
    $thirdPartyPath = $TaskParameter['ThirdPartyPath']

    $parentPathParam = @{ }
    if( $TaskParameter.ContainsKey('SourceRoot') )
    {
        $parentPathParam['ParentPath'] = $TaskParameter['SourceRoot'] | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'SourceRoot'
    }

    $resolveErrors = @()
    $path = $path | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'Path' @parentPathParam

    if( $thirdPartyPath )
    {
        $thirdPartyPath = $thirdPartyPath | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName 'ThirdPartyPath' @parentPathParam
    }

    $arcPath = Join-Path -Path $TaskContext.BuildRoot -ChildPath 'Arc'
    if( -not (Test-Path -Path $arcPath -PathType Container) )
    {
        throw ('Unable to create ''{0}'' package because the Arc platform ''{1}'' does not exist. Arc is required when using the WhsCI module to package your application. See https://confluence.webmd.net/display/WHS/Arc for instructions on how to integrate Arc into your repository.' -f $Name,$arcPath)
        return
    }

    $badChars = [IO.Path]::GetInvalidFileNameChars() | ForEach-Object { [regex]::Escape($_) }
    $fixRegex = '[{0}]' -f ($badChars -join '')
    $fileName = '{0}.{1}.upack' -f $name,($version -replace $fixRegex,'-')
    $outDirectory = $TaskContext.OutputDirectory

    $outFile = Join-Path -Path $outDirectory -ChildPath $fileName

    $tempRoot = [IO.Path]::GetRandomFileName()
    $tempBaseName = 'WhsCI+Invoke-WhsCIAppPackageTask+{0}' -f $name
    $tempRoot = '{0}+{1}' -f $tempBaseName,$tempRoot
    $tempRoot = Join-Path -Path $env:TEMP -ChildPath $tempRoot
    New-Item -Path $tempRoot -ItemType 'Directory' -WhatIf:$false | Out-String | Write-Verbose
    $tempPackageRoot = Join-Path -Path $tempRoot -ChildPath 'package'
    New-Item -Path $tempPackageRoot -ItemType 'Directory' -WhatIf:$false | Out-String | Write-Verbose

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
        $operationDescription = 'packaging Arc'
        $shouldProcessCaption = ('creating {0} package' -f $outFile)
        if( $PSCmdlet.ShouldProcess($operationDescription,$operationDescription,$shouldProcessCaption) )
        {
            robocopy $arcPath $arcDestination '/MIR' $excludedFiles $excludedCIComponents '/NP' | Write-Debug
        }

        $upackJsonPath = Join-Path -Path $tempRoot -ChildPath 'upack.json'
        @{
            name = $name;
            version = $version.ToString();
            title = $name;
            description = $description
        } | ConvertTo-Json | Set-Content -Path $upackJsonPath -WhatIf:$false

        foreach( $item in $path )
        {
            $itemName = $item | Split-Path -Leaf
            $destination = Join-Path -Path $tempPackageRoot -ChildPath $itemName
            $excludeParams = $exclude | ForEach-Object { '/XF' ; $_ ; '/XD' ; $_ }
            $operationDescription = 'packaging {0}' -f $itemName
            if( $PSCmdlet.ShouldProcess($operationDescription,$operationDescription,$shouldProcessCaption) )
            {
                robocopy $item $destination '/MIR' '/NP' $include 'upack.json' $excludeParams '/XD' '.git' '/XD' '.hg' '/XD' 'obj' | Write-Debug
            }
        }

        foreach( $item in $thirdPartyPath )
        {
            $itemName = $item | Split-Path -Leaf
            $destination = Join-Path -Path $tempPackageRoot -ChildPath $itemName
            $operationDescription = 'packaging third-party {0}' -f $itemName
            if( $PSCmdlet.ShouldProcess($operationDescription,$operationDescription,$shouldProcessCaption) )
            {
                robocopy $item $destination '/MIR' '/NP' | Write-Debug
            }
        }

        Get-ChildItem -Path $tempRoot | Compress-Item -OutFile $outFile

        # Upload to ProGet
        $branch = (Get-Item -Path 'env:GIT_BRANCH').Value -replace '^origin/',''
        $branch = $branch -replace '/.*$',''
        if( (Test-WhsCIRunByBuildServer) -and $branch -match '^(release|master|develop)$' )
        {
            $proGetPackageUri = $TaskContext.ProGetAppFeedUri
            $proGetCredential = $TaskContext.ProGetCredential
            $buildMasterSession = $TaskContext.BuildMasterSession

            $branch = $Matches[1]
            $headers = @{ }
            $bytes = [Text.Encoding]::UTF8.GetBytes(('{0}:{1}' -f $proGetCredential.UserName,$proGetCredential.GetNetworkCredential().Password))
            $creds = 'Basic ' + [Convert]::ToBase64String($bytes)
            $headers.Add('Authorization', $creds)
    
            $operationDescription = 'uploading {0} package to ProGet {1}' -f ($outFile | Split-Path -Leaf),$proGetPackageUri
            if( $PSCmdlet.ShouldProcess($operationDescription,$operationDescription,$shouldProcessCaption) )
            {
                Write-Debug -Message ('PUT {0}' -f $proGetPackageUri)
                $result = Invoke-RestMethod -Method Put `
                                            -Uri $proGetPackageUri `
                                            -ContentType 'application/octet-stream' `
                                            -Body ([IO.File]::ReadAllBytes($outFile)) `
                                            -Headers $headers
                if( -not $? -or ($result -and $result.StatusCode -ne 201) )
                {
                    throw ('Failed to upload ''{0}'' package to {1}:{2}{3}' -f ($outFile | Split-Path -Leaf),$proGetPackageUri,[Environment]::NewLine,($result | Format-List * -Force | Out-String))
                }
            }

            $release = Get-BMRelease -Session $BuildMasterSession -Application $name -Name $branch
            $release | Format-List | Out-String | Write-Verbose
            $packageName = '{0}.{1}.{2}' -f $version.Major,$version.Minor,$version.Patch
            $package = New-BMReleasePackage -Session $BuildMasterSession -Release $release -PackageNumber $packageName -Variable @{ 'ProGetPackageName' = $version.ToString() }
            $package | Format-List | Out-String | Write-Verbose
            $deployment = Publish-BMReleasePackage -Session $BuildMasterSession -Package $package
            $deployment | Format-List | Out-String | Write-Verbose
        }

        $shouldProcessDescription = ('returning package path ''{0}''' -f $outFile)
        if( $PSCmdlet.ShouldProcess($shouldProcessDescription, $shouldProcessDescription, $shouldProcessCaption) )
        {
            $outFile
        }
    }
    finally
    {
        Get-ChildItem -Path $env:TEMP -Filter ('{0}+*' -f $tempBaseName) |
            Remove-Item -Recurse -Force -WhatIf:$false
    }
}