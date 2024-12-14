#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    Import-WhiskeyTestTaskModule -Name 'Glob'

    [Whiskey.Context]$script:context = $null
    $script:fsCaseSensitive = $false
    $script:testRoot = $null

    # Don't let Carbon's alias interfere with our function.
    if( (Test-Path -Path 'alias:Resolve-RelativePath') )
    {
        Remove-Item -Path 'alias:Resolve-RelativePath'
    }

    function Resolve-RelativePath
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory,Position=0)]
            [String[]]$Path
        )

        $outsideBuildRootIdentifier = '..{0}' -f [IO.Path]::DirectorySeparatorChar
        foreach( $item in $Path )
        {
            # Normalize separators
            $item = $item | Convert-WhiskeyPathDirectorySeparator

            if( $item.StartsWith($outsideBuildRootIdentifier) )
            {
                Write-Output $item
            }
            else
            {
                Write-Output (Join-Path -Path '.' -ChildPath $item)
            }
        }
    }

    function GivenDirectory
    {
        param(
            $Name
        )

        if( -not ([IO.Path]::IsPathRooted($Name)) )
        {
            $Name = Join-Path -Path $script:testRoot -ChildPath $Name
        }
        New-Item -Path $Name -ItemType 'Directory'
    }

    function GivenFile
    {
        param(
            [String[]]$Name,
            [Switch]$Hidden
        )

        foreach( $path in $Name )
        {
            if( -not [IO.Path]::IsPathRooted($path) )
            {
                $path = Join-Path -Path $script:testRoot -ChildPath $path
            }
            $item = New-Item -Path $path -Force
            if( $Hidden )
            {
                $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
            }
        }
    }

    function ThenPipelineSucceeded
    {
        $Global:Error | Should -BeNullOrEmpty
        $threwException | Should -BeFalse
    }

    function ThenTaskCalled
    {
        param(
            [hashtable]$WithParameter
        )

        $taskParameters = Get-LastTaskBoundParameter

        $null -eq $taskParameters | Should -BeFalse

        if( $WithParameter )
        {
            $taskParameters.Count | Should -Be $WithParameter.Count
            foreach( $key in $WithParameter.Keys )
            {
                ($taskParameters[$key] | Sort-Object) | Should -Be ($WithParameter[$key] | Sort-Object) -Because $key
            }
        }
    }

    function ThenTaskNotCalled
    {
        $taskParameters = Get-LastTaskBoundParameter
        $null -eq $taskParameters | Should -BeTrue
    }

    function ThenThrewException
    {
        param(
            $Pattern
        )

        $threwException | Should -BeTrue
        $Global:Error | Should -Match $Pattern
    }

    function WhenRunningTask
    {
        [CmdletBinding()]
        param(
            [String]$Name,

            [hashtable]$Parameter,

            [String]$BuildRoot = $script:testRoot
        )

        $script:context = New-WhiskeyTestContext -ForDeveloper -ForBuildRoot $BuildRoot -IncludePSModule 'Glob'
        $script:context.PipelineName = 'Build'
        $script:context.TaskIndex = 1

        $Global:Error.Clear()
        $script:threwException = $false
        try
        {
            Invoke-WhiskeyTask -TaskContext $script:context -Name $Name -Parameter $Parameter
        }
        catch
        {
            $script:threwException = $true
            Write-CaughtError $_
        }
    }
}

