
#Requires -Version 4
Set-StrictMode -Version 'Latest'

& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

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

    Mock -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -MockWith {return [SemVersion.SemanticVersion]'1.1.1-rc.1+build'}.GetNewClosure()
    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter {$ScriptBlock -match 'publish'}
    Mock -CommandName 'Remove-Item' -ModuleName 'Whiskey' -ParameterFilter {$Path -match '\.npmrc'}

    if ($ByDeveloper)
    {
        $context = New-WhiskeyTestContext -ForDeveloper
        $npmrcFileContents = ''
    }
    
    if ($ByBuildServer)
    {
        $context = New-WhiskeyTestContext -ForBuildServer
        $npmFeedUri = $context.ProGetSession.NpmFeedUri
        $npmUserName = $context.ProGetSession.Credential.UserName
        $npmEmail = $env:USERNAME + '@webmd.net'
        $npmCredPassword = $context.ProGetSession.Credential.GetNetworkCredential().Password
        $npmBytesPassword  = [System.Text.Encoding]::UTF8.GetBytes($npmCredPassword)
        $npmPassword = [System.Convert]::ToBase64String($npmBytesPassword)
        $npmConfigPrefix = '//{0}{1}:' -f $npmFeedUri.Authority,$npmFeedUri.LocalPath
        $npmrcFileLine2 = ('{0}_password="{1}"' -f $npmConfigPrefix, $npmPassword)
        $npmrcFileLine3 = ('{0}username={1}' -f $npmConfigPrefix, $npmUserName)
        $npmrcFileLine4 = ('{0}email={1}' -f $npmConfigPrefix, $npmEmail)
        $npmrcFileContents = @"
$npmrcFileLine2
$npmrcFileLine3
$npmrcFileLine4
"@
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
    $returnContextParams.NpmrcFileContents = $npmrcFileContents

    return $returnContextParams

}

Describe 'Invoke-WhiskeyPublishNodeModuleTask when called by Developer' {
    $returnContextParams = New-PublishNodeModuleStructure -ByDeveloper
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter

    Invoke-WhiskeyPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should not publish the Node module package to the defined registry' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -Times 0
    }
}

Describe 'Invoke-WhiskeyPublishNodeModuleTask when called by Developer with defined working directory' {
    $returnContextParams = New-PublishNodeModuleStructure -ByDeveloper -WithWorkingDirectoryOverride
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter

    Invoke-WhiskeyPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should not publish the Node module package to the defined registry' {
        Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -Times 0
    }
}

Describe 'Invoke-WhiskeyPublishNodeModuleTask when called by Build Server' {
    $returnContextParams = New-PublishNodeModuleStructure -ByBuildServer
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    $npmrcPath = Join-Path -Path $taskContext.BuildRoot -ChildPath '.npmrc'
    $npmrcFileContents = $returnContextParams.NpmrcFileContents

    Invoke-WhiskeyPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should validate the version is in the appropriate SemVersion.SemanticVersion format' {
        Assert-MockCalled -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -Times 1 -Exactly
    }

    It 'should create a temporary .npmrc file in the root of the application build directory' {
        Test-Path -Path $npmrcPath | Should be $true
    }

    It 'should populate the .npmrc file with the appropriate configuration values' {
        $actualFileContents = Get-Content -Raw -Path $npmrcPath
        $actualFileContents.Trim() | Should Be $npmrcFileContents.Trim()
    }

    It 'should publish the Node module package to the defined registry' {
        Assert-MockCalled   -CommandName 'Invoke-Command' -ModuleName 'Whiskey' `
                            -ParameterFilter {$ScriptBlock -match 'publish'} -Times 1 -Exactly
    }
    
    It 'should remove the temporary config file .npmrc from the build root' {
        Assert-MockCalled -CommandName 'Remove-Item' -ModuleName 'Whiskey' `
                          -ParameterFilter {$Path -match '\.npmrc'} -Times 1 -Exactly
    }
}

Describe 'Invoke-WhiskeyPublishNodeModuleTask when called by Build Server' {
    $returnContextParams = New-PublishNodeModuleStructure -ByBuildServer -WithWorkingDirectoryOverride
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    $npmrcPath = Join-Path -Path $taskContext.BuildRoot -ChildPath '.npmrc'
    $npmrcFileContents = $returnContextParams.NpmrcFileContents

    Invoke-WhiskeyPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter

    It 'should validate the version is in the appropriate SemVersion.SemanticVersion format' {
        Assert-MockCalled -CommandName 'ConvertTo-WhiskeySemanticVersion' -ModuleName 'Whiskey' -Times 1 -Exactly
    }

    It 'should create a temporary .npmrc file in the root of the application build directory' {
        Test-Path -Path $npmrcPath | Should be $true
    }

    It 'should populate the .npmrc file with the appropriate configuration values' {
        $actualFileContents = Get-Content -Raw -Path $npmrcPath
        $actualFileContents.Trim() | Should Be $npmrcFileContents.Trim()
    }
    
    It 'should publish the Node module package to the defined registry' {
        Assert-MockCalled   -CommandName 'Invoke-Command' -ModuleName 'Whiskey' `
                            -ParameterFilter {$ScriptBlock -match 'publish'} -Times 1 -Exactly
    }
    
    It 'should remove the temporary config file .npmrc from the build root' {
        Assert-MockCalled -CommandName 'Remove-Item' -ModuleName 'Whiskey' `
                          -ParameterFilter {$Path -match '\.npmrc'} -Times 1 -Exactly
    }
}

Describe 'Invoke-WhiskeyPublishNodeModuleTask when called with Clean Switch' {
    $returnContextParams = New-PublishNodeModuleStructure -ByBuildServer -WithWorkingDirectoryOverride
    $taskContext = $returnContextParams.TaskContext
    $taskParameter = $returnContextParams.TaskParameter
    $npmrcPath = Join-Path -Path $taskContext.BuildRoot -ChildPath '.npmrc'

    Invoke-WhiskeyPublishNodeModuleTask -TaskContext $taskContext -TaskParameter $taskParameter -Clean
   
    It 'should not create a temporary .npmrc file in the root of the application build directory' {
        Test-Path -Path $npmrcPath | Should be $False
    }
  
    It 'should not populate the .npmrc file with the appropriate configuration values' {
        Test-Path $npmrcPath | Should be $False
    }
  
    It 'should not publish the Node module package to the defined registry' {
        Assert-MockCalled   -CommandName 'Invoke-Command' -ModuleName 'Whiskey' `
                            -ParameterFilter {$ScriptBlock -match 'publish'} -Times 0
    }
    
    It 'should not attempt to remove the temporary config file .npmrc from the build root' {
        Assert-MockCalled -CommandName 'Remove-Item' -ModuleName 'Whiskey' `
                          -ParameterFilter {$Path -match '\.npmrc'} -Times 0
    }
}
