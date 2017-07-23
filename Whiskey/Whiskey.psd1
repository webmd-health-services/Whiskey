#
# Module manifest for module 'Whiskey'
#
# Generated by: ajensen
#
# Generated on: 12/8/2016
# 

@{

    # Script module or binary module file associated with this manifest.
    RootModule = 'Whiskey.psm1'

    # Version number of this module.
    ModuleVersion = '0.11.0'

    # ID used to uniquely identify this module
    GUID = '93bd40f1-dee5-45f7-ba98-cb38b7f5b897'

    # Author of this module
    Author = 'WebMD Health Services'

    # Company or vendor of this module
    CompanyName = 'WebMD Health Services'

    # Copyright statement for this module
    Copyright = '(c) 2016 WebMD Health Services. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Continuous Integration/Continuous Delivery module.'

    # Minimum version of the Windows PowerShell engine required by this module
    # PowerShellVersion = ''

    # Name of the Windows PowerShell host required by this module
    # PowerShellHostName = ''

    # Minimum version of the Windows PowerShell host required by this module
    # PowerShellHostVersion = ''

    # Minimum version of Microsoft .NET Framework required by this module
    # DotNetFrameworkVersion = ''

    # Minimum version of the common language runtime (CLR) required by this module
    # CLRVersion = ''

    # Processor architecture (None, X86, Amd64) required by this module
    # ProcessorArchitecture = ''

    # Modules that must be imported into the global environment prior to importing this module
    # RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @( 'bin\SemanticVersion.dll' )

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    #ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    # TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    # FormatsToProcess = @()

    # Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
    NestedModules = @( 
                        'BitbucketServerAutomation',
                        'BuildMasterAutomation',
                        'powershell-yaml',
                        'ProGetAutomation'
                     )

    # Functions to export from this module
    FunctionsToExport = @( 
                            'Add-WhiskeyApiKey',
                            'Add-WhiskeyCredential',
                            'ConvertTo-WhiskeySemanticVersion',
                            'Get-WhiskeyTask',
                            'Get-WhiskeyCommitID',
                            'Get-WhiskeyOutputDirectory',
                            'Install-WhiskeyNodeJs',
                            'Install-WhiskeyTool',
                            'Invoke-WhiskeyMSBuild',
                            'Invoke-WhiskeyMSBuildTask',
                            'Invoke-WhiskeyNodeTask',
                            'Invoke-WhiskeyNUnit2Task',
                            'Invoke-WhiskeyPester3Task',
                            'Invoke-WhiskeyPester4Task',
                            'Invoke-WhiskeyPipeline',
                            'Invoke-WhiskeyPublishFileTask',
                            'Invoke-WhiskeyBuild',
                            'Invoke-WhiskeyTask',
                            'New-WhiskeyContext',
                            'Publish-WhiskeyBuildMasterPackage',
                            'Publish-WhiskeyNuGetPackage',
                            'Publish-WhiskeyProGetUniversalPackage',
                            'Publish-WhiskeyBBServerTag',
                            'Register-WhiskeyEvent',
                            'Resolve-WhiskeyNuGetPackageVersion',
                            'Resolve-WhiskeyPowerShellModuleVersion',
                            'Resolve-WhiskeyTaskPath',
                            'Set-WhiskeyBuildStatus',
                            'Stop-WhiskeyTask',
                            'Test-WhiskeyRunByBuildServer',
                            'Uninstall-WhiskeyTool',
                            'Unregister-WhiskeyEvent',
                            'Write-CommandOutput'
                         );

    # Cmdlets to export from this module
    #CmdletsToExport = '*'

    # Variables to export from this module
    #VariablesToExport = '*'

    # Aliases to export from this module
    AliasesToExport = '*'

    # DSC resources to export from this module
    # DscResourcesToExport = @()

    # List of all modules packaged with this module
    # ModuleList = @()

    # List of all files packaged with this module
    # FileList = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{

        PSData = @{

            # Tags applied to this module. These help with module discovery in online galleries.
            # Tags = @()

            # A URL to the license for this module.
            # LicenseUri = ''

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/webmd-health-services/Whiskey'

            # A URL to an icon representing this module.
            # IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
* Fixed: parsing a whiskey.yml file that contains a single value property fails, e.g. just the string `BuildTasks`.
* ***BREAKING***: Builds will now fail if a whiskey.yml file doesn't contain a `BuildTasks` property.
* Whiskey now runs two pipelines: a build pipeline and a publish pipeline. The build pipeline always runs. The publish pipeline only runs if being run by a build server and running on a branch that publishes.
* ***BREAKING***: Pulishing to BuildMaster no longer happens automagically.
* Created a `PublishBuildMasterPackage` task for creating a package in BuildMaster and starting a deploy.
* Added support for running custom plugins before/after Whiskey runs each task. Use the `Register-WhiskeyEvent` and `Unregister-WhiskeyEvent` functions to register/unregister commands to run before and after each task or specific tasks.
* Created `PublishProGetUniversalPackage` task for publishing universal packages to ProGet.
* The `ProGetUniversalPackage` task no longer publishes the package to ProGet. It only creates the package. To publish the package, use the new `PublishProGetUniversalPackage` task.
* ***BREAKING***: `New-WhiskeyContext` no longer has `ProGetAppFeedUri`, `ProGetAppFeedName`, `ProGetCredential`, or `PowerShellFeedUri` parameters. This information was moved to the tasks that require them. Update your `whiskey.yml` files to include that information as properties on the `PublishProGetUniversalPackage` and `PublishPowerShellModule` tasks.
* ***BREAKING***: Whiskey no longer tags a successful build in Bitbucket Server by default. This functionality was converted into a `PublishBitbucketServerTag` task. Add this task to the `PublishTasks` pipeline in your `whiskey.yml` file.
* ***BREAKING***: `New-WhiskeyContext` no longer has `BBServerCredential` or `BBServerUri` parameters, since it no longer tags successful builds in Bitbucket Server. Use the `PublishBitbucketServerTag` task in your `PublishTasks` pipeline instead.
* Fixed: `Node` task fails under PowerShell 5.1 because the max value for the `ConvertTo-Json` cmdlet's `Depth` parameter is `100` in PowerShell 5.1, and the `Node` task was using `[int]::MaxValue`.
* Fixed: Modules disappear from scope when they are re-imported by scripts run in the `PowerShell` task because scripts are run in the Whiskey module's scope. The PowerShell task now runs PowerShell task in a new PowerShell process. Update your scripts so they work when run in a new PowerShell session.
* Added a `CompressionLevel` property to the `ProGetUniversalPackage` task to control the compression level of the package. The default is `1` (low compression, larger file size). 
* Fixed: the `ProGetUniversalPackage` task fails when installing the 7-zip NuGet package if automatic NuGet package restore isn't enabled globally. It now creates a process-level `EnableNuGetPackageRestore` environment variable and sets its value to `true`.
* Fixed: the `PublishProGetUniversalPackage` task doesn't fail if publishing to ProGet fails.
* Renamed the `PublishNuGetLibrary` task to `PublishNuGetPackage`. You can continue to use the old name, but it will eventually be removed.
* ***BREAKING***: `PublishNuGetPackage` task now requires the URI where it should publish NuGet packages. This used to be passed to the `New-WhiskeyContext` function's `NuGetFeedUri` parameter.
* ***BREAKING***: `PublishNuGetPackage` now requires an `ApiKeyID` property that is the ID/name of the API key to use when publshing NuGet packages. Add API keys with the `Add-WhiskeyApiKey` function.
* ***BREAKING***: The `NuGetFeedUri` parameters was removed from the `New-WhiskeyContext` function. The NuGet feed URI is now a `Uri` property on the `PublishNuGetPackage` task.
* Tasks can now have multiple names. Add multiple task attributes to a task.
* Created `NuGetPack` task for creating NuGet packages.
* ***BREAKING***: The `PublishNuGetPackage` task no longer creates the NuGet package. Use the `NuGetPack` task.
* Created `Invoke-WhiskeyTask` function for running tasks.
* Default task property values can now be set via the `TaskDefaults` hashtable on the Whiskey context object. If a task doesn't have a property, but the `TaskDefaults` property does, the value from `TaskDefaults` is used.
* ***BREAKING***: Running a task in clean mode is now opt-in. Set the `SupportsClean` property on your task's `TaskAttribute` to run your task during clean mode. Use the `$TaskContext.ShouldClean()` method to determine if you're running in clean mode or not.
* Created new `Initialize` run mode. This mode is intended for tasks to install or initialize any tools it uses. For example, if a project uses Pester to run PowerShell scripts, the `PowerShell` task should just install Pester when run in Initialize mode. That way, developers get Pester installed without needing to run an entire build. To opt-in to Initialize mode, set the `SupportsInitialize` property on your task's `TaskAttribute` to `true`. Use the `$TaskContext.ShouldInitialize()` function to determine if you're running in initialize mode or not.
* ***BREAKING***: the `PublishNodeModule` task now requires a `CredentialID` property that is the ID of the credential to use when publishing. Use the `Add-WhiskeyCredential` to add credentials to the build.
* ***BREAKING***: the `PublishNodeModule` task now requires an `EmailAddress` property that is the e-mail address to use when publishing node modules.
* Created an `Add-WhiskeyApiKey` function for adding API keys needed by build tasks.
* Created an `Add-WhiskeyCredential` function for adding credentials needed by build tasks.
* ***BREAKING***: The `PublishPowerShellModule` task now requires a `RepositoryUri` property, which should be the URI where the module should be published.
* ***BREAKING***: The `PublishPowerShellModule` task now requires an `ApiKeyID` property, which is the ID of the API key to use when publishing. Use the `Add-WhiskeyApiKey` function to add API keys to the build.
* ***BREAKING***: `New-WhiskeyContext` no longer has a `BuildConfiguration` parameter. Builds are now always run in `Debug` configuration on developer computers and in `Release` configuration on build servers.
* ***BREAKING***: The `Pester3` and `Pester4` tasks now save Pester to `Modules\Pester` on PowerShell 4.
* ***BREAKING***: Task functions are no longer public. Use `Invoke-WhiskeyTask` to run a task from a custom task.
'@
        } # End of PSData hashtable

    } # End of PrivateData hashtable

    # HelpInfo URI of this module
    # HelpInfoURI = ''

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}
