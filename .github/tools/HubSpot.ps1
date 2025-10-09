# HubSpot Integration Tool for Panoramic Data Sales Team
# This script provides functions to interact with HubSpot using environment variables for authentication

param(
    [string]$Action,
    [string]$ObjectType,
    [hashtable]$Parameters = @{}
)

# Configuration
$HUBSPOT_BASE_URL = "https://api.hubapi.com"

# Get credentials from environment variables or prompt user
$HUBSPOT_ACCESS_TOKEN = $env:HUBSPOT_PERSONAL_ACCESS_TOKEN

if (-not $HUBSPOT_ACCESS_TOKEN) {
    Write-Host "HubSpot credentials not found in environment variables." -ForegroundColor Yellow
    Write-Host "HubSpot API URL: $HUBSPOT_BASE_URL" -ForegroundColor Cyan
    Write-Host "Please set the HUBSPOT_PERSONAL_ACCESS_TOKEN environment variable with your Personal Access Token" -ForegroundColor Yellow
    $HUBSPOT_ACCESS_TOKEN = Read-Host "Enter your HubSpot Personal Access Token" -AsSecureString
    $HUBSPOT_ACCESS_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($HUBSPOT_ACCESS_TOKEN))
    if (-not $HUBSPOT_ACCESS_TOKEN) {
        Write-Error "Personal Access Token is required to access HubSpot"
        exit 1
    }
}

# Create authentication header
$headers = @{
    "Authorization" = "Bearer $HUBSPOT_ACCESS_TOKEN"
    "Content-Type" = "application/json"
    "Accept" = "application/json"
}

# Helper function to make HubSpot API calls
function Invoke-HubSpotAPI {
    param(
        [string]$Method = "GET",
        [string]$Endpoint,
        [object]$Body = $null,
        [hashtable]$QueryParams = @{}
    )
    
    $uri = "$HUBSPOT_BASE_URL/$Endpoint"
    
    # Add query parameters if provided
    if ($QueryParams.Count -gt 0) {
        $queryString = ($QueryParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&"
        $uri += "?$queryString"
    }
    
    try {
        $requestParams = @{
            Uri = $uri
            Method = $Method
            Headers = $headers
        }
        
        if ($Body) {
            $requestParams.Body = ($Body | ConvertTo-Json -Depth 10)
        }
        
        $response = Invoke-RestMethod @requestParams
        return $response
    }
    catch {
        Write-Error "HubSpot API call failed: $($_.Exception.Message)"
        Write-Error "URI: $uri"
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            Write-Error "Status Code: $statusCode"
        }
        throw
    }
}

# Function to get contact details
function Get-HubSpotContact {
    param(
        [string]$ContactId,
        [string]$Email,
        [string[]]$Properties = @("email", "firstname", "lastname", "company", "phone", "lifecyclestage")
    )
    
    if ($ContactId) {
        Write-Host "Fetching HubSpot contact by ID: $ContactId"
        $endpoint = "crm/v3/objects/contacts/$ContactId"
        $queryParams = @{
            "properties" = ($Properties -join ",")
        }
        return Invoke-HubSpotAPI -Endpoint $endpoint -QueryParams $queryParams
    }
    elseif ($Email) {
        Write-Host "Fetching HubSpot contact by email: $Email"
        $endpoint = "crm/v3/objects/contacts/$Email"
        $queryParams = @{
            "idProperty" = "email"
            "properties" = ($Properties -join ",")
        }
        return Invoke-HubSpotAPI -Endpoint $endpoint -QueryParams $queryParams
    }
    else {
        Write-Error "Either ContactId or Email must be provided"
        return $null
    }
}

