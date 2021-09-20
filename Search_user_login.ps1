param (
    $username = "daido009"
)

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


# Get-ElasticV6Index -Node https://elasticsearch.saq.qc.ca:9200 -Credential $credELKProd -DisableSslCertificateValidation

$credELKProd = Get-Credential


$query = @"
{
  "size": 1,
  "query": {
    "bool": {
      "must": [
        {
             "multi_match": {
     "query": "$username",
     "fields": ["event_data.TargetUserName","event_data.UserName"]
   }
        },
        {
          "terms": {
            "event_id": [
              "8004",
              "4768",
              "4624",
              "4776"
            ]
          }
        }
      ]
    }
  },
  "aggs": {
    "1": {
      "top_hits": {
        "size": 1,
        "sort": [
            {
              "@timestamp" : {
                "order": "desc"
              }
            }
          ]
      }
    }
  }
}
"@

$result = Invoke-RestMethod -Method Post -Uri "https://kibana.saq.qc.ca:9200/winlogbeat-6.4.2-2019.*/_search" -Body $query -Credential $credELKProd -ContentType 'application/json'