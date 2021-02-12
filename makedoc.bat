rmdir docs /S /Q
rmdir "Modules\FSLabs Copilot\Manual" /S /Q
del config.ld

lua5.1 makecontrollist.lua
lua5.1 ldoc_cfg.lua
xcopy "topics\img" "docs\img" /i /y

call ldoc . --dir docs
del config.ld
xcopy "docs" "Modules\FSLabs Copilot\Manual" /i /y /E /C