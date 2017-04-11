
function Invoke-WhsCIAppPackageTask
{
    <#
    .SYNOPSIS
    Creates a WHS application deployment package.

    .DESCRIPTION
    The `Invoke-WhsCIAppPackageTask` function implements the `AppPackage` task, which creates an universal ProGet package for a WHS application. When running on the build server and building on the `develop`, a `release/*`, or the `master` branch, the package is uploaded to ProGet and starts a deploy for the package in BuildMaster. If the application doesn't exist in ProGet, it is created for you. In order for the BuildMaster deploy to start, the application has to exist in BuildMaster, and a `develop`, `release`, or `master` release (for those respective branches) must also exist.
    
    The package should contain everything the application needs to install itself and run on any server it is deployed to, with minimal/no pre-requisites installed.
    
    The `AppPackage` task has the following elements:
    
    * `Name` (**mandatory**): the name of the package. Must 
    * `Description` (**mandatory**): a short description of the package.
    * `Path` (**mandatory**): the directories and filenames to include in the package. The paths must relative to the `whsbuild.yml` file (you can change the path root via the `SourceRoot` element). Each item is added to the root of the application package using the name of the directory/file. If you have two paths that have the same name, the second item will replace the first.
    * `Include` (**mandatory**): a whitlelist of wildcards and file names to include in the package. For any directory in the `Path` parameter, only files that match an item in this whitelist are included in the package.
    * `Exclude`: a list of wildcards and file names to exclude from the package. Sometimes, a whitelist can be a little greedy and include some files you might not want. Use this element to exclude files.
    * `ThirdPartyPath`: a list of directores and files that should be included in the package *unfiltered*. These are paths that are copied without using the `Include` or `Exclude` elements. This is useful to include items you depend on but have no control over, like Node.js applications' `node_modules` directory.
    * `ExcludeArc`: by default, WHS's automation platform, `Arc`, is included in your package. If your application doesn't need Arc, set this element to `true` and it won't be included.
    * `SourceRoot`: this changes the root path used to resolve the relative paths in the `Path` element. Use this element when your application's root directory isn't the same directory your `whsbuild.yml` file is in. This path should be relative to the `whsbuild.yml` file.
    
    Here is a sample `whsbuild.yml` file showing an `AppPackage` task definition:
    
    BuildTasks:
    - WhsInit:
        Name: WhsInit
        Description: The WHS application used by WHS's Technology team to bootstrap computers and keep them up-to-date. 
        Path:
        - Certificates
        - WhsInitAutomation
        - Initialize-Computer.ps1
        - "Initialize-Whs*Repository.ps1"
        - Reset-Computer.ps1
        - Test-Computer.ps1
        - "Update-Whs*Repository.ps1"
        - Update-WhsInit.ps1
        - WhsEnvironments.json
        Include:
        - "*.ps81"
        - "*.crt"
        - "*.cer"
        - "*.pfx"

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
    if( Test-Path -Path (Join-Path -Path $TaskContext.BuildRoot -ChildPath 'WhsEnvironments.json') -PathType Leaf )
    {
        if( -not ($TaskParameter.Path -contains 'WhsEnvironments.json'))
        {
            $TaskParameter.Path += 'WhsEnvironments.json'
        }
    }

    $version = [semversion.SemanticVersion]$TaskContext.Version
    $name = $TaskParameter['Name']
    $description = $TaskParameter['Description']
    $path = $TaskParameter['Path']
    $include = $TaskParameter['Include']
    $exclude = $TaskParameter['Exclude']
    $thirdPartyPath = $TaskParameter['ThirdPartyPath']
    $excludeArc = $TaskParameter['ExcludeArc']
    
    
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
        $shouldProcessCaption = ('creating {0} package' -f $outFile)
        if( -not $excludeArc )
        {
            $arcPath = Join-Path -Path $TaskContext.BuildRoot -ChildPath 'Arc'
            if( -not (Test-Path -Path $arcPath -PathType Container) )
            {
                Stop-WhsCITask -TaskContext $TaskContext -Message ('Unable to create ''{0}'' package because the Arc platform ''{1}'' does not exist. Arc is required when using the WhsCI module to package your application. See https://confluence.webmd.net/display/WHS/Arc for instructions on how to integrate Arc into your repository. You can exclude Arc from your package by setting the `ExcludeArc` task property in {1} to `true`.' -f $Name,$arcPath,$TaskContext.ConfigurationPath)
                return
            }

            $arcDestination = Join-Path -Path $tempPackageRoot -ChildPath 'Arc'
            $operationDescription = 'packaging Arc'
            if( $PSCmdlet.ShouldProcess($operationDescription,$operationDescription,$shouldProcessCaption) )
            {
                robocopy $arcPath $arcDestination '/MIR' '/NP' | Write-Verbose
            }
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
            if( (Test-Path -Path $item -PathType Leaf) )
            {
                Copy-Item -Path $item -Destination $destination
            }
            else
            {
                $excludeParams = $exclude | ForEach-Object { '/XF' ; $_ ; '/XD' ; $_ }
                $operationDescription = 'packaging {0}' -f $itemName
                if( $PSCmdlet.ShouldProcess($operationDescription,$operationDescription,$shouldProcessCaption) )
                {
                    robocopy $item $destination '/MIR' '/NP' $include 'upack.json' $excludeParams '/XD' '.git' '/XD' '.hg' '/XD' 'obj' | Write-Verbose
                }
            }
        }

        foreach( $item in $thirdPartyPath )
        {
            $itemName = $item | Split-Path -Leaf
            $destination = Join-Path -Path $tempPackageRoot -ChildPath $itemName
            if( (Test-Path -Path $item -PathType Leaf) )
            {
                Copy-Item -Path $item -Destination $destination
            }
            else
            {
                $operationDescription = 'packaging third-party {0}' -f $itemName
                if( $PSCmdlet.ShouldProcess($operationDescription,$operationDescription,$shouldProcessCaption) )
                {
                    robocopy $item $destination '/MIR' '/NP' | Write-Verbose
                }
            }
        }

        Get-ChildItem -Path $tempRoot | Compress-Item -OutFile $outFile

        if( -not (Test-WhsCIRunByBuildServer) )
        {
            return
        }

        # Upload to ProGet
        if( $TaskContext.Publish )
        {
            $proGetPackageUri = $TaskContext.ProGetSession.AppFeedUri
            $proGetCredential = $TaskContext.ProGetSession.Credential
            $buildMasterSession = $TaskContext.BuildMasterSession
            $headers = @{ }
            $bytes = [Text.Encoding]::UTF8.GetBytes(('{0}:{1}' -f $proGetCredential.UserName,$proGetCredential.GetNetworkCredential().Password))
            $creds = 'Basic ' + [Convert]::ToBase64String($bytes)
            $headers.Add('Authorization', $creds)
    
            $operationDescription = 'uploading {0} package to ProGet {1}' -f ($outFile | Split-Path -Leaf),$proGetPackageUri
            if( $PSCmdlet.ShouldProcess($operationDescription,$operationDescription,$shouldProcessCaption) )
            {
                Write-Verbose -Message ('PUT {0}' -f $proGetPackageUri)
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

            $TaskContext.PackageVariables['ProGetPackageVersion'] = $version            
            if ( -not $TaskContext.ApplicationName ) 
            {
                $TaskContext.ApplicationName = $name
            }
            
            # Legacy. Must do this until all plans/pipelines reference/use the ProGetPackageVersion property instead.
            $TaskContext.PackageVariables['ProGetPackageName'] = $version
        }

        $shouldProcessDescription = ('returning package path ''{0}''' -f $outFile)
        if( $PSCmdlet.ShouldProcess($shouldProcessDescription, $shouldProcessDescription, $shouldProcessCaption) )
        {
            $outFile
        }
    }
    finally
    {
        $maxTries = 50
        $tryNum = 0
        $failedToCleanUp = $true
        do
        {
            if( -not (Test-Path -Path $tempRoot -PathType Container) )
            {
                $failedToCleanUp = $false
                break
            }
            Write-Verbose -Message ('[{0,2}] Deleting directory ''{1}''.' -f $tryNum,$tempRoot) -Verbose
            Start-Sleep -Milliseconds 100
            Remove-Item -Path $tempRoot -Recurse -Force -WhatIf:$false -ErrorAction Ignore
        }
        while( $tryNum++ -lt $maxTries )

        if( $failedToCleanUp )
        {
            Write-Warning -Message ('Failed to delete temporary directory ''{0}''.' -f $tempRoot)
        }
    }
}