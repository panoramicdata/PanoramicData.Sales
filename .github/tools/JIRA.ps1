# JIRA Integration Tool for Panoramic Data QA Team
# This script provides functions to interact with JIRA using environment variables for authentication

param(
    [string]$Action,
    [string]$IssueKey,
    [hashtable]$Parameters = @{},
    [string]$ParametersJson
)

# Configuration
$JIRA_BASE_URL = "https://jira.panoramicdata.com"
$API_VERSION = "2"
$JIRA_API_URL = "$JIRA_BASE_URL/rest/api/$API_VERSION"

# Get credentials from environment variables or prompt user
$JIRA_USERNAME = $env:JIRA_USERNAME
$JIRA_PASSWORD = $env:JIRA_PASSWORD

if (-not $JIRA_USERNAME) {
    Write-Host "JIRA credentials not found in environment variables." -ForegroundColor Yellow
    Write-Host "JIRA URL: $JIRA_BASE_URL" -ForegroundColor Cyan
    $JIRA_USERNAME = Read-Host "Enter your JIRA username"
    if (-not $JIRA_USERNAME) {
        Write-Error "Username is required to access JIRA"
        exit 1
    }
}

if (-not $JIRA_PASSWORD) {
    Write-Host "Enter your JIRA password or API token (input will be hidden)" -ForegroundColor Cyan
    $securePassword = Read-Host -AsSecureString
    $JIRA_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    if (-not $JIRA_PASSWORD) {
        Write-Error "Password/API token is required to access JIRA"
        exit 1
    }
}

# Create authentication header
$credentials = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${JIRA_USERNAME}:${JIRA_PASSWORD}"))
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

# Helper function to make JIRA API calls
function Invoke-JiraAPI {
    param(
        [string]$Method = "GET",
        [string]$Endpoint,
        [object]$Body = $null
    )
    
    $uri = "$JIRA_API_URL/$Endpoint"
    
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
        Write-Error "JIRA API call failed: $($_.Exception.Message)"
        Write-Error "URI: $uri"
        throw
    }
}

# Function to get issue details
function Get-JiraIssue {
    param(
        [string]$IssueKey,
        [switch]$IncludeComments,
        [switch]$IncludeHistory,
        [switch]$IncludeAll
    )
    
    Write-Host "Fetching JIRA issue: $IssueKey"
    
    # Build expand parameter based on what's requested
    $expandItems = @()
    if ($IncludeComments -or $IncludeAll) {
        $expandItems += "comments"
    }
    if ($IncludeHistory -or $IncludeAll) {
        $expandItems += "changelog"
    }
    
    $endpoint = "issue/$IssueKey"
    if ($expandItems.Count -gt 0) {
        $expandParam = $expandItems -join ","
        $endpoint += "?expand=$expandParam"
    }
    
    $issue = Invoke-JiraAPI -Endpoint $endpoint
    
    # If including comments or history, also get additional details
    if ($IncludeComments -or $IncludeAll) {
        Write-Host "Including comments for issue: $IssueKey"
    }
    if ($IncludeHistory -or $IncludeAll) {
        Write-Host "Including state transition history for issue: $IssueKey"
    }
    
    return $issue
}

# Function to get all comments for an issue
function Get-JiraIssueComments {
    param([string]$IssueKey)
    
    Write-Host "Fetching comments for JIRA issue: $IssueKey"
    $comments = Invoke-JiraAPI -Endpoint "issue/$IssueKey/comment"
    return $comments
}

# Function to get issue change history (including state transitions)
function Get-JiraIssueHistory {
    param([string]$IssueKey)
    
    Write-Host "Fetching change history for JIRA issue: $IssueKey"
    $changelog = Invoke-JiraAPI -Endpoint "issue/$IssueKey/changelog"
    return $changelog
}

# Function to get detailed issue information with comments and history
function Get-JiraIssueDetailed {
    param([string]$IssueKey)
    
    Write-Host "Fetching detailed information for JIRA issue: $IssueKey"
    
    # Get issue with all expanded information
    $issue = Get-JiraIssue -IssueKey $IssueKey -IncludeAll
    
    # Create a comprehensive result object
    $detailedResult = @{
        Issue = $issue
        Comments = $issue.fields.comment.comments
        StatusTransitions = @()
        AllChanges = $issue.changelog.histories
    }
    
    # Extract status transitions from the changelog
    if ($issue.changelog -and $issue.changelog.histories) {
        foreach ($history in $issue.changelog.histories) {
            foreach ($item in $history.items) {
                if ($item.field -eq "status") {
                    $transition = @{
                        Date = $history.created
                        Author = $history.author.displayName
                        FromStatus = $item.fromString
                        ToStatus = $item.toString
                        Comment = $history.items | Where-Object { $_.field -eq "comment" } | Select-Object -First 1 -ExpandProperty toString
                    }
                    $detailedResult.StatusTransitions += $transition
                }
            }
        }
    }
    
    return $detailedResult
}

