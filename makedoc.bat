rmdir docs /S /Q
rmdir "Modules\FSLabs Copilot\Manual" /S /Q

lua5.1 makecontrollist.lua
xcopy "topics\img" "docs\img" /i /y

call ldoc . --dir docs
xcopy "docs" "Modules\FSLabs Copilot\Manual" /i /y /E /C