#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

## Make sure any modules we depend on are installed
$modulesToInstall = @(
    'GitHubActions'
    'Pester'
)
$modulesToInstall | ForEach-Object {
    if (-not (Get-Module -ListAvailable -All $_)) {
        Write-Output "Module [$_] not found, INSTALLING..."
        Install-Module $_ -Force
    }
}

## Import dependencies
Import-Module GitHubActions -Force
Import-Module Pester -Force

Write-ActionInfo "Running from [$($PSScriptRoot)]"

function splitListInput { $args[0] -split ',' | % { $_.Trim() } }
function writeListInput { $args[0] | % { Write-ActionInfo "    - $_" } }


$inputs = @{
    test_results_path  = Get-ActionInput test_results_path
    full_names_filters = Get-ActionInput full_names_filters
    include_paths      = Get-ActionInput include_paths
    exclude_paths      = Get-ActionInput exclude_paths
    include_tags       = Get-ActionInput include_tags
    exclude_tags       = Get-ActionInput exclude_tags
    output_level       = Get-ActionInput output_level
    report_name        = Get-ActionInput report_name
    report_title       = Get-ActionInput report_title
    github_token       = Get-ActionInput github_token -Required
    skip_check_run     = Get-ActionInput skip_check_run
    gist_name          = Get-ActionInput gist_name
    gist_token         = Get-ActionInput gist_token
    gist_badge_label   = Get-ActionInput gist_badge_label
    gist_badge_message = Get-ActionInput gist_badge_message
    coverage_paths     = Get-ActionInput coverage_paths
    coverage_report_name = Get-ActionInput coverage_report_name
    coverage_report_title = Get-ActionInput coverage_report_title
    coverage_gist      = Get-ActionInput coverage_gist
    coverage_gist_badge = Get-ActionInput coverage_gist_badge
    tests_fail_step    = Get-ActionInput tests_fail_step
}

$test_results_dir = Join-Path $PWD _TMP
Write-ActionInfo "Creating test results space"
if (-not (Test-Path -Path $test_results_dir -PathType Container)) {
    mkdir $test_results_dir
}

