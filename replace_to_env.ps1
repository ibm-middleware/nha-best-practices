# ============================================================
# Replace sanitized example.com placeholders with company values
# ============================================================
# Usage: Run from the root folder that contains
#        NativeHA_MQ_Management/ and nativeha_templates/
#
#   cd C:\path\to\your\repo
#   .\replace_to_company.ps1
#
# Step 1: Fill in YOUR company values below
# Step 2: Run the script
# Step 3: Review changes with: git diff
# ============================================================

# ---- FILL IN YOUR COMPANY VALUES HERE ----

$CompanyDomain          = "yourcompany.com"
$BitbucketHost          = "bitbucket.yourcompany.com"
$BitbucketProjectKey    = "YOURPROJECT"
$OcpCluster1Api         = "api.ocp-east-001.yourcompany.com"
$OcpCluster1Apps        = "apps.ocp-east-001.yourcompany.com"
$OcpCluster2Api         = "api.ocp-west-001.yourcompany.com"
$OcpCluster2Apps        = "apps.ocp-west-001.yourcompany.com"
$VenafiUrl              = "pki.yourcompany.com"
$VaultUrl               = "vault.yourcompany.com:8200"
$SmtpHost               = "smtp-relay.yourcompany.com"
$SmtpRelayHost          = "smtp-relay.yourcompany.com"
$AutomationEmail        = "mq-automation@yourcompany.com"
$CertAutomationEmail    = "mq-cert-automation@yourcompany.com"
$AdminEmail             = "your-team-dl@yourcompany.com"
$CaCertFilename         = "yourcompany-ca.crt"
$LicenseNonprod         = "L-XXXX-XXXXXX"
$LicenseProd            = "L-YYYY-YYYYYY"
$ContainerRegistry      = "registry.yourcompany.com"

# Environment names (change if your company uses different names)
$Env1Name               = "QA1"
$Env2Name               = "QA2"
$Env3Name               = "QA3"
$Env1Code               = "Q1"
$Env2Code               = "Q2"
$Env3Code               = "Q3"

# OCP region names (change if your company uses different names)
$Region1                = "cluster1"
$Region2                = "cluster2"

# ---- END OF COMPANY VALUES ----

# Build replacement map (order matters - longer/more specific patterns first)
$replacements = [ordered]@{
    # OCP cluster URLs (specific first)
    "api.ocp-cluster1.example.com"      = $OcpCluster1Api
    "apps.ocp-cluster1.example.com"     = $OcpCluster1Apps
    "api.ocp-cluster2.example.com"      = $OcpCluster2Api
    "apps.ocp-cluster2.example.com"     = $OcpCluster2Apps

    # Service URLs
    "pki.example.com"                   = $VenafiUrl
    "vault.example.com:8200"            = $VaultUrl
    "smtp.example.com"                  = $SmtpHost
    "smtp-relay.example.com"            = $SmtpRelayHost
    "registry.example.com"              = $ContainerRegistry
    "nativeha.example.com"              = "nativeha.$CompanyDomain"
    "aap.example.com"                   = "aap.$CompanyDomain"

    # Bitbucket (specific first)
    "api.bitbucket.example.com/2.0"     = "$BitbucketHost/rest/api/latest"
    "git@bitbucket.example.com:MQPROJECT" = "git@${BitbucketHost}:${BitbucketProjectKey}"
    "bitbucket.example.com"             = $BitbucketHost

    # Emails
    "mq-cert-automation@example.com"    = $CertAutomationEmail
    "mq-automation@example.com"         = $AutomationEmail
    "admin@example.com"                 = $AdminEmail

    # CA cert filename
    "company-ca.crt"                    = $CaCertFilename

    # License IDs
    "L-XXXX-XXXXXX"                     = $LicenseNonprod
    "L-YYYY-YYYYYY"                     = $LicenseProd

    # Domain (must be last - catches remaining example.com refs)
    "example.com"                       = $CompanyDomain
}

# Only if you changed environment names from QA1/QA2/QA3
# Uncomment and set if your environments differ
# $envReplacements = [ordered]@{
#     "QA1"  = $Env1Name
#     "QA2"  = $Env2Name
#     "QA3"  = $Env3Name
#     "qa1"  = $Env1Name.ToLower()
#     "qa2"  = $Env2Name.ToLower()
#     "qa3"  = $Env3Name.ToLower()
#     '"Q1"' = "`"$Env1Code`""
#     '"Q2"' = "`"$Env2Code`""
#     '"Q3"' = "`"$Env3Code`""
# }

# Only if you changed region names from cluster1/cluster2
# Uncomment and set if your regions differ
# $regionReplacements = [ordered]@{
#     "cluster1"  = $Region1
#     "cluster2"  = $Region2
#     "CLUSTER1"  = $Region1.ToUpper()
#     "CLUSTER2"  = $Region2.ToUpper()
# }

# ---- SCRIPT LOGIC (do not modify below) ----

$extensions = @("*.yaml", "*.yml", "*.j2", "*.py", "*.md", "*.txt", "*.cfg", "*.sh")
$searchDirs = @("NativeHA_MQ_Management", "nativeha_templates")

$totalFiles = 0
$totalReplacements = 0

foreach ($dir in $searchDirs) {
    if (-not (Test-Path $dir)) {
        Write-Host "WARNING: Directory '$dir' not found. Skipping." -ForegroundColor Yellow
        continue
    }

    foreach ($ext in $extensions) {
        $files = Get-ChildItem -Path $dir -Filter $ext -Recurse -File -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            $original = $content
            $fileChanged = $false

            foreach ($key in $replacements.Keys) {
                if ($content.Contains($key)) {
                    $content = $content.Replace($key, $replacements[$key])
                    $fileChanged = $true
                }
            }

            # Uncomment if using env replacements
            # if ($envReplacements) {
            #     foreach ($key in $envReplacements.Keys) {
            #         if ($content.Contains($key)) {
            #             $content = $content.Replace($key, $envReplacements[$key])
            #             $fileChanged = $true
            #         }
            #     }
            # }

            # Uncomment if using region replacements
            # if ($regionReplacements) {
            #     foreach ($key in $regionReplacements.Keys) {
            #         if ($content.Contains($key)) {
            #             $content = $content.Replace($key, $regionReplacements[$key])
            #             $fileChanged = $true
            #         }
            #     }
            # }

            if ($fileChanged) {
                Set-Content -Path $file.FullName -Value $content -NoNewline -Encoding UTF8
                $totalFiles++
                Write-Host "  Updated: $($file.FullName)" -ForegroundColor Green
            }
        }
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Replacement complete" -ForegroundColor Cyan
Write-Host "  Files updated: $totalFiles" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Review changes:  git diff" -ForegroundColor Yellow
Write-Host "  2. Commit:          git add -A && git commit -m 'Configure for company environment'" -ForegroundColor Yellow
Write-Host "  3. Push:            git push origin main" -ForegroundColor Yellow
