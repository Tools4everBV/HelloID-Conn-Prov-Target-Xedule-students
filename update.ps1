#################################################
# HelloID-Conn-Prov-Target-Xedule-students-Update
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
        $correlatedAccount.Studeert = $correlatedAccount.Studeert | Select-Object -First 1
        $outputContext.PreviousData = $correlatedAccount | Remove-ArrayProperties
        $splatCompareProperties = @{
            ReferenceObject  = @(($correlatedAccount | Select-Object * -ExcludeProperty Studeert).PSObject.Properties)
            DifferenceObject = @(($actionContext | Select-Object * -ExcludeProperty Studeert).Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $action = 'UpdateAccount'
        } else {
            $action = 'NoChanges'
        }
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
            $body = @{
                Id = $actionContext.References.Account
            }
            foreach ($property in $propertiesChanged.Name) {
                $body[$property] = $actionContext.Data.$property
            }
            $splatUpdateParams = @{
                Uri         = "$($actionContext.Configuration.BaseUrl)/students-groups/api/Student/ore/$($actionContext.Configuration.oreId)?customer=$($actionContext.Configuration.Customer)"
                Method      = 'PATCH'
                Body        = ([System.Text.Encoding]::UTF8.GetBytes(( $body | ConvertTo-Json )))
                headers     = $headers
                ContentType = 'application/json; charset=utf-8'
            }
            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating Xedule-students account with accountReference: [$($actionContext.References.Account)]"
                $response = Invoke-RestMethod @splatUpdateParams
                if ($response.Success -eq $false ) {
                    throw $response.Message
                }
            } else {
                Write-Information "[DryRun] Update Xedule-students account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to Xedule-students account with accountReference: [$($actionContext.References.Account)]"

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'No changes will be made to the account during enforcement'
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
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Xedule-studentsError -ErrorObject $ex
        $auditMessage = "Could not update Xedule-students account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Xedule-students account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
