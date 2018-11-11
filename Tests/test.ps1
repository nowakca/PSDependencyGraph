function test1 {
    test2
    test4
}

function test2 {
    test3
}

function test3 {
    function test3_1 {
        test3_2
    }
    function test3_2 {
    }
    test3_1
    test3_2
}

function test4 {
    test3
}


Import-Module ../PSDependencyGraph -Force
show-PSScriptCallGraph ./test.ps1

<#
caller  called
------  ------
test1   test2, test4
test2   test3
test3   test3_1, test3_2
test3_1 test3_2
test3_2 
test4   test3

Yeah, I'll do something with pester at some point, but for now I just needed to get something going
#>
