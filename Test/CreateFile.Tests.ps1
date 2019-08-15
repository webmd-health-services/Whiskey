#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)
$failed = $false
$context = $null
$buildRoot = $null
$variables = $null
$dates = $null

function Init
{
    $script:failed = $false
    $script:context = $null
    $script:buildRoot = $TestDrive.FullName
    $script:variables = @{}
    $script:dates = @{}
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
  $script:dates[$Path] = (Get-Item $Path).LastWriteTime
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

function ThenDate
{
   param(
       $Path
   )
   $Path = Join-Path -Path $buildRoot -ChildPath $Path
   (Get-Item $Path).LastWriteTime | Should -BeGreaterThan $script:dates[$Path]
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

        $tasks = $context.Configuration['Build'] | 
            Where-Object { $_.ContainsKey('CreateFile') } | 
            ForEach-Object { $_['CreateFile'] }
        
        foreach ($task in $tasks)
        {
            try
            {
                Invoke-WhiskeyTask -TaskContext $context -Name 'CreateFile' -Parameter $task
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

Describe 'CreateFile.when file doesn''t exist.' {
    It 'should create the file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Content: 'Hello World.'
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains 'Hello World.'
    }
   
}

Describe 'CreateFile.when content contains variables' {
    It 'should expand variable value in content'{
        Init
        GivenVariable 'Environment' -WithValue 'Test'
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Content: 'My environment is: $(Environment)'
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains 'My environment is: Test'
    }
}

Describe 'CreateFile.when there is no content' {
    It 'should create an empty file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
'@
        WhenRunningTask
        ThenFile -Path 'file.txt'
    }
}

Describe 'CreateFile.when the path is missing' {
    It 'should not create a file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Content: 'No path file'
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches 'path is mandatory.'
    }
}

Describe 'CreateFile.when the file already exists' {
    It 'should only create the first file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Content: 'First File.'

        - CreateFile:
            Path: file.txt
            Content: 'Second File... First File Overwritten'
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenFile -Path 'file.txt' -Contains 'First File.'
        ThenError -Matches '''Path'' already exists. Please change ''path'' to create new file.'
    }
}

Describe 'CreateFile.when the file exists but using Force to overwrite it.' {
    It 'should overwrite the file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Content: 'First File.'
        
        - CreateFile:
            Path: file.txt
            Content: 'Second File... First File Overwritten'
            Force: true
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains 'Second File... First File Overwritten'
    }
}

Describe 'CreateFile.when the path is outside root' {
    It 'should not create the file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: ../file.txt
            Content: 'File above root.'
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches 'outside\ of\ the\ build\ root'
    }
}

Describe 'CreateFile.when the path does not contain a file extension' {
    It 'should create the file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file'
    }
}

Describe 'CreateFile.when a directory already exists with same path name' {
    It 'should not create the file'{
        Init
        GivenDirectory -Path 'file.txt'
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches 'Unable to create file '{0}': a directory exists at that path.'
    }
}

Describe 'CreateFile.when a directory already exists with same path name and Force enabled' {
    It 'should not create the file'{
        Init
        GivenDirectory -Path 'file.txt'
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Force: True
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches 'Unable to create file '{0}': a directory exists at that path.'
    }
}

Describe 'CreateFile.when a subdirectory in the path does not exist' {
    It 'should not create the path' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: notreal\stillnotreal\file.txt
            Content: 'I am not real.'
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches 'Unable to create file '{0}': one or more of its parent directory, '{1}', does not exist. Either create this directory or use the ''Force'' property to create it.'
    }
}
 
Describe 'CreateFile.when a subdirectory in path does not exist but Force is true' {
    It 'should create the entire path' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: real\Iamreal\file.txt
            Content: 'I am a real.'
            Force: true
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'real\Iamreal\file.txt' -Contains 'I am a real.'
    }
}

Describe 'CreateFile.when parent directory is a file.' {
    It 'should not create the file.' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: 
            - IExistButImActuallyAFile.txt
            - IExistButImActuallyAFile.txt\file.txt
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenFile -Path 'IExistButImActuallyAFile.txt'
        ThenError -Matches 'Parent directory of '{0}' is a file, not a directory.'
    }
}

Describe 'CreateFile.when multiple files are given.' {
    It 'should create all the files.' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
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

Describe 'CreateFile.when one of the paths is invalid' {
    It 'should stop at first invalid path' {
        Init
        GivenDirectory -Path 'file2.txt'
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path:
            - file.txt
            - file2.txt
            - file3.txt
            Content: 'file'
'@
    WhenRunningTask -ErrorAction SilentlyContinue
    ThenError -Matches 'Unable to create file '{0}': a directory exists at that path.'
    ThenFile -Path 'file.txt' -Contains 'file'
    }
}

Describe 'CreateFile.when Touch specified and file exists' {
    It 'should update the last write time' {
        Init
        GivenFile 'file.txt'
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Touch: True
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenSuccess
        ThenDate 'file.txt'
    }
}
 
Describe 'CreateFile.when multiple existing files and are given and force is true.' {
    It 'should overwrite all the files.' {
        Init
        GivenFile -Path 'file.txt' -Contains 'file1'
        GivenFile -Path 'file2.txt' -Contains 'file2'
        GivenFile -Path 'file3.txt' -Contains 'file3'
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path:
            - file.txt
            - file2.txt
            - file3.txt
            Content: 'fubarbarfu'
            Force: True
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains 'fubarbarfu'
        ThenFile -Path 'file2.txt' -Contains 'fubarbarfu'
        ThenFile -Path 'file3.txt' -Contains 'fubarbarfu'
    }
}

Describe 'CreateFile.when multiple files are given and Touch is true.' {
    It 'should update the last write time of all the files.' {
        Init
        GivenFile -Path 'file.txt'
        GivenFile -Path 'file2.txt'
        GivenFile -Path 'file3.txt'
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path:
            - file.txt
            - file2.txt
            - file3.txt
            Touch: True
'@
        WhenRunningTask
        ThenSuccess
        ThenDate -Path 'file.txt'
        ThenDate -Path 'file2.txt'
        ThenDate -Path 'file3.txt'
    }
}