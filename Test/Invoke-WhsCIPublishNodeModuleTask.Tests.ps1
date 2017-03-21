
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhsCITest.ps1' -Resolve)

function New-PublishNodeModuleStructure
{
    param(
        [Switch]
        $ByDeveloper,

        [Switch]
        $ByBuildServer,

        [Switch]
        $WithWorkingDirectoryOverride
    )

    Mock -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -MockWith {return [SemVersion.SemanticVersion]'1.1.1-rc.1+build'}.GetNewClosure()
    Mock -CommandName 'Install-WhsCINodeJs' -ModuleName 'WhsCI' -MockWith {return 'C:\PathToNode\whsbuild.yml'}
    Mock -CommandName 'Join-Path' -ModuleName 'WhsCI' -ParameterFilter {$ChildPath -eq 'node_modules\npm\bin\npm-cli.js'} -MockWith {return 'C:\PathToNode\PathToNPM'}
    Mock -CommandName 'New-Item' -ModuleName 'WhsCI' -ParameterFilter {$Path -match '.npmrc'} -MockWith {return 'C:\NotANullPath'}
    Mock -CommandName 'Add-Content' -ModuleName 'WhsCI'
    Mock -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -ParameterFilter {$ScriptBlock -match 'publish'}

    if ($ByDeveloper)
    {
        $context = New-WhsCITestContext -ForDeveloper
    }
    
    if ($ByBuildServer)
    {
        $context = New-WhsCITestContext -ForBuildServer
    }
    
    $taskParameter = @{}
    $workingDir = $context.BuildRoot
    if ($WithWorkingDirectoryOverride)
    {
        $taskParameter['WorkingDirectory'] = 'App'
        $workingDir = Join-Path -Path $context.BuildRoot -ChildPath $taskParameter.WorkingDirectory
        Install-Directory $workingDir
    }
    $testPackageJsonPath = Join-Path -Path $workingDir -ChildPath 'package.json'
    $testPackageJson = '{
  "name": "whs_publishnodemodule_test",
  "version": "1.2.0",
  "main": "index.js",
  "engines": {
    "node": "^4.4.7"
  }
}'
    $testPackageJsonPath = New-Item -Path $testPackageJsonPath -ItemType File -Value $testPackageJson
    
    $returnContextParams = @{}
    $returnContextParams.TaskContext = $context
    $returnContextParams.TaskParameter = $taskParameter
    
    return $returnContextParams

}

Describe 'Invoke-WhsCIPublishNodeModuleTask when called by Developer' {
    $returnContextParams = New-PublishNodeModuleStructure -ByDeveloper
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter

    Invoke-WhsCIPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should ensure the appropriate versions of Node and NPM are installed' {
        Assert-MockCalled -CommandName 'Install-WhsCINodeJs' -ModuleName 'WhsCI' -Times 1 -Exactly
    }

    It 'should ensure that a package.json file exists in the appropriate working directory' {
        Test-Path (Join-Path -Path $taskContext.BuildRoot -ChildPath 'package.json') | Should be $true
    }
}

Describe 'Invoke-WhsCIPublishNodeModuleTask when called by Developer with defined working directory' {
    $returnContextParams = New-PublishNodeModuleStructure -ByDeveloper -WithWorkingDirectoryOverride
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    $workingDir = Join-Path -Path $taskContext.BuildRoot -ChildPath $taskParameter.WorkingDirectory

    Invoke-WhsCIPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should ensure the appropriate versions of Node and NPM are installed' {
        Assert-MockCalled -CommandName 'Install-WhsCINodeJs' -ModuleName 'WhsCI' -Times 1 -Exactly
    }

    It 'should ensure that a package.json file exists in the appropriate working directory' {
        Test-Path (Join-Path -Path $workingDir -ChildPath 'package.json') | Should be $true
    }
}

Describe 'Invoke-WhsCIPublishNodeModuleTask when called by Build Server' {
    $returnContextParams = New-PublishNodeModuleStructure -ByBuildServer
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter

    Invoke-WhsCIPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should validate the version is in the appropriate SemVersion.SemanticVersion format' {
        Assert-MockCalled -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -Times 1 -Exactly
    }

    It 'should ensure that a package.json file exists in the appropriate working directory' {
        Test-Path (Join-Path -Path $taskContext.BuildRoot -ChildPath 'package.json') | Should be $true
    }

    It 'should create a temporary .npmrc file in the root of the application build directory' {
        Assert-MockCalled -CommandName 'New-Item' -ModuleName 'WhsCI' -Times 1 -Exactly
    }

    It 'should populate the .npmrc file with the appropriate configuration values' {
        Assert-MockCalled -CommandName 'Add-Content' -ModuleName 'WhsCI' -Times 4 -Exactly
    }

    It 'should publish the Node module package to the defined registry' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -Times 1 -Exactly
    }
}

    Describe 'Invoke-WhsCIPublishNodeModuleTask when called by Build Server' {
    $returnContextParams = New-PublishNodeModuleStructure -ByBuildServer -WithWorkingDirectoryOverride
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    $workingDir = Join-Path -Path $taskContext.BuildRoot -ChildPath $taskParameter.WorkingDirectory

    Invoke-WhsCIPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should validate the version is in the appropriate SemVersion.SemanticVersion format' {
        Assert-MockCalled -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -Times 1 -Exactly
    }

    It 'should ensure that a package.json file exists in the appropriate working directory' {
        Test-Path (Join-Path -Path $workingDir -ChildPath 'package.json') | Should be $true
    }

    It 'should create a temporary .npmrc file in the root of the application build directory' {
        Assert-MockCalled -CommandName 'New-Item' -ModuleName 'WhsCI' -Times 1 -Exactly
    }

    It 'should populate the .npmrc file with the appropriate configuration values' {
        Assert-MockCalled -CommandName 'Add-Content' -ModuleName 'WhsCI' -Times 4 -Exactly
    }

    It 'should publish the Node module package to the defined registry' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -Times 1 -Exactly
    }
}