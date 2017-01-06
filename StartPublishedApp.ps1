#Start Published App
#Requires -Version 3.0
#This File is in Unicode format.  Do not edit in an ASCII editor.

<#
.SYNOPSIS
	Connects to a Citrix StoreFront server andd starts the requested Published Applications.
.DESCRIPTION
	Connects to a Citrix StoreFront server andd starts the requested Published Applications.
.PARAMETER BaseURL
    This is the location of the Citrix Storefront WebStore. It must start with http://...
    https is not supported at this time.
.PARAMETER Username
    The username for connecting to the Published Application. It must include a domain name DOMAIN\... or in UPN format
.PARAMETER Password
    The password for connecting to the Published Application.
.PARAMETER Application
    Published Application name to start
.EXAMPLE
    PS C:\PSScript > .\StartPublishedApp.ps1 -BaseURL http://www.example.com/Citrix/StoreWeb -Username DOMAIN\SomeUser -Password SomePassword -Appliction Calculator
.INPUTS
	None.  You cannot pipe objects to this script.
.OUTPUTS
	No objects are output from this script.
.NOTES
	NAME: StartPublishedApp.ps1
	VERSION: 0.2
	AUTHOR: Edward Dijk
	LASTEDIT: Maart 13, 2015
.LINK
    Website : http://www.enso-it.nl
#>

param(
    [Parameter(Mandatory=$true,Position=1)]
    [string]$BaseURL,

    [Parameter(Mandatory=$true,Position=2)]
    [string]$Username,

    [Parameter(Mandatory=$true,Position=3)]
    [string]$Password,

    [Parameter(Mandatory=$true,Position=4)]
    [string]$Application
)


Function ExecuteAPI{
    param(
        [string]$URI,
        $Postheader,
        $Body,
        $Websession
    )
    WriteLog -TempPath $TempPath -LogFile $LogFile -Message "ExecuteAPI URL : $URI"
    
    Try{
        $Result = Invoke-WebRequest -Uri $URI -WebSession $WebSession -Method Post -Headers $PostHeader -Body $Body
        }
    Catch{
        $ErrorMessage = $_.Exception.Message
        WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Error ExecuteAPI : $ErrorMessage"
        Exit
        }
        
    Return $Result
}

Function GetToken{
    param(
        $WebResult
    )

    $Token = $WebResult.Headers["Set-Cookie"] -split ";"
    $Token = $Token[2].trim().split(",")[1]
    $Token = $Token -split "="
    Write-Host "Token : ",$Token[1] -ForegroundColor Cyan
    Return $Token[1]
    }

Function GetAppURL{
    param(
        $WebResult,
        $PublishedApp
    )

    $JSON = ConvertFrom-Json -InputObject $WebResult -Verbose -Debug
    WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Published App : $PublishedApp"
    
    Foreach($App in $JSON.resources){
        if($App.name -eq $PublishedApp){
            Return $App.launchurl.trim()
         }
    }
}

Function WriteLog{
    param(
        [string]$TempPath,
        [string]$LogFile,
        [string]$Message
        )

    $FullPath = $TempPath + "\" + $LogFile  

    Add-Content -Path $FullPath -Value "[$([DateTime]::Now)] - $Message"
    Write-Debug -Message "[$([DateTime]::Now)] - $Message" 
}

Function WriteICAFile{
    param(
        $WebResult,
        $Path
        )
    $ICAFile = $WebResult.RawContent.Substring($WebResult.RawContent.IndexOf("[Encoding]",0))
    WriteLog -TempPath $TempPath -LogFile $LogFile -Message "ICA File Path : $Path"

    $Filename = ([System.IO.Path]::GetRandomFileName().Split("."))[0] + ".ICA"
    $Filename = "$Path\$Filename"
    WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Filename : $Filename"

    If(-not (Test-Path -Path $Filename)){
            Out-File -FilePath $Filename -InputObject $ICAFile -Encoding ascii
        }Else{
            WriteLog -TempPath $TempPath -LogFile $LogFile -Message "File Exists!"
            WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Filename : $Filename"
            Exit
        }

            
    Return $Filename
}




#Initialize
$ErrorActionPreference = "stop"
$TempPath = $env:TEMP
$LogFile = "StartPublishedApp.log"


$PostHeader = @{
    "X-Citrix-IsUsingHTTPS" = "No"
    }

WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Starting Script..."


#Create A WebSession
Try{
    $Result = Invoke-WebRequest -Uri $BaseURL -SessionVariable WebSession
    }
Catch{
    WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Error creating Web Session to : $BaseURL"
    $ErrorMessage = $_.Exception.Message
    WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Error : $ErrorMessage"
    Exit
    }


#Main
$Result = $null

#Get Resources (This is for the CsrfToken Cookie)
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Getting CsrfToken"
$Result = ExecuteAPI -URI "$BaseURL/Resources/List" -Postheader $PostHeader -Websession $WebSession 

#GetToken
$CsrfToken = GetToken -WebResult $Result
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "CsrfToken : $CsrfToken"
$PostHeader.Add("Csrf-Token",$CsrfToken)

#Inloggen
$Body = "username=$Username&password=$Password"
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Authenticating to StoreFront"
$Result = ExecuteAPI -URI "$BaseURL/PostCredentialsAuth/Login" -Postheader $PostHeader -Websession $WebSession -Body $Body

#Check if authetication succesful
If($Result.Content.Contains("fail")){
    WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Authetication failed!"
    Exit
}


#Get Resources
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Getting a Resource List"
$Result = ExecuteAPI -URI "$BaseURL/Resources/List" -Postheader $PostHeader -Websession $WebSession


#GetApp
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Getting the LaunchURL"
$LaunchURL = GetAppURL -WebResult $Result -PublishedApp $Application
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "LaunchURL : $LaunchURL"

#GetICA
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Getting ICA file"
$Result = ExecuteAPI -URI "$BaseURL/$LaunchURL" -Postheader $PostHeader -Websession $WebSession


#WriteICA
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Writing ICA File"
$FileName = WriteICAFile -WebResult $Result -Path $TempPath

#Check Filesize
if((Get-Content -Path $FileName) -eq $null){
    WriteLog -TempPath $TempPath -LogFile $LogFile -Message "ICA file is empty!"
    Exit
}



#Launch
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Launch ICA file : $Filename"
Start-process $FileName

#Finish
WriteLog -TempPath $TempPath -LogFile $LogFile -Message "Script Finished"