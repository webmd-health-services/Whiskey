<!--markdownlint-disable MD012 no-multiple-blanks -->
<!--markdownlint-disable MD024 no-duplicate-heading/no-duplicate-header -->

# Whiskey Changelog

## 0.62.0

### Upgrade Instructions

Rename usages of the `InstallNode` task to `InstallNodeJs`.

This version is the beginning of getting Whiskey out of the tool management business. Managing tools and toolsets makes
Whiskey responsible for too much. The first step is deprecating all of Whiskey's tasks that manage a local Node.js
instance. If you to continue to use the local version of Node.js that Whiskey installs, add an `InstallNodeJs` task to
your whiskey.yml file before running any Node-related tasks/commands. This will make sure Node.js is installed and in
your PATH.

```yaml
- InstallNodeJs
```

See the [InstallNodeJs](https://github.com/webmd-health-services/Whiskey/wiki/InstallNodeJs-Task) documentation for more
information.

The `Npm`, `NodeLicenseChecker`, and `PublishNodeModule` tasks are now obsolete. Replace them with raw `npm` commands,
e.g.

```yaml
- npm install
```

Replace usages of the `NodeLicenseChecker` task with commands to install then run the license checker:

```yaml
- npm install license-checker -g
- license-checker
```

Replace usages of `PublishNodeModule` task with these commands:

```yaml
- npm version $(WHISKEY_SEMVER2_NO_BUILD_METADATA) --no-git-tag-version --allow-same-version
- npm prune --produciton
- npm publish
```

You'll need to make sure you have an ".npmrc" file in the current user's home directory configured with credentials in
order for the `publish` task to work. To get you started, here is the template of the ".npmrc" file the task currently
create a temporary ".npmrc" in the build root:

```ini
//REGISTRY_DOMAIN_NAME/REGISTRY_PATH:_password="BASE_64_ENCODED_PASSWORD"
//REGISTRY_DOMAIN_NAME/REGISTRY_PATH:username=USERNAME
//REGISTRY_DOMAIN_NAME/REGISTRY_PATH:email=EMAIL
registry=REGISTRY_URL
```

YOu can also use the `npm login` or `npm adduser` commands, which by default will create a user-level ".npmrc" file.

### Added

#### InstallNodeJs Task

The `InstallNodeJs` task now looks up the Node.js version to install from a ".node-version" file, if a version isn't
given with the task's `Version` property. The ".node-version" file is is expected to be in the build root. If that file
doesn't exist, that task looks for a `whiskey.node` property in the "package.json" file in the build root. The path to
the "package.json" file to use can be customized with the new `PackageJsonPath` property. If neither file exists, the
task will install the latest LTS version of Node.js. The task supports partial version numbers, e.g. `16`, `16.20`, and
`16.20.2` would all install Node.js version "16.20.2".

Wherever Node.js is installed, the `InstallNodeJs` task now adds the install directory to the current build process's
`PATH` environment variable. By default, the task installs into a ".node" directory in the build root. Use the `Path`
task property to change the directory.

The task now supports pinning NPM to a specific version. Use the `NpmVersion` task property or by
specifying a `whiskey.npm` property in the "package.json" file. Partial version numbers are supported.

The task now supports changing the CPU architecture of the Node.js package to download via the `Cpu` property. This
should match the architecture/CPU portion of the Node.js package, which is currently the last part, e.g.
"node-VERSION-OS-CPU.extension".

#### Support for Raw Commands as Build Tasks

You can now have raw executable commands in your whiskey.yml files. Instead of:

```yaml
Build
- Exec:
    Path: cmd
    Argument: [ '/C', 'echo "Hello, World!"' ]
```

you can now:

```yaml
Build:
- cmd /C echo "Hello, World!"
```

If you want to use/set global properties on the command, the `Exec` task name is still required, but Whiskey now
supports a simplified syntax. Instead of:

```yaml
Build:
- Exec:
    Path: cmd
    Argument: ['/C' 'echo "Hello, World!"' ]
    WorkingDirectory: subdir
```

you can now:

```yaml
Build:
- Exec: cmd /C echo "Hello, World!"
  WorkingDirectory: subdir
```

Note that when using this simplified syntax, the `Exec` task name ***must*** be the first item in the task's YAML map.

#### Simplified Syntax for Simple PowerShell/Version Tasks

This syntactic sugar also applies to the `PowerShell` and `Version` tasks. Instead of:


```yaml
Build:
- PowerShell:
    ScriptBlock: prism install
- Version:
    Version: 1.2.3
```

You can now:

```yaml
Build:
- PowerShell: prism install
- Version: 1.2.3
```

Task authors can get support for this syntax for these tasks by using the new `DefaultPropertyName` property on their
task's `Task` attribute:

```powershell
function Invoke-MyTask
{
  [CmdletBinding()]
  [Whiskey.Task('MyTask', DefaultParameterName='MyProperty')]
  param(
    [String] $MyProperty
  )
}
```

which will let users call your task like this:

```yaml
Build:
- MyTask: MyPropertyValue
```

### Changed

The `InstallNode` task renamed to `InstallNodeJs`.

### Deprecated

The `Npm`, `NodeLicenseChecker`, and `PublishNodeModule` tasks. Replace usages with raw `npm` commands . In order for
that to work, however, you will either need to install a global version of Node.js whose commands are available in your
build's `PATH` or use Whiskey's `InstallNodeJs` task, which will install a private version of Node.js for your build and
adds it to your build's `PATH`. We recommend using [Volta](https://volta.sh/) as a global Node.js version manager
because it supports side-by-side versions of Node.js and automatic installation.

For task authors, automatically installing Node and node modules is deprecated. Remove usages of
`[Whiskey.RequiresTool('Node')]` and `[Whiskey.RequiresNodeModule]` attributes from your tasks. Instead of requiring
Whiskey to install Node.js, add Whiskey's `InstallNodeJs` task to the build. To get a node module installed, add `npm
install MODULE -g` commands to the build.

All `Whiskey.Requires*` task attributes will eventually be deprecated and removed in favor of build tasks.

The `Uri` property name on the `NuGetPush` and `PublishBuildMasterPackage` tasks. Use the `Url` property instead. The
`Uri` property will be removed in a future version of Whiskey.

### Removed

The `Force` parameter on the `InstallNodeJs` task. The task now will automatically re-install Node.js if it isn't at the
expected version.

The `InstallNodeJs` task no longer uses the `engines.node` property in the "package.json" file to determine what version
of Node.js to install. Instead, it uses the `Version` task property. If that isn't given, it uses the version in the
".node-version" file in the build root. If that file doesn't exist, it uses the `whiskey.node` property in the
"package.json" file. Otherwise, it installs the latest LTS version.

## 0.61.0

> Released 12 June 2024

### Added

* Added `ContentType` property to `PublishProGetAsset` task for setting the published asset's MIME type. Defaults to
  `application/octet-stream`.

### Changed

* Updated ProGetAutomation dependency version to `3.*` (from `2.*`).
* Improved `PublishProGetAsset` task error messages.
* Improved speed of Whiskey build by more efficiently searching for available Whiskey task functions.

### Fixed

* Wrong property name in `PublishProGetAsset` task error message.

## 0.60.5

> Released 2 Apr 2024

Fixed: Version task fails when incrementing a Node Module's prerelease version but no version of the module has been
published to the registry yet.
Fixed: Some verbose output does not unroll nested arrays.

## 0.60.4

> Released 5 Feb 2024

Fixed: the `Delete` task can incorrectly fail a build.


## 0.60.3

> Released 27 Dec 2023

Fixed: Whiskey now displays a warning if it cannot find `PowerShellGet` with a version higher than `2.0.10`.


## 0.60.2

> Released 12 Oct 2023

Fixed: The `Version` tasks increments the prerelease version even though it's label is null or empty.


## 0.60.1

> Released 11 Oct 2023

Fixed: The `Version` task incremments the prerelease version even though a prerelease label doesn't exist.


## 0.60.0

> Released 09 Oct 2023

* The `Version` task will no longer retrieve the next patch and prerelease versions by default. The
`IncrementPatchVersion` and `IncrementPrereleaseVersion` parameters can be passed to this task to retrieve their
respective versions.


## 0.59.0

> Released 21 Apr 2023

* Updated Whiskey to use ProGetAutomation `2.*` by default.
* Fixed: arguments aren't passed to nested tasks.


## 0.58.0

> Releaesd 14 Apr 2023

`ProGetUniversalPackage` now includes/excludes items using paths. If any item in the `Include` or `Exclude` property
contains a directory separator character (e.g. `/` or `\`), it is matched against the path of each file/directory,
relative to the current working directory.


## 0.57.0

> Released 2023-04-10

### Added

* Whiskey's verbose and debug messages now include timing information like information messages.
* Parameter `PipelineName` to Whiskey's default build.ps1 script, which allows running a specific pipeline from a
whiskey.yml file.
* Parameter `ConfigurationPath` to Whiskey's default build.ps1 script, which allows running a build using a specific
whiskey.yml file.
* The `PublishProGetAsset` and `PublishProGetUniversalPackage` tasks now write what they're publishing to the
information stream.

### Changed

* Updated the `Pester` task to no longer run tests in a background job.
[There's about a 6x reduction in the stack size of PowerShell processes started by `Start-Job`](https://github.com/PowerShell/PowerShell/issues/17407),
which causes "call depth overflow" exceptions during some Pester tests. The `Pester` task now runs tests in a
seperate PowerShell process.
* Updated the `ProGetUniversalPackage`, `PublishProGetAsset`, `PublishProGetUniversalPackage` tasks to use the latest
ProGetAutomation version that matches wildcard `1.*` (excluding prerelease versions). They were using version `0.10.*`.
* Updated `Version` task to no longer use a privately packaged version of ProGetAutomation and instead use the same
version as the `ProGetUniversalPackage`, `PublishProGetAsset`, and `PublishProGetUniversalPackage` tasks.

### Fixed

* Fixed: Installing .NET fails if the global.json file requests a version of .NET that is newer than any installed
version.
* Fixed: Installing .NET fails when the global.json file does not contain a `rollForward` property.
* Fixed: The `Pester` tasks sometimes fail with "call depth overflow" exceptions.

### Removed

* The `Pester` task's `AsJob` switch. The `Pester` task now runs tests in a seperate PowerShell process.


## 0.56.0

> Released 2023-04-06

### Changed

* `MSBuild` task no longer strips double/single quotes from around property values or adds a backslash if a property
value ends with a backslash. Instead, the `MSBuild` task escapes values using MSBuild's internal rules (i.e.
it URL-encodes the value). If you have quotes around property values, remove them.

### Fixed

* Fixed: `MSBuild` task fails if a property value contains a semi-colon.


## 0.55.0

> Released 2023-04-05

### Added

* The `Version` task now supports setting patch/prerelease version numbers from a universal package that's in a group.
* The `Version` task now supports authenticating to ProGet to get universal packages.


## 0.54.0

> Released 2023-04-03

### Added

The `build.ps1` can now authenticate requests to GitHub when determining the version of Whiskey to download.

### Changed

* Whiskey now checks .NET's `global.json` files for their RollForward value before installing .NET Core toolsfollows Microsoft's policy on rolling forward currently installed .NET Core versions.
* MSBuild task now writes NuGet restore and MSBuild commands to the information stream.
* Commands written to the information stream now quote arguments that contain a semicolon.
* NPM task now writes the commands it runs to the information stream.
* NuGetPush task writes `nuget push` command to the information stream.

### Fixed

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


## 0.53.2

> Released 2022-08-23

Fixed: PublishBitbucketServerTag task fails when building a pull request in Jenkins. When building PRs, Jenkins merges
the source and destination branches together on the build server. This merge only exists on the build server, so can't
be tagged in Bitbucket Server.


## 0.53.1

> Released 2022-08-12

Fixed: Pester task doesn't fail when running in a background job and tests fail.


## 0.53.0

> Released 2022-08-09

### Upgrade Instructions


Whiskey no longer installs PackageManagement or PowerShellGet modules (again). On all computers running Whiskey builds
install a version of:

* PackageManagement from 1.3.2 to 1.4.8.1
* PowerShellGet from 2.1.5 to 2.2.5

We recommend using Prism for PowerShell module management and to get working package management module's installed. [It
has a script you can run in your build process to bootstrap package management and Prism
itself.](https://github.com/webmd-health-services/Prism#adding-to-builds)

### Changes

* Whiskey no longer installs Package Management or PowerShellGet modules. It now uses whatever versions of those modules
are installed.
* Please use PowerShellGet 2.1.5 or later. This will fix an issue with the `PublishPowerShellModule` task hanging.


## 0.52.2

> Released 2022-08-04

* Fixed: `Ignore` is not allowed as a value in the `$ErrorActionPreference` variable when running `node.exe` executable
  directly from filepath.
* Fixed: Whiskey fails if PackageManagement 1.4.8.1 is installed and more than one task runs that depends on the
PackageManagement module.
* Whiskey now supports PackageManagement 1.4.8.1.


## 0.52.1

> Released 2022-07-25

* Fixed: typo in command name. Mis-typed `Convert-Path` as `ConvertPath`.


## 0.52.0

> Released 2022-07-05

* PowerShellGet minimum required version is now 2.0.0.
* PackageManagement PowerShell module minimum required version is now 1.3.2.
* If a minimum version of PowerShellGet or PackageManagement isn't installed, Whiskey installs PowerShellGet 2.2.5 and
  PackageManagement 1.4.7 into the repository's private PSModules directory. So, Whiskey still requires PowerShellGet
  and PackageManagement, but will install them if needed.


## 0.51.1

> Released 2022-06-10

* Fixed: the `Version` task fails when reading version from a Node.js package.json file.


## 0.51.0

> Released 2022-05-26

### Added

* The Parallel task now has a timeout (default is 10 minutes) in which background jobs have to complete. If jobs take
  longer than the timeout, the build will fail. Use the `Timeout` property to customize the job timeout.

### Changes

* Parallel task now watches each background job in order until it finishes, displaying its output while waiting.
* When PowerShell task is executing a script block, it now writes the script block to output instead of the path and
  args to the temporary script used to run the script block.

### Fixes

* MSBuild task returns multiple paths to Visual Studio 2022's 32-bit MSBuild.exe.


## 0.50.1

> Released 2022-05-19

Fixed: NuGet package dependencies are not installed.


## 0.50.0

> Released 2022-05-18

### Upgrade Instructions

Whiskey now requires PackageManagement 1.4.7 and PowerShellGet 2.2.5 to be installed on any computer on which it runs.
Please ensure these modules are installed.

### Added

* Whiskey's "Version" task now calculates the next prerelease version number for a package by querying the package's
  package repository.

### Changed

* Whiskey now depends on and requires PackageManagement 1.4.7 and PowerShellGet 2.2.5. These must be pre-installed on
computers running whiskey.

### Fixed

* Fixed: Parallel task fails if it runs a custom task that was imported from a module.

### Removed

* Removed OpenCover support from the NUnit2 and NUnit3 tasks.


## 0.49.2

* Fixed: Whiskey fails to resolve a task's tool path if the task is running with a custom working directory.


## 0.49.1

> Released 2022-02-08

### Fixed

* Fixed: Whiskey fails to install a task's tool if the task is running with a custom working directory.


## 0.49.0

> Released 2021-12-30

### Added

* Added a `NoLog` parameter to the `DotNet` task to turn off logging.
* Whiskey now supports publishing PowerShell modules with AppVeyor deployments instead of directly from/by Whiskey. Use
the `PublishPowerShellModule` to publish a .nupkg file of your module, then use AppVeyor to publish that module to the
PowerShell Gallery, or other PowerShell NuGet-based feed.
* Added a `Pester` task that runs PowerShell tests with Pester version 5 or later.
* Whiskey overrides PowerShell's default error and exception output formats so that only error messages are output.
PowerShell's default error view is hard to recognize and read in non-colorized build output. To **not** use Whiskey's
format, set the `WHISKEY_DISABLE_ERROR_FORMAT` environment variable to `True` **before** importing Whiskey.

### Changed

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

### Deprecated

* The `Pester3` and `Pester4` tasks are obsolete and no longer supported. Use the `Pester` task instead.

### Fixed

* Fixed: Whiskey build doesn't fail if Whiskey configuration file contains invalid YAML.
* Fixed: Whiskey fails to run on AppVeyor's Visual Studio 2013 build image, i.e. on .NET 4.6.2 or earlier.
* Fixed: installing Node.js fails if the build's output directory doesn't exist.
* Fixed: when downloading Node.js, exceptions not related to downloading don't get shown to the user.
* Fixed: `Resolve-WhiskeyTaskPath` can return extra files if searching on a case-sensitive file system and the directory
being searched has no upper or lower case letters.
* Fixed: the `DotNet` command fails when running some commands under .NET 6.0 SDK because .NET 6.0 is stricter about
validating parameters.
* Fixed: `GetPowerShellModule` writes an error and fails a build if getting a prerelease version of a module.

### Removed

* Warnings written by `Import-Module` are now hidden.
* The `PublishPowerShellModule` no longer registers permanent PowerShell repositories. If no repository exists that
matches either of the `RepositoryName` or `RepositoryLocation` properties, the task registers a repository that
publishes to `RepositoryLocation`, publishes to it, then unregisters the repository.


## 0.48.3

> Released 2021-03-23

* Verbose and debug build output messages no longer have timestamp prefixes (hard to recognize info output).
* Warning build output no longer has a task name prefix (hard to recognize info output).


## 0.48.2

> Released 2021-03-22

* Fixed: the Context object's TaskName property isn't public/settable.


## 0.48.1

> Released 2021-03-19

* Fixed: Whiskey's build output doesn't show timings when a task ends.
* Fixed: the Context object's StartedAt property isn't public/settable.


## 0.48.0

> Released 2021-03-19

* Fixed: installing Node.js during a build can fail if you've got an aggressive virus scanner running.
* Fixed: builds fail when run under a Jenkins PR build.
* Improved Whiskey's build output.