# Function to search issues
function Search-JiraIssues {
    param(
        [string]$JQL,
        [int]$MaxResults = 50,
        [int]$StartAt = 0
    )
    
    Write-Host "Searching JIRA issues with JQL: $JQL"
    $searchBody = @{
        jql = $JQL
        maxResults = $MaxResults
        startAt = $StartAt
        fields = @("summary", "status", "assignee", "priority", "created", "updated")
    }
    
    $results = Invoke-JiraAPI -Method "POST" -Endpoint "search" -Body $searchBody
    return $results
}

# Function to create issue
function New-JiraIssue {
    param(
        [string]$ProjectKey,
        [string]$IssueType,
        [string]$Summary,
        [string]$Description,
        [string]$Assignee = $null
    )
    
    Write-Host "Creating new JIRA issue in project: $ProjectKey"
    
    $issueBody = @{
        fields = @{
            project = @{ key = $ProjectKey }
            issuetype = @{ name = $IssueType }
            summary = $Summary
            description = $Description
        }
    }
    
    if ($Assignee) {
        $issueBody.fields.assignee = @{ name = $Assignee }
    }
    
    $newIssue = Invoke-JiraAPI -Method "POST" -Endpoint "issue" -Body $issueBody
    Write-Host "Created issue: $($newIssue.key)"
    return $newIssue
}

# Function to update issue
function Update-JiraIssue {
    param(
        [string]$IssueKey,
        [hashtable]$Fields
    )
    
    Write-Host "Updating JIRA issue: $IssueKey"
    
    $updateBody = @{
        fields = $Fields
    }
    
    Invoke-JiraAPI -Method "PUT" -Endpoint "issue/$IssueKey" -Body $updateBody
    Write-Host "Updated issue: $IssueKey"
}

# Function to add comment
function Add-JiraComment {
    param(
        [string]$IssueKey,
        [string]$Comment
    )
    
    Write-Host "Adding comment to JIRA issue: $IssueKey"
    
    $commentBody = @{
        body = $Comment
    }
    
    $result = Invoke-JiraAPI -Method "POST" -Endpoint "issue/$IssueKey/comment" -Body $commentBody
    Write-Host "Added comment to issue: $IssueKey"
    return $result
}

# Function to transition issue
function Set-JiraIssueStatus {
    param(
        [string]$IssueKey,
        [string]$TransitionName
    )
    
    Write-Host "Transitioning JIRA issue $IssueKey to: $TransitionName"
    
    # Get available transitions
    $transitions = Invoke-JiraAPI -Endpoint "issue/$IssueKey/transitions"
    $transition = $transitions.transitions | Where-Object { $_.name -eq $TransitionName }
    
    if (-not $transition) {
        Write-Error "Transition '$TransitionName' not found for issue $IssueKey"
        Write-Host "Available transitions:"
        $transitions.transitions | ForEach-Object { Write-Host "  - $($_.name)" }
        return
    }
    
    $transitionBody = @{
        transition = @{ id = $transition.id }
    }
    
    Invoke-JiraAPI -Method "POST" -Endpoint "issue/$IssueKey/transitions" -Body $transitionBody
    Write-Host "Transitioned issue $IssueKey to: $TransitionName"
}

# Function to get QA team issues
function Get-QATeamIssues {
    param(
        [string]$TeamMember = $null,
        [string]$Status = $null
    )
    
    $jql = "project = MS"
    
    if ($TeamMember) {
        $jql += " AND assignee = $TeamMember"
    } else {
        $jql += " AND assignee in (claire.campbell, sam.walters)"
    }
    
    if ($Status) {
        $jql += " AND status = '$Status'"
    }
    
    $jql += " ORDER BY priority DESC, created DESC"
    
    return Search-JiraIssues -JQL $jql
}

