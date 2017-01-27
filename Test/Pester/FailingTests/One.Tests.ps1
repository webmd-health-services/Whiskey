
Describe 'FailingTests One #1' {
    It 'should fail' {
        $true | Should Be $false
    }
}

Describe 'FailingTests One #2' {
    It 'should fail, too' {
        $true | Should Be $false
    }
}