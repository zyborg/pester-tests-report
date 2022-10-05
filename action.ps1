#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

## Make sure any modules we depend on are installed
$modulesToInstall = @(
    'Pester'
)
$modulesToInstall | ForEach-Object {
    if (-not (Get-Module -ListAvailable -All $_)) {
        Write-Host "Module [$_] not found, INSTALLING..."
        Install-Module $_ -Force
    }
}

## Import dependencies
Import-Module Pester -Force

Write-Host "Running from [$($PSScriptRoot)]"

function splitListInput { $args[0] -split ',' | % { $_.Trim() } }
function writeListInput { $args[0] | % { Write-Host "    - $_" } }


$inputs = @{
    test_results_path  = $env:INPUT_TEST_RESULTS_PATH
    full_names_filters = $env:INPUT_FULL_NAMES_FILTERS
    include_paths      = $env:INPUT_INCLUDE_PATHS
    exclude_paths      = $env:INPUT_EXCLUDE_PATHS
    include_tags       = $env:INPUT_INCLUDE_TAGS
    exclude_tags       = $env:INPUT_EXCLUDE_TAGS
    output_level       = $env:INPUT_OUTPUT_LEVEL
    report_name        = $env:INPUT_REPORT_NAME
    report_title       = $env:INPUT_REPORT_TITLE
    github_token       = $env:INPUT_GITHUB_TOKEN
    skip_check_run     = $env:INPUT_SKIP_CHECK_RUN
    gist_name          = $env:INPUT_GIST_NAME
    gist_token         = $env:INPUT_GIST_TOKEN
    gist_badge_label   = $env:INPUT_GIST_BADGE_LABEL
    gist_badge_message = $env:INPUT_GIST_BADGE_MESSAGE
    coverage_paths     = $env:INPUT_COVERAGE_PATHS
    coverage_report_name = $env:INPUT_COVERAGE_REPORT_NAME
    coverage_report_title = $env:INPUT_COVERAGE_REPORT_TITLE
    coverage_gist      = $env:INPUT_COVERAGE_GIST
    coverage_gist_badge_label = $env:INPUT_COVERAGE_GIST_BADGE_LABEL
    tests_fail_step    = $env:INPUT_TESTS_FAIL_STEP
}

$test_results_dir = Join-Path $PWD _TMP
Write-Host "Creating test results space"
if (-not (Test-Path -Path $test_results_dir -PathType Container)) {
    mkdir $test_results_dir
}

