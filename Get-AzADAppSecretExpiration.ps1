# Purpose: Pull Azure AD applications and email owners that secret/certificate is expiring within 30 days.
# Update the smtp settings at the bottom to match your environment

Import-Module AzureAD
Connect-AzureAD -AccountId user1@server.com

## UPDATE these values
$ccusers="user@email.com"
$summaryusers="user@email.com"
$fromaddr="AzureSecretsExpiring@email.com"
$smtpserver="smtp.email.com"

Get-AzureADApplication -All $true | ForEach-Object{
    $applicationName = $objectType = $objectId = $applicationId = $homePage = $identifierUrls = $replyUrls = $keyId = $startDate = $endDate = ""
    $applicationName = $_.DisplayName
    #$objectType = $_.ObjectType
    $objectId = $_.ObjectId
    $applicationId = $_.AppId
    $homePage = $_.Homepage
    $identifierUrls = $_.IdentifierUris -Join ","
    $replyUrls = $_.ReplyUrls -Join ","
    $data = @()
    # pull secrets
    $data = (Get-AzureADApplication -ObjectId $objectId).PasswordCredentials | ForEach-Object{
        $objectType = 'Secret'
        $keyId = $_.KeyId
        $startDate = $_.StartDate
        $endDate = $_.EndDate
        [PSCustomObject] @{
                        'applicationName'        = $applicationName
                        'objectType'             = $objectType
                        'objectId'               = $objectId
                        'applicationId'          = $applicationId
                        'multiTenant'            = $multiTenant
                        'homePage'               = $homePage
                        'identifierUrls'         = $identifierUrls
                        'replyUrls'              = $replyUrls
                        'keyId'                  = $keyId
                        'startDate'              = $startDate
                        'endDate'                = $endDate
                        }

    }
    # pull certificates
    $keydata = (Get-AzureADApplication -ObjectId $objectId).KeyCredentials | ForEach-Object{
        $objectType = $_.Type
        $keyId = $_.KeyId
        $startDate = $_.StartDate
        $endDate = $_.EndDate
        [PSCustomObject] @{
                        'applicationName'        = $applicationName
                        'objectType'             = $objectType
                        'objectId'               = $objectId
                        'applicationId'          = $applicationId
                        'multiTenant'            = $multiTenant
                        'homePage'               = $homePage
                        'identifierUrls'         = $identifierUrls
                        'replyUrls'              = $replyUrls
                        'keyId'                  = $keyId
                        'startDate'              = $startDate
                        'endDate'                = $endDate
                        }

    }
    $data1 = [Array]$data1 + $data
    $keydata1 = [Array]$keydata1 + $keydata
}
# sort and filter secrets to newest
$list1 = $data1 | Group-Object -Property objectId | ForEach-Object{$_.Group | Sort-Object -Property endDate -Descending | Select-Object -First 1}
# sort and filter certificates to newest
$list2 = $keydata1 | Group-Object -Property objectId | ForEach-Object{$_.Group | Sort-Object -Property endDate -Descending | Select-Object -First 1}
$masterlist = $list1 + $list2
$masterlist = $masterlist | Sort-Object applicationName
# limit to expiring within 30 days
$limit = (Get-Date).AddDays(30)
$limit1 = Get-Date
foreach ($l in $masterlist){
    $data2 = if ($l.endDate -lt $limit -and $l.endDate -gt $limit1){
        [PSCustomObject]@{
            'applicationName' = $l.applicationName
            'objectType' = $l.objectType
            'objectId' = $l.objectId
            'keyId' = $l.keyId
            'endDate' = $l.endDate
        }
    }
    $data3 = [Array]$data3 + $data2
}
$data3 = $data3 | Sort-Object endDate
# get owner of application
$email = foreach ($d in $data3){
    $owners = Get-AzureADApplicationOwner -objectID $d.objectID
    foreach ($o in $owners.mail){
        if ($o) {
            [PSCustomObject]@{
                'ApplicationName' = $d.applicationName
                'Type' = $d.objectType
                'ObjectId' = $d.objectId
                'KeyId' = $d.keyId
                'ExpirationDate' = $d.endDate
                'Owner' = $o
            }
        }
    }
}
# groups apps by owner
$list = $email | group-object -Property owner
# email table styling
$style = "<style>BODY{font-family: Arial; font-size: 10pt;}"
$style = $style + "TABLE{border: 1px solid black; border-collapse: collapse;}"
$style = $style + "TH{border: 1px solid black; background: #dddddd; padding: 5px; }"
$style = $style + "TD{border: 1px solid black; padding: 5px; }"
$style = $style + "</style>"

# sends individual email to owner containing only their apps
foreach ($l in $list){
    $toaddr = $l.name
    #$ccaddr = $ccusers
    $fromaddr = "AzureSecretsExpiring@server.com"
    $emailbody = $l | Select-Object -ExpandProperty group 
    $subject = "Application Secrets Expiring Soon"
    $smtpserver = "smtp.server.com"
    $body = ($emailbody | ConvertTo-Html -Head $style | Out-String)
    $body += "<br><br> To update please visit: https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/RegisteredApps"
    $sendMailParams = @{
        From = $fromaddr
        To = $toaddr
        Cc = $ccaddr
        Subject = $subject
        Body = $body
        SMTPServer = $smtpserver
        DeliveryNotificationOption = "onFailure"
        BodyAsHtml = $True
    }
    Send-MailMessage @sendMailParams
}

# Summary email - contains all app secrets that are expiring
$toaddr = $summaryusers
#$ccaddr = $ccusers
$fromaddr  = "AzureSecretsExpiring@server.com"
$subject = "Application Secrets Expiring Soon"
$smtpserver = "smtp.server.com"
$body = ($email | ConvertTo-Html -Head $style | Out-String)
$body += "<br><br> To update please visit: https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/RegisteredApps"
$sendMailParams = @{
    From = $fromaddr
    To = $toaddr
    Cc = $ccaddr
    Subject = $subject
    Body = $body
    SMTPServer = $smtpserver
    DeliveryNotificationOption = "onFailure"
    BodyAsHtml = $True
}
Send-MailMessage @sendMailParams
