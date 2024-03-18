
$Config         = (Get-Content "$PSScriptRoot\XDR-Config.json" -Raw) | ConvertFrom-Json
$XDR_SERVER     = $Config.XDR_SERVER
$TOKEN          = $Config.TOKEN
$XDR_URI        = "https://" + $XDR_SERVER
$StartTime      = $(get-date)

# Change the following variables only
$HostName       = ""  # Target Hostname
$FilePath       = ""   # Path to file to be collected

#########################################################################################

# Make sure PowerShell version is 7.x
$PS_Version         = $PSVersionTable.PSVersion.Major
$PSVersionRequired  = "7"
If ($PS_Version -ne $PSVersionRequired){
	Write-Host "[ERROR]	Pwershell version is $PS_Version. Powershell version $PSVersionRequired is required."
	Exit
}

# Make sure LanguageMode is set to FullLanguage
$LanguageMode = $ExecutionContext.SessionState.LanguageMode
If ($LanguageMode -ne "FullLanguage"){
	Write-Host "[ERROR]	Pwershell Language Mode is not set to FullLanguage. It is currently set to $LanguageMode"
	Exit
}

# Authentication Header
$Headers = @{
    "Content-Type" = "application/json;charset=utf-8"
    Authorization = "Bearer $TOKEN"
}

# Collect File Task
$COLLECT_FILE_URI   = $XDR_URI + "/v3.0/response/endpoints/collectFile"
$COLLECT_FILE_DATA = @{
    "endpointName" = $HostName;
    "filePath"  = $FilePath;
    "description" = "Collect File - API V3.0"
}

$COLLECT_FILE_PAYLOAD = $COLLECT_FILE_DATA | ConvertTo-Json -Depth 4 -AsArray
try {
    $COLLECT_FILE_RESPONSE = Invoke-RestMethod $COLLECT_FILE_URI -Method 'POST' -Headers $Headers -Body $COLLECT_FILE_PAYLOAD
    $FileCollectionActionID = $COLLECT_FILE_RESPONSE.actionId
} catch {
    Write-Host "ERROR: Failed to Submit File Collection: $_"
    Exit
}

Start-Sleep 5 # Wait 5 seconds to make sure task is running

# Get Collect File Task Status
$COLLECTED_FILE_TASK_URI        = $XDR_URI + "/v3.0/response/tasks/$FileCollectionActionID"
$COLLECTED_FILE_TASK_DETAILS    = Invoke-RestMethod $COLLECTED_FILE_TASK_URI -Method 'GET' -Headers $headers
$COLLECTED_FILE_TASK_STATUS     = $COLLECTED_FILE_TASK_DETAILS.items[0].status
Do{    
    if ($COLLECTED_FILE_TASK_STATUS -eq "failed" -OR $COLLECTED_FILE_TASK_STATUS -eq "timeout" -or $COLLECTED_FILE_TASK_STATUS -eq "skipped"){
        Write-Host "WARNING: File Collection Status is: $COLLECTED_FILE_TASK_STATUS"
        Write-Host "Exiting Script..."
        Exit
    }
    Write-Progress -Activity "Please wait while the file is being Collected."
    $COLLECTED_FILE_TASK_DETAILS    = Invoke-RestMethod $COLLECTED_FILE_TASK_URI -Method 'GET' -Headers $headers
    $COLLECTED_FILE_TASK_STATUS     = $COLLECTED_FILE_TASK_DETAILS.items[0].status
} While ($COLLECTED_FILE_TASK_STATUS -ne "succeeded")
#} While ($COLLECTED_FILE_TASK_STATUS -eq "pending" -OR $COLLECTED_FILE_TASK_STATUS -eq "ongoing" -OR $COLLECTED_FILE_TASK_STATUS -eq "running")


# Get Collected File downlaod URL and FileName
# V1 API v3.0 currently does not have the download info API;  using v 2.0.
$COLLECTED_FILE_URI     = $XDR_URI + "/v2.0/xdr/response/downloadInfo"
$FileCollectionActionID = $COLLECTED_FILE_TASK_DETAILS.items[0].id
$COLLECTED_FILE_DATA = @{
    "actionId" = $FileCollectionActionID
}

