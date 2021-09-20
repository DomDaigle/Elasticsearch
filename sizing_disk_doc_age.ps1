param (
    $global:server = "slpelk0675.saq.qc.ca",
    [bool]$takeAction = $true,
    [bool]$removeDoc = $true,
    [bool]$removeIndex = $false
 )

function deleteIndex {
    param (
        $index
    )

    Invoke-WebRequest -Method Delete -Uri "https://$($server):9200/$index" -Credential $credELKProd 

}

function deleteDocsByQuery {
    param(
        $index,
        $query
    )

    #Invoke-WebRequest -Method Post -Uri "https://$($server):9200/$index/_delete_by_query?wait_for_completion=false" -Body $query -Credential $credELKProd -ContentType 'application/json'
    
    $result_webrequest = Invoke-WebRequest -Method Post -Uri "https://$($server):9200/$index/_delete_by_query?wait_for_completion=false" -Body $query -Credential $credELKProd -ContentType 'application/json'
    do
    {
      $tasks = ((Invoke-WebRequest -Method Get -Uri "https://$($server):9200/_tasks?detailed=true&actions=*/delete/byquery" -Credential $credELKProd -ContentType 'application/json').content | ConvertFrom-Json)
      Write-Debug ('$tasks.nodes: ' + $($tasks.nodes))
      sleep -Seconds 10
    } Until (!($tasks.nodes -match "^@{.*}?"))

    Invoke-WebRequest -Method Post -Uri "https://$($server):9200/$index/_forcemerge?max_num_segments=1" -Credential $credELKProd -ContentType 'application/json'

}

