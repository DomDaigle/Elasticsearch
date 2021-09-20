$query = @"
{
    "query": {
        "bool" : {
          "filter" : [
            {
              "range" : {
                "@timestamp" : {
                    "lte": "now-90d/d"
                }
              }
            },
            {
              "exists": {
                "field": "@timestamp"
              }
            }
          ]
        }
    }
}
"@

$result_webrequest = Invoke-WebRequest -Method Post -Uri "https://slqelk0315.saq.qc.ca:9200/filebeat-7.12.0-2021.04.21-000003/_delete_by_query?wait_for_completion=false" -Body $query -Credential $credELKProd -ContentType 'application/json'
#$tasks = ((Invoke-WebRequest -Method Get -Uri "https://slqelk0315.saq.qc.ca:9200/_tasks?detailed=true&actions=*/delete/byquery" -Credential $credELKProd -ContentType 'application/json').content | ConvertFrom-Json)

do
{
  $tasks = ((Invoke-WebRequest -Method Get -Uri "https://slqelk0315.saq.qc.ca:9200/_tasks?detailed=true&actions=*/delete/byquery" -Credential $credELKProd -ContentType 'application/json').content | ConvertFrom-Json)
  $tasks.nodes
  sleep -Seconds 10
} Until ($tasks.nodes)


<#
while (!($tasks.nodes -match "")) {
    sleep -Seconds 10
    $tasks = ((Invoke-WebRequest -Method Get -Uri "https://slqelk0315.saq.qc.ca:9200/_tasks?detailed=true&actions=*/delete/byquery" -Credential $credELKProd -ContentType 'application/json').content | ConvertFrom-Json)
    write-host "loop"
}
#>
Invoke-WebRequest -Method Post -Uri "https://slqelk0315.saq.qc.ca:9200/filebeat-7.12.0-2021.04.21-000003/_forcemerge?max_num_segments=1" -Credential $credELKProd -ContentType 'application/json'

