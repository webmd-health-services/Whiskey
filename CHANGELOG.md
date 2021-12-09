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

* The `Pester3` task is obsolete and is no longer supported. Use the `Pester4` task instead.

## Fixed

* Fixed: Whiskey build doesn't fail if Whiskey configuration file contains invalid YAML.
* Fixed: Whiskey fails to run on AppVeyor's Visual Studio 2013 build image, i.e. on .NET 4.6.2 or earlier.
* Fixed: installing Node.js fails if the build's output directory doesn't exist.
* Fixed: when downloading Node.js, exceptions not related to downloading don't get shown to the user.
* Fixed: `Resolve-WhiskeyTaskPath` can return extra files if searching on a case-sensitive file system and the directory
being searched has no upper or lower case letters.
* Fixed: the `DotNet` command fails when running some commands under .NET 6.0 SDK because .NET 6.0 is stricter about
validating parameters.

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
