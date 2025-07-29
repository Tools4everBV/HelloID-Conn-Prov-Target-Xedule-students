#################################################
# HelloID-Conn-Prov-Target-Xedule-students-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Resolve-Xedule-studentsError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
        } catch {
            $httpErrorObj.FriendlyMessage = "Error: [$($httpErrorObj.ErrorDetails)] [$($_.Exception.Message)]"
        }
        Write-Output $httpErrorObj
    }
}

function Get-XeduleToken {
    param ()
    $headers = @{
        'Content-Type' = 'application/x-www-form-urlencoded'
    }
    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $actionContext.Configuration.ClientId
        client_secret = $actionContext.Configuration.ClientSecret
        scope         = 'api://xedule-connect/.default'
    }
    $splatGetToken = @{
        Uri     = "https://login.microsoftonline.com/$($actionContext.Configuration.TenantId)/oauth2/v2.0/token"
        Method  = 'POST'
        Headers = $headers
        Body    = $body
    }
    $tokenResponse = Invoke-RestMethod @splatGetToken
    Write-Output $tokenResponse.access_token
}

try {
    Write-Information 'Starting account data import'
    # Get the token and set the headers
    $headers = @{
        'Ocp-Apim-Subscription-Key' = $actionContext.Configuration.OcpApimSubscriptionKey
        'Authorization'             = "Bearer $(Get-XeduleToken)"
    }

    $start = 0
    $amount = 500
    $importedAccounts = [System.Collections.Generic.List[object]]::new()
    do {
        $urlWithSkipTake = "$($actionContext.Configuration.BaseUrl)/students-groups/api/Student/ore/$($actionContext.Configuration.oreId)?customer=$($actionContext.Configuration.Customer)&start=$start&aantal=$amount"
        $splatGetUserParams = @{
            Uri     = $urlWithSkipTake
            Method  = 'GET'
            headers = $headers
        }
        $importedAccountRaw = (Invoke-RestMethod @splatGetUserParams).Objects
        if ($importedAccountRaw.Count -gt 0) {
            $importedAccounts.AddRange($importedAccountRaw)
        }
        $start += $amount
    } until ($importedAccountRaw.count -lt $amount)

    # Map the imported data to the account field mappings
    foreach ($importedAccount in $importedAccounts) {
        $data = @{}
        foreach ($field in $actionContext.ImportFields) {
            $data[$field] = $importedAccount.$field
        }
        $isEnabled = if ($null -eq $importedAccount.Studeert) {
            $false
        } else {
            $true
        }

        Write-Output @{
            AccountReference = $importedAccount.Id
            DisplayName      = "$($importedAccount.Voornaam) $($importedAccount.Achternaam)"
            UserName         = $importedAccount.Login
            Enabled          = $isEnabled
            Data             = $data
        }
    }

    Write-Information 'Account data import completed'
} catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Xedule-studentsError -ErrorObject $ex
        Write-Warning "Could not import Xedule-students account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        Write-Warning "Could not import Xedule-students account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
}
