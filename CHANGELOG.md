<!--markdownlint-disable MD012 no-multiple-blanks -->
<!--markdownlint-disable MD024 no-duplicate-heading/no-duplicate-header -->

# 0.57.0

## Added

* Whiskey's verbose and debug messages now include timing information like information messages.
* Parameter `PipelineName` to Whiskey's default build.ps1 script, which allows running a specific pipeline from a
whiskey.yml file.
* Parameter `ConfigurationPath` to Whiskey's default build.ps1 script, which allows running a build using a specific
whiskey.yml file.
* The `PublishProGetAsset` and `PublishProGetUniversalPackage` tasks now write what they're publishing to the
information stream.

## Changed

* Updated the `Parallel`, `Pester`, and `PowerShell` tasks to use `Start-ThreadJob` to run background jobs instead of
`Start-Job`. [There's about a 6x reduction in the stack size of PowerShell processes started by `Start-Job`](https://github.com/PowerShell/PowerShell/issues/17407),
which causes "call depth overflow" exceptions during builds.
* Updated the `ProGetUniversalPackage`, `PublishProGetAsset`, `PublishProGetUniversalPackage` tasks to use the latest
ProGetAutomation version that matches wildcard `1.*` (excluding prerelease versions). They were using version `0.10.*`.
* Updated `Version` task to no longer use a privately packaged version of ProGetAutomation and instead use the same
version as the `ProGetUniversalPackage`, `PublishProGetAsset`, and `PublishProGetUniversalPackage` tasks.

## Fixed

* Fixed: Installing .NET fails if the global.json file requests a version of .NET that is newer than any installed
version.
* Fixed: The `Parallel`, `Pester`, and `PowerShell` tasks sometimes fail with "call depth overflow" exceptions.

# 0.56.0

## Changed

* `MSBuild` task no longer strips double/single quotes from around property values or adds a backslash if a property
value ends with a backslash. Instead, the `MSBuild` task escapes values using MSBuild's internal rules (i.e.
it URL-encodes the value). If you have quotes around property values, remove them.

## Fixed

* Fixed: `MSBuild` task fails if a property value contains a semi-colon.

# 0.55.0

## Added

* The `Version` task now supports setting patch/prerelease version numbers from a universal package that's in a group.
* The `Version` task now supports authenticating to ProGet to get universal packages.

# 0.54.0

## Added

The `build.ps1` can now authenticate requests to GitHub when determining the version of Whiskey to download.

## Changed

* Whiskey now checks .NET's `global.json` files for their RollForward value before installing .NET Core toolsfollows Microsoft's policy on rolling forward currently installed .NET Core versions.
* MSBuild task now writes NuGet restore and MSBuild commands to the information stream.
* Commands written to the information stream now quote arguments that contain a semicolon.
* NPM task now writes the commands it runs to the information stream.
* NuGetPush task writes `nuget push` command to the information stream.

## Fixed

* Fixed: MSBuild task throws an unhelpful internal error when given a `NuGetVersion` that does not exist.
* Fixed: tasks fail that pass empty strings as arguments to console commands. PowerShell 7.3 changed the way variables
are passed as command arguments. A variable whose value is an empty string, is passed to the command as a
double-quoted string and `$null` values are ommitted. Updated the following tasks to no longer pass empty strings as
arguments:
  * MSBuild
  * NUnit2
  * NUnit3
  * NuGetPack
* Fixed: build.ps1 fails if it exceeds your GitHub API rate limits. Added parameter `GitHubBearerToken` to authenticate
to GitHub's API. If a `GITHUB_BEARER_TOKEN` environment variable exists, the `build.ps1` script will use that value
unless the `GitHubBearerToken` parameter has a value.
* Fixed: the `Version` task picks the wrong next prerelease version number if the target package feed uses semver 1.
* Fixed: Whiskey doesn't tell you when it can't find a version of a NuGet package.

# 0.53.2

Fixed: PublishBitbucketServerTag task fails when building a pull request in Jenkins. When building PRs, Jenkins merges
the source and destination branches together on the build server. This merge only exists on the build server, so can't
be tagged in Bitbucket Server.


# 0.53.1

Fixed: Pester task doesn't fail when running in a background job and tests fail.


# 0.53.0

## Upgrade Instructions


Whiskey no longer installs PackageManagement or PowerShellGet modules (again). On all computers running Whiskey builds
install a version of:

* PackageManagement from 1.3.2 to 1.4.8.1
* PowerShellGet from 2.1.5 to 2.2.5

We recommend using Prism for PowerShell module management and to get working package management module's installed. [It
has a script you can run in your build process to bootstrap package management and Prism
itself.](https://github.com/webmd-health-services/Prism#adding-to-builds)

## Changes

* Whiskey no longer installs Package Management or PowerShellGet modules. It now uses whatever versions of those modules
are installed.
* Please use PowerShellGet 2.1.5 or later. This will fix an issue with the `PublishPowerShellModule` task hanging.


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
