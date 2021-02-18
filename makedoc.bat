rmdir docs /S /Q
rmdir "FSUIPC folder\FSLabs Copilot\Manual" /S /Q
del config.ld

lua5.1 makecontrollist.lua || exit /b 1
lua5.1 ldoc_cfg.lua || exit /b 1
xcopy "topics\img" "docs\img" /i /y

call ldoc . --dir docs || exit /b 1
del config.ld
xcopy "docs" "FSUIPC folder\FSLabs Copilot\Manual" /i /y /E /C