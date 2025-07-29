#################################################
# HelloID-Conn-Prov-Target-Xedule-students-Enable
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
#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    # Get the token and set the headers
    $headers = @{
        'Ocp-Apim-Subscription-Key' = $actionContext.Configuration.OcpApimSubscriptionKey
        'Authorization'             = "Bearer $(Get-XeduleToken)"
    }

    Write-Information 'Verifying if a Xedule-students account exists'
    $splatGetUserParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/students-groups/api/Student/ore/$($actionContext.Configuration.oreId)/id/$($actionContext.References.Account)?customer=$($actionContext.Configuration.Customer)"
        Method  = 'GET'
        headers = $headers
    }
    $getResponse = Invoke-RestMethod @splatGetUserParams
    $correlatedAccount = $getResponse.Object

    if ($null -ne $correlatedAccount -and $getResponse.Success -eq $true) {
        $action = 'EnableAccount'
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'EnableAccount' {
            $body = @{
                Id       = $actionContext.References.Account
                Studeert = @(
                    @{
                        From = (Get-Date).AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ss')
                        To   = (Get-Date).AddDays(9999).ToString('yyyy-MM-ddTHH:mm:ss')  # Does not Work (information Requested from supplier)
                    }
                )
            }
            $splatUpdateParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/students-groups/api/Student/ore/$($actionContext.Configuration.oreId)?customer=$($actionContext.Configuration.Customer)"
                Method      = 'PATCH'
                Body        = ([System.Text.Encoding]::UTF8.GetBytes(( $body | ConvertTo-Json )))
                headers     = $headers
                ContentType = 'application/json; charset=utf-8'
            }
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Enabling Xedule-students account with accountReference: [$($actionContext.References.Account)]"
                $response = Invoke-RestMethod @splatUpdateParams
                if ($response.Success -eq $false ) {
                    throw $response.Message
                }
            } else {
                Write-Information "[DryRun] Enable Xedule-students account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Enable account was successful'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Xedule-students account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Xedule-students account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }

} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Xedule-studentsError -ErrorObject $ex
        $auditMessage = "Could not enable Xedule-students account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not enable Xedule-students account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}