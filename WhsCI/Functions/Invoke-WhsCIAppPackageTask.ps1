
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
        $TaskParameter,

        [Switch]
        $Clean
    )
    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    if( $Clean )
    {
        return
    }

    foreach( $mandatoryName in @( 'Name', 'Description', 'Include', 'Path' ) )
    {
        if( -not $TaskParameter.ContainsKey($mandatoryName) )
        {
            Stop-WhsCITask -TaskContext $TaskContext -Message ('Element ''{0}'' is mandatory.' -f $mandatoryName)
        }
    }

    # ProGet uses build metadata to distinguish different versions, so we can't use a full semantic version.
    $version = [semversion.SemanticVersion]$TaskContext.Version.ReleaseVersion
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
        $whsEnvironmentsPath = (Join-Path -Path $TaskContext.BuildRoot -ChildPath 'WhsEnvironments.json')
        if( Test-Path -Path $whsEnvironmentsPath -PathType Leaf )
        {
            Copy-Item -Path $whsEnvironmentsPath -Destination $tempPackageRoot
        }        
        $shouldProcessCaption = ('creating {0} package' -f $outFile)        
        $upackJsonPath = Join-Path -Path $tempRoot -ChildPath 'upack.json'
        @{
            name = $name;
            version = $version.ToString();
            title = $name;
            description = $description
        } | ConvertTo-Json | Set-Content -Path $upackJsonPath -WhatIf:$false
        
        # Add the version.json file
        @{
            Version = $TaskContext.Version.Version.ToString();
            SemanticVersion = $TaskContext.Version.ToString();
            PrereleaseMetadata = $TaskContext.Version.Prerelease;
            BuildMetadata = $TaskContext.Version.Build;
            ReleaseVersion = $TaskContext.Version.ReleaseVersion.ToString();
        } | ConvertTo-Json -Depth 1 | Set-Content -Path (Join-Path -Path $tempPackageRoot -ChildPath 'version.json')
        
        function Copy-ToPackage
        {
	        param(
		        [Parameter(Mandatory=$true)]
		        [object[]]
		        $Path,
		
		        [Switch]
		        $AsThirdPartyItem
	        )
	
            foreach( $item in $Path )
            {
                $override = $False
                if( $item -is [hashtable] )
                {
    	            $sourcePath = $null
                    $override = $True
    	            foreach( $key in $item.Keys )
	                {
		                $destinationItemName = $item[$key]
		                $sourcePath = $key
	                }
                }
                else
                {
                    $sourcePath = $item
                }
                $pathparam = 'path'
                if( $AsThirdPartyItem )
                {
                    $pathparam = 'ThirdPartyPath'
                }

                $sourcePath = $sourcePath | Resolve-WhsCITaskPath -TaskContext $TaskContext -PropertyName $pathparam @parentPathParam
                if( -not $sourcePath )
                {
    	            return
                }
                $relativePath = $sourcePath -replace ('^{0}' -f ([regex]::Escape($TaskContext.BuildRoot))),''
                $relativePath = $relativePath.Trim("\")
                if( -not $override )
                {
                    $destinationItemName = $relativePath
                }

                $destination = Join-Path -Path $tempPackageRoot -ChildPath $destinationItemName
                $parentDestinationPath = ( Split-Path -Path $destination -Parent)

                #if parent doesn't exist in the destination dir, create it
                if( -not ( Test-Path -Path $parentDestinationPath ) )
                {
                        New-Item -Name $name -Path $parentDestinationPath -ItemType 'Directory' -Force | Out-String | Write-Verbose
                }

                if( (Test-Path -Path $sourcePath -PathType Leaf) )
                {
                    Copy-Item -Path $sourcePath -Destination $destination
                }
                else
                {
    	            if( $AsThirdPartyItem )
	                {
		                $excludeParams = @()
		                $whitelist = @()
                        $operationDescription = 'packaging third-party {0}' -f $item
	                }
	                else
	                {
            	        $excludeParams = Invoke-Command {
							        '.git'
							        '.hg'
							        'obj'
							        $exclude
						        } |
					    ForEach-Object { '/XF' ; $_ ; '/XD' ; $_ }
            	        $operationDescription = 'packaging {0}' -f $item
		                $whitelist = Invoke-Command {
						                'upack.json',
						                $include
						                } 
	                }
                    if( $PSCmdlet.ShouldProcess($operationDescription,$operationDescription,$shouldProcessCaption) )
                    {
                        robocopy $sourcePath $destination '/MIR' '/NP' $whitelist $excludeParams | Write-Verbose
                    }
                }
            }
        }       

        Copy-ToPackage -Path $TaskParameter['Path']
        if( $TaskParameter.ContainsKey('ThirdPartyPath') -and $TaskParameter['ThirdPartyPath'] )
        {
	        Copy-ToPackage -Path $TaskParameter['ThirdPartyPath'] -AsThirdPartyItem
        }

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

        Get-ChildItem -Path $tempRoot | Compress-Item -OutFile $outFile

        # Upload to ProGet
        if( -not $TaskContext.Publish )
        {
            return
        }

        $progetSession = New-ProGetSession -Uri $TaskContext.ProGetSession.Uri -Credential $TaskContext.ProGetSession.Credential
        $progetFeedName = $TaskContext.ProGetSession.AppFeed.Split('/')[1]
        Publish-ProGetUniversalPackage -ProGetSession $progetSession -FeedName $progetFeedName -PackagePath $outFile -ErrorAction Stop
            
        $TaskContext.PackageVariables['ProGetPackageVersion'] = $version            
        if ( -not $TaskContext.ApplicationName ) 
        {
            $TaskContext.ApplicationName = $name
        }
            
        # Legacy. Must do this until all plans/pipelines reference/use the ProGetPackageVersion property instead.
        $TaskContext.PackageVariables['ProGetPackageName'] = $version

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
            Write-Verbose -Message ('[{0,2}] Deleting directory ''{1}''.' -f $tryNum,$tempRoot)
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