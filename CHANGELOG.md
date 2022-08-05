
# 0.52.3

* Minimum version of PowerShellGet is now 2.1.5. This fixes an issue with the `PublishPowerShellModule` task hanging.


# 0.52.2

* Fixed: `Ignore` is not allowed as a value in the `$ErrorActionPreference` variable when running `node.exe` executable
  directly from filepath.
* Fixed: Whiskey fails if PackageManagement 1.4.8.1 is installed and more than one task runs that depends on the
PackageManagement module.
* Whiskey now supports PackageManagement 1.4.8.1.


# 0.52.1

* Fixed: typo in command name. Mis-typed `Convert-Path` as `ConvertPath`.


# 0.52.0

* PowerShellGet minimum required version is now 2.0.0.
* PackageManagement PowerShell module minimum required version is now 1.3.2.
* If a minimum version of PowerShellGet or PackageManagement isn't installed, Whiskey installs PowerShellGet 2.2.5 and
  PackageManagement 1.4.7 into the repository's private PSModules directory. So, Whiskey still requires PowerShellGet
  and PackageManagement, but will install them if needed.


# 0.51.1

* Fixed: the `Version` task fails when reading version from a Node.js package.json file.


# 0.51.0

## Added

* The Parallel task now has a timeout (default is 10 minutes) in which background jobs have to complete. If jobs take
  longer than the timeout, the build will fail. Use the `Timeout` property to customize the job timeout.

## Changes

* Parallel task now watches each background job in order until it finishes, displaying its output while waiting.
* When PowerShell task is executing a script block, it now writes the script block to output instead of the path and
  args to the temporary script used to run the script block.

## Fixes

* MSBuild task returns multiple paths to Visual Studio 2022's 32-bit MSBuild.exe.


# 0.50.1

Fixed: NuGet package dependencies are not installed.


# 0.50.0

## Upgrade Instructions

Whiskey now requires PackageManagement 1.4.7 and PowerShellGet 2.2.5 to be installed on any computer on which it runs.
Please ensure these modules are installed.

## Added

* Whiskey's "Version" task now calculates the next prerelease version number for a package by querying the package's
  package repository.

## Changed

* Whiskey now depends on and requires PackageManagement 1.4.7 and PowerShellGet 2.2.5. These must be pre-installed on
computers running whiskey.

## Fixed

* Fixed: Parallel task fails if it runs a custom task that was imported from a module.

## Removed

* Removed OpenCover support from the NUnit2 and NUnit3 tasks.


# 0.49.2

* Fixed: Whiskey fails to resolve a task's tool path if the task is running with a custom working directory.


# 0.49.1

## Fixed

* Fixed: Whiskey fails to install a task's tool if the task is running with a custom working directory.


# 0.49.0

## Added

* Added a `NoLog` parameter to the `DotNet` task to turn off logging.
* Whiskey now supports publishing PowerShell modules with AppVeyor deployments instead of directly from/by Whiskey. Use
the `PublishPowerShellModule` to publish a .nupkg file of your module, then use AppVeyor to publish that module to the
PowerShell Gallery, or other PowerShell NuGet-based feed.
* Added a `Pester` task that runs PowerShell tests with Pester version 5 or later.
* Whiskey overrides PowerShell's default error and exception output formats so that only error messages are output.
PowerShell's default error view is hard to recognize and read in non-colorized build output. To **not** use Whiskey's
format, set the `WHISKEY_DISABLE_ERROR_FORMAT` environment variable to `True` **before** importing Whiskey.

## Changed

* The `PublishPowerShellModule` task's default behavior is now to publish a module to a .nupkg file in the current
build's output directory. This allows another tool/process to publish the module (i.e. you can remove your deploy logic
from your build).
* Renamed the `PublishPowerShellModule` task's `RepositoryUri` property to `RepositoryLocation`, since
`Publish-Module` allows publishing to the file system.
* `PublishPowerShellModule` task ignores the `RepositoryName` property if the `RepositoryLocation` property is given. If
a repository exists whose publish location is `RepositoryLocation`, that repository is used. Otherwise, a temp
repository is registered that publishes to `RepositoryLocation` to publish the module, and then unregistered after
publishing.
* The `PublishPowerShellModule` task will fail if no repository with the same name as the `RepositoryName` property
exists and the `RepositoryLocation` property doesn't have a value.

## Deprecated

* The `Pester3` and `Pester4` tasks are obsolete and no longer supported. Use the `Pester` task instead.

## Fixed

* Fixed: Whiskey build doesn't fail if Whiskey configuration file contains invalid YAML.
* Fixed: Whiskey fails to run on AppVeyor's Visual Studio 2013 build image, i.e. on .NET 4.6.2 or earlier.
* Fixed: installing Node.js fails if the build's output directory doesn't exist.
* Fixed: when downloading Node.js, exceptions not related to downloading don't get shown to the user.
* Fixed: `Resolve-WhiskeyTaskPath` can return extra files if searching on a case-sensitive file system and the directory
being searched has no upper or lower case letters.
* Fixed: the `DotNet` command fails when running some commands under .NET 6.0 SDK because .NET 6.0 is stricter about
validating parameters.
* Fixed: `GetPowerShellModule` writes an error and fails a build if getting a prerelease version of a module.

## Removed

* Warnings written by `Import-Module` are now hidden.
* The `PublishPowerShellModule` no longer registers permanent PowerShell repositories. If no repository exists that
matches either of the `RepositoryName` or `RepositoryLocation` properties, the task registers a repository that
publishes to `RepositoryLocation`, publishes to it, then unregisters the repository.


# 0.48.3

* Verbose and debug build output messages no longer have timestamp prefixes (hard to recognize info output).
* Warning build output no longer has a task name prefix (hard to recognize info output).


# 0.48.2

* Fixed: the Context object's TaskName property isn't public/settable.


# 0.48.1

* Fixed: Whiskey's build output doesn't show timings when a task ends.
* Fixed: the Context object's StartedAt property isn't public/settable.


# 0.48.0

* Fixed: installing Node.js during a build can fail if you've got an aggressive virus scanner running.
* Fixed: builds fail when run under a Jenkins PR build.
* Improved Whiskey's build output.