# Function to search contacts
function Search-HubSpotContacts {
    param(
        [string]$Query,
        [string[]]$Properties = @("email", "firstname", "lastname", "company", "phone", "lifecyclestage"),
        [int]$Limit = 100
    )
    
    Write-Host "Searching HubSpot contacts with query: $Query"
    
    $endpoint = "crm/v3/objects/contacts/search"
    $body = @{
        "query" = $Query
        "limit" = $Limit
        "properties" = $Properties
    }
    
    return Invoke-HubSpotAPI -Method "POST" -Endpoint $endpoint -Body $body
}

# Function to get company details
function Get-HubSpotCompany {
    param(
        [string]$CompanyId,
        [string]$Domain,
        [string[]]$Properties = @("name", "domain", "industry", "city", "state", "country", "numberofemployees")
    )
    
    if ($CompanyId) {
        Write-Host "Fetching HubSpot company by ID: $CompanyId"
        $endpoint = "crm/v3/objects/companies/$CompanyId"
        $queryParams = @{
            "properties" = ($Properties -join ",")
        }
        return Invoke-HubSpotAPI -Endpoint $endpoint -QueryParams $queryParams
    }
    elseif ($Domain) {
        Write-Host "Fetching HubSpot company by domain: $Domain"
        $endpoint = "crm/v3/objects/companies/$Domain"
        $queryParams = @{
            "idProperty" = "domain"
            "properties" = ($Properties -join ",")
        }
        return Invoke-HubSpotAPI -Endpoint $endpoint -QueryParams $queryParams
    }
    else {
        Write-Error "Either CompanyId or Domain must be provided"
        return $null
    }
}

# Function to search companies
function Search-HubSpotCompanies {
    param(
        [string]$Query,
        [string[]]$Properties = @("name", "domain", "industry", "city", "state", "country", "numberofemployees"),
        [int]$Limit = 100
    )
    
    Write-Host "Searching HubSpot companies with query: $Query"
    
    $endpoint = "crm/v3/objects/companies/search"
    $body = @{
        "query" = $Query
        "limit" = $Limit
        "properties" = $Properties
    }
    
    return Invoke-HubSpotAPI -Method "POST" -Endpoint $endpoint -Body $body
}

# Function to get deal details
function Get-HubSpotDeal {
    param(
        [string]$DealId,
        [string[]]$Properties = @("dealname", "amount", "dealstage", "pipeline", "closedate", "createdate")
    )
    
    Write-Host "Fetching HubSpot deal: $DealId"
    $endpoint = "crm/v3/objects/deals/$DealId"
    $queryParams = @{
        "properties" = ($Properties -join ",")
    }
    
    return Invoke-HubSpotAPI -Endpoint $endpoint -QueryParams $queryParams
}

# Function to search deals
function Search-HubSpotDeals {
    param(
        [string]$Query,
        [string[]]$Properties = @("dealname", "amount", "dealstage", "pipeline", "closedate", "createdate"),
        [int]$Limit = 100
    )
    
    Write-Host "Searching HubSpot deals with query: $Query"
    
    $endpoint = "crm/v3/objects/deals/search"
    $body = @{
        "query" = $Query
        "limit" = $Limit
        "properties" = $Properties
    }
    
    return Invoke-HubSpotAPI -Method "POST" -Endpoint $endpoint -Body $body
}

# Function to create a contact
function New-HubSpotContact {
    param(
        [hashtable]$Properties
    )
    
    Write-Host "Creating new HubSpot contact"
    $endpoint = "crm/v3/objects/contacts"
    $body = @{
        "properties" = $Properties
    }
    
    return Invoke-HubSpotAPI -Method "POST" -Endpoint $endpoint -Body $body
}

# Function to update a contact
function Update-HubSpotContact {
    param(
        [string]$ContactId,
        [hashtable]$Properties
    )
    
    Write-Host "Updating HubSpot contact: $ContactId"
    $endpoint = "crm/v3/objects/contacts/$ContactId"
    $body = @{
        "properties" = $Properties
    }
    
    return Invoke-HubSpotAPI -Method "PATCH" -Endpoint $endpoint -Body $body
}

