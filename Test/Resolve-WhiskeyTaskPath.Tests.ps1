
& (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-WhiskeyTest.ps1' -Resolve)

Describe 'Resolve-WhiskeyTaskPath.when passed wildcards' {
    $context = New-WhiskeyTestContext -ForDeveloper
    'file.txt','code.cs','project.csproj','project2.csproj'  | 
        ForEach-Object { Join-Path -Path $context.BuildRoot -ChildPath $_ } |
        ForEach-Object { New-Item -Path $_ -ItemType 'File' }

    $result = '*.csproj' | Resolve-WhiskeyTaskPath -TaskContext $context -PropertyName 'fubar'

    It 'should return matched values' {
        $result[0] | Should -Be (Join-Path -Path $context.BuildRoot -ChildPath 'project.csproj')
        $result[1] | Should -Be (Join-Path -Path $context.BuildRoot -ChildPath 'project2.csproj')
    }

}
