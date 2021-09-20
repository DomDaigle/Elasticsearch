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

$final_result = @()

if (!($credELKProd)) {
    $credELKProd = Get-Credential
}

$size = 10000

$queryLTE90days = @"
{
    "query": {
    "range": {
      "@timestamp": {
        "lte": "now-90d/d"
      }
    }
  }
}
"@

$queryNbDoc = @"
{
  "size": 0,
  "aggs" : {
    "size_per_day" : {
        "date_histogram" : {
            "field" : "@timestamp",
            "interval" : "day"
        }
    }
  }
}
"@

$match_all = @"
{ 
   "query": {
      "match_all": {}
      }
}
"@


$div = $null



#$all_indices = Invoke-WebRequest -Method Get -Uri "https://slpelk0675.saq.qc.ca:9200/_cat/indices?format=JSON&bytes=b" -Credential $credELKProd -ContentType 'application/json'
$all_QUA_indices = Invoke-WebRequest -Method Get -Uri "https://slqelk0315.saq.qc.ca:9200/_cat/indices?format=JSON&bytes=b" -Credential $credELKProd -ContentType 'application/json'
$json_all_QUA_indices = $all_QUA_indices.Content | ConvertFrom-Json
#$json_all_indices = $all_indices.Content | ConvertFrom-Json
$result_age = getdocumentsByAge $all_QUA_indices 90 lte $queryLTE90days

foreach ($indice in $json_all_indices) {
    
    #[int]$docs_count = $indice.'docs.count'
    if ($indice.'docs.count' -gt 0) {
        $avg_size_byDoc= $indice.'store.size'/ $indice.'docs.count'
        
        $indiceNbDoc = Invoke-RestMethod -Method POST -Uri "https://elasticprod.saq.qc.ca:9200/$($indice.index)/_search" -Body $queryNbDoc -Credential $credELKProd -ContentType 'application/json'
        #$result = Invoke-RestMethod -Method POST -Uri "https://elasticprod.saq.qc.ca:9200/filebeat-7.10.2-2021.04.23-000002/_search" -Body $match_all -Credential $credELKProd -ContentType 'application/json'
        #$result.hits.hits | ConvertTo-Json -Depth 50 -Compress| Out-File c:\temp\extract_elk.json
        $json_indiceNbDoc = $indiceNbDoc.aggregations.size_per_day.buckets
        foreach ($day in $json_indiceNbDoc) {
            $avg_size_byDay = ($day.doc_count * $avg_size_byDoc) 
            if ($avg_size_byDay -ge 1073741824) {
                $unit = "GB"
            } elseif (($avg_size_byDay -lt 1073741824) -and ($avg_size_byDay -ge 1048576 ) ) {
                $unit = "MB"
              } else {
                $unit = "KB"
              }
            $properties = @{
               index = $indice.index
               total_size = $indice.'store.size'
               total_docs = $indice.'docs.count'
               date =  $day.key_as_string
               doc_byDay = $day.doc_count
               #size_byDay = $avg_size_byDay / "1$unit"
               size_byDay = $avg_size_byDay / 1GB
               sizeByDayNonConvert = $avg_size_byDay
               unit = $unit
               
            }

            $obj = New-Object -TypeName psobject -Property $properties
            $final_result += $obj
        }
    }

}

function getdocumentsByAge
{
    param (
        [string]$indices,
        [int]$nbday,
        [string]$condition,
        $query
    )

    foreach ($indice in $indices){
        $documents = Invoke-RestMethod -Method POST -Uri "https://elasticprod.saq.qc.ca:9200/$($indice.index)/_search" -Body $query -Credential $credELKProd -ContentType 'application/json'
    }



}