# Function to get recent contacts
function Get-HubSpotRecentContacts {
    param(
        [int]$Limit = 100,
        [string[]]$Properties = @("email", "firstname", "lastname", "company", "phone", "lifecyclestage", "createdate")
    )
    
    Write-Host "Fetching recent HubSpot contacts (limit: $Limit)"
    $endpoint = "crm/v3/objects/contacts"
    $queryParams = @{
        "limit" = $Limit
        "properties" = ($Properties -join ",")
        "sorts" = "createdate"
    }
    
    return Invoke-HubSpotAPI -Endpoint $endpoint -QueryParams $queryParams
}

# Function to get pipelines
function Get-HubSpotPipelines {
    param(
        [string]$ObjectType = "deals"
    )
    
    Write-Host "Fetching HubSpot pipelines for object type: $ObjectType"
    $endpoint = "crm/v3/pipelines/$ObjectType"
    
    return Invoke-HubSpotAPI -Endpoint $endpoint
}

# Function to get all properties for an object type
function Get-HubSpotProperties {
    param(
        [string]$ObjectType = "contacts"
    )
    
    Write-Host "Fetching HubSpot properties for object type: $ObjectType"
    $endpoint = "crm/v3/properties/$ObjectType"
    
    return Invoke-HubSpotAPI -Endpoint $endpoint
}

