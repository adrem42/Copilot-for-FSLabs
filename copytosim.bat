@ECHO OFF
xcopy "Modules" "C:\Users\Peter\Documents\Prepar3D v5 Add-ons\FSUIPC6" /i /y /E /C
IF "%1" == "d" (
	set config="Debug"
) ELSE (
	set config="Release"
)
copy "x64\%config%\FSLCopilot.dll" "C:\Users\Peter\Documents\Prepar3D v4 Add-ons\Copilot for FSLabs"
copy "x64\%config%\FSLCopilot.dll" "C:\Users\Peter\Documents\Prepar3D v5 Add-ons\Copilot for FSLabs"
copy "x64\Release\FSLCopilot.dll" "Prepar3D vx Add-ons\Copilot for FSLabs"
