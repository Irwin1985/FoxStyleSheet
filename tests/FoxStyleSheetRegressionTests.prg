*-- FoxStyleSheetRegressionTests.prg - one test per defect found in the 2026-10-03 review,
*-- plus the integration test that applies the themes to a real (hidden) form.
*-- Run from the repository folder: foxproof run --prg tests\FoxStyleSheetRegressionTests.prg

#DEFINE FSS_PRG "foxstylesheet.prg"

* ============================================================ *
* Events reach subclassed controls
* ============================================================ *
DEFINE CLASS TestSubclassEvents AS Custom

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
	ENDPROC

	*-- Defect 1: TextBox.onGotFocus was bound to a subclassed TextBox but never applied
	PROCEDURE Test_ClassEventReachesSubclassedControl() HELP [Fact, Trait("Category", "Events")]
		LOCAL loForm, loFss
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("TextBox.onGotFocus {" + CHR(13) + "  backColor = rgb(1, 2, 3)" + CHR(13) + "}", loForm)
		RAISEEVENT(loForm.txtSub, "GotFocus")
		__assert.Equal(RGB(1, 2, 3), loForm.txtSub.BackColor)
		RAISEEVENT(loForm.txtName, "GotFocus")
		__assert.Equal(RGB(1, 2, 3), loForm.txtName.BackColor)
	ENDPROC

	PROCEDURE Test_SelectorByOwnClassName() HELP [Fact, Trait("Category", "Events")]
		LOCAL loForm, loFss
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("ProbeTextBox.onGotFocus {" + CHR(13) + "  backColor = rgb(4, 5, 6)" + CHR(13) + "}", loForm)
		RAISEEVENT(loForm.txtSub, "GotFocus")
		__assert.Equal(RGB(4, 5, 6), loForm.txtSub.BackColor)
		RAISEEVENT(loForm.txtName, "GotFocus")
		__assert.False(loForm.txtName.BackColor == RGB(4, 5, 6), "a plain TextBox is not a ProbeTextBox")
	ENDPROC

ENDDEFINE

* ============================================================ *
* Where the library lives
* ============================================================ *
DEFINE CLASS TestPaths AS Custom

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
	ENDPROC

	*-- Defect 2: SYS(16) in a method has a "PROCEDURE ..." prefix (rule 41)
	PROCEDURE Test_PrgPathIsTheLibraryFolder() HELP [Fact, Trait("Category", "Paths")]
		LOCAL loFss
		loFss = CREATEOBJECT("FoxStyleSheet")
		__assert.False("PROCEDURE" $ UPPER(loFss.cPrgPath), loFss.cPrgPath)
		__assert.Equal(UPPER(ADDBS(JUSTPATH(FULLPATH(FSS_PRG)))), UPPER(loFss.cPrgPath))
	ENDPROC

ENDDEFINE

