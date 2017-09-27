
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

$nvmHome = $env:NVM_HOME
$restoreNvmHome = $false
if( (Test-Path -Path 'env:NVM_HOME') )
{
    $restoreNvmHome = $true
    Remove-Item -Path 'env:NVM_HOME'
}

$nodePath = $null

function Assert-ThatInstallNodeJs
{
    [CmdletBinding()]
    param(
        [string]
        $InstallsVersion,

        [Switch]
        $OnBuildServer,

        [Switch]
        $OnDeveloperComputer,

        [Switch]
        $WhenUsingDefaultInstallDirectory,

        [Switch]
        $PreserveInstall,

        [string]
        $PackageName = 'nodetest'
    )

    $Global:Error.Clear()

    $installDir = Join-Path -Path $env:TEMP -ChildPath 'z'
    $installDirParam = @{ NvmInstallDirectory = $installDir }
    if( $WhenUsingDefaultInstallDirectory )
    {
        Mock -CommandName 'Join-Path' -ModuleName 'Whiskey' -ParameterFilter { $Path -eq $env:APPDATA -and $ChildPath -eq 'nvm'  } -MockWith { Join-Path -Path $installDir -ChildPath 'nvm' }.GetNewClosure()
        $installDirParam = @{ }
    }

    Mock -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -Verifiable

    $registryUri = 'https://proget.example.com/'
    $testPackageJson = 
'{
  "name": "' + $PackageName + '",
  "version": "0.0.1",
  "description": "TestApp",
  "main": "main.js",
  "scripts": {
    "test": "Yo"
  },
  "engines": { 
    "node": "' + $InstallsVersion + '" 
  }, 
  "author": "doofus",
  "license": "MIT"
}
'

    try
    {

        Install-Directory -Path $installDir
        $null = New-Item (Join-Path -Path $installDir -ChildPath 'package.json') -ItemType File -Value $testPackageJson -Force
        $script:nodePath = $null
        $expectedNodePath = $null
        $expectedNpmPath = $null
        $script:nodePath = Install-WhiskeyNodeJs -RegistryUri $registryUri -ApplicationRoot $installDir @installDirParam -ForDeveloper:$OnDeveloperComputer

        $nvmRoot = Join-Path -Path $installDir -ChildPath 'nvm'
        $nodeRoot = Join-Path -Path $nvmRoot -ChildPath ('v{0}' -f $InstallsVersion)
        $expectedNodePath = Join-Path -Path $nodeRoot -ChildPath 'node.exe'
        $expectedNpmPath = Join-Path -Path $nodeRoot -ChildPath 'node_modules\npm\bin\npm-cli.js'
        
        if( $OnBuildServer )
        {
            $npmCliJsPath = Join-Path -Path $nodeRoot -ChildPath 'node_modules\npm\bin\npm-cli.js' -Resolve
            $expectedLatest = [version]'3.10.10'  # This is the known latest version of 3.
            It 'should upgrade to NPM 3' {
                [version]$version = & $nodePath $npmCliJsPath '--version'
                $version | Should Be $expectedLatest
            }
        }
        
        if( $OnDeveloperComputer )
        {
            It 'should write an error' {
                $Global:Error | Should Match 'is not installed'
            }
            
            It 'should not install Node.js' {
                $expectedNodePath | Should Not Exist
                $expectedNpmPath | Should Not Exist
            }
            
            It 'should not return anything' {
                $nodePath | Should BeNullOrEmpty
            }
        }
        elseif($InstallsVersion -eq '438.4393.329')
        {
            It ('should write an error that Node version ''{0}'' is not available' -f $InstallsVersion) {
                $Global:Error | Should Match ('Failed to install Node.js version {0}.' -f $InstallsVersion)
            }
            
            It 'should not install Node.js' {
                $nodePath | Should BeNullOrEmpty
            }
        }
        elseif(($InstallsVersion -eq '') -or ($InstallsVersion -eq 'fubarsnafu'))
        {
            It ('should write an error that Node version ''{0}'' is invalid' -f $InstallsVersion) {
                $Global:Error | Should Match ('Node version ''{0}'' is invalid' -f $InstallsVersion)
            }
            
            It 'should not install Node.js' {
                $nodePath | Should BeNullOrEmpty
            }
        }
        elseif( -not $PackageName )
        {
        }
        else
        {
            It 'should write no errors' {
                $Global:Error | Should BeNullOrEmpty
            }
            
            It ('should install Node.js {0}' -f $InstallsVersion) {
                 $expectedNodePath | Should Exist
            }

            It 'should return path to node' {
                $nodePath | Should Be $expectedNodePath
            }

            It ('should install NPM for Node.js {0}' -f $InstallsVersion) {
                $expectedNpmPath | Should Exist
            }

            It 'should set registry' {
                Assert-MockCalled -CommandName 'Invoke-Command' -ModuleName 'Whiskey' -ParameterFilter { $ScriptBlock.ToString() -match 'config\ --global\ set\ registry\ \$RegistryUri' }
            }

            It 'should set always-auth' {
                & $nodePath $expectedNpmPath config get -g always-auth | Should Be 'false'
            }
        }

        if( $WhenUsingDefaultInstallDirectory )
        {
            It ('should install to {0}' -f $env:APPDATA) {
                Assert-MockCalled -CommandName 'Join-Path' -ModuleName 'Whiskey' -Times 1 -ParameterFilter { $Path -eq $env:APPDATA }
            }
        }
    }
    finally
    {
        if( -not $PreserveInstall )
        {
            $emptyDir = Join-Path -Path $env:TEMP -ChildPath ([IO.Path]::GetRandomFileName())
            New-Item -Path $emptyDir -ItemType 'Directory'
            robocopy $emptyDir $installDir /MIR | Write-Verbose
            while( (Test-Path -Path $installDir) )
            {
                Start-Sleep -Milliseconds 100
                Write-Verbose ('Removing {0}' -f $installDir) 
                Remove-Item -Path $installDir -Recurse -Force
            }
        }

        if( (Test-Path -Path 'env:NVM_HOME') )
        {
            Remove-Item -Path 'env:NVM_HOME'
        }
    }
}