# Main execution logic
switch ($Action.ToLower()) {
    "get" {
        if (-not $IssueKey) {
            Write-Error "IssueKey parameter required for 'get' action"
            exit 1
        }
        Get-JiraIssue -IssueKey $IssueKey
    }
    "search" {
        $jql = $Parameters["JQL"]
        if (-not $jql) {
            Write-Error "JQL parameter required for 'search' action"
            exit 1
        }
        $maxResults = if ($Parameters["MaxResults"]) { $Parameters["MaxResults"] } else { 50 }
        Search-JiraIssues -JQL $jql -MaxResults $maxResults
    }
    "create" {
        New-JiraIssue -ProjectKey $Parameters["ProjectKey"] -IssueType $Parameters["IssueType"] -Summary $Parameters["Summary"] -Description $Parameters["Description"] -Assignee $Parameters["Assignee"]
    }
    "update" {
        if (-not $IssueKey) {
            Write-Error "IssueKey parameter required for 'update' action"
            exit 1
        }
        Update-JiraIssue -IssueKey $IssueKey -Fields $Parameters["Fields"]
    }
    "comment" {
        if (-not $IssueKey) {
            Write-Error "IssueKey parameter required for 'comment' action"
            exit 1
        }
        Add-JiraComment -IssueKey $IssueKey -Comment $Parameters["Comment"]
    }
    "transition" {
        if (-not $IssueKey) {
            Write-Error "IssueKey parameter required for 'transition' action"
            exit 1
        }
        Set-JiraIssueStatus -IssueKey $IssueKey -TransitionName $Parameters["TransitionName"]
    }
    "recent" {
        # Get recent tickets created by current user
        $days = if ($Parameters["Days"]) { $Parameters["Days"] } else { 7 }
        $username = if ($Parameters["Username"]) { $Parameters["Username"] } else { "david.bond" }
        
        Write-Host "Getting tickets created by $username in the last $days days..." -ForegroundColor Cyan
        $jql = "reporter = $username AND created >= -${days}d ORDER BY created DESC"
        $searchResult = Search-JiraIssues -JQL $jql
        
        if ($searchResult.issues -and $searchResult.issues.Count -gt 0) {
            Write-Host "`nFound $($searchResult.total) recent tickets:" -ForegroundColor Green
            
            $searchResult.issues | ForEach-Object {
                # Handle JIRA date format properly
                $createdDate = $_.fields.created
                if ($createdDate -match '(\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2})') {
                    $created = $matches[1]
                } else {
                    $created = $createdDate
                }
                
                [PSCustomObject]@{
                    Key = $_.key
                    Summary = $_.fields.summary
                    Status = $_.fields.status.name
                    Priority = $_.fields.priority.name
                    Created = $created
                    Assignee = if($_.fields.assignee) { $_.fields.assignee.displayName } else { "Unassigned" }
                }
            } | Format-Table -AutoSize
        } else {
            Write-Host "No tickets found in the last $days days" -ForegroundColor Yellow
        }
    }
    "team" {
        Get-QATeamIssues -TeamMember $Parameters["TeamMember"] -Status $Parameters["Status"]
    }
    "comments" {
        if (-not $IssueKey) {
            Write-Error "IssueKey parameter required for 'comments' action"
            exit 1
        }
        Get-JiraIssueComments -IssueKey $IssueKey
    }
    "history" {
        if (-not $IssueKey) {
            Write-Error "IssueKey parameter required for 'history' action"
            exit 1
        }
        Get-JiraIssueHistory -IssueKey $IssueKey
    }
    "detailed" {
        if (-not $IssueKey) {
            Write-Error "IssueKey parameter required for 'detailed' action"
            exit 1
        }
        Get-JiraIssueDetailed -IssueKey $IssueKey
    }
    "getfull" {
        if (-not $IssueKey) {
            Write-Error "IssueKey parameter required for 'getfull' action"
            exit 1
        }
        Get-JiraIssue -IssueKey $IssueKey -IncludeAll
    }
    default {
        Write-Host "JIRA Tool for Panoramic Data QA Team"
        Write-Host "Usage: .\JIRA.ps1 -Action <action> [-IssueKey <key>] [-Parameters @{...}]"
        Write-Host ""
        Write-Host "Actions:"
        Write-Host "  get       - Get issue details (requires IssueKey)"
        Write-Host "  getfull   - Get issue with comments and history (requires IssueKey)"
        Write-Host "  detailed  - Get comprehensive issue info with formatted comments and transitions (requires IssueKey)"
        Write-Host "  comments  - Get all comments for an issue (requires IssueKey)"
        Write-Host "  history   - Get change history/transitions for an issue (requires IssueKey)"
        Write-Host "  search    - Search issues (requires JQL in Parameters)"
        Write-Host "  recent    - Get recent tickets by user (optional Days and Username in Parameters)"
        Write-Host "  create    - Create new issue (requires ProjectKey, IssueType, Summary, Description in Parameters)"
        Write-Host "  update    - Update issue (requires IssueKey and Fields in Parameters)"
        Write-Host "  comment   - Add comment (requires IssueKey and Comment in Parameters)"
        Write-Host "  transition- Change issue status (requires IssueKey and TransitionName in Parameters)"
        Write-Host "  team      - Get QA team issues (optional TeamMember and Status in Parameters)"
        Write-Host ""
        Write-Host "Environment Variables Required:"
        Write-Host "  JIRA_USERNAME - Your JIRA username"
        Write-Host "  JIRA_PASSWORD - Your JIRA password/API token"
        Write-Host ""
        Write-Host "Examples:"
        Write-Host "  .\JIRA.ps1 -Action get -IssueKey 'MS-123'"
        Write-Host "  .\JIRA.ps1 -Action getfull -IssueKey 'MS-123'"
        Write-Host "  .\JIRA.ps1 -Action detailed -IssueKey 'MS-123'"
        Write-Host "  .\JIRA.ps1 -Action comments -IssueKey 'MS-123'"
        Write-Host "  .\JIRA.ps1 -Action history -IssueKey 'MS-123'"
        Write-Host "  .\JIRA.ps1 -Action search -Parameters @{JQL='project=MS AND status=Open'}"
        Write-Host "  .\JIRA.ps1 -Action team -Parameters @{TeamMember='claire.campbell'}"
    }
}