$test_results_path = $inputs.test_results_path
if ($test_results_path) {
    Write-Host "Test Results Path provided as input; skipping Pester tests"

    $result_clixml_path = $env:INPUT_RESULT_CLIXML_PATH
    if ($result_clixml_path) {
        $script:pesterResult = Import-Clixml $result_clixml_path
        Write-Host "Pester Result CLIXML provided as input; loaded"
    }
}
else {
    $full_names_filters = splitListInput $inputs.full_names_filters
    $include_paths      = splitListInput $inputs.include_paths
    $exclude_paths      = splitListInput $inputs.exclude_paths
    $include_tags       = splitListInput $inputs.include_tags
    $exclude_tags       = splitListInput $inputs.exclude_tags
    $coverage_paths     = splitListInput $inputs.coverage_paths
    $output_level       = splitListInput $inputs.output_level

    Write-Host "Running Pester tests with following:"
    Write-Host "  * realtive to PWD: $PWD"
    $pesterConfig = [PesterConfiguration]::new()

    if ($full_names_filters) {
        Write-Host "  * full_names_filters:"
        writeListInput $full_names_filters
        $pesterConfig.Filter.FullName = $full_names_filters
    }
    else { Write-Host "  * Default full_names_filters"}

    if ($include_paths) {
        Write-Host "  * include_paths:"
        writeListInput $include_paths
        $pesterConfig.Run.Path = $include_paths
    }
    else { Write-Host "  * Default include_paths"}

    if ($exclude_paths) {
        Write-Host "  * exclude_paths:"
        writeListInput $exclude_paths
        $pesterConfig.Run.ExcludePath = $exclude_paths
    }
    else { Write-Host "  * Default exclude_paths"}

    if ($include_tags) {
        Write-Host "  * include_tags:"
        writeListInput $include_tags
        $pesterConfig.Filter.Tag = $include_tags    
    }
    else { Write-Host "  * Default include_tags"}
    
    if ($exclude_tags) {
        Write-Host "  * exclude_tags:"
        writeListInput $exclude_tags
        $pesterConfig.Filter.ExcludeTag = $exclude_tags    
    }
    else { Write-Host "  * Default exclude_tags"}

    if ($output_level) {
        Write-Host "  * output_level: $output_level"
        $pesterConfig.Output.Verbosity = $output_level
    }

    if ($coverage_paths) {
        Write-Host "  * coverage_paths:"
        writeListInput $coverage_paths
        $coverageFiles = @()
        foreach ($path in $coverage_paths) {
            $coverageFiles +=  Get-ChildItem $Path -Recurse -Include @("*.ps1","*.psm1") -Exclude "*.Tests.ps1"
        }
        $pesterConfig.CodeCoverage.Enabled = $true
        $pesterConfig.CodeCoverage.Path = $coverageFiles
        $coverage_results_path = Join-Path $test_results_dir coverage.xml
        $pesterConfig.CodeCoverage.OutputPath = $coverage_results_path
    }

    if ($inputs.tests_fail_step) {
        Write-Host "  * tests_fail_step: true"
    }

    $test_results_path = Join-Path $test_results_dir test-results.nunit.xml

    ## TODO: For now, only NUnit is supported in Pester 5.x
    ##$pesterConfig.TestResult.OutputFormat = ''
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.TestResult.Enabled = $true
    $pesterConfig.TestResult.OutputPath = $test_results_path

    $error_message = ''
    $error_clixml_path = ''
    $result_clixml_path = Join-Path $test_results_dir pester-result.xml

    $script:pesterResult = Invoke-Pester -Configuration $pesterConfig -ErrorVariable $pesterError
    if ($pesterError) {
        Write-ActionWarning "Pester invocation produced error:"
        Write-ActionWarning $pesterError

        $error_message = "$pesterError"
        $error_clixml_path = Join-Path $test_results_dir pester-error.xml
        Export-Clixml -InputObject $pesterError -Path $error_clixml_path
    }
    Export-Clixml -InputObject $pesterResult -Path $result_clixml_path

    if ($error_message) {
        Write-Host "::set-output name=error_message::$error_message"
    }
    if ($error_clixml_path) {
        Write-Host "::set-output name=error_clixml_path::$error_clixml_path"
    }
    if ($inputs.tests_fail_step -and ($pesterResult.FailedCount -gt 0)) {
        $script:stepShouldFail = $true
    }

    Write-Host "::set-output name=result_clixml_path::$result_clixml_path"
    Write-Host "::set-output name=result_value::$($pesterResult.Result)"
    Write-Host "::set-output name=total_count::$($pesterResult.TotalCount)"
    Write-Host "::set-output name=passed_count::$($pesterResult.PassedCount)"
    Write-Host "::set-output name=failed_count::$($pesterResult.FailedCount)"
}

function Resolve-EscapeTokens {
    param(
        [object]$Message,
        [object]$Context,
        [switch]$UrlEncode
    )

    $m = ''
    $Message = $Message.ToString()
    $p2 = -1
    $p1 = $Message.IndexOf('%')
    while ($p1 -gt -1) {
        $m += $Message.Substring($p2 + 1, $p1 - $p2 - 1)
        $p2 = $Message.IndexOf('%', $p1 + 1)
        if ($p2 -lt 0) {
            $m += $Message.Substring($p1)
            break
        }
        $etName = $Message.Substring($p1 + 1, $p2 - $p1 - 1)
        if ($etName -eq '') {
            $etValue = '%'
        }
        else {
            $etValue = $Context.$etName
        }
        $m += $etValue
        $p1 = $Message.IndexOf('%', $p2 + 1)
    }
    $m += $Message.Substring($p2 + 1)

    if ($UrlEncode) {
        $m = [System.Web.HTTPUtility]::UrlEncode($m).Replace('+', '%20')
    }

    $m
}

function Build-MarkdownReport {
    $script:report_name = $inputs.report_name
    $script:report_title = $inputs.report_title

    if (-not $script:report_name) {
        $script:report_name = "TEST_RESULTS_$([datetime]::Now.ToString('yyyyMMdd_hhmmss'))"
    }
    if (-not $report_title) {
        $script:report_title = $report_name
    }

    $script:test_report_path = Join-Path $test_results_dir test-results.md
    & "$PSScriptRoot/nunit-report/nunitxml2md.ps1" -Verbose `
        -xmlFile $script:test_results_path `
        -mdFile $script:test_report_path -xslParams @{
            reportTitle = $script:report_title
        }
}

function Build-CoverageReport {
    Write-Host "Building human-readable code-coverage report"
    $script:coverage_report_name = $inputs.coverage_report_name
    $script:coverage_report_title = $inputs.coverage_report_title

    if (-not $script:coverage_report_name) {
        $script:coverage_report_name = "COVERAGE_RESULTS_$([datetime]::Now.ToString('yyyyMMdd_hhmmss'))"
    }
    if (-not $coverage_report_title) {
        $script:coverage_report_title = $report_name
    }

    $script:coverage_report_path = Join-Path $test_results_dir coverage-results.md
    & "$PSScriptRoot/jacoco-report/jacocoxml2md.ps1" -Verbose `
        -xmlFile $script:coverage_results_path `
        -mdFile $script:coverage_report_path -xslParams @{
            reportTitle = $script:coverage_report_title
        }

    & "$PSScriptRoot/jacoco-report/embedmissedlines.ps1" -mdFile $script:coverage_report_path
}

