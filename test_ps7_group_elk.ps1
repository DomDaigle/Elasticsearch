if (!($credELKProd))
{
    $credELKProd = Get-Credential
}

$RoleMappingDetails = ConvertFrom-Json (Invoke-WebRequest -Method GET -Uri "https://elasticprod.saq.qc.ca:9200/_security/role_mapping/$RoleMapping" -Credential $credELKProd -ContentType 'application/json')