try {
    $COLLECTED_FILE_RESPONSE    = Invoke-RestMethod $COLLECTED_FILE_URI -Method 'GET' -Headers $headers -body $COLLECTED_FILE_DATA
    $CollectedFileDownloadURL   = $COLLECTED_FILE_RESPONSE.data.url
    $CollectedFilefileName      = $COLLECTED_FILE_RESPONSE.data.filename
}
catch {
    Write-Host "ERROR: Failed to Retreive Downloaded File Information: $_" # Need to be changed
    Exit      
}

# Download Collected File
try{
    Invoke-RestMethod -URI  $CollectedFileDownloadURL -OutFile $CollectedFilefileName
} catch {
    Write-Host "ERROR: Failed to Download Collected File to Local System: $_"
    Exit
}

# Get Downloaded File ready for Submission
$FilePath               = "$PSScriptRoot\$CollectedFilefileName"
$FileContent            = Get-Item -Path $FilePath
$FilePassword           = $COLLECTED_FILE_RESPONSE.data.password
$FilePassword_Encoded   = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($FilePassword))  # Works

# Submit File to Sandbox
$SANDBOX_FILE_URI       = $XDR_URI + "/v3.0/sandbox/files/analyze"
$SANDBOX_FILE_DATA      = @{
    file = $FileContent
    archivePassword = $FilePassword_Encoded
}
try {
    $SANDBOXED_FILE_RESPONSE    = Invoke-RestMethod -Uri $SANDBOX_FILE_URI -Method 'POST' -Headers $headers -Form $SANDBOX_FILE_DATA -TimeoutSec 600
    $SubmissionTaskID           = $SANDBOXED_FILE_RESPONSE.id
} catch {
    Write-Host "ERROR: Failed to Submit file for Analysis: $_"
    Exit
}

# Delete local copy of submitted file
try {
    Write-Host "INFO: Deleting Downloaded Sample"
    Remove-Item -Path $FilePath
} catch {
    Write-Host "ERROR: Failed to Delete Downloaded Sample: $_" 
    Exit
}

# Get Sandbox submission status
$SANDBOX_FILE_URI       = $XDR_URI + "/v3.0/sandbox/tasks/$SubmissionTaskID"
$SandboxSubmission_INFO = Invoke-RestMethod $SANDBOX_FILE_URI -Method 'GET' -Headers $headers
$SubmissionStatus       = $SandboxSubmission_INFO.status
Do{
    try {
        If ($SubmissionStatus -eq "failed"){
            $SB_Error = $SandboxSubmission_INFO.error.message
            Write-Host "WARNING: Sandbox Submission ID $SubmissionTaskID has failed: $SB_Error"
            Exit
        }
        $SandboxSubmission_INFO = Invoke-RestMethod $SANDBOX_FILE_URI -Method 'GET' -Headers $headers
        $SubmissionStatus       = $SandboxSubmission_INFO.status
    }
    catch {
        Write-Host "ERROR: Failed to Retreive Submission Status: $_" 
        Exit    
    }
    Write-Progress -Activity "Processing Action Id: $SubmissionTaskID.  Please wait while the file is being scanned."
}While($SubmissionStatus -ne "succeeded")

# Downlaod Sandbox submission report
try {
    $SANDBOX_ANALYSIS_URI = $XDR_URI + "/v3.0/sandbox/analysisResults/$SubmissionTaskID/report"
    Invoke-RestMethod -URI $SANDBOX_ANALYSIS_URI -Method 'GET' -Headers $headers -OutFile (($SandboxSubmission_INFO.id) + ".pdf")
} catch {
    Write-Host "ERROR: Failed to Retreive Sandbox Submission report: $_" 
}

$elapsedTime    = $(get-date) - $StartTime
$totalTime      = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)
Write-Host "Script Execution is Complete.  It took $totalTime"