* ============================================================ *
* The "_" property runs code
* ============================================================ *
DEFINE CLASS TestRunCode AS Custom

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
	ENDPROC

	*-- Defect 3: "this" was replaced inside "thisform", and the error escaped link()
	PROCEDURE Test_ThisformInFormSelector() HELP [Fact, Trait("Category", "RunCode")]
		LOCAL loForm, loFss, loEx
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		TRY
			loFss.link("form {" + CHR(13) + "  _ = thisform.Tag = 'set by fss'" + CHR(13) + "}", loForm)
		CATCH TO loEx
			__assert.Fail("link raised " + TRANSFORM(loEx.ErrorNo) + ": " + loEx.Message)
		ENDTRY
		__assert.Equal("set by fss", loForm.Tag)
	ENDPROC

	PROCEDURE Test_ThisInControlSelector() HELP [Fact, Trait("Category", "RunCode")]
		LOCAL loForm, loFss
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("TextBox {" + CHR(13) + "  _ = this.Tag = 'mine'" + CHR(13) + "}", loForm)
		__assert.Equal("mine", loForm.txtName.Tag)
	ENDPROC

	PROCEDURE Test_ThisInsideAStringIsKept() HELP [Fact, Trait("Category", "RunCode")]
		LOCAL loForm, loFss
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("TextBox {" + CHR(13) + "  _ = this.ToolTipText = 'this field'" + CHR(13) + "}", loForm)
		__assert.Equal("this field", loForm.txtName.ToolTipText)
	ENDPROC

	*-- A failing line is recorded, it does not raise out of link()
	PROCEDURE Test_FailingCodeDoesNotRaise() HELP [Fact, Trait("Category", "RunCode")]
		LOCAL loForm, loFss, loEx
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		TRY
			loFss.link("form {" + CHR(13) + "  _ = NoSuchFunction123()" + CHR(13) + "}", loForm)
		CATCH TO loEx
			__assert.Fail("link raised " + TRANSFORM(loEx.ErrorNo) + ": " + loEx.Message)
		ENDTRY
		__assert.Equal(1, loFss.nErrors)
		__assert.True("NOSUCHFUNCTION123" $ UPPER(loFss.cLastError), loFss.cLastError)
	ENDPROC

ENDDEFINE

* ============================================================ *
* Parser
* ============================================================ *
DEFINE CLASS TestParser AS Custom

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
	ENDPROC

	*-- Defect 4: the selector list needed a space after the comma
	PROCEDURE Test_SelectorListWithoutSpaces() HELP [Fact, Trait("Category", "Parser")]
		LOCAL loForm, loFss
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("TextBox,EditBox {" + CHR(13) + "  backColor = rgb(1, 2, 3)" + CHR(13) + "}", loForm)
		__assert.Equal(RGB(1, 2, 3), loForm.txtName.BackColor)
		__assert.Equal(RGB(1, 2, 3), loForm.edtNotes.BackColor)
	ENDPROC

	*-- Defect 4: and a space before the brace
	PROCEDURE Test_SelectorWithoutSpaceBeforeBrace() HELP [Fact, Trait("Category", "Parser")]
		LOCAL loForm, loFss
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("form{" + CHR(13) + "  backColor = rgb(4, 5, 6)" + CHR(13) + "}", loForm)
		__assert.Equal(RGB(4, 5, 6), loForm.BackColor)
	ENDPROC

	PROCEDURE Test_OneLineBlock() HELP [Fact, Trait("Category", "Parser")]
		LOCAL loForm, loFss
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("form { backColor = rgb(7, 8, 9) }", loForm)
		__assert.Equal(RGB(7, 8, 9), loForm.BackColor)
	ENDPROC

	*-- The parser does not need VBScript.RegExp, which Microsoft is retiring
	PROCEDURE Test_NoVBScriptDependency() HELP [Fact, Trait("Category", "Parser")]
		__assert.False("VBSCRIPT.REGEXP" $ UPPER(FILETOSTR(FSS_PRG)))
	ENDPROC

	*-- Defect 5: a missing theme file was taken as the theme text and nothing happened
	PROCEDURE Test_MissingThemeFileIsReported() HELP [Fact, Trait("Category", "Parser")]
		LOCAL loForm, loFss, llOk
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		llOk = loFss.link("C:\no-such-folder\Wrod.fss", loForm)
		__assert.False(llOk)
		__assert.Equal(1, loFss.nErrors)
		__assert.True("WROD.FSS" $ UPPER(loFss.cLastError), loFss.cLastError)
	ENDPROC

ENDDEFINE

