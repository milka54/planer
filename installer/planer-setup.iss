; Установщик «Планер» для Windows (Inno Setup 7)
; Собрать: ISCC.exe planer-setup.iss

#define AppName "Планер"
#define AppVersion "1.3.6"
#define AppPublisher "Planer"
#define AppExeName "planer.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{8F3A2C10-7B5E-4D2A-9C41-PLANER1200}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
OutputDir=.
OutputBaseFilename=planer-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
DisableProgramGroupPage=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительно:"

[Files]
; Всё содержимое сборки: exe, dll, папка data и др.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Иконка отдельным файлом — чтобы ярлыки ссылались на неё напрямую
; (иначе Windows кэширует старую иконку из exe).
Source: "..\windows\runner\resources\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\app_icon.ico"; IconIndex: 0
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\app_icon.ico"; IconIndex: 0; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Запустить {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Удаляем пользовательские данные приложения (не трогаем — остаются настройки)
; Type: filesandordirs; Name: "{app}"
