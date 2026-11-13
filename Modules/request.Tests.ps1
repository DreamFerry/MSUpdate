# Requires -Modules Pester
Import-Module Pester

BeforeAll {
    Import-Module "$PSScriptRoot/request.psm1"
}

AfterAll {
    Remove-Module request
}

Describe "Request-Update" {
    Context "When Category is w11-26h2" {
        It "Should return version in format number.number" {
            $result = Request-Update -Category "w11-26h2"
            $result | Should -Match '^26300\.\d+$'
        }
    }

    Context "When Category is w10-22h2" {
        It "Should return version in format number.number" {
            $result = Request-Update -Category "w10-22h2"
            $result | Should -Match '^19045\.\d+$'
        }
    }
}

Describe "Get-UUPFiles" {
    Context "When Id is provided" {
        It "Should return non-null hashtable" {
            $result = Get-UUPFiles -Id "8c10c883-071c-43c3-bff8-8ed82fba2436"
            $result | Should -Not -Be $null
            $result | Should -BeOfType 'System.Collections.Hashtable'
            $result.Keys | Should -Contain "Microsoft-Windows-WirelessDisplay-FOD-Package-x86.cab"
        }
    }
}

Describe "Get-UUPFile" {
    Context "When Id and FileName are provided" {
        It "Should return file details" {
            $fileName = "Microsoft-Windows-WirelessDisplay-FOD-Package-x86.cab"
            $result = Get-UUPFile -Id "8c10c883-071c-43c3-bff8-8ed82fba2436" -FileName $fileName
            $result | Should -Not -Be $null
            $result | Should -BeOfType 'PSCustomObject'
            $result.url | Should -Match '^https?://'
            $result.size | Should -BeGreaterThan 0
            $result.sha1 | Should -Match '^[a-fA-F0-9]{40}$'
        }
        It "Should hit the cache on second call" {
            $fileName = "Microsoft-Windows-WirelessDisplay-FOD-Package-x86.cab"
            $null = Get-UUPFile -Id "8c10c883-071c-43c3-bff8-8ed82fba2436" -FileName $fileName
            $result = Get-UUPFile -Id "8c10c883-071c-43c3-bff8-8ed82fba2436" -FileName $fileName
            $result | Should -Not -Be $null
            $result | Should -BeOfType 'PSCustomObject'
        }
    }
}