* ============================================================ *
* Optional features: page backgrounds and Codejock
* ============================================================ *
DEFINE CLASS TestOptional AS Custom

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
	ENDPROC

	*-- A solid page background without System.app: a BMP written by the library
	PROCEDURE Test_PageBackgroundWithoutSystemApp() HELP [Fact, Trait("Category", "Optional")]
		LOCAL loForm, loFss, lcPicture, lcBmp, loPicture
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("page {" + CHR(13) + "  picture = rgb(10, 20, 30)" + CHR(13) + "}", loForm)
		lcPicture = loForm.pgf.Page1.Picture
		__assert.Equal(0, loFss.nErrors, loFss.cLastError)
		__assert.Equal("BMP", UPPER(JUSTEXT(lcPicture)), lcPicture)
		lcBmp = FILETOSTR(lcPicture)
		__assert.Equal("BM", LEFT(lcBmp, 2))
		__assert.Equal(LEN(lcBmp), CTOBIN(SUBSTR(lcBmp, 3, 4), "4RS"), "the size in the header")
		__assert.Equal(CHR(30) + CHR(20) + CHR(10), SUBSTR(lcBmp, 55, 3), "the first pixel, in BGR")
		loPicture = LOADPICTURE(lcPicture)
		__assert.IsObject(loPicture)
	ENDPROC

	PROCEDURE Test_NoSystemAppDependency() HELP [Fact, Trait("Category", "Optional")]
		__assert.False("SYSTEM.APP" $ UPPER(FILETOSTR(FSS_PRG)))
	ENDPROC

	*-- Bring your own Codejock: the ProgId is a property
	PROCEDURE Test_CodejockProgIdIsConfigurable() HELP [Fact, Trait("Category", "Optional")]
		LOCAL loFss
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.cCodejockProgId = "No.Such.Component.1"
		__assert.False(loFss.IsCodejockAvailable())
		loFss.cCodejockProgId = "Scripting.FileSystemObject"
		__assert.True(loFss.IsCodejockAvailable())
	ENDPROC

ENDDEFINE

* ============================================================ *
* Log
* ============================================================ *
DEFINE CLASS TestLog AS Custom

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
	ENDPROC

	*-- Every link() wrote about 26 INFO lines to a log that never shrinks
	PROCEDURE Test_LinkWritesNoInfoByDefault() HELP [Fact, Trait("Category", "Log")]
		LOCAL loForm, loFss, lnBefore
		loForm = MakeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		lnBefore = LogLines(loFss.cPath + "FoxStyleSheet.log", "| INFO")
		loFss.link("themes\Word.fss", loForm)
		__assert.Equal(lnBefore, LogLines(loFss.cPath + "FoxStyleSheet.log", "| INFO"))
	ENDPROC

	*-- The log never shrank: past nMaxLogBytes it moves to .old and starts again
	PROCEDURE Test_LogIsCapped() HELP [Fact, Trait("Category", "Log")]
		LOCAL loLogger, lcFile, lnI, laInfo[1]
		lcFile = ADDBS(SYS(2023)) + SYS(2015) + ".log"
		loLogger = CREATEOBJECT("FssLogger")
		loLogger.SetLogFile(lcFile)
		loLogger.nMaxLogBytes = 500
		FOR lnI = 1 TO 50
			loLogger.LogWarning("line " + TRANSFORM(lnI) + " of a log that has to be capped")
		NEXT
		__assert.True(ADIR(laInfo, lcFile) = 1)
		__assert.True(laInfo[1, 2] <= 600, "size " + TRANSFORM(laInfo[1, 2]))
		__assert.True(FILE(FORCEEXT(lcFile, "old")), "the previous log is kept as .old")
		__assert.True("line 50 " $ FILETOSTR(lcFile), "the last line is in the current log")
		DELETE FILE (lcFile)
		DELETE FILE (FORCEEXT(lcFile, "old"))
	ENDPROC

	*-- Every line used to SET DATE, CENTURY and HOURS of the application and put them back
	PROCEDURE Test_LogLeavesDateSettingsAlone() HELP [Fact, Trait("Category", "Log")]
		LOCAL loLogger, lcFile, lcMark
		lcFile = ADDBS(SYS(2023)) + SYS(2015) + ".log"
		lcMark = SET("MARK")
		SET MARK TO "|"
		loLogger = CREATEOBJECT("FssLogger")
		loLogger.SetLogFile(lcFile)
		loLogger.LogWarning("dates")
		__assert.Equal("|", SET("MARK"))
		SET MARK TO (lcMark)
		DELETE FILE (lcFile)
	ENDPROC

	*-- A logger without a file wrote FoxStyleSheet.log into the current folder
	PROCEDURE Test_LoggerDoesNotWriteToCurrentFolder() HELP [Fact, Trait("Category", "Log")]
		LOCAL loLogger, lnBefore
		lnBefore = LogLines(FULLPATH("FoxStyleSheet.log"), "")
		loLogger = CREATEOBJECT("FssLogger")
		loLogger.LogWarning("regression test")
		__assert.Equal(lnBefore, LogLines(FULLPATH("FoxStyleSheet.log"), ""))
	ENDPROC