function deletedocumentsByAge
{
    param (
        $indices,
        [int]$nbday,
        [string]$condition,
        $query90jours,
        $queryLastDoc
    )
    
    function isforDeletion {
        param (
            $indice,
            $queryLastDoc
        )
        $retour = ""
        Write-Verbose -Message "FONCTION isforDeletion: Query elastic pour trouver le dernier document de l'index $($indice.index)"
        $retour = try {$chklastdoc = Invoke-RestMethod -Method Post -Uri "https://$($server):9200/$($indice.index)/_search" -Body $queryLastDoc -Credential $credELKProd -ContentType 'application/json'} catch {"NO_TIMESTAMP"}
        If (!($retour -eq "NO_TIMESTAMP") -and $chklastdoc.hits.total.value){
            Write-Verbose -Message "FONCTION isforDeletion: Initialistion date du jour et 90 jours plus tôt"
            $90daysAgo = ((get-date).AddDays(-90)).Date
            write-debug ('$90daysAgo: ' + $90daysAgo)
            $indexDate = (get-date $chklastdoc.hits.hits._source.'@timestamp').Date
            write-debug ('$indexDate: ' + $indexDate)

            if ($indexDate -le $90daysAgo) {
                 Write-Verbose -Message "FONCTION isforDeletion: dernier document de l'index $($indice.index) est plus vieux que 90 jours"
                 
                $retour = "DELETE_INDEX"
            }
            else {
                $retour = "continue" 
            }

        }
        write-debug ('$retour: ' + $retour)
        $retour
        
    }

    $date = Get-Date -Format FileDateTime
    $NO_TIMESTAMP_INDEX = @()
    foreach ($indice in $indices){
      $actionTook = ""
      [int]$doc_todelete = ""
      $catch_result = ""
      if ($indice.'docs.count' -gt 0) {
        $avg_size_byDoc= $indice.'store.size'/ $indice.'docs.count'
      }
      if (!($indice.index -match "^\..*")){
        Write-Verbose -Message "FONCTION getdocumentsByAge: Appel fonction isforDeletion pour validation date dernier document"
        # Appel fonction validation date dernier document 
        write-debug ('$indice.index: ' + $indice.index)
        $result_isforDeletion = isforDeletion $indice $queryLastDoc
        #if (!($result_isforDeletion -eq "OK")) {
            # retourne VRAI si le dernier document plus vieux que 90 jours
            if ($result_isforDeletion -eq "DELETE_INDEX") {
                $actionNeeded = "DELETE_INDEX"
                $size_saving = $indice.'store.size'
                Write-Verbose -Message "FONCTION getdocumentsByAge: DELETE de l'index $($indice.index), dernier document plus vieux que 90 jours"
                Write-Debug "DELETE_INDEX $($indice.index)"
                if ($takeAction -and $removeIndex ) {
                    deleteIndex $($indice.index)
                    $actionTook = "DELETED_INDEX"
                }
                else {
                        $actionTook = "NOTHING"
                    }
        } 
            elseif ($result_isforDeletion -eq "continue") {
            Write-Verbose -Message "FONCTION getdocumentsByAge: Query de tous les documents plus vieux de 90jours"
            $catch_result = try {$documents = Invoke-RestMethod -Method Post -Uri "https://$($server):9200/$($indice.index)/_search?scroll=1m" -Body $query90jours -Credential $credELKProd -ContentType 'application/json'} catch {$($indice.index)}
            if ($indice.'docs.count' -eq $documents.hits.total.value) {
                $doc_todelete = $documents.hits.total.value
                Write-Debug -Message "FONCTION getdocumentsByAge: DELETE de l'index $($indice.index), car tous les documents sont plus vieux de 90 jours"
                Write-Debug "DELETE_INDEX $($indice.index)"
            } 
            elseif ($documents.hits.total.value -gt 0) {
                    $size_saving = $documents.hits.total.value * $avg_size_byDoc                   
                    $actionNeeded = "DELETE_DOCS"
                    $doc_todelete = $documents.hits.total.value
                    Write-Debug -Message "APPEL FONCTION deleteDocs: $($indice.index)"
                    Write-Debug -Message "DELETE_DOC:  $($documents.hits.total.value) DOCUMENTS de l'index $($indice.index)"
                    if ($takeAction -and $removeDoc){

                        deleteDocsByQuery $($indice.index) $query90jours
                        $actionTook = "DELETED_DOCS"
                    }
                    else {
                        $actionTook = "NOTHING"
                    }
                    
                
            }

          }
            elseif ($result_isforDeletion -eq "NO_TIMESTAMP") {
            $actionNeeded = "no_timestamp"
            $NO_TIMESTAMP_INDEX += $($indice.index)
          }
        #}
      }
      $properties = [ordered]@{
               index = $indice.index
               total_size = $indice.'store.size'
               total_docs = $indice.'docs.count'
               doc_toDelete = $doc_todelete
               sizesaving = $size_saving/ 1GB
               sizesavingNonConvert = $size_saving
               action_needed = $actionNeeded
               action_took = $actionTook               
            }
      $obj = New-Object -TypeName PSObject -Property $properties
      $obj | Export-Csv -Path ./elk_actions_sizing_$server-$takeAction-$date.csv -Append -NoTypeInformation
      #$final_result += $obj
      $properties.Clear()
      Clear-Variable actionNeeded, size_saving, doc_todelete, catch_result
      $indice = ""
    }



}

$DebugPreference = "continue"

$global:final_result = @()
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

Write-Verbose -Message "INITIALISATION Query Elastic: Donne le dernier document d'un index"
$queryLastdocLTE90days = @"
{
    "size": 1, 
    "sort": { "@timestamp": "desc"},
    "query": {
     "match_all": {}
  }
}
"@

Write-Verbose -Message "INITIALISATION Query Elastic: Donne tous les documents plus vieux que 60 jours d'un index "
$queryLTE90days = @"
{
    "query": {
        "bool" : {
          "filter" : [
            {
              "range" : {
                "@timestamp" : {
                    "lte": "now-60d/d"
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

Write-Verbose -Message "Execution query qui retourne tous les indices du cluster"
$all_QUA_indices = Invoke-WebRequest -Method Get -Uri "https://$($server):9200/_cat/indices?format=JSON&bytes=b" -Credential $credELKProd -ContentType 'application/json'

Write-Verbose -Message "Parse le résultat et converti en JSON"
$json_all_QUA_indices = $all_QUA_indices.Content | ConvertFrom-Json

Write-Verbose -Message "Appel de la fonction getdocumentsByAge"
$result_age = deletedocumentsByAge $json_all_QUA_indices 90 lte $queryLTE90days $queryLastdocLTE90days


$DebugPreference = "SilentlyContinue"