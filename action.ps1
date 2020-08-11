#!/usr/bin/env pwsh

$ErrorActionPreference = 'Stop'

## Make sure any modules we depend on are installed
$modulesToInstall = @(
    'GitHubActions'
    'Pester'
)
$modulesToInstall | ForEach-Object {
    if (-not (Get-Module -ListAvailable $_)) {
        Write-Output "Module [$_] not found, INSTALLING..."
        Install-Module $_ -Force
    }
}

## Import dependencies
Import-Module GitHubActions -Force
Import-Module Pester -Force


function splitListInput { $args[0] -split ',' | % { $_.Trim() } }
function writeListInput { $args[0] | % { Write-ActionInfo "    - $_" } }


$inputs = @{
    test_results_path = Get-ActionInput test_results_path
    include_paths     = Get-ActionInput include_paths
    exclude_paths     = Get-ActionInput exclude_paths
    include_tags      = Get-ActionInput include_tags
    exclude_tags      = Get-ActionInput exclude_tags
    output_level      = Get-ActionInput output_level
    report_name       = Get-ActionInput report_name
    report_title      = Get-ActionInput report_title
}

$test_results_dir = Join-Path $PWD _TMP
$test_results_path = $inputs.test_results_path
if ($test_results_path) {
    Write-ActionInfo "Test Results Path provided as input; skipping Pester tests"
}
else {
    $include_paths = splitListInput $inputs.include_paths
    $exclude_paths = splitListInput $inputs.exclude_paths
    $include_tags  = splitListInput $inputs.include_tags
    $exclude_tags  = splitListInput $inputs.exclude_tags

    Write-ActionInfo "Running Pester tests with following:"
    Write-ActionInfo "  * realtive to PWD: $PWD"
    $pesterConfig = [PesterConfiguration]::new()

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

    if ($inputs.output_level) {
        Write-ActionInfo "  * output_level: $output_level"
        $pesterConfig.Output.Verbosity = $output_level
    }

    Write-ActionInfo "Creating test results space"
    $test_results_path = Join-Path $test_results_dir test-results.nunit.xml
    if (-not (Test-Path -Path $test_results_dir -PathType Container)) {
        mkdir $test_results_dir
    }

    ## TODO: For now, only NUnit is supported in Pester 5.x
    ##$pesterConfig.TestResult.OutputFormat = ''
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.TestResult.Enabled = $true
    $pesterConfig.TestResult.OutputPath = $test_results_path

    $error_message = ''
    $error_clixml_path = ''
    $result_clixml_path = Join-Path $test_results_dir pester-result.xml

    $pesterResult = Invoke-Pester -Configuration $pesterConfig -ErrorVariable $pesterError
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

    Set-ActionOutput -Name result_clixml_path -Value $result_clixml_path
    Set-ActionOutput -Name result_value -Value ($pesterResult.Result)
    Set-ActionOutput -Name total_count -Value ($pesterResult.TotalCount)
    Set-ActionOutput -Name passed_count -Value ($pesterResult.PassedCount)
    Set-ActionOutput -Name failed_count -Value ($pesterResult.FailedCount)
}

if ($test_results_path) {
    Set-ActionOutput -Name test_results_path -Value $test_results_path

    $report_name = $inputs.report_name
    $report_title = $inputs.report_title

    if (-not $report_name) {
        $report_name = "TEST_RESULTS_$([datetime]::Now.ToString('yyyyMMdd_hhmmss'))"
    }
    if (-not $report_title) {
        $report_title = $report_name
    }

    $test_report_path = Join-Path $test_results_dir test-results.md
    ./nunit-report/nunitxml2md.ps1 -Verbose -xmlFile $test_results_path -mdFile $test_report_path

    $reportData = [System.IO.File]::ReadAllText($test_report_path)

    Write-ActionInfo "Publishing Report to GH Workflow"
    $ghToken = Get-ActionInput -Name github_token -Required
    $ctx = Get-ActionContext
    $repo = Get-ActionRepo
    $repoFullName = "$($repo.Owner)/$($repo.Name)"

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
        name       = $report_name
        head_sha   = $ref
        status     = 'completed'
        conclusion = 'neutral'
        output     = @{
            title   = $report_title
            summary = "This run completed at ``${[datetime]::Now}``"
            text    = $reportData
        }
    }
    Invoke-WebRequest -Headers $hdr $url -Method Post -Body ($bdy | ConvertTo-Json)
}
