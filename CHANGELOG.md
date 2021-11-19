# 0.49.0

* Fixed: Whiskey build doesn't fail if Whiskey configuration file contains invalid YAML.
* Fixed: Whiskey fails to run on AppVeyor's Visual Studio 2013 build image, i.e. on .NET 4.6.2 or earlier.
* Fixed: installing Node.js fails if the build's output directory doesn't exist.
* Fixed: when downloading Node.js, exceptions not related to downloading don't get shown to the user.
* The `Pester3` task is obsolete and is no longer supported. Use the `Pester4` task instead.
* Warnings written by `Import-Module` are now hidden.
* Fixed: `Resolve-WhiskeyTaskPath` can return extra files if searching on a case-sensitive file system and the directory
being searched has no upper or lower case letters.

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
