# 0.2.0

# Upgrade Instructions:

 * Rename any `Pester` tasks to `Pester3` in your `whsbuild.yml` file(s).
 * The `Pester3` task now requires the version of Pester to use. Add a `Version` property to any `Pester3` sections in your `whsbuild.yml` file(s). The latest version of Pester is 3.4.3 (as of this writing).

# What's Changed

 * Created `Invoke-WhsCIBuild` function for running a build as specified in a `whsbuild.yml` file.
 * Renamed `Pester` task to `Pester3`.
 * Fixed: `New-WhsAppPackage` puts packages in the root of the repository, not the `.output` directory.
 * Added `WhsAppPackage` task to `whsbuild.yml` schema and `Invoke-WhsCIBuild`. This task creates application deployment packages.
 * Created `Install-WhsCITool` function for installing tools (currently only PowerShell modules) needed by WhsCI functions.
 * Created `Invoke-WhsCIPester3Task` function for running tests with Pester 3.
 * Created `Invoke-WhsCINodeTask` function for running Node.js builds.
 * Added `Node` task for running Node.js builds.
 * Added a `Test-WhsCIRunByBuildServer` function to test if a build is being run by/under a build server. Currently, only Jenkins detection is supported.
 * Created `Invoke-WhsCIPowerShellTask` function for running PowerShell scripts.


# 0.1.0

Initial WhsCI module, used for build automation and tasks.

 * Created `New-WhsAppPackage` function for creating generic, universal packages for deploying applications.
