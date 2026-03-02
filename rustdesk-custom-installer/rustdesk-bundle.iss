[Setup]
AppName=RustDesk Custom Bundle
AppVersion=1.0.0
DefaultDirName={autopf}\RustDeskCustom
DefaultGroupName=RustDesk Custom
OutputDir=.
OutputBaseFilename=RustDesk-Custom-Installer
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
WizardStyle=modern

[Files]
Source: "instalador-rustdesk.exe"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall
Source: "rd-config.ps1"; DestDir: "{tmp}"; Flags: ignoreversion deleteafterinstall

[Run]
; Ajusta /S, /quiet, etc. según soporte de tu instalador
Filename: "{tmp}\instalador-rustdesk.exe"; Parameters: "--silent-install"; Flags: waituntilterminated; StatusMsg: "Instalando RustDesk..."
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{tmp}\rd-config.ps1"""; Flags: waituntilterminated; StatusMsg: "Aplicando configuracion..."