ENDDEFINE

* ============================================================ *
* The themes, applied to a real form
* ============================================================ *
DEFINE CLASS TestThemesOnAForm AS Custom

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
	ENDPROC

	PROCEDURE Test_EveryThemeAppliesCleanly() HELP [Fact, Trait("Category", "Themes")]
		LOCAL laThemes[1], lnThemes, lnI, loForm, loFss, lnBefore
		lnThemes = ADIR(laThemes, "themes\*.fss")
		__assert.True(lnThemes >= 14, "themes found: " + TRANSFORM(lnThemes))
		FOR lnI = 1 TO lnThemes
			loForm = MakeForm()
			loFss = CREATEOBJECT("FoxStyleSheet")
			lnBefore = LogLines(loFss.cPath + "FoxStyleSheet.log", "| WARNING")
			loFss.link("themes\" + laThemes[lnI, 1], loForm)
			__assert.Equal(0, loFss.nErrors, laThemes[lnI, 1] + ": " + loFss.cLastError)
			__assert.Equal(lnBefore, LogLines(loFss.cPath + "FoxStyleSheet.log", "| WARNING"), laThemes[lnI, 1] + " logged warnings")
			__assert.False(loForm.BackColor == RGB(240, 240, 240), laThemes[lnI, 1] + " did not style the form")
			__assert.Equal("Segoe UI", loForm.txtName.FontName, laThemes[lnI, 1])
			loFss = .NULL.
			loForm = .NULL.
		NEXT
	ENDPROC

ENDDEFINE

* ============================================================ *
* Helpers
* ============================================================ *
FUNCTION MakeForm
	LOCAL loForm
	loForm = CREATEOBJECT("Form")
	loForm.AddObject("txtName", "TextBox")
	loForm.AddObject("txtSub", "ProbeTextBox")
	loForm.AddObject("edtNotes", "EditBox")
	loForm.AddObject("cmdOk", "CommandButton")
	loForm.AddObject("lblName", "Label")
	loForm.AddObject("chkActive", "CheckBox")
	loForm.AddObject("cboKind", "ComboBox")
	loForm.AddObject("pgf", "PageFrame")
	loForm.pgf.PageCount = 2
	RETURN loForm
ENDFUNC

*-- Lines of a log file that contain tcText ("" counts them all)
FUNCTION LogLines
	LPARAMETERS tcFile, tcText
	LOCAL laLines[1], lnLines, lnI, lnCount
	IF !FILE(tcFile)
		RETURN 0
	ENDIF
	lnLines = ALINES(laLines, FILETOSTR(tcFile))
	IF EMPTY(tcText)
		RETURN lnLines
	ENDIF
	lnCount = 0
	FOR lnI = 1 TO lnLines
		IF tcText $ laLines[lnI]
			lnCount = lnCount + 1
		ENDIF
	NEXT
	RETURN lnCount
ENDFUNC

DEFINE CLASS ProbeTextBox AS TextBox
ENDDEFINE
