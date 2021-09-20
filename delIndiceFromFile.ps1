param (
    $server = "slpelk0675.saq.qc.ca"
)

function deleteIndex {
    param (
        $index
    )

    Invoke-WebRequest -Method Delete -Uri "https://$($server):9200/$index" -Credential $credELKProd 
}

Write-Debug -Message ""
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


if (!($credELKProd)) {
    Write-Debug -Message "Demande D'authentification"
    $credELKProd = Get-Credential
}


$indices = Get-Content -Path "C:\Admin\Elasticsearch\index_to_delete.txt"

foreach ($indice in $indices) {
    deleteIndex $indice
}