function Publish-ToCheckRun {
    param(
        [string]$reportData,
        [string]$reportName,
        [string]$reportTitle
    )

    Write-Host "Publishing Report to GH Workflow"

    $ghToken = $inputs.github_token
    $repoFullName = $env:GITHUB_REPOSITORY

    Write-Host "Resolving REF"
    $ref = $env:GITHUB_SHA
    if ($env:GITHUB_EVENT_NAME -eq 'pull_request') {
        Write-Host "Resolving PR REF"
        $payload = Get-Content -Raw $env:GITHUB_EVENT_PATH -Encoding utf8 | ConvertFrom-Json
        $ref = $payload.pull_request.head.sha
        if (-not $ref) {
            Write-Host "Resolving PR REF as AFTER"
            $ref = $payload.after
        }
    }
    if (-not $ref) {
        Write-ActionError "Failed to resolve REF"
        exit 1
    }
    Write-Host "Resolved REF as $ref"
    Write-Host "Resolve Repo Full Name as $repoFullName"

    Write-Host "Adding Check Run"
    $url = "https://api.github.com/repos/$repoFullName/check-runs"
    $hdr = @{
        Accept = 'application/vnd.github.antiope-preview+json'
        Authorization = "token $ghToken"
    }
    $bdy = @{
        name       = $reportName
        head_sha   = $ref
        status     = 'completed'
        conclusion = 'neutral'
        output     = @{
            title   = $reportTitle
            summary = "This run completed at ``$([datetime]::Now)``"
            text    = $reportData
        }
    }
    Invoke-WebRequest -Headers $hdr $url -Method Post -Body ($bdy | ConvertTo-Json)
}