# Main script logic based on Action parameter
switch ($Action.ToLower()) {
    "get" {
        if ($ObjectType) {
            switch ($ObjectType.ToLower()) {
                "contact" {
                    if ($Parameters.ContainsKey("Id")) {
                        Get-HubSpotContact -ContactId $Parameters.Id
                    }
                    elseif ($Parameters.ContainsKey("Email")) {
                        Get-HubSpotContact -Email $Parameters.Email
                    }
                    else {
                        Write-Error "For contact retrieval, provide either 'Id' or 'Email' parameter"
                    }
                }
                "company" {
                    if ($Parameters.ContainsKey("Id")) {
                        Get-HubSpotCompany -CompanyId $Parameters.Id
                    }
                    elseif ($Parameters.ContainsKey("Domain")) {
                        Get-HubSpotCompany -Domain $Parameters.Domain
                    }
                    else {
                        Write-Error "For company retrieval, provide either 'Id' or 'Domain' parameter"
                    }
                }
                "deal" {
                    if ($Parameters.ContainsKey("Id")) {
                        Get-HubSpotDeal -DealId $Parameters.Id
                    }
                    else {
                        Write-Error "For deal retrieval, provide 'Id' parameter"
                    }
                }
                "pipelines" {
                    $objectType = if ($Parameters.ContainsKey("Type")) { $Parameters.Type } else { "deals" }
                    Get-HubSpotPipelines -ObjectType $objectType
                }
                "properties" {
                    $objectType = if ($Parameters.ContainsKey("Type")) { $Parameters.Type } else { "contacts" }
                    Get-HubSpotProperties -ObjectType $objectType
                }
                default {
                    Write-Error "Unsupported object type: $ObjectType. Supported types: contact, company, deal, pipelines, properties"
                }
            }
        }
        else {
            Write-Error "ObjectType parameter is required for 'get' action"
        }
    }
    
    "search" {
        if ($ObjectType -and $Parameters.ContainsKey("Query")) {
            switch ($ObjectType.ToLower()) {
                "contacts" {
                    $limit = if ($Parameters.ContainsKey("Limit")) { $Parameters.Limit } else { 100 }
                    Search-HubSpotContacts -Query $Parameters.Query -Limit $limit
                }
                "companies" {
                    $limit = if ($Parameters.ContainsKey("Limit")) { $Parameters.Limit } else { 100 }
                    Search-HubSpotCompanies -Query $Parameters.Query -Limit $limit
                }
                "deals" {
                    $limit = if ($Parameters.ContainsKey("Limit")) { $Parameters.Limit } else { 100 }
                    Search-HubSpotDeals -Query $Parameters.Query -Limit $limit
                }
                default {
                    Write-Error "Unsupported object type for search: $ObjectType. Supported types: contacts, companies, deals"
                }
            }
        }
        else {
            Write-Error "ObjectType and Query parameters are required for 'search' action"
        }
    }
    
    "recent" {
        if ($ObjectType) {
            switch ($ObjectType.ToLower()) {
                "contacts" {
                    $limit = if ($Parameters.ContainsKey("Limit")) { $Parameters.Limit } else { 100 }
                    Get-HubSpotRecentContacts -Limit $limit
                }
                default {
                    Write-Error "Recent listings only supported for contacts currently"
                }
            }
        }
        else {
            Write-Error "ObjectType parameter is required for 'recent' action"
        }
    }
    
    "create" {
        if ($ObjectType) {
            switch ($ObjectType.ToLower()) {
                "contact" {
                    if ($Parameters.ContainsKey("Properties")) {
                        New-HubSpotContact -Properties $Parameters.Properties
                    }
                    else {
                        Write-Error "Properties parameter is required for creating a contact"
                    }
                }
                default {
                    Write-Error "Create action currently only supports contacts"
                }
            }
        }
        else {
            Write-Error "ObjectType parameter is required for 'create' action"
        }
    }
    
    "update" {
        if ($ObjectType) {
            switch ($ObjectType.ToLower()) {
                "contact" {
                    if ($Parameters.ContainsKey("Id") -and $Parameters.ContainsKey("Properties")) {
                        Update-HubSpotContact -ContactId $Parameters.Id -Properties $Parameters.Properties
                    }
                    else {
                        Write-Error "Id and Properties parameters are required for updating a contact"
                    }
                }
                default {
                    Write-Error "Update action currently only supports contacts"
                }
            }
        }
        else {
            Write-Error "ObjectType parameter is required for 'update' action"
        }
    }
    
    "test" {
        Write-Host "Testing HubSpot API connection..." -ForegroundColor Cyan
        try {
            $testResult = Invoke-HubSpotAPI -Endpoint "crm/v3/objects/contacts" -QueryParams @{"limit" = "1"}
            Write-Host "✓ HubSpot API connection successful!" -ForegroundColor Green
            Write-Host "Total contacts available: $($testResult.total)" -ForegroundColor Cyan
            return $testResult
        }
        catch {
            Write-Host "✗ HubSpot API connection failed!" -ForegroundColor Red
            Write-Error $_.Exception.Message
        }
    }
    
    default {
        Write-Host @"
HubSpot Integration Tool for Panoramic Data Sales Team
Usage: .\HubSpot.ps1 -Action <action> -ObjectType <type> -Parameters @{key=value}

Environment Variables Required:
  HUBSPOT_PERSONAL_ACCESS_TOKEN - Your HubSpot Personal Access Token

Available Actions:
  test                          - Test HubSpot API connection
  get                          - Get specific object by ID/email/domain
  search                       - Search for objects using query
  recent                       - Get recent objects
  create                       - Create new objects
  update                       - Update existing objects

Object Types:
  contact, company, deal, pipelines, properties

Examples:
  .\HubSpot.ps1 -Action test
  .\HubSpot.ps1 -Action get -ObjectType contact -Parameters @{Email="user@example.com"}
  .\HubSpot.ps1 -Action get -ObjectType company -Parameters @{Domain="example.com"}
  .\HubSpot.ps1 -Action search -ObjectType contacts -Parameters @{Query="sales"}
  .\HubSpot.ps1 -Action recent -ObjectType contacts -Parameters @{Limit=50}
  .\HubSpot.ps1 -Action get -ObjectType pipelines -Parameters @{Type="deals"}
  .\HubSpot.ps1 -Action create -ObjectType contact -Parameters @{Properties=@{email="new@example.com"; firstname="John"; lastname="Doe"}}

For detailed help on a specific action, use Get-Help .\HubSpot.ps1 -Detailed
"@
    }
}