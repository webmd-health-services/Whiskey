
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
    Mock -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -ParameterFilter {$ScriptBlock -match 'publish'}
    Mock -CommandName 'Remove-Item' -ModuleName 'WhsCI' -ParameterFilter {$Path -match '\.npmrc'}

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

    It 'should not publish the Node module package to the defined registry' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -Times 0
    }
}

Describe 'Invoke-WhsCIPublishNodeModuleTask when called by Developer with defined working directory' {
    $returnContextParams = New-PublishNodeModuleStructure -ByDeveloper -WithWorkingDirectoryOverride
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter

    Invoke-WhsCIPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should not publish the Node module package to the defined registry' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'WhsCI' -Times 0
    }
}

Describe 'Invoke-WhsCIPublishNodeModuleTask when called by Build Server' {
    $returnContextParams = New-PublishNodeModuleStructure -ByBuildServer
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    $npmrcPath = Join-Path -Path $taskContext.BuildRoot -ChildPath '.npmrc'

    Invoke-WhsCIPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should validate the version is in the appropriate SemVersion.SemanticVersion format' {
        Assert-MockCalled -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -Times 1 -Exactly
    }

    It 'should create a temporary .npmrc file in the root of the application build directory' {
        Test-Path -Path $npmrcPath | Should be $true
    }

    It 'should populate the .npmrc file with the appropriate NPM registry value' {
        $npmrcPath | Should Contain $taskContext.ProgetSession.NpmFeedUri
    }

    It 'should populate the .npmrc file with authentication credentials' {
        $npmrcPath | Should Contain ('username={0}' -f $taskContext.ProGetSession.Credential.UserName)
        $npmrcPath | Should Contain '_password'
    }

    It 'should populate the .npmrc file with the current user''s email address' {
        $npmEmail = $env:USERNAME + '@webmd.net'
        $npmrcPath | Should Contain $npmEmail
    }
    
    It 'should publish the Node module package to the defined registry' {
        Assert-MockCalled   -CommandName 'Invoke-Command' -ModuleName 'WhsCI' `
                            -ParameterFilter {$ScriptBlock -match 'publish'} -Times 1 -Exactly
    }
    
    It 'should remove the temporary config file .npmrc from the build root' {
        Assert-MockCalled -CommandName 'Remove-Item' -ModuleName 'WhsCI' `
                          -ParameterFilter {$Path -match '\.npmrc'} -Times 1 -Exactly

    }
}

    Describe 'Invoke-WhsCIPublishNodeModuleTask when called by Build Server' {
    $returnContextParams = New-PublishNodeModuleStructure -ByBuildServer -WithWorkingDirectoryOverride
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    $npmrcPath = Join-Path -Path $taskContext.BuildRoot -ChildPath '.npmrc'

    Invoke-WhsCIPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should validate the version is in the appropriate SemVersion.SemanticVersion format' {
        Assert-MockCalled -CommandName 'ConvertTo-WhsCISemanticVersion' -ModuleName 'WhsCI' -Times 1 -Exactly
    }

    It 'should create a temporary .npmrc file in the root of the application build directory' {
        Test-Path -Path $npmrcPath | Should be $true
    }

    It 'should populate the .npmrc file with the appropriate NPM registry value' {
        $npmrcPath | Should Contain $taskContext.ProgetSession.NpmFeedUri
    }

    It 'should populate the .npmrc file with authentication credentials' {
        $npmrcPath | Should Contain ('username={0}' -f $taskContext.ProGetSession.Credential.UserName)
        $npmrcPath | Should Contain '_password'
    }

    It 'should populate the .npmrc file with the current user''s email address' {
        $npmEmail = $env:USERNAME + '@webmd.net'
        $npmrcPath | Should Contain $npmEmail
    }
    
    It 'should publish the Node module package to the defined registry' {
        Assert-MockCalled   -CommandName 'Invoke-Command' -ModuleName 'WhsCI' `
                            -ParameterFilter {$ScriptBlock -match 'publish'} -Times 1 -Exactly
    }
    
    It 'should remove the temporary config file .npmrc from the build root' {
        Assert-MockCalled -CommandName 'Remove-Item' -ModuleName 'WhsCI' `
                          -ParameterFilter {$Path -match '\.npmrc'} -Times 1 -Exactly
    }
}