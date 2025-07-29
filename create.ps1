#################################################
# HelloID-Conn-Prov-Target-Xedule-students-Create
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

function Remove-ArrayProperties {
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        $Object,

        [parameter()]
        $ExcludeProperties = @()
    )
    process {
        $propertiesToRemove = $Object.PSObject.Properties | Where-Object {
            ($_.TypeNameOfValue -eq 'System.Object[]') -and
            ($ExcludeProperties -notcontains $_.Name)
        }
        foreach ($property in $propertiesToRemove) {
            $Object.PSObject.Properties.Remove($property.Name)
        }
        Write-Output $Object
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
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Get the token and set the headers
    $headers = @{
        'Ocp-Apim-Subscription-Key' = $actionContext.Configuration.OcpApimSubscriptionKey
        'Authorization'             = "Bearer $(Get-XeduleToken)"
    }

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        $splatGetUserParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/students-groups/api/Student/ore/$($actionContext.Configuration.oreId)/referenceKey/$($correlationValue)?customer=$($actionContext.Configuration.Customer)"
            Method  = 'GET'
            headers = $headers
        }
        $getResponse = Invoke-RestMethod @splatGetUserParams
        $correlatedAccount = $getResponse.Objects
    }

    if ($correlatedAccount.Count -eq 0) {
        $action = 'CreateAccount'
    } elseif ($correlatedAccount.Count -eq 1) {
        $correlatedAccount = $correlatedAccount | Select-Object -First 1
        $action = 'CorrelateAccount'
    } elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            $splatCreateParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/students-groups/api/Student/ore/$($actionContext.Configuration.oreId)?customer=$($actionContext.Configuration.Customer)"
                Method      = 'POST'
                Body        = ([System.Text.Encoding]::UTF8.GetBytes(($actionContext.Data | ConvertTo-Json )))
                headers     = $headers
                ContentType = 'application/json; charset=utf-8'
            }

            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Xedule-students account'
                $response = Invoke-RestMethod @splatCreateParams
                if ($response.Success -eq $false ) {
                    throw $response.Message
                }
                $createdAccount = $response.Object
                $createdAccount.Studeert = $createdAccount.Studeert | Select-Object -First 1
                $outputContext.Data = $createdAccount | Remove-ArrayProperties
                $outputContext.AccountReference = $createdAccount.Id
            } else {
                Write-Information '[DryRun] Create and correlate Xedule-students account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Xedule-students account'
            $correlatedAccount.Studeert = $correlatedAccount.Studeert | Select-Object -First 1
            $outputContext.Data = $correlatedAccount | Remove-ArrayProperties
            $outputContext.AccountReference = $correlatedAccount.Id
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.Success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Xedule-studentsError -ErrorObject $ex
        $auditMessage = "Could not create or correlate Xedule-students account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate Xedule-students account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}