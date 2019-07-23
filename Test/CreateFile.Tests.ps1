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

function GivenDirectory
{
   param(
       $Path
   )

   $Path = Join-Path -Path $buildRoot -ChildPath $Path
   New-Item -Path $Path -ItemType "directory"
}

function ThenFile {
    param(
        $Path,
        $Contains
    )

    $Path = Join-Path -Path $buildRoot -ChildPath $Path

    $Path | Should -Exist

    if ($Contains)
    {
        $actualContent = Get-Content -Path $Path 
        $actualContent | Should -Match $Contains
    }

    else
    {
        $actualContent = Get-Content -Path $Path 
        $actualContent | Should -BeNullOrEmpty
    }
}

function ThenSuccess {
    $Global:Error | Should -BeNullOrEmpty
    $script:failed | Should -BeFalse
}

function ThenTaskFailed {
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

function WhenRunningTask {
    [CmdletBinding()]
    param(
    )

    $Global:Error.Clear()

    
    try {

        [Whiskey.Context]$script:context = New-WhiskeyTestContext -ForDeveloper -ConfigurationPath (Join-Path -Path $buildRoot -ChildPath 'whiskey.yml')
        
        foreach($key in $variables.Keys)
        {
            Add-WhiskeyVariable -Context $context -Name $key -Value $variables[$key]
        }

        $tasks = $context.Configuration['Build'] | 
            Where-Object { $_.ContainsKey('CreateFile') } | 
            ForEach-Object { $_['CreateFile'] }
        
        foreach ($task in $tasks) {
            Invoke-WhiskeyTask -TaskContext $context -Name 'CreateFile' -Parameter $task
        }
    }
    catch {
        Write-Error -ErrorRecord $_
        $script:failed = $true
    }
}

Describe -Name 'CreateFile.when creating a file' {
    It -Name 'should create the file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Content: "Hello World."
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains 'Hello World.'
    }
   
}

 Describe -Name 'CreateFile.when and resolves Whiskey variables' {
    It -Name 'should create the file'{
        Init
        GivenVariable 'Environment' -WithValue 'Test'
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Content: "My environment is: $(Environment)"
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains "My environment is: Test"
    }
 }

Describe -Name 'CreateFile.when the content is empty' {
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

Describe -Name 'CreateFile.when the path is missing' {
    It -Name 'should not create a file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Content: "No path file"
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches "'Path' property is missing. Please set it to list of target locations to create new file."
    }
}

Describe -Name 'Createfile.when the path already exists' {
    It 'should only create the first file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Content: "First File."

        - CreateFile:
            Path: file.txt
            Content: "Second File... First File Overwritten"
            Force: N
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenFile -Path 'file.txt' -Contains 'First File.'
        ThenError -Matches "'Path' already exists. Please change 'path' to create new file."
    }
}

Describe -Name 'Createfile.when the path already exists and Force enabled' {
    It 'should only create the first file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
            Content: "First File."
        
        - CreateFile:
            Path: file.txt
            Content: "Second File... First File Overwritten"
            Force: true
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenSuccess
        ThenFile -Path 'file.txt' -Contains "Second File... First File Overwritten"
    }
}

Describe -Name 'Createfile.when the path is outside root' {
    It 'should not create the file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: ../file.txt
            Content: "File above root."
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches "'Path' given is outside of root. Please change one or more elements of the 'path'".
    }
}

Describe -Name 'Createfile.when the path does not contain a file extension' {
    It 'should create the file' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenSuccess
        ThenFile -Path 'file'
    }
}

Describe -Name 'CreateFile.when a directory already exists with same path name' {
    It -Name 'should not create the file'{
        Init
        GivenDirectory -Path 'file.txt'
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: file.txt
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches "'Path' already points to a directory of the same name."
    }
 }

 Describe -Name 'CreateFile.when a directory already exists with same path name and Force enabled' {
    It -Name 'should not create the file'{
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
        ThenError -Matches "'Path' already points to a directory of the same name."
    }
 }

 Describe -Name 'CreateFile.when a subdirectory in the path does not exist' {
    It -Name 'should not create the path' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: \notreal\stillnotreal\file.txt
            Content: 'I am not real.'
'@
        WhenRunningTask -ErrorAction SilentlyContinue
        ThenTaskFailed
        ThenError -Matches "'Path' contains subdirectories that do not exist."
    }
 }
 
 Describe -Name 'CreateFile.when a subdirectory in path does not exist but Force is true' {
    It -Name 'should create the entire path' {
        Init
        GivenWhiskeyYml @'
        Build:
        - CreateFile:
            Path: \real\Iamreal\file.txt
            Content: 'I am a real.'
            Force: true
'@
        WhenRunningTask
        ThenSuccess
        ThenFile -Path '\real\Iamreal\file.txt' -Contains 'I am a real.'
    }
 }