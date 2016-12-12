
Describe 'FailingTests Two #1' {
    It 'should fail' {
        $true | Should Be $false
    }
}

Describe 'FailingTests Two #2' {
    It 'should fail, too' {
        $true | Should Be $false
    }
}