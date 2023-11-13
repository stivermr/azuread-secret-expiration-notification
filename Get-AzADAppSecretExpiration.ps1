# Purpose: Pull Azure AD applications and email owners that secret/certificate is expiring within 30 days.
# Update the smtp settings at the bottom to match your environment

Import-Module Microsoft.Graph.authentication
Import-Module Microsoft.Graph.applications
Import-Module Microsoft.Graph.Users


Connect-MgGraph


## UPDATE these values
$ccusers="user@email.com"
$summaryusers="user@email.com"
$fromaddr="AzureSecretsExpiring@email.com"
$smtpserver="smtp.email.com"
$emailsubject = "Application Secrets Expiring Soon"

$applications = Get-MgApplication -All

# Collect secret and certifiate information for applications expiring within 30 days
$limit = (Get-Date).AddDays(30)
$limit1 = Get-Date
$credentialsToRenew = foreach ($app in $applications) {
    $appId = $app.AppId
    $objectId = $app.Id
    $appName = $app.DisplayName
    $identifierUrls = $app.IdentifierUris -join ","
    
    $credentials = @()

    # Retrieve and process secret credentials
    $credentials += $app.PasswordCredentials | Where-Object { $_.EndDateTime -lt $limit -and $_.EndDateTime -gt $limit1 } | ForEach-Object {
        [PSCustomObject]@{
            'applicationName' = $appName
            'objectType' = 'Secret'
            'appId' = $appId
            'objectId' = $objectId
            'identifierUrls' = $identifierUrls
            'keyId' = $_.KeyId
            'startDate' = $_.StartDateTime
            'endDate' = $_.EndDateTime
        }
    }

    # Retrieve and process certificate credentials
    $credentials += $app.KeyCredentials | Where-Object { $_.EndDateTime -lt $limit -and $_.EndDateTime -gt $limit1 } | ForEach-Object {
        [PSCustomObject]@{
            'applicationName' = $appName
            'objectType' = $_.Type
            'appId' = $appId
            'objectId' = $objectId
            'identifierUrls' = $identifierUrls
            'keyId' = $_.KeyId
            'startDate' = $_.StartDateTime
            'endDate' = $_.EndDateTime
        }
    }

    $credentials
}

# Filter out applications with names containing "SSO"
$credentialsToRenew = $credentialsToRenew | Where-Object { $_.ApplicationName -notlike '*- AAP*' }

# Output the selected credentials
#$credentialsToRenew | Sort-Object endDate

# group and sort secrets and certificates
$applist = $credentialsToRenew | Group-Object -Property objectId | ForEach-Object{$_.Group | Sort-Object -Property endDate -Descending} |  Sort-Object applicationName

# get owner of application
$email = foreach ($d in $applist){
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