function Publish-ToGist {
    param(
        [string]$reportData,
        [string]$coverageData
    )

    Write-Host "Publishing Report to GH Workflow"

    $reportGistName = $inputs.gist_name
    $gist_token = $inputs.gist_token
    Write-Host "Resolved Report Gist Name.....: [$reportGistName]"

    $gistsApiUrl = "https://api.github.com/gists"
    $apiHeaders = @{
        Accept        = "application/vnd.github.v3+json"
        Authorization = "token $gist_token"
    }

    ## Request all Gists for the current user
    $listGistsResp = Invoke-WebRequest -Headers $apiHeaders -Uri $gistsApiUrl

    ## Parse response content as JSON
    $listGists = $listGistsResp.Content | ConvertFrom-Json
    Write-Host "Got [$($listGists.Count)] Gists for current account"

    ## Isolate the first Gist with a file matching the expected metadata name
    $reportGist = $listGists | Where-Object { $_.files.$reportGistName } | Select-Object -First 1

    if ($reportGist) {
        Write-Host "Found the Tests Report Gist!"
        ## Debugging:
        #$reportDataRawUrl = $reportGist.files.$reportGistName.raw_url
        #Write-Host "Fetching Tests Report content from Raw Url"
        #$reportDataRawResp = Invoke-WebRequest -Headers $apiHeaders -Uri $reportDataRawUrl
        #$reportDataContent = $reportDataRawResp.Content
        #if (-not $reportData) {
        #    Write-ActionWarning "Tests Report content seems to be missing"
        #    Write-ActionWarning "[$($reportGist.files.$reportGistName)]"
        #    Write-ActionWarning "[$reportDataContent]"
        #}
        #else {
        #    Write-Information "Got existing Tests Report"
        #}
    }

    $gistFiles = @{
        $reportGistName = @{
            content = $reportData
        }
    }
    if ($inputs.gist_badge_label) {
        $gist_badge_label = $inputs.gist_badge_label
        $gist_badge_message = $inputs.gist_badge_message

        if (-not $gist_badge_message) {
            $gist_badge_message = '%Result%'
        }

        $gist_badge_label = Resolve-EscapeTokens $gist_badge_label $pesterResult -UrlEncode
        $gist_badge_message = Resolve-EscapeTokens $gist_badge_message $pesterResult -UrlEncode
        $gist_badge_color = switch ($pesterResult.Result) {
            'Passed' { 'green' }
            'Failed' { 'red' }
            default { 'yellow' }
        }
        $gist_badge_url = "https://img.shields.io/badge/$gist_badge_label-$gist_badge_message-$gist_badge_color"
        Write-Host "Computed Badge URL: $gist_badge_url"
        $gistBadgeResult = Invoke-WebRequest $gist_badge_url -ErrorVariable $gistBadgeError
        if ($gistBadgeError) {
            $gistFiles."$($reportGistName)_badge.txt" = @{ content = $gistBadgeError.Message }
        }
        else {
            $gistFiles."$($reportGistName)_badge.svg" = @{ content = $gistBadgeResult.Content }
        }
    }
    if ($coverageData) {
        $gistFiles."$([io.path]::GetFileNameWithoutExtension($reportGistName))_Coverage.md" = @{ content = $coverageData }
    }
    if ($inputs.coverage_gist_badge_label) {
        $coverage_gist_badge_label = $inputs.coverage_gist_badge_label
        $coverage_gist_badge_label = Resolve-EscapeTokens $coverage_gist_badge_label $pesterResult -UrlEncode

        $coverageXmlData = Select-Xml -Path $coverage_results_path -XPath "/report/counter[@type='LINE']"
        $coveredLines = $coverageXmlData.Node.covered
        Write-Host "Covered Lines: $coveredLines"
        $missedLines = $coverageXmlData.Node.missed
        Write-Host "Missed Lines: $missedLines"
        if ($missedLines -eq 0) {
            $coveragePercentage = 100
        } else {
            $coveragePercentage = [math]::Round(100 - (($missedLines / $coveredLines) * 100))
        }
        $coveragePercentageString = "$coveragePercentage%"

        if ($coveragePercentage -eq 100) {
            $coverage_gist_badge_color = 'brightgreen'
        } elseif ($coveragePercentage -ge 80) {
            $coverage_gist_badge_color = 'green'
        } elseif ($coveragePercentage -ge 60) {
            $coverage_gist_badge_color = 'yellowgreen'
        } elseif ($coveragePercentage -ge 40) {
            $coverage_gist_badge_color = 'yellow'
        } elseif ($coveragePercentage -ge 20) {
            $coverage_gist_badge_color = 'orange'
        } else {
            $coverage_gist_badge_color = 'red'
        }

        $coverage_gist_badge_url = "https://img.shields.io/badge/$coverage_gist_badge_label-$coveragePercentageString-$coverage_gist_badge_color"
        Write-Host "Computed Coverage Badge URL: $coverage_gist_badge_url"
        $coverageGistBadgeResult = Invoke-WebRequest $coverage_gist_badge_url -ErrorVariable $coverageGistBadgeError
        if ($coverageGistBadgeError) {
            $gistFiles."$($reportGistName)_coverage_badge.txt" = @{ content = $coverageGistBadgeError.Message }
        }
        else {
            $gistFiles."$($reportGistName)_coverage_badge.svg" = @{ content = $coverageGistBadgeResult.Content }
        }
    }

    if (-not $reportGist) {
        Write-Host "Creating initial Tests Report Gist"
        $createGistResp = Invoke-WebRequest -Headers $apiHeaders -Uri $gistsApiUrl -Method Post -Body (@{
            public = $true ## Set thit to false to make it a Secret Gist
            files = $gistFiles
        } | ConvertTo-Json)
        $createGist = $createGistResp.Content | ConvertFrom-Json
        $reportGist = $createGist
        Write-Host "Create Response: $createGistResp"
    }
    else {
        Write-Host "Updating Tests Report Gist"
        $updateGistUrl = "$gistsApiUrl/$($reportGist.id)"
        $updateGistResp = Invoke-WebRequest -Headers $apiHeaders -Uri $updateGistUrl -Method Patch -Body (@{
            files = $gistFiles
        } | ConvertTo-Json)

        Write-Host "Update Response: $updateGistResp"
    }
}

if ($test_results_path) {
    Write-Host "::set-output name=test_results_path::$test_results_path"

    Build-MarkdownReport

    $reportData = [System.IO.File]::ReadAllText($test_report_path)

    if ($coverage_results_path) {
        Write-Host "::set-output name=coverage_results_path::$coverage_results_path"

        Build-CoverageReport

        $coverageSummaryData = [System.IO.File]::ReadAllText($coverage_report_path)
    }

    if ($inputs.skip_check_run -ne $true) {
        Publish-ToCheckRun -ReportData $reportData -ReportName $report_name -ReportTitle $report_title
        if ($coverage_results_path) {
            Publish-ToCheckRun -ReportData $coverageSummaryData -ReportName $coverage_report_name -ReportTitle $coverage_report_title
        }
    }
    if ($inputs.gist_name -and $inputs.gist_token) {
        if ($inputs.coverage_gist) {
            Publish-ToGist -ReportData $reportData -CoverageData $coverageSummaryData
        } else {
            Publish-ToGist -ReportData $reportData
        }
    }
}

if ($stepShouldFail) {
    Write-Host "Thowing error as one or more tests failed and 'tests_fail_step' was true."
    throw "One or more tests failed."
}