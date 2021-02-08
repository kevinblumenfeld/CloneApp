function Import-TemplateApp {
    <#
        .SYNOPSIS
        To be used with functions from Posh365

        .DESCRIPTION
        To be used with functions from Posh365

        Install-Module Posh365
        Register-GraphApplication -Tenant Contoso -App Intune

        # The registration is a one-time thing.
        # Once it is complete, use the below command each time to connect to Graph
        Connect-PoshGraph -Tenant ContosoIntune

        .PARAMETER Owner
        Parameter description

        .PARAMETER xmlPath
        Parameter description

        .PARAMETER GithubUsername
        Parameter description

        .PARAMETER GistFilename
        Parameter description

        .PARAMETER SecretDurationYears
        Parameter description

        .PARAMETER Name
        Parameter description

        .PARAMETER ConsentAction
        Parameter description

        .EXAMPLE
        Install-Module Posh365
        Register-GraphApplication -Tenant Contoso -App Intune

        # The registration is a one-time thing.
        # Once it is complete, use the below command each time to connect to Graph
        Connect-PoshGraph -Tenant ContosoIntune


        .NOTES
        This really should be a private function. Eventually, I will use:
            & modulename { commands to be ran in the module scope }

            #>
    [cmdletbinding(DefaultParameterSetName = 'PlaceHolder')]
    param (

        [Parameter(Mandatory, ParameterSetName = 'FileSystem')]
        [Parameter(Mandatory, ParameterSetName = 'GIST')]
        [mailaddress]
        $Owner,

        [Parameter(Mandatory, ParameterSetName = 'FileSystem')]
        [string]
        [ValidateScript( { Test-Path $_ })]
        $xmlPath,

        [Parameter(Mandatory, ParameterSetName = 'GIST')]
        [string]
        $GithubUsername,

        [Parameter(Mandatory, ParameterSetName = 'GIST')]
        [string]
        $GistFilename,

        [Parameter(ParameterSetName = 'FileSystem')]
        [Parameter(ParameterSetName = 'GIST')]
        $SecretDurationYears,

        [Parameter(Mandatory, ParameterSetName = 'FileSystem')]
        [Parameter(Mandatory, ParameterSetName = 'GIST')]
        [string]
        $Name,

        [Parameter(ParameterSetName = 'FileSystem')]
        [Parameter(ParameterSetName = 'GIST')]
        [ValidateSet('OpenBrowser', 'OutputUrl', 'Both')]
        [string]
        $ConsentAction,

        [Parameter(Mandatory, ParameterSetName = 'FileSystem')]
        [Parameter(Mandatory, ParameterSetName = 'GIST')]
        [switch]
        $GCCHigh
    )
    $Date = Get-Date
    $NewAppSplat = @{ }
    $NewAppSplat['ReplyUrls'] = 'https://portal.azure.com'
    $Name = '{0}-{1}' -f $Name, $Date.ToString("yyyyMMdd_HHmmss")
    Write-Host "Finding ObjectId for owner: $Owner" -ForegroundColor Cyan -NoNewline
    try {
        $AppOwner = Get-AzureADUser -ObjectId $Owner -ErrorAction Stop
        Write-Host " Found`r`n" -ForegroundColor Green
    }
    catch {
        Write-Host " Not Found. Halting script" -ForegroundColor Red
        continue
    }
    try {
        $null = Get-AzureADApplication -filter "DisplayName eq '$Name'" -ErrorAction Stop
    }
    catch {
        Write-Host "Azure AD Application Name: $Name already exists" -ForegroundColor Red
        Write-Host "Choose a new name with the -Name parameter" -ForegroundColor Cyan
        continue
    }

    if ($PSCmdlet.ParameterSetName -eq 'FileSystem') { $App = Import-Clixml $xmlPath }
    else {
        try {
            $Tempfilepath = Join-Path -Path $Env:TEMP -ChildPath ('{0}.xml' -f [guid]::newguid().guid)
            (Get-CloneGist -Username $GithubUserName -Filename $GistFilename)[0].content | Set-Content -Path $Tempfilepath -ErrorAction Stop
            $App = Import-Clixml $Tempfilepath
        }
        catch {
            Write-Host "Error importing GIST $($_.Exception.Message)" -ForegroundColor Red
            continue
        }
        finally {
            Remove-Item -Path $Tempfilepath -Force -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    $Tenant = Get-AzureADTenantDetail
    try {
        $NewAppSplat['DisplayName'] = $Name
        $NewAppSplat['ErrorAction'] = 'Stop'
        $TargetApp = New-AzureADApplication @NewAppSplat
    }
    catch {
        Write-Host "Unable to create new application:  $($_.Exception.Message)" -ForegroundColor Red
        continue
    }

    $Output = [ordered]@{ }
    $Output['DisplayName'] = $Name
    $Output['ApplicationId'] = $TargetApp.AppId
    $Output['TenantId'] = $Tenant.ObjectID
    $Output['ObjectId'] = $TargetApp.ObjectId
    $Output['Owner'] = $Owner

    $RequiredList = [System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.RequiredResourceAccess]]::new()
    foreach ($ResourceAppId in $App['API'].keys) {
        $RequiredObject = [Microsoft.Open.AzureAD.Model.RequiredResourceAccess]::new()
        $AccessObject = [System.Collections.Generic.List[Microsoft.Open.AzureAD.Model.ResourceAccess]]::new()
        foreach ($ResourceAccess in $App['API'][$ResourceAppId]['ResourceList']) {
            $AccessObject.Add([Microsoft.Open.AzureAD.Model.ResourceAccess]@{
                    Id   = $ResourceAccess.Id
                    Type = $ResourceAccess.Type
                })
        }
        $RequiredObject.ResourceAppId = $ResourceAppId
        $RequiredObject.ResourceAccess = $AccessObject
        $RequiredList.Add($RequiredObject)
    }
    Set-AzureADApplication -ObjectId $TargetApp.ObjectId -RequiredResourceAccess $RequiredList
    Add-AzureADApplicationOwner -ObjectId $TargetApp.ObjectId -RefObjectId $AppOwner.ObjectId

    if ($SecretDurationYears) {
        $Params = @{
            ObjectId            = $TargetApp.ObjectId
            EndDate             = $Date.AddYears($SecretDurationYears)
            CustomKeyIdentifier = $Date.ToString("yyyyMMdd_HHmmss")
        }
        $SecretResult = New-AzureADApplicationPasswordCredential @Params
        $Output['Secret'] = $SecretResult.value
    }

    if ($ConsentAction -match 'OutputUrl|Both') {
        Write-Host "`r`n"
        Write-Host "The link below will open automatically.  Grant admin consent by logging in as $($Owner.Address): "  -ForegroundColor Black -BackgroundColor White
        Write-Host "`r`n"
        if ($GCCHigh) {
            $ConsentURL = 'https://login.microsoftonline.us/{0}/v2.0/adminconsent?client_id={1}&state=12345&redirect_uri={2}&scope={3}&prompt=admin_consent' -f @(
                $Tenant.ObjectID, $TargetApp.AppId, 'https://portal.azure.us/', 'https://graph.microsoft.com/.default')

        }
        else {
            $ConsentURL = 'https://login.microsoftonline.com/{0}/v2.0/adminconsent?client_id={1}&state=12345&redirect_uri={2}&scope={3}&prompt=admin_consent' -f @(
                $Tenant.ObjectID, $TargetApp.AppId, 'https://portal.azure.com/', 'https://graph.microsoft.com/.default')

        }

        Write-Host "$ConsentURL" -ForegroundColor Green
    }
    if ($ConsentAction -match 'OpenBrowser|Both') {
        Write-Host "`r`nSleeping 20 seconds prior to opening link in your browser.  Stand by..." -ForegroundColor Yellow
        Start-Sleep -Seconds 20
        Start-Process $ConsentURL
    }
    [PSCustomObject]$Output
}
