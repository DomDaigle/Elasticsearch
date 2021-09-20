function ConvertPSObjectToHashtable
{
    param (
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process
    {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string])
        {
            $collection = @(
                foreach ($object in $InputObject) { ConvertPSObjectToHashtable $object }
            )

            Write-Output -NoEnumerate $collection
        }
        elseif ($InputObject -is [psobject])
        {
            $hash = @{}

            foreach ($property in $InputObject.PSObject.Properties)
            {
                $hash[$property.Name] = ConvertPSObjectToHashtable $property.Value
            }

            $hash
        }
        else
        {
            $InputObject
        }
    }
}

$json = @"
{
    "outer": "value1",
    "outerArray": [
        "value2",
        "value3"
    ],
    "outerHash": {
        "inner": "value4",
        "innerArray": [
            "value5",
            "value6"
        ],
        "innerHash": {
            "innermost1": "value7",
            "innermost2": "value8",
            "innermost3": "value9"
        }
    }
}
"@
$j = $json | ConvertFrom-Json
$x = $j | ConvertPSObjectToHashtable


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

### Recuperation des ROLES ELK Prod


if (!($credELKProd)) {
    $credELKProd = Get-Credential
}



# Creation de la query pour API ELK _security
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



# API Security un peu mal fait donc petit tour de passe passe .

<#
# Collect des roles ELK 
$elkquery = (Invoke-WebRequest -Method GET -Uri "https://elasticprod.saq.qc.ca:9200/_security/role" -Credential $credELKProd -ContentType 'application/json').content | ConvertFrom-Json

$ELKRoles = $elkquery.PSObject.Properties | %{if ($_.MemberType -eq "NoteProperty"){$_.name}}


foreach ($ELKRole in $ELKRoles) {
    $roleDetails = (Invoke-WebRequest -Method GET -Uri "https://elasticprod.saq.qc.ca:9200/_security/role/$ELKRole" -Credential $credELKProd -ContentType 'application/json').content | ConvertFrom-Json
    if ($roleDetails.$ELKRole.cluster) {
        $cluster = $roleDetails.$ELKRole.cluster -join ","
    }
    if ($roleDetails.$ELKRole.indices) {
        $indices = $roleDetails.$ELKRole.indices 
    }
    if ($roleDetails.$ELKRole.applications) {
        $application = $roleDetails.$ELKRole.applications
    }
    if ($roleDetails.$ELKRole.runas) {
        $runas = $roleDetails.$ELKRole.runas 
    }
    if ($roleDetails.$ELKRole.transient_metadata.enabled) {
        $enabled = $roleDetails.$ELKRole.transient_metadata.enabled
    }
}

#>

# Collect des role_mapping ELK
$elkqueryRoleMapping = (Invoke-WebRequest -Method GET -Uri "https://elasticprod.saq.qc.ca:9200/_security/role_mapping" -Credential $credELKProd -ContentType 'application/json').content | ConvertFrom-Json
$ELKRoleMapping = $elkqueryRoleMapping.PSObject.Properties | %{if ($_.MemberType -eq "NoteProperty"){$_.name}}

foreach ($RoleMapping in $ELKRoleMapping) {
    $RoleMapping
    #$RoleMappingDetails = (Invoke-WebRequest -Method GET -Uri "https://elasticprod.saq.qc.ca:9200/_security/role_mapping/$RoleMapping" -Credential $credELKProd -ContentType 'application/json').content | ConvertFrom-Json
    $RoleMappingDetails = (Invoke-WebRequest -Method GET -Uri "https://elasticprod.saq.qc.ca:9200/_security/role_mapping/$RoleMapping" -Credential $credELKProd -ContentType 'application/json').content
    $Json_result = ConvertPSObjectToHashtable $RoleMappingDetails
    $temp = $RoleMappingDetails.$RoleMapping.rules.PSObject.Properties | select -ExpandProperty value
    $temp
    $temp= @()
    #$RoleMappingDetails.$RoleMapping.rules

}

### Recuperation des infos groupe AD pour ELK


########### REM TEMPO
<#
$groupELK = Get-ADGroup -Filter * -SearchBase "OU=ELK,OU=Groupes,DC=saq,DC=qc,DC=ca" -Properties description

foreach ($group in $groupELK) {
    
    $members = Get-ADGroupMember -Identity $group.name 

    foreach ($member in $members) {
        $properties = @{
            group = $group.name
            Description = $group.description 
            member = $member.name
            memberDN = $member.distinguishedName
            objectClass = $member.objectClass

        }
        
        $obj =  New-Object -TypeName psobject -Property $properties
        $elkRoles += $obj

    }

}
#>