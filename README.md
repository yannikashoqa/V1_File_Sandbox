# V1_File_Sandbox


AUTHOR		: Yanni Kashoqa

TITLE		: Submit a file on a remote system to Vision One Sandbox 

DESCRIPTION	: This Powershell script will initiate a file collection task in Vision One from a system that already have the Vision One Sensor, submit it to the sandbox and then download the report locally.

REQUIRMENTS
- PowerShell 7.x (Make sure Language Mode is set to Full Language.) 
    - Check Language Mode by running:  $ExecutionContext.SessionState.LanguageMode
- Target system must be online
- Supported Sensors:  
    - Vision One Sensor (XES)
    - Cloud One Workload Security Activity Monitoring (Windows and Linux)
- Modify the values of $HostName and $FilePath in the script:
    - Windows Example: "C:\Temp\Suspicious.exe"
    - Linux Example: "/tmp/Eicar.com"     
- Update the XDR-Config.json with your Vision One Token:

~~~~JSON
{
    "XDR_SERVER": "api.xdr.trendmicro.com",
    "TOKEN": ""
}
~~~~
