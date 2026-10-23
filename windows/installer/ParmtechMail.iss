#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "build\\windows\\x64\\runner\\Release"
#endif
#ifndef OutputDir
  #define OutputDir "artifacts"
#endif

[Setup]
AppId={{8FA58091-C3DF-459E-9E43-7DB64C9A1E28}
AppName=Parmtech Mail
AppVersion={#AppVersion}
AppPublisher=ParmTech
DefaultDirName={localappdata}\Programs\Parmtech Mail
DefaultGroupName=Parmtech Mail
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=Parmtech-Mail-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName=Parmtech Mail

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Parmtech Mail"; Filename: "{app}\parm_mail.exe"
Name: "{autodesktop}\Parmtech Mail"; Filename: "{app}\parm_mail.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\parm_mail.exe"; Description: "Launch Parmtech Mail"; Flags: postinstall nowait skipifsilent