Describe 'Resolve-WhiskeyTaskPath' {
    BeforeEach {
        $script:context = $null
        $script:fsCaseSensitive = -not (Test-Path -Path ($PSScriptRoot.ToUpperInvariant()))
        $script:testRoot = New-WhiskeyTestRoot
        Clear-LastTaskBoundParameter
    }

    AfterEach {
        Reset-WhiskeyTestPSModule
    }

    It 'resolves optional item to relative path' {
        WhenRunningTask 'ValidateOptionalPathTask' -Parameter @{ 'Path' = 'whiskey.yml' }
        ThenPipelineSucceeded
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath -Path 'whiskey.yml') }
    }

    It 'validates optional path exists' {
        WhenRunningTask 'ValidateOptionalPathTask' -Parameter @{ 'Path' = 'somefile.txt' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'does\ not\ exist'
    }

    It 'resolves wildcards to paths' {
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.yml' }
        ThenPipelineSucceeded
        ThenTaskCalled
        $taskParameters = Get-LastTaskBoundParameter
        $taskParameters['Path'] | Should -HaveCount 2
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'abc.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'whiskey.yml')
    }

    It 'resolves hidden paths' {
        GivenFile '.hidden.yml' -Hidden
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.yml' }
        ThenPipelineSucceeded
        $expectedPaths = @(
            (Resolve-RelativePath '.hidden.yml')
            (Resolve-RelativePath 'whiskey.yml')
        )
        ThenTaskCalled -WithParameter @{ 'Path' = $expectedPaths }
    }

    It 'validates path with wildcard characters exists' {
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.fubar' } -ErrorAction SilentlyContinue
        ThenThrewException 'does\ not\ exist'
        ThenTaskNotCalled
    }

    It 'validates wildcard resolves to a single item' {
        GivenFile 'abc.txt'
        GivenFile 'xyz.txt'
        WhenRunningTask 'ValidateOptionalPathTask' -Parameter @{ 'Path' = '*.txt' } -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'requires\ a\ single\ path'
        ThenTaskNotCalled
    }

    It 'resolves path to a file' {
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'abc.yml') }
    }

    It 'validates path is to a file' {
        GivenDirectory 'abc.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should resolve to a file'
    }

    It 'validates path is to a directory' {
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryDirectoryTask' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should resolve to a directory'
    }

    It 'validates all paths are to files' {
        GivenFile 'abc.yml'
        GivenDirectory 'def.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = '*.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'should resolve to a file'
    }

    It 'does not validate an optional, not provided path' {
        WhenRunningTask 'ValidateOptionalFileTask' -Parameter @{ }
        ThenTaskCalled -WithParameter @{ }
    }

    It 'validates mandatory path exists' {
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryPathTask' -Parameter @{ } -ErrorAction SilentlyContinue
        ThenThrewException -Pattern 'is\ mandatory'
        ThenTaskNotCalled
    }

    It 'allows paths outside the build directory' {
        WhenRunningTask 'ValidateMandatoryNonexistentOutsideBuildRootFileTask' -Parameter @{ 'Path' = '..\YOLO.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Join-Path -Path '..' -ChildPath 'YOLO.yml') }
        ThenPipelineSucceeded
    }

    It 'validates paths are under build directory' {
        WhenRunningTask 'ValidateMandatoryNonexistentFileTask' -Parameter @{ 'Path' = '../YOLO.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException 'outside\ the\ build\ root'
    }

    It 'resolves mandatory file that exists to a relative path' {
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'abc.yml') }
        ThenPipelineSucceeded
    }

    It 'validates mandatory path exists' {
        WhenRunningTask 'ValidateMandatoryFileTask' -Parameter @{ 'Path' = 'abc.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'does\ not\ exist'
    }

    It 'converts absolute path to relative path' {
        WhenRunningTask 'ValidateMandatoryNonexistentFileTask' -Parameter @{ 'Path' = [IO.Path]::GetFullPath((Join-Path -Path $script:testRoot -Childpath 'abc.yml' )) }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'abc.yml') }
        ThenPipelineSucceeded
    }

    It 'allows mandatory paths that do not exist' {
        WhenRunningTask 'ValidateMandatoryNonexistentFileTask' -Parameter @{ 'Path' = 'packages\tool\*.yolo' } #-ErrorAction SilentlyContinue
        ThenTaskCalled -WithParameter @{ 'Path' = '' }
        ThenPipelineSucceeded
    }

    It 'rejects paths outside the build directory' {
        WhenRunningTask -Name 'ValidateMandatoryNonexistentFileTask' `
                        -Parameter @{ 'Path' = ('..\' + (Split-Path -Path $script:testRoot -Leaf) + '!\abc.yml') } `
                        -BuildRoot ($script:testRoot + '///') `
                        -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'outside\ the\ build\ root'
    }

    It 'resolves multiple items with wildcards to relative paths' {
        GivenFile 'abc.yml'
        GivenFile 'xyz.yml'
        GivenFile 'trolololo.txt'
        GivenFile 'yayaya.txt'
        WhenRunningTask 'ValidateOptionalPathsTask' -Parameter @{ 'Path' = '*.yml', '*.txt' }
        ThenPipelineSucceeded
        ThenTaskCalled
        $taskParameters = Get-LastTaskBoundParameter
        $taskParameters | Should -Not -BeNullOrEmpty
        $taskParameters['Path'] | Should -HaveCount 5
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'abc.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'xyz.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'trolololo.txt')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'yayaya.txt')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'whiskey.yml')
        ThenPipelineSucceeded
    }

    It 'resolves multiple paths to relative paths' {
        GivenFile 'abc.yml'
        GivenFile 'xyz.yml'
        GivenFile 'hjk.yml'
        WhenRunningTask 'ValidateMandatoryFilesTask' -Parameter @{ 'Path' = 'abc.yml', 'xyz.yml', 'hjk.yml' } -ErrorAction SilentlyContinue
        ThenTaskCalled
        $taskParameters = Get-LastTaskBoundParameter
        $taskParameters | Should -Not -BeNullOrEmpty
        $taskParameters['Path'] | Should -HaveCount 3
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'abc.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'xyz.yml')
        $taskParameters['Path'] | Should -Contain (Resolve-RelativePath 'hjk.yml')
        ThenPipelineSucceeded
    }

    It 'prevents paths from using a different case to reach outside the build directory' {
        # Make sure we're in a directory that has letters.
        $buildRoot = Join-Path -Path $script:testRoot -ChildPath 'fubar'
        GivenDirectory $buildRoot
        $tempDir = $buildRoot | Split-Path -Parent
        $buildDirName = $buildRoot | Split-Path -Leaf
        $attackersBuildDirName = $buildDirName.ToUpper()
        $attackersBuildDir = Join-Path -Path $tempDir -ChildPath $attackersBuildDirName
        $whiskeyYmlFile = JOin-Path -Path $buildRoot -ChildPath 'whiskey.yml'
        GivenFile $whiskeyYmlFile
        $attackersFile = Join-Path -Path $attackersBuildDir -ChildPath 'abc.yml'
        GivenFile $attackersFile
        $optionalParam = @{}
        if( $script:fsCaseSensitive )
        {
            $optionalParam['ErrorAction'] = 'SilentlyContinue'
        }
        WhenRunningTask 'ValidateOptionalNonexistentPathTask' `
                        -Parameter @{ 'Path' = ('..\{0}\abc.yml' -f $attackersBuildDirName) } `
                        @optionalParam `
                        -BuildRoot $buildRoot
        if( $script:fsCaseSensitive )
        {
            ThenTaskNotCalled
            ThenThrewException -Pattern 'outside\ the\ build\ root'
        }
        else
        {
            ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'abc.yml') }
            ThenPipelineSucceeded
        }
    }

    It 'allows paths that are outside working directory and still in build directory' {
        GivenDirectory 'subdir'
        WhenRunningTask 'ValidateOptionalNonExistentPathTask' -Parameter @{ 'Path' = '..\NewFile.txt'; 'WorkingDirectory' = 'subdir' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath '..\Newfile.txt') }
    }

    It 'creates files' {
        # We use a directory since `New-Item` defaults to creating files.
        WhenRunningTask 'CreateMissingFileTask' -Parameter @{ 'Path' = 'dir\One.txt','Two.txt' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'dir\One.txt','Two.txt') }
        Join-Path -Path $script:testRoot -ChildPath 'dir\One.txt' | Should -Exist
        Join-Path -Path $script:testRoot -ChildPath 'Two.txt' | Should -Exist
    }

    It 'creates directories' {
        # We use a directory since `New-Item` defaults to creating files.
        WhenRunningTask 'CreateMissingDirectoryTask' -Parameter @{ 'Path' = 'One','Two' }
        ThenTaskCalled -WithParameter @{ 'Path' = (Resolve-RelativePath 'One','Two') }
        Join-Path -Path $script:testRoot -ChildPath 'One' | Should -Exist
        Join-Path -Path $script:testRoot -ChildPath 'Two' | Should -Exist
    }

    It 'fails if creating item of unknown type' {
        WhenRunningTask 'CreateMissingItemwithPathTypeMissingTask' -Parameter @{ 'Path' = 'One.txt' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'add a PathType property'
    }

    It 'allows period for current directory' {
        WhenRunningTask 'ValidateMandatoryDirectoryTask' -Parameter @{ 'Path' = '.' }
        ThenTaskCalled -WithParameter @{ 'Path' = ('.{0}' -f [IO.Path]::DirectorySeparatorChar) }
    }

    It 'normalizes directory separators for multipe paths some with wildcards' {
        WhenRunningTask 'ValidateMandatoryNonexistentFilesTask' -Parameter @{ 'Path' = @( 'file.txt','*.json','anotherfile.txt') }
        $expectedPaths = & {
            Resolve-RelativePath 'file.txt'
            Resolve-RelativePath 'anotherfile.txt'
        }
        ThenTaskCalled -WithParameter @{ 'Path' = $expectedPaths }
    }

    It 'normalize directory separators' {
        if( [IO.Path]::DirectorySeparatorChar -eq '\' )
        {
            $separator = '/'
        }
        else
        {
            $separator = '\'
        }
        $paths = @(
            ((Join-Path -Path $script:testRoot -ChildPath 'some\custom\path.zip') -replace ([regex]::Escape([IO.Path]::DirectorySeparatorChar)),$separator),
            ('some{0}other{0}path.zip' -f $separator)
            # Make sure on Windows, separator gets switched to backslash.
            'another{0}path.txt' -f [IO.Path]::AltDirectorySeparatorChar
        )
        WhenRunningTask 'ValidateMandatoryNonexistentFilesTask' -Parameter @{ 'Path' = $paths }
        $expectedPaths = & {
            Resolve-RelativePath ('some{0}custom{0}path.zip' -f [IO.Path]::DirectorySeparatorChar)
            Resolve-RelativePath ('some{0}other{0}path.zip' -f [IO.Path]::DirectorySeparatorChar)
            Resolve-RelativePath ('another{0}path.txt' -f [IO.Path]::DirectorySeparatorChar)
        }
        ThenTaskCalled -WithParameter @{ 'Path' = $expectedPaths }
    }

    It 'allows glob syntax' {
        GivenFile 'absolute','abc.yml', 'cdf.yml', 'root.txt','root.txt.orig', 'dir\file.txt', 'dir\whiskey.yml', 'dir1\file.txt.orig', 'dir2\dir3\anotherfile.txt', 'dir2\dir3\anotherfile.txt.fubar'
        # These files test that we search hidden places
        GivenFile '.hidden.yml' -Hidden
        GivenDirectory '.hidden' -Hidden
        GivenFile '.hidden\config.txt'
        # These files test that we're doing a case-senstive search on Linux.
        GivenFile 'uppercase.TXT'

        WhenRunningTask 'ValidatePathWithGlobTask' -Parameter @{
            'Path' = @( '*.yml', '**\*.txt', '**\*.txt.*', (Join-Path -Path $script:testRoot -ChildPath 'absolute'));
            'Exclude' = @( 'PSModules\**', '**\*.orig', 'whiskey.yml' ) }
        $expectedPaths = & {
            Resolve-RelativePath 'absolute'
            Resolve-RelativePath 'abc.yml'
            Resolve-RelativePath 'cdf.yml'
            Resolve-RelativePath 'root.txt'
            Resolve-RelativePath 'dir\file.txt'
            Resolve-RelativePath 'dir2\dir3\anotherfile.txt'
            Resolve-RelativePath 'dir2\dir3\anotherfile.txt.fubar'
            Resolve-RelativePath '.hidden.yml'
            Resolve-RelativePath '.hidden\config.txt'

            # If we're not on a case-sensitive file sytem, make sure results use the correct case sensitivity.
            if( (Test-Path -Path $script:testRoot.ToUpperInvariant()) )
            {
                Resolve-RelativePath 'uppercase.TXT'
            }
        }
        ThenTaskCalled -WithParameter @{ 'Path' = $expectedPaths }
    }

    It 'validates glob path resolves to single item' {
        GivenFile 'abc.yml'
        WhenRunningTask 'ValidateSinglePathWithGlobTask' -Parameter @{ 'Path' = '**/*.yml' } -ErrorAction SilentlyContinue
        ThenTaskNotCalled
        ThenThrewException -Pattern 'use glob.*type is not.*task authoring error'
    }

    # Whiskey detects the case-sensitivity of the file system and calls Find-GlobFile with matching case-sensitivity.
    # This detection needs to handle when resolving paths from the root directory.
    Context 'globbing in the root directory' {
        AfterEach {
            Reset
            if( -not $IsWindows )
            {
                sudo chmod o-w /
            }
        }

        It 'detects case-sensitivity' -Skip:(-not (Get-ChildItem -Path ([IO.Path]::DirectorySeparatorChar) -File)) {
            if( -not $IsWindows )
            {
                sudo chmod o+w /
            }
            $rootPath =
                Resolve-Path -Path ([IO.Path]::DirectorySeparatorChar) |
                Select-Object -ExpandProperty 'ProviderPath'
            Initialize-WhiskeyTestPSModule -BuildRoot $rootPath -Name 'Glob'
            Push-Location $rootPath
            try
            {
                $paths =
                    Get-ChildItem -Path $rootPath -File |
                    Split-Path -Leaf

                $changedCasePaths =
                    $paths |
                    ForEach-Object {
                        Write-Output ($_.ToUpperInvariant())
                    }

                $exclude =
                    Get-ChildItem -Path $rootPath -Directory -Force |
                        ForEach-Object { '**\{0}\**' -f $_.Name }

                $context = New-WhiskeyTestContext -ForBuildServer -ForBuildRoot $script:testRoot
                $context.BuildRoot = $rootPath
                $resolvedPaths =
                    $changedCasePaths |
                    Resolve-WhiskeyTaskPath -TaskContext $context -UseGlob -PropertyName 'Path' -Exclude $exclude -ErrorAction Ignore
                $expectedPaths = & {
                    foreach( $changedCasePath in $changedCasePaths )
                    {
                        $fullPath = Join-Path -Path $rootPath -ChildPath $changedCasePath
                        # Case-insensitive ?
                        if( (Test-Path -Path $fullPath) )
                        {
                            Write-Output (Resolve-RelativePath -Path $changedCasePath)
                        }
                    }
                }

                $expectedPaths = $expectedPaths | Where-Object {$_ -ne ".\DOCKERFILE.WINDOWS"}
                $resolvedPaths | Sort-Object | Should -Be ($expectedPaths | Sort-Object)
            }
            finally
            {
                Pop-Location
            }
        }
    }
}