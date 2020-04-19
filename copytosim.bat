@ECHO OFF
xcopy "Modules" "C:\Prepar3D V4\Modules" /i /y /E /C
IF "%1" == "d" (
	set config="Debug"
) ELSE (
	set config="Release"
)
copy "x64\%config%\Copilot.dll" "C:\Users\Peter\Documents\Prepar3D v4 Add-ons\Copilot for FSLabs"
copy "x64\Release\Copilot.dll" "Prepar3D vx Add-ons\Copilot for FSLabs"