function ThenFails
{
    param(
        $WithError
    )

    It ('should fail') {
        $Global:Error | Should -Match $WithError
        $nodePath | Should -BeNullOrEmpty
    }
}


Describe 'Install-WhiskeyNodeJs.when run by build server and NVM isn''t installed' {
    Assert-ThatInstallNodeJs -InstallsVersion '4.4.7' -OnBuildServer -PreserveInstall
    Context 'now its installed' {
        Assert-ThatInstallNodeJs -InstallsVersion '4.4.7' -OnBuildServer
  }
}

Describe 'Install-WhiskeyNodeJs.when run on developer computer and NVM isn''t installed' {
    Assert-ThatInstallNodeJs -InstallsVersion '4.4.7' -OnDeveloperComputer -ErrorAction SilentlyContinue
}

Describe 'Install-WhiskeyNodejs.when using default installation directory' {
    Assert-ThatInstallNodeJs -InstallsVersion '4.4.7' -OnBuildServer -WhenUsingDefaultInstallDirectory
}

Describe 'Install-WhiskeyNodejs.should fail when node engine is missing' {
    Assert-ThatInstallNodeJs -InstallsVersion ''
}

Describe 'Install-WhiskeyNodejs.should fail when node version is invalid' {
    Assert-ThatInstallNodeJs -InstallsVersion 'fubarsnafu'
}

Describe 'Install-WhiskeyNodejs.should fail when node version does not exist' {
    Assert-ThatInstallNodeJs -InstallsVersion '438.4393.329' -ErrorAction SilentlyContinue
}

Describe 'Install-WhiskeyNodeJs.when package.json has no name' {
    Assert-ThatInstallNodeJs -InstallsVersion '4.4.7' -PackageName '' -ErrorAction SilentlyContinue
    ThenFails -WithError 'package name is missing'
}

if( $restoreNvmHome )
{
    Set-Item -Path 'env:NVM_HOME' -Value $nvmHome
}

