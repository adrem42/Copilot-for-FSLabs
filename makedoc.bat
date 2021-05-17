rmdir docs /S /Q
rmdir "Prepar3D vx Add-ons\Copilot for FSLabs\Manual" /S /Q
del config.ld

REM lua5.1 makecontrollist.lua || exit /b 1
lua5.1 ldoc_cfg.lua || exit /b 1
xcopy "topics\img" "docs\img" /i /y

call ldoc . --dir docs || exit /b 1
del config.ld
xcopy "docs" "Prepar3D vx Add-ons\Copilot for FSLabs\Manual" /i /y /E /C