#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$failed = $false
$context = $null
$buildRoot = $null
$variables = $null

function Init
{
    $script:failed = $false
    $script:context = $null
    $script:buildRoot = $TestDrive.FullName
    $script:variables = @{}
}

function GivenDirectory
{
    param(
        $Path
    )

    $Path = Join-Path -Path $buildRoot -ChildPath $Path
    New-Item -Path $Path -ItemType 'directory'
}

function GivenFile
{
    param(
        $Path,
        $Contains
    )
    $Path = Join-Path -Path $buildRoot -ChildPath $Path
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

    $Content | Set-Content -Path (Join-Path -Path $buildRoot -ChildPath 'whiskey.yml')
}

function ThenLastModified
{
    param(
        $Path,
        $After
    )

    $Path = Join-Path -Path $buildRoot -ChildPath $Path
    (Get-Item $Path).LastWriteTime | Should -BeGreaterThan $After
}

function ThenFile
{
    param(
        $Path,
        $Contains
    )

    $Path = Join-Path -Path $buildRoot -ChildPath $Path

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

    $Path = Join-Path -Path $buildroot -ChildPath $Path
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

        [Whiskey.Context]$script:context = New-WhiskeyTestContext -ForDeveloper -ConfigurationPath (Join-Path -Path $buildRoot -ChildPath 'whiskey.yml')
        
        foreach($key in $variables.Keys)
        {
            Add-WhiskeyVariable -Context $context -Name $key -Value $variables[$key]
        }

        $tasks = 
            $context.Configuration['Build'] | 
            Where-Object { $_.ContainsKey('File') } | 
            ForEach-Object { $_['File'] }
        
        foreach ($task in $tasks)
        {
            try
            {
                Invoke-WhiskeyTask -TaskContext $context -Name 'File' -Parameter $task
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

Describe 'File.when file doesn''t exist.' {
    It 'should create the file' {
        Init
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
   
}

Describe 'File.when content contains variables' {
    It 'should expand variable value in content'{
        Init
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
}

Describe 'File.when there is no content' {
    It 'should create an empty file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: file.txt
'@
        WhenRunningTask
        ThenFile -Path 'file.txt'
    }
}

Describe 'File.when the path is missing' {
    It 'should not create a file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - File:
            Content: 'No path file'
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches 'is\ mandatory.'
    }
}

Describe 'File.when the file already exists and content is given' {
    It 'should change the content of the file' {
        Init
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
}

Describe 'File.when the path is outside root' {
    It 'should not create the file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: ../file.txt
            Content: 'File above root.'
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenNotFile -Path '../file.txt'
        ThenError -Matches 'outside\ the\ build\ root'
    }
}

Describe 'File.when the path does not contain a file extension' {
    It 'should create the file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - File:
            Path: file
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file'
    }
}

Describe 'File.when a directory already exists with same path name' {
    It 'should not create the file'{
        Init
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
}

Describe 'File.when a subdirectory in the path does not exist' {
    It 'should create the full path' {
        Init
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
}

Describe 'File.when multiple files are given.' {
    It 'should create all the files.' {
        Init
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
}

Describe 'File.when Touch specified and file exists' {
    It 'should update the last write time and not change content' {
        Init
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
}
 
Describe 'File.when multiple files are given and Touch is true.' {
    It 'should update the last write time of all the files.' {
        Init
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
}

Describe 'File.when already existing paths are given with no content or touch' {
    It 'should do nothing' {
        Init
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