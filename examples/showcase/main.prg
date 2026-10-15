*==============================================================================
* FoxStyleSheet + VFPStretch showcase
* One screen that takes a theme (light or dark, as Windows is, and a sun or
* moon button to switch), stretches with its window, and opens a folder
* picker (GetDirPro) in the same theme.
*
*   foxpack restore           <- puts the two libraries in lib\
*   DO main.prg               <- from the IDE
*   showcase.exe              <- after building showcase.pjx
*==============================================================================
Local lcFolder, loForm
lcFolder = Justpath(Sys(16))
If !Empty(m.lcFolder) And Directory(m.lcFolder)
	Cd (m.lcFolder)
Endif

Set Talk Off
Set Safety Off
Set Deleted On
Set Century On

* As an EXE the application is the form: no FoxPro main window behind it.
If _vfp.StartMode > 0
	_Screen.Visible = .F.
Endif

Set Procedure To lib\foxstylesheet\foxstylesheet.prg, lib\vfpstretch\vfpstretch.prg, lib\getdirpro\getdirpro.prg, frmcustomers.prg Additive

If Type("_Screen.oVfpStretch") != "O"
	=Addproperty(_Screen, "oVfpStretch", Createobject("vfpStretch"))
Endif

loForm = Createobject("frmCustomers")
loForm.Show()
* the form ends the loop when it closes (frmCustomers.Destroy)
Read Events
Return
