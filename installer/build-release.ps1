# Сборка релиза ПК-версии (Windows)

# 1. Сборка приложения
cd D:\projects\Planer
flutter build windows --release

# 2. Сборка установщика
& "C:\Program Files\Inno Setup 7\ISCC.exe" installer\planer-setup.iss

# 3. (Опционально) Подписание — убирает предупреждение SmartScreen
#    Нужен сертификат кодовой подписи (см. раздел ниже).
#    Раскомментируйте и укажите свои данные:
#
# $cert = "C:\certs\planer.pfx"
# $pass = "пароль_от_сертификата"
# $signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
#
# & $signtool sign /f $cert /p $pass /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
#     "build\windows\x64\runner\Release\planer.exe"
# & $signtool sign /f $cert /p $pass /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 `
#     "installer\planer-setup.exe"

# 4. Портативный пакет для обновления из приложения (без установщика)
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath dist\planer-win-portable.zip -Force

# 5. Копирование в dist/ для загрузки в релиз
Copy-Item installer\planer-setup.exe dist\planer-setup.exe -Force

Write-Host "Готово: dist\planer-setup.exe, dist\planer-win-portable.zip"
Write-Host "Не забудьте обновить dist\version.json (версия + описание)"