$test_results_path = $inputs.test_results_path
if ($test_results_path) {
    Write-ActionInfo "Test Results Path provided as input; skipping Pester tests"

    $result_clixml_path = Get-ActionInput result_clixml_path
    if ($result_clixml_path) {
        $script:pesterResult = Import-Clixml $result_clixml_path
        Write-ActionInfo "Pester Result CLIXML provided as input; loaded"
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

    Write-ActionInfo "Running Pester tests with following:"
    Write-ActionInfo "  * realtive to PWD: $PWD"
    $pesterConfig = [PesterConfiguration]::new()

    if ($full_names_filters) {
        Write-ActionInfo "  * full_names_filters:"
        writeListInput $full_names_filters
        $pesterConfig.Filter.FullName = $full_names_filters
    }
    else { Write-ActionInfo "  * Default full_names_filters"}

    if ($include_paths) {
        Write-ActionInfo "  * include_paths:"
        writeListInput $include_paths
        $pesterConfig.Run.Path = $include_paths
    }
    else { Write-ActionInfo "  * Default include_paths"}

    if ($exclude_paths) {
        Write-ActionInfo "  * exclude_paths:"
        writeListInput $exclude_paths
        $pesterConfig.Run.ExcludePath = $exclude_paths
    }
    else { Write-ActionInfo "  * Default exclude_paths"}

    if ($include_tags) {
        Write-ActionInfo "  * include_tags:"
        writeListInput $include_tags
        $pesterConfig.Filter.Tag = $include_tags    
    }
    else { Write-ActionInfo "  * Default include_tags"}
    
    if ($exclude_tags) {
        Write-ActionInfo "  * exclude_tags:"
        writeListInput $exclude_tags
        $pesterConfig.Filter.ExcludeTag = $exclude_tags    
    }
    else { Write-ActionInfo "  * Default exclude_tags"}

    if ($output_level) {
        Write-ActionInfo "  * output_level: $output_level"
        $pesterConfig.Output.Verbosity = $output_level
    }

    if ($coverage_paths) {
        Write-ActionInfo "  * coverage_paths:"
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
        Write-ActionInfo "  * tests_fail_step: true"
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
        Set-ActionOutput -Name error_message -Value $error_message
    }
    if ($error_clixml_path) {
        Set-ActionOutput -Name error_clixml_path -Value $error_clixml_path
    }
    if ($inputs.tests_fail_step -and ($pesterResult.FailedCount -gt 0)) {
        $script:stepShouldFail = $true
    }

    Set-ActionOutput -Name result_clixml_path -Value $result_clixml_path
    Set-ActionOutput -Name result_value -Value ($pesterResult.Result)
    Set-ActionOutput -Name total_count -Value ($pesterResult.TotalCount)
    Set-ActionOutput -Name passed_count -Value ($pesterResult.PassedCount)
    Set-ActionOutput -Name failed_count -Value ($pesterResult.FailedCount)
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
    Write-ActionInfo "Building human-readable code-coverage report"
    $script:coverage_report_name = $inputs.coverage_report_name
    $script:coverage_report_title = $inputs.coverage_report_title

    if (-not $script:coverage_report_name) {
        $script:coverage_report_name = "COVERAGE_RESULTS_$([datetime]::Now.ToString('yyyyMMdd_hhmmss'))"
    }
    if (-not $coverage_report_title) {
        $script:coverage_report_title = $report_name
    }

    $script:coverage_summary_path = Join-Path $test_results_dir Summary.txt
    $script:coverage_badge_path = Join-Path $test_results_dir badge_shieldsio_linecoverage_lightgrey.svg
    dotnet tool install -g dotnet-reportgenerator-globaltool
    $sourceDirs = ""
    foreach ($path in $coverage_paths) {
        if ($sourceDirs) {
            $sourceDirs += ";"
        }
        $sourceDirs += Split-Path $path
    }
    reportgenerator -reports:"$script:coverage_results_path" -targetdir:"$test_results_dir" -reporttypes:"Badges;TextSummary" -title:"$coverage_report_title" -sourcedirs:"$SourceDirs"
}

function Publish-ToCheckRun {
    param(
        [string]$reportData,
        [string]$reportName,
        [string]$reportTitle
    )

    Write-ActionInfo "Publishing Report to GH Workflow"

    $ghToken = $inputs.github_token
    $ctx = Get-ActionContext
    $repo = Get-ActionRepo
    $repoFullName = "$($repo.Owner)/$($repo.Repo)"

    Write-ActionInfo "Resolving REF"
    $ref = $ctx.Sha
    if ($ctx.EventName -eq 'pull_request') {
        Write-ActionInfo "Resolving PR REF"
        $ref = $ctx.Payload.pull_request.head.sha
        if (-not $ref) {
            Write-ActionInfo "Resolving PR REF as AFTER"
            $ref = $ctx.Payload.after
        }
    }
    if (-not $ref) {
        Write-ActionError "Failed to resolve REF"
        exit 1
    }
    Write-ActionInfo "Resolved REF as $ref"
    Write-ActionInfo "Resolve Repo Full Name as $repoFullName"

    Write-ActionInfo "Adding Check Run"
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

    Write-ActionInfo "Publishing Report to GH Workflow"

    $reportGistName = $inputs.gist_name
    $gist_token = $inputs.gist_token
    Write-ActionInfo "Resolved Report Gist Name.....: [$reportGistName]"

    $gistsApiUrl = "https://api.github.com/gists"
    $apiHeaders = @{
        Accept        = "application/vnd.github.v3+json"
        Authorization = "token $gist_token"
    }

    ## Request all Gists for the current user
    $listGistsResp = Invoke-WebRequest -Headers $apiHeaders -Uri $gistsApiUrl

    ## Parse response content as JSON
    $listGists = $listGistsResp.Content | ConvertFrom-Json -AsHashtable
    Write-ActionInfo "Got [$($listGists.Count)] Gists for current account"

    ## Isolate the first Gist with a file matching the expected metadata name
    $reportGist = $listGists | Where-Object { $_.files.$reportGistName } | Select-Object -First 1

    if ($reportGist) {
        Write-ActionInfo "Found the Tests Report Gist!"
        ## Debugging:
        #$reportDataRawUrl = $reportGist.files.$reportGistName.raw_url
        #Write-ActionInfo "Fetching Tests Report content from Raw Url"
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
        Write-ActionInfo "Computed Badge URL: $gist_badge_url"
        $gistBadgeResult = Invoke-WebRequest $gist_badge_url -ErrorVariable $gistBadgeError
        if ($gistBadgeError) {
            $gistFiles."$($reportGistName)_badge.txt" = @{ content = $gistBadgeError.Message }
        }
        else {
            $gistFiles."$($reportGistName)_badge.svg" = @{ content = $gistBadgeResult.Content }
        }
    }
    if ($coverageData) {
        $gistFiles."$([io.path]::GetFileNameWithoutExtension($reportGistName))_Coverage.html" = @{ content = $coverageData }
    }
    if ($inputs.coverage_gist_badge) {
        $coverageBadgeData = [System.IO.File]::ReadAllText($coverage_badge_path)
        $gistFiles."$([io.path]::GetFileNameWithoutExtension($reportGistName))_Coverage_badge.svg" = @{ content = $coverageBadgeData }
    }

    if (-not $reportGist) {
        Write-ActionInfo "Creating initial Tests Report Gist"
        $createGistResp = Invoke-WebRequest -Headers $apiHeaders -Uri $gistsApiUrl -Method Post -Body (@{
            public = $true ## Set thit to false to make it a Secret Gist
            files = $gistFiles
        } | ConvertTo-Json)
        $createGist = $createGistResp.Content | ConvertFrom-Json -AsHashtable
        $reportGist = $createGist
        Write-ActionInfo "Create Response: $createGistResp"
    }
    else {
        Write-ActionInfo "Updating Tests Report Gist"
        $updateGistUrl = "$gistsApiUrl/$($reportGist.id)"
        $updateGistResp = Invoke-WebRequest -Headers $apiHeaders -Uri $updateGistUrl -Method Patch -Body (@{
            files = $gistFiles
        } | ConvertTo-Json)

        Write-ActionInfo "Update Response: $updateGistResp"
    }
}

if ($test_results_path) {
    Set-ActionOutput -Name test_results_path -Value $test_results_path

    Build-MarkdownReport

    $reportData = [System.IO.File]::ReadAllText($test_report_path)

    if ($coverage_results_path) {
        Set-ActionOutput -Name coverage_results_path -Value $coverage_results_path

        Build-CoverageReport

        $coverageSummaryData = [System.IO.File]::ReadAllText($coverage_summary_path)
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
    Write-ActionInfo "Thowing error as ne or more tests failed and 'tests_fail_step' was true."
    throw "One or more tests failed."
}