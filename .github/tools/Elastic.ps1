# Elastic Integration Tool for Panoramic Data QA Team
# This script provides functions to interact with Elasticsearch using environment variables for authentication

param(
    [string]$Action,
    [string]$Index,
    [hashtable]$Parameters = @{},
    [string]$ParametersJson
)

# Configuration
$ELASTIC_BASE_URL = "https://pdl-elastic-prod.panoramicdata.com"

# Get credentials from environment variables or prompt user
$ELASTIC_USERNAME = $env:ELASTIC_USERNAME
$ELASTIC_PASSWORD = $env:ELASTIC_PASSWORD

if (-not $ELASTIC_USERNAME) {
    Write-Host "Elastic credentials not found in environment variables." -ForegroundColor Yellow
    Write-Host "Elastic URL: $ELASTIC_BASE_URL" -ForegroundColor Cyan
    $ELASTIC_USERNAME = Read-Host "Enter your Elastic username"
    if (-not $ELASTIC_USERNAME) {
        Write-Error "Username is required to access Elastic"
        exit 1
    }
}

if (-not $ELASTIC_PASSWORD) {
    Write-Host "Enter your Elastic password (input will be hidden)" -ForegroundColor Cyan
    $securePassword = Read-Host -AsSecureString
    $ELASTIC_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    if (-not $ELASTIC_PASSWORD) {
        Write-Error "Password is required to access Elastic"
        exit 1
    }
}

# Create authentication header
$credentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${ELASTIC_USERNAME}:${ELASTIC_PASSWORD}"))
$headers = @{
    "Authorization" = "Basic $credentials"
    "Content-Type" = "application/json"
    "Accept" = "application/json"
}

# If ParametersJson is provided, convert it and merge with Parameters
if ($ParametersJson) {
    $jsonParams = $ParametersJson | ConvertFrom-Json -AsHashtable
    foreach ($key in $jsonParams.Keys) {
        $Parameters[$key] = $jsonParams[$key]
    }
}

# Helper function to make Elasticsearch API calls
function Invoke-ElasticAPI {
    param(
        [string]$Method = "GET",
        [string]$Endpoint,
        [object]$Body = $null,
        [hashtable]$QueryParams = @{}
    )
    
    $uri = "$ELASTIC_BASE_URL/$Endpoint"
    
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
            $requestParams.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
        }
        
        $response = Invoke-RestMethod @requestParams
        return $response
    }
    catch {
        Write-Error "Elasticsearch API call failed: $($_.Exception.Message)"
        Write-Error "URI: $uri"
        if ($_.Exception.Response) {
            $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Error "Response: $responseBody"
        }
        throw
    }
}

# Function to get cluster health
function Get-ElasticHealth {
    Write-Host "Checking Elasticsearch cluster health..."
    $health = Invoke-ElasticAPI -Endpoint "_cluster/health"
    
    Write-Host "Cluster Status: $($health.status)"
    Write-Host "Number of Nodes: $($health.number_of_nodes)"
    Write-Host "Active Primary Shards: $($health.active_primary_shards)"
    Write-Host "Active Shards: $($health.active_shards)"
    
    return $health
}

# Function to list indices
function Get-ElasticIndices {
    param([string]$Pattern = "*")
    
    Write-Host "Listing Elasticsearch indices matching pattern: $Pattern"
    $indices = Invoke-ElasticAPI -Endpoint "_cat/indices/$Pattern" -QueryParams @{v = "true"; format = "json"}
    return $indices
}

# Function to search documents
function Search-ElasticDocuments {
    param(
        [string]$Index,
        [hashtable]$Query,
        [int]$Size = 100,
        [int]$From = 0,
        [string[]]$Sort = @(),
        [string[]]$Fields = @()
    )
    
    Write-Host "Searching in index: $Index"
    
    $searchBody = @{
        query = $Query
        size = $Size
        from = $From
    }
    
    if ($Sort.Count -gt 0) {
        $searchBody.sort = $Sort
    }
    
    if ($Fields.Count -gt 0) {
        $searchBody._source = $Fields
    }
    
    $results = Invoke-ElasticAPI -Method "POST" -Endpoint "$Index/_search" -Body $searchBody
    
    Write-Host "Found $($results.hits.total.value) total documents"
    return $results
}

# Function to get document by ID
function Get-ElasticDocument {
    param(
        [string]$Index,
        [string]$DocumentId
    )
    
    Write-Host "Fetching document $DocumentId from index: $Index"
    $document = Invoke-ElasticAPI -Endpoint "$Index/_doc/$DocumentId"
    return $document
}

# Function to index a document
function Add-ElasticDocument {
    param(
        [string]$Index,
        [object]$Document,
        [string]$DocumentId = $null
    )
    
    if ($DocumentId) {
        Write-Host "Indexing document with ID $DocumentId in index: $Index"
        $result = Invoke-ElasticAPI -Method "PUT" -Endpoint "$Index/_doc/$DocumentId" -Body $Document
    } else {
        Write-Host "Indexing document in index: $Index"
        $result = Invoke-ElasticAPI -Method "POST" -Endpoint "$Index/_doc" -Body $Document
    }
    
    Write-Host "Document indexed with ID: $($result._id)"
    return $result
}

# Function to update a document
function Update-ElasticDocument {
    param(
        [string]$Index,
        [string]$DocumentId,
        [object]$UpdateDoc
    )
    
    Write-Host "Updating document $DocumentId in index: $Index"
    
    $updateBody = @{
        doc = $UpdateDoc
    }
    
    $result = Invoke-ElasticAPI -Method "POST" -Endpoint "$Index/_update/$DocumentId" -Body $updateBody
    Write-Host "Document updated successfully"
    return $result
}

# Function to delete a document
function Remove-ElasticDocument {
    param(
        [string]$Index,
        [string]$DocumentId
    )
    
    Write-Host "Deleting document $DocumentId from index: $Index"
    $result = Invoke-ElasticAPI -Method "DELETE" -Endpoint "$Index/_doc/$DocumentId"
    Write-Host "Document deleted successfully"
    return $result
}

