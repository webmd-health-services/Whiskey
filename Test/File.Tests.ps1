#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

    $script:failed = $false
    $script:context = $null
    $script:buildRoot = $null
    $script:testNum = 0
    $script:variables = $null

    function GivenDirectory
    {
        param(
            $Path
        )

        $Path = Join-Path -Path $script:buildRoot -ChildPath $Path
        New-Item -Path $Path -ItemType 'directory'
    }

    function GivenFile
    {
        param(
            $Path,
            $Contains
        )
        $Path = Join-Path -Path $script:buildRoot -ChildPath $Path
        if ($Contains)
        {
            New-Item -Path $Path -Value $Contains
        }
        else
        {
            New-Item -Path $Path
        }
    }

    function GivenVariable
    {
        param(
            $Name,
            $WithValue
        )

        $script:variables[$Name] = $WithValue
    }

    function GivenWhiskeyYml
    {
        param(
            $Content
        )

        $Content | Set-Content -Path (Join-Path -Path $script:buildRoot -ChildPath 'whiskey.yml')
    }

    function ThenLastModified
    {
        param(
            $Path,
            $After
        )

        $Path = Join-Path -Path $script:buildRoot -ChildPath $Path
        (Get-Item $Path).LastWriteTime | Should -BeGreaterThan $After
    }

    function ThenFile
    {
        param(
            $Path,
            $Contains
        )

        $Path = Join-Path -Path $script:buildRoot -ChildPath $Path

        $Path | Should -Exist

        if ($Contains)
        {
            $actualContent = Get-Content -Path $Path
            $actualContent | Should -BeExactly $Contains
        }

        else
        {
            $actualContent = Get-Content -Path $Path
            $actualContent | Should -BeNullOrEmpty
            Get-Item -Path $Path | Select-Object -Expand 'Length' | Should -Be 0
        }
    }

    function ThenNotFile
    {
        param(
            $Path
        )

        $Path = Join-Path -Path $script:buildRoot -ChildPath $Path
        $Path = [IO.Path]::GetFullPath($Path)

        $Path | Should -Not -Exist
    }

    function ThenSuccess
    {
        $Global:Error | Should -BeNullOrEmpty
        $script:failed | Should -BeFalse
    }

    function ThenTaskFailed
    {
        $Global:Error | Should -Not -BeNullOrEmpty
        $script:failed | Should -BeTrue
    }

    function ThenError
    {
        param(
            $Matches
        )

        $Global:Error | Should -Match $Matches
    }

    function WhenRunningTask
    {
        [CmdletBinding()]
        param(
        )

        $Global:Error.Clear()


        try
        {
            $configPath = Join-Path -Path $script:buildRoot -ChildPath 'whiskey.yml'
            [Whiskey.Context]$script:context = New-WhiskeyTestContext -ForDeveloper `
                                                                      -ConfigurationPath $configPath `
                                                                      -ForBuildRoot $script:buildRoot

            foreach($key in $script:variables.Keys)
            {
                Add-WhiskeyVariable -Context $script:context -Name $key -Value $script:variables[$key]
            }

            $tasks =
                $script:context.Configuration['Build'] |
                Where-Object { $_.ContainsKey('File') } |
                ForEach-Object { $_['File'] }

            foreach ($task in $tasks)
            {
                try
                {
                    Invoke-WhiskeyTask -TaskContext $script:context -Name 'File' -Parameter $task
                }
                catch
                {
                    Write-Error -ErrorRecord $_
                    $script:failed = $true
                }
            }
        }
        catch
        {
            Write-Error -ErrorRecord $_
            $script:failed = $true
        }
    }
}

Describe 'File' {
    BeforeEach {
        $script:failed = $false
        $script:context = $null
        $script:buildRoot = Join-Path -Path $TestDrive -ChildPath ($script:testNum++)
        New-Item -Path $script:buildRoot -ItemType Directory
        $script:variables = @{}
    }

    It 'creates new file' {
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: file.txt
            Content: 'Hello World.'
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains 'Hello World.'
    }

    It 'expand variables in content'{
        GivenVariable 'Environment' -WithValue 'Test'
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: file.txt
            Content: 'My environment is: $(Environment)'
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains 'My environment is: Test'
    }

    It 'create empty files' {
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: file.txt
'@
        WhenRunningTask
        ThenFile -Path 'file.txt'
    }

    It 'validates path is mandatory' {
        GivenWhiskeyYml @'
        Build:
        - File:
            Content: 'No path file'
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches 'is\ mandatory.'
    }

    It 'updates file content' {
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: file.txt
            Content: 'First File.'

        - File:
            Path: file.txt
            Content: 'Second File... First File Overwritten'
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains 'Second File... First File Overwritten'
    }

    It 'allows no file extension' {
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: file
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file'
    }

    It 'validates file can be created'{
        GivenDirectory -Path 'file.txt'
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: file.txt
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches 'Path '{0}' is a directory but must be a file.'
    }

    It 'creates file containers' {
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: notreal\stillnotreal\file.txt
            Content: 'I am real.'
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'notreal\stillnotreal\file.txt' -Contains 'I am real.'
    }

    It 'creates multiple files' {
        GivenWhiskeyYml @'
        Build:
        - File:
            Path:
            - file.txt
            - file2.txt
            - file3.txt
            Content: 'file'
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains 'file'
        ThenFile -Path 'file2.txt' -Contains 'file'
        ThenFile -Path 'file3.txt' -Contains 'file'
    }

    It 'touches file metadata' {
        GivenFile -Path 'file.txt' -Contains 'This is a file.'
        $currentDate = Get-Date
        Start-Sleep 1
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: file.txt
            Touch: True
'@
        WhenRunningTask
        ThenSuccess
        ThenLastModified -Path 'file.txt' -After $currentDate
        ThenFile -Path 'file.txt' -Contains 'This is a file.'
    }

    It 'touches file metadata for multiple files' {
        GivenFile -Path 'file.txt'
        GivenFile -Path 'file2.txt'
        GivenFile -Path 'file3.txt'
        $currentDate = Get-Date
        Start-Sleep 1
        GivenWhiskeyYml @'
        Build:
        - File:
            Path:
            - file.txt
            - file2.txt
            - file3.txt
            Touch: True
'@
        WhenRunningTask
        ThenSuccess
        ThenLastModified -Path 'file.txt' -After $currentDate
        ThenLastModified -Path 'file2.txt' -After $currentDate
        ThenLastModified -Path 'file3.txt' -After $currentDate
    }

    It 'does nothing' {
        GivenFile -Path 'abc.yml'
        GivenFile -Path 'def.yml'
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: '*.yml'
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'abc.yml' -Contains ''
        ThenFile -Path 'def.yml' -Contains ''
    }
}