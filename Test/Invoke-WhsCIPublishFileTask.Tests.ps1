
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function New-PublishFileStructure
{
    param(
        [Switch]
        $ByDeveloper,

        [Switch]
        $ByBuildServer,

        [Switch]
        $NoFilePathsProvided,

        [Switch]
        $NoDestinationDirectoriesProvided,

        [Switch]
        $InvalidDestinationWriteLocation
    )
    
    $Global:Error.Clear()
    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith {return [SemVersion.SemanticVersion]'1.1.1-rc.1+build'}.GetNewClosure()

    if ($ByDeveloper)
    {
        $taskContext = New-WhsCITestContext -ForDeveloper
    }
    
    if ($ByBuildServer)
    {
        $taskContext = New-WhsCITestContext -ForBuildServer
    }

    $sourceDir1 = Join-Path $taskContext.BuildRoot -ChildPath '\SourceDir1'
    $sourceDir2 = Join-Path $sourceDir1 -ChildPath '\SourceDir2'
    $sourceDir3 = Join-Path $sourceDir1 -ChildPath '\SourceDir3'
    $destDir1 = Join-Path $taskContext.BuildRoot -ChildPath '\DestDir1'
    $destDirDNE = Join-Path $taskContext.BuildRoot -ChildPath '\DestDirDNE'
    $testFile1 = Join-Path $sourceDir1 -ChildPath 'TestFile1.txt'
    $testFile2 = Join-Path $sourceDir2 -ChildPath 'TestFile2.txt'
    $testFile3 = Join-Path $sourceDir3 -ChildPath 'TestFile3.txt'
    $testFileDNE = 'TestFileDNE.txt'
    
    Install-Directory -Path $sourceDir1
    Install-Directory -Path $sourceDir2
    Install-Directory -Path $sourceDir3
    Install-Directory -Path $destDir1
    $null = New-Item -Path $testFile1 -ItemType File -Value 'I am TestFile1.txt'
    $null = New-Item -Path $testFile2 -ItemType File -Value 'I am TestFile2.txt'
    $null = New-Item -Path $testFile3 -ItemType File -Value 'I am TestFile3.txt'
    
    $taskParameter = @{}
    $taskParameter.SourceFiles = ('\SourceDir1\TestFile1.txt', '\SourceDir1\SourceDir2\TestFile2.txt', '\SourceDir1\SourceDir3\TestFile3.txt', $testFileDNE)
    $taskParameter.DestinationDirectories = ($taskContext.BuildRoot, $destDir1, $destDirDNE)

    if ($NoFilePathsProvided)
    {
        $taskParameter.Remove('SourceFiles')
    }

    if ($NoDestinationDirectoriesProvided)
    {
        $taskParameter.Remove('DestinationDirectories')
    }

    if ($InvalidDestinationWriteLocation)
    {
        $taskParameter.DestinationDirectories = ($taskContext.BuildRoot, $destDir1, $destDirDNE, 'DX:\BadLocation')
    }
        
    $returnContextParams = @{}
    $returnContextParams.TaskContext = $taskContext
    $returnContextParams.TaskParameter = $taskParameter

    return $returnContextParams
}

Describe 'Invoke-WhsCIPublishFileTask when called by Developer' {
    $returnContextParams = New-PublishFileStructure -ByDeveloper
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter

    Invoke-WhsCIPublishFileTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }
    
    It 'should not create any new directories' {
        Test-Path -Path (Join-Path $taskContext.BuildRoot -ChildPath '\DestDirDNE') | should be $false
    }
    
    It 'should not publish any files' {
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile3.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile3.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile3.txt') | should be $false
    }    
}

Describe 'Invoke-WhsCIPublishFileTask when called by Build Server' {
    $returnContextParams = New-PublishFileStructure -ByBuildServer
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    Mock -CommandName 'Write-Warning' -ModuleName 'WhsCI' -ParameterFilter {$Message -match 'The source file ''TestFileDNE.txt'' does not exist.'}

    Invoke-WhsCIPublishFileTask -TaskContext $taskContext -TaskParameter $taskParameter -WarningVariable +warnings
    
    It 'should not write any errors' {
        $Global:Error | Should BeNullOrEmpty
    }
    
    It 'should write warnings about the file that does not exist' {    
        Assert-MockCalled -CommandName 'Write-Warning' -ModuleName 'WhsCI' -Times 3 -Exactly -ParameterFilter {$Message -match 'The source file ''TestFileDNE.txt'' does not exist.'}
    }
    
    It 'should create a new destination directory that does not exist' {
        Test-Path -Path (Join-Path $taskContext.BuildRoot -ChildPath '\DestDirDNE') | should be $true
    }
    
    It 'should publish the 3 test files to the 3 destination directories' {
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile1.txt') | should be $true
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile2.txt') | should be $true
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile3.txt') | should be $true
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile1.txt') | should be $true
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile2.txt') | should be $true
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile3.txt') | should be $true
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile1.txt') | should be $true
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile2.txt') | should be $true
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile3.txt') | should be $true
    }    
}

Describe 'Invoke-WhsCIPublishFileTask when a valid `SourceFiles` list is not provided' {
    $returnContextParams = New-PublishFileStructure -ByBuildServer -NoFilePathsProvided
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    
    Invoke-WhsCIPublishFileTask -TaskContext $taskContext -TaskParameter $taskParameter -ErrorAction SilentlyContinue
    
    It 'should write an error that the `SourceFiles` parameter is not valid' {
        $Global:Error | Should Match 'No source files were defined. Please provide a valid list of files utilizing the `TaskParameter.SourceFiles` parameter.'
    }
   
    It 'should not create any new directories' {
        Test-Path -Path (Join-Path $taskContext.BuildRoot -ChildPath '\DestDirDNE') | should be $false
    }
    
    It 'should not publish any files' {
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile3.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile3.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile3.txt') | should be $false
    }
}

Describe 'Invoke-WhsCIPublishFileTask when a valid `DestinationDirectories` list is not provided' {
    $returnContextParams = New-PublishFileStructure -ByBuildServer -NoDestinationDirectoriesProvided
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    
    Invoke-WhsCIPublishFileTask -TaskContext $taskContext -TaskParameter $taskParameter -ErrorAction SilentlyContinue
    
    It 'should write an error that the `DestinationDirectories` parameter is not valid' {
        $Global:Error | Should Match 'No target directory locations were defined. Please provide a valid list of directories utilizing the `TaskParameter.DestinationDirectories` parameter.'
    }
   
    It 'should not create any new directories' {
        Test-Path -Path (Join-Path $taskContext.BuildRoot -ChildPath '\DestDirDNE') | should be $false
    }
    
    It 'should not publish any files' {
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile3.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile3.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile3.txt') | should be $false
    }
}

Describe 'Invoke-WhsCIPublishFileTask when an invalid destination directory drive is passed' {
    $returnContextParams = New-PublishFileStructure -ByBuildServer -InvalidDestinationWriteLocation
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    
    Invoke-WhsCIPublishFileTask -TaskContext $taskContext -TaskParameter $taskParameter -ErrorAction SilentlyContinue
    
    It 'should write an error that the destination drive name does not exist' {
        $Global:Error | Should BeLike 'Cannot find drive. A drive with the name * does not exist.'
    }
   
    It 'should not create any new directories' {
        Test-Path -Path (Join-Path $taskContext.BuildRoot -ChildPath '\DestDirDNE') | should be $false
    }
    
    It 'should not publish any files' {
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\TestFile3.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDir1\TestFile3.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile1.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile2.txt') | should be $false
        Test-Path -Path (Join-Path -Path $taskContext.BuildRoot -ChildPath '\DestDirDNE\TestFile3.txt') | should be $false
    }
}
