# Purpose: Pull Azure AD applications and email owners that secret/certificate is expiring within 30 days.
# Update the smtp settings at the bottom to match your environment

Import-Module Microsoft.Graph.authentication
Import-Module Microsoft.Graph.applications
Import-Module Microsoft.Graph.Users


Connect-MgGraph -AccountId user1@server.com


## UPDATE these values
$ccusers="user@email.com"
$summaryusers="user@email.com"
$fromaddr="AzureSecretsExpiring@email.com"
$smtpserver="smtp.email.com"
$emailsubject = "Application Secrets Expiring Soon"

Get-MgApplication -All | ForEach-Object{
    $applicationName = $objectType = $objectId = $applicationId = $homePage = $identifierUrls = $replyUrls = $keyId = $startDate = $endDate = ""
    $applicationName = $_.DisplayName
    $objectId = $_.Id
    $applicationId = $_.AppId
    $identifierUrls = $_.IdentifierUris -Join ","
    $secretdata = @()
    # pull secrets
    $secretdata = (Get-MgApplication -ApplicationId $objectId).PasswordCredentials | ForEach-Object{
        $objectType = 'Secret'
        $keyId = $_.KeyId
        $startDate = $_.StartDateTime
        $endDate = $_.EndDateTime
        [PSCustomObject] @{
                        'applicationName'        = $applicationName
                        'objectType'             = $objectType
                        'objectId'               = $objectId
                        'applicationId'          = $applicationId
                        'identifierUrls'         = $identifierUrls
                        'keyId'                  = $keyId
                        'startDate'              = $startDate
                        'endDate'                = $endDate
                        }

    }
    # pull certificates
    $certdata = (Get-MgApplication -ApplicationId $objectId).KeyCredentials | ForEach-Object{
        $objectType = $_.Type
        $keyId = $_.KeyId
        $startDate = $_.StartDateTime
        $endDate = $_.EndDateTime
        [PSCustomObject] @{
                        'applicationName'        = $applicationName
                        'objectType'             = $objectType
                        'objectId'               = $objectId
                        'applicationId'          = $applicationId
                        'identifierUrls'         = $identifierUrls
                        'keyId'                  = $keyId
                        'startDate'              = $startDate
                        'endDate'                = $endDate
                        }

    }
    $secretdata1 = [Array]$secretdata1 + $secretdata
    $certdata1 = [Array]$certdata1 + $certdata
}
# sort and filter secrets to newest
$list1 = $secretdata1 | Group-Object -Property objectId | ForEach-Object{$_.Group | Sort-Object -Property endDate -Descending | Select-Object -First 1}
# sort and filter certificates to newest
$list2 = $certdata1 | Group-Object -Property objectId | ForEach-Object{$_.Group | Sort-Object -Property endDate -Descending | Select-Object -First 1}
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
            'appId' = $l.applicationId
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
    $owners = @()
    $owners = Get-MgApplicationOwner -ApplicationId (Get-MgApplication -All -Filter "AppId eq '$($d.appId)'").Id
	if ($owners){
        $owners = foreach ($m in $owners){(Get-MgUser -UserId $m.Id).mail}
	    foreach ($o in $owners){
                [PSCustomObject]@{
                'ApplicationName' = $d.applicationName
                'Type' = $d.objectType
                'AppId' = $l.applicationId
                'ObjectId' = $d.objectId
                'KeyId' = $d.keyId
                'ExpirationDate' = $d.endDate
                'Owner' = $o
                }
		
        }
	}
	else{
		[PSCustomObject]@{
                'ApplicationName' = $d.applicationName
                'Type' = $d.objectType
                'ObjectId' = $d.objectId
                'KeyId' = $d.keyId
                'ExpirationDate' = $d.endDate
                'Owner' = $null
		}
    }
}

$list = $email | group-object -Property owner
# email table styling
$style = "<style>BODY{font-family: Arial; font-size: 10pt;}"
$style = $style + "TABLE{border: 1px solid black; border-collapse: collapse;}"
$style = $style + "TH{border: 1px solid black; background: #dddddd; padding: 5px; }"
$style = $style + "TD{border: 1px solid black; padding: 5px; }"
$style = $style + "</style>"

# send email to each owner
foreach ($l in $list){
    if ($l.name){
        $toaddr = $l.name
    }else{
        $toaddr = $ccusers
    }
    $ccaddr = $ccusers
    $fromaddr = $fromaddr
    $emailbody = $l | Select-Object -ExpandProperty group 
    $subject = $emailsubject
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

# Summary email
#$toaddr = $list.Name
$toaddr = $summaryusers
$fromaddr  = $fromaddr
$subject = $emailsubject
$body = ($email | ConvertTo-Html -Head $style | Out-String)
$body += "<br><br> To update please visit: https://portal.azure.com/#blade/Microsoft_AAD_IAM/ActiveDirectoryMenuBlade/RegisteredApps"
$sendMailParams = @{
    From = $fromaddr
    To = $toaddr
    #Cc = $ccaddr
    Subject = $subject
    Body = $body
    SMTPServer = $smtpserver
    DeliveryNotificationOption = "onFailure"
    BodyAsHtml = $True
}
Send-MailMessage @sendMailParams