# Function to search test logs
function Search-TestLogs {
    param(
        [string]$TestName = $null,
        [string]$Environment = $null,
        [string]$LogLevel = $null,
        [datetime]$StartTime = $null,
        [datetime]$EndTime = $null,
        [int]$Size = 100
    )
    
    $mustQueries = @()
    
    if ($TestName) {
        $mustQueries += @{ match = @{ "test_name" = $TestName } }
    }
    
    if ($Environment) {
        $mustQueries += @{ match = @{ "environment" = $Environment } }
    }
    
    if ($LogLevel) {
        $mustQueries += @{ match = @{ "log_level" = $LogLevel } }
    }
    
    if ($StartTime -or $EndTime) {
        $rangeQuery = @{ range = @{ "@timestamp" = @{} } }
        if ($StartTime) {
            $rangeQuery.range."@timestamp".gte = $StartTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        if ($EndTime) {
            $rangeQuery.range."@timestamp".lte = $EndTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        $mustQueries += $rangeQuery
    }
    
    $query = if ($mustQueries.Count -gt 0) {
        @{ bool = @{ must = $mustQueries } }
    } else {
        @{ match_all = @{} }
    }
    
    Write-Host "Searching test logs..."
    return Search-ElasticDocuments -Index "test-logs-*" -Query $query -Size $Size -Sort @(@{ "@timestamp" = @{ order = "desc" } })
}

# Function to get test execution statistics
function Get-TestExecutionStats {
    param(
        [string]$Environment = $null,
        [datetime]$StartTime = $null,
        [datetime]$EndTime = $null
    )
    
    $filters = @()
    
    if ($Environment) {
        $filters += @{ term = @{ "environment.keyword" = $Environment } }
    }
    
    if ($StartTime -or $EndTime) {
        $rangeFilter = @{ range = @{ "@timestamp" = @{} } }
        if ($StartTime) {
            $rangeFilter.range."@timestamp".gte = $StartTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        if ($EndTime) {
            $rangeFilter.range."@timestamp".lte = $EndTime.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        }
        $filters += $rangeFilter
    }
    
    $searchBody = @{
        size = 0
        aggs = @{
            test_results = @{
                terms = @{
                    field = "test_result.keyword"
                }
            }
            environments = @{
                terms = @{
                    field = "environment.keyword"
                }
            }
            daily_executions = @{
                date_histogram = @{
                    field = "@timestamp"
                    calendar_interval = "day"
                }
            }
        }
    }
    
    if ($filters.Count -gt 0) {
        $searchBody.query = @{
            bool = @{
                filter = $filters
            }
        }
    }
    
    Write-Host "Getting test execution statistics..."
    return Invoke-ElasticAPI -Method "POST" -Endpoint "test-executions-*/_search" -Body $searchBody
}

# Main execution logic
switch ($Action.ToLower()) {
    "health" {
        Get-ElasticHealth
    }
    "indices" {
        $pattern = if ($Parameters["Pattern"]) { $Parameters["Pattern"] } else { "*" }
        Get-ElasticIndices -Pattern $pattern
    }
    "search" {
        if (-not $Index) {
            Write-Error "Index parameter required for 'search' action"
            exit 1
        }
        $query = if ($Parameters["Query"]) { $Parameters["Query"] } else { @{ match_all = @{} } }
        $size = if ($Parameters["Size"]) { $Parameters["Size"] } else { 100 }
        $from = if ($Parameters["From"]) { $Parameters["From"] } else { 0 }
        Search-ElasticDocuments -Index $Index -Query $query -Size $size -From $from
    }
    "get" {
        if (-not $Index -or -not $Parameters["DocumentId"]) {
            Write-Error "Index and DocumentId parameters required for 'get' action"
            exit 1
        }
        Get-ElasticDocument -Index $Index -DocumentId $Parameters["DocumentId"]
    }
    "index" {
        if (-not $Index -or -not $Parameters["Document"]) {
            Write-Error "Index and Document parameters required for 'index' action"
            exit 1
        }
        Add-ElasticDocument -Index $Index -Document $Parameters["Document"] -DocumentId $Parameters["DocumentId"]
    }
    "update" {
        if (-not $Index -or -not $Parameters["DocumentId"] -or -not $Parameters["UpdateDoc"]) {
            Write-Error "Index, DocumentId, and UpdateDoc parameters required for 'update' action"
            exit 1
        }
        Update-ElasticDocument -Index $Index -DocumentId $Parameters["DocumentId"] -UpdateDoc $Parameters["UpdateDoc"]
    }
    "delete" {
        if (-not $Index -or -not $Parameters["DocumentId"]) {
            Write-Error "Index and DocumentId parameters required for 'delete' action"
            exit 1
        }
        Remove-ElasticDocument -Index $Index -DocumentId $Parameters["DocumentId"]
    }
    "testlogs" {
        $size = if ($Parameters["Size"]) { $Parameters["Size"] } else { 100 }
        Search-TestLogs -TestName $Parameters["TestName"] -Environment $Parameters["Environment"] -LogLevel $Parameters["LogLevel"] -StartTime $Parameters["StartTime"] -EndTime $Parameters["EndTime"] -Size $size
    }
    "teststats" {
        Get-TestExecutionStats -Environment $Parameters["Environment"] -StartTime $Parameters["StartTime"] -EndTime $Parameters["EndTime"]
    }
    default {
        Write-Host "Elastic Tool for Panoramic Data QA Team"
        Write-Host "Usage: .\Elastic.ps1 -Action <action> [-Index <index>] [-Parameters @{...}]"
        Write-Host ""
        Write-Host "Actions:"
        Write-Host "  health    - Check cluster health"
        Write-Host "  indices   - List indices (optional Pattern in Parameters)"
        Write-Host "  search    - Search documents (requires Index, optional Query/Size/From in Parameters)"
        Write-Host "  get       - Get document by ID (requires Index and DocumentId in Parameters)"
        Write-Host "  index     - Index a document (requires Index and Document in Parameters, optional DocumentId)"
        Write-Host "  update    - Update a document (requires Index, DocumentId, and UpdateDoc in Parameters)"
        Write-Host "  delete    - Delete a document (requires Index and DocumentId in Parameters)"
        Write-Host "  testlogs  - Search test logs (optional TestName/Environment/LogLevel/StartTime/EndTime/Size in Parameters)"
        Write-Host "  teststats - Get test execution statistics (optional Environment/StartTime/EndTime in Parameters)"
        Write-Host ""
        Write-Host "Environment Variables Required:"
        Write-Host "  ELASTIC_USERNAME - Your Elasticsearch username"
        Write-Host "  ELASTIC_PASSWORD - Your Elasticsearch password"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  .\Elastic.ps1 -Action health"
        Write-Host "  .\Elastic.ps1 -Action indices"
        Write-Host "  .\Elastic.ps1 -Action search -Index 'test-logs-*' -Parameters @{Query=@{match=@{environment='staging'}}}"
        Write-Host "  .\Elastic.ps1 -Action testlogs -Parameters @{Environment='production'; LogLevel='ERROR'}"
        Write-Host "  .\Elastic.ps1 -Action teststats -Parameters @{Environment='staging'}"
    }
}