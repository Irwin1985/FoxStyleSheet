*-- FoxStyleSheetThemeTests.prg - 2.2.0: switching themes on a live form, the
*-- light and dark themes, the sun and moon icons, FssThemeToggle and the title bar.
*-- Run from the repository folder: foxproof run --prg tests\FoxStyleSheetThemeTests.prg

#DEFINE FSS_PRG "foxstylesheet.prg"

* ============================================================ *
* A second link() changes the theme
* ============================================================ *
DEFINE CLASS TestRelink AS Custom

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
	ENDPROC

	PROCEDURE Test_SecondLinkReplacesTheStaticStyles() HELP [Fact, Trait("Category", "Relink")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("form {" + CHR(13) + "  backColor = rgb(1, 1, 1)" + CHR(13) + "}", loForm)
		loFss.link("form {" + CHR(13) + "  backColor = rgb(2, 2, 2)" + CHR(13) + "}", loForm)
		__assert.Equal(RGB(2, 2, 2), loForm.BackColor)
	ENDPROC

	*-- the event styles of the first theme must not survive the second one
	PROCEDURE Test_SecondLinkDropsTheOldEventStyles() HELP [Fact, Trait("Category", "Relink")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("TextBox.onGotFocus {" + CHR(13) + "  backColor = rgb(9, 9, 9)" + CHR(13) + "}", loForm)
		loFss.link("TextBox {" + CHR(13) + "  backColor = rgb(5, 5, 5)" + CHR(13) + "}", loForm)
		RAISEEVENT(loForm.txtName, "GotFocus")
		__assert.Equal(RGB(5, 5, 5), loForm.txtName.BackColor, "the GotFocus of the first theme still ran")
	ENDPROC

	PROCEDURE Test_SecondLinkDropsTheOldNamedEventStyles() HELP [Fact, Trait("Category", "Relink")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link(".txtName.onGotFocus {" + CHR(13) + "  backColor = rgb(9, 9, 9)" + CHR(13) + "}", loForm)
		loFss.link("form {" + CHR(13) + "  backColor = rgb(5, 5, 5)" + CHR(13) + "}", loForm)
		loForm.txtName.BackColor = RGB(7, 7, 7)
		RAISEEVENT(loForm.txtName, "GotFocus")
		__assert.Equal(RGB(7, 7, 7), loForm.txtName.BackColor)
	ENDPROC

	*-- an event style must run once, not once per link()
	PROCEDURE Test_EventsAreNotBoundTwice() HELP [Fact, Trait("Category", "Relink")]
		LOCAL loForm, loFss, lcTheme
		loForm = ThemeForm()
		loForm.txtName.Tag = ""
		lcTheme = "TextBox.onGotFocus {" + CHR(13) + "  _ = this.Tag = this.Tag + 'x'" + CHR(13) + "}"
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link(lcTheme, loForm)
		loFss.link(lcTheme, loForm)
		RAISEEVENT(loForm.txtName, "GotFocus")
		__assert.Equal("x", loForm.txtName.Tag)
	ENDPROC

	PROCEDURE Test_ResourcesOfTheOldThemeAreGone() HELP [Fact, Trait("Category", "Relink")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loForm.Tag = ""
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("_res_ {" + CHR(13) + "  word = 'old'" + CHR(13) + "}" + CHR(13) + "form {" + CHR(13) + "  _ = thisform.Tag = $word" + CHR(13) + "}", loForm)
		loFss.link("form {" + CHR(13) + "  _ = thisform.Tag = '$word'" + CHR(13) + "}", loForm)
		__assert.Equal("$word", loForm.Tag)
	ENDPROC

	PROCEDURE Test_cThemeIsTheLastTheme() HELP [Fact, Trait("Category", "Relink")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("light", loForm)
		__assert.Equal("light", loFss.cTheme)
		loFss.link("dark", loForm)
		__assert.Equal("dark", loFss.cTheme)
	ENDPROC

	PROCEDURE Test_FssEngineOfFindsTheEngine() HELP [Fact, Trait("Category", "Relink")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		__assert.True(ISNULL(FssEngineOf(loForm)), "no theme yet")
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("light", loForm)
		__assert.True(FssEngineOf(loForm) == loFss, "the engine link() hung from the form")
	ENDPROC

ENDDEFINE

* ============================================================ *
* The light and dark themes
* ============================================================ *
DEFINE CLASS TestLightDark AS Custom

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
	ENDPROC

	PROCEDURE Test_LightAndDarkAreBuiltIn() HELP [Fact, Trait("Category", "LightDark")]
		__assert.True(",light," $ "," + LOWER(FssBuiltInThemeNames()) + ",")
		__assert.True(",dark," $ "," + LOWER(FssBuiltInThemeNames()) + ",")
	ENDPROC

	PROCEDURE Test_LightLinksWithoutErrors() HELP [Fact, Trait("Category", "LightDark")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		__assert.True(loFss.link("light", loForm), loFss.cLastError)
		__assert.Equal(RGB(243, 243, 243), loForm.BackColor)
	ENDPROC

	PROCEDURE Test_DarkLinksWithoutErrors() HELP [Fact, Trait("Category", "LightDark")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		__assert.True(loFss.link("dark", loForm), loFss.cLastError)
		__assert.Equal(RGB(32, 32, 32), loForm.BackColor)
		__assert.Equal(RGB(240, 240, 240), loForm.txtName.ForeColor)
	ENDPROC

	*-- dark then light must look exactly like light alone
	PROCEDURE Test_DarkThenLightIsLight() HELP [Fact, Trait("Category", "LightDark")]
		LOCAL loLight, loSwitched, loFss1, loFss2
		loLight = ThemeForm()
		loFss1 = CREATEOBJECT("FoxStyleSheet")
		loFss1.link("light", loLight)
		loSwitched = ThemeForm()
		loFss2 = CREATEOBJECT("FoxStyleSheet")
		loFss2.link("dark", loSwitched)
		loFss2.link("light", loSwitched)
		__assert.Equal(StyleSnapshot(loLight), StyleSnapshot(loSwitched))
	ENDPROC

	*-- the twins must set the same properties, or a switch leaves colours behind
	PROCEDURE Test_LightAndDarkSetTheSameProperties() HELP [Fact, Trait("Category", "LightDark")]
		__assert.Equal(ThemeShape(FssBuiltInTheme("light")), ThemeShape(FssBuiltInTheme("dark")))
	ENDPROC

	PROCEDURE Test_SystemThemeIsLightOrDark() HELP [Fact, Trait("Category", "LightDark")]
		__assert.True(INLIST(FssSystemTheme(), "light", "dark"), FssSystemTheme())
	ENDPROC

	*-- a form that is not shown has a window, but the title bar must never fail link()
	PROCEDURE Test_TitleBarPropertiesNeverFail() HELP [Fact, Trait("Category", "LightDark")]
		LOCAL loForm, loFss
		loForm = CREATEOBJECT("TopLevelForm")
		loFss = CREATEOBJECT("FoxStyleSheet")
		__assert.True(loFss.link("form {" + CHR(13) + "  darkTitleBar = .t." + CHR(13) + ;
			"  titleBarColor = rgb(10, 20, 30)" + CHR(13) + "  titleBarTextColor = -1" + CHR(13) + "}", loForm), loFss.cLastError)
	ENDPROC

ENDDEFINE

* ============================================================ *
* Icons and FssThemeToggle
* ============================================================ *
DEFINE CLASS TestIcons AS Custom

	cFile = ""

	PROCEDURE SetUp
		SET PROCEDURE TO (FSS_PRG) ADDITIVE
		THIS.cFile = ADDBS(SYS(2023)) + "fss_icon_test.bmp"
	ENDPROC

	PROCEDURE TearDown
		IF FILE(THIS.cFile)
			DELETE FILE (THIS.cFile)
		ENDIF
	ENDPROC

	PROCEDURE Test_SunIsInkInTheMiddleAndBackInTheCorner() HELP [Fact, Trait("Category", "Icons")]
		LOCAL loFss
		loFss = CREATEOBJECT("FoxStyleSheet")
		__assert.True(loFss.DrawIcon(THIS.cFile, "sun", 20, RGB(200, 100, 0), RGB(10, 20, 30)))
		__assert.Equal(54 + 20 * 60, LEN(FILETOSTR(THIS.cFile)), "a 20 x 20 24-bit BMP")
		__assert.Equal(RGB(200, 100, 0), BmpPixel(THIS.cFile, 10, 10), "the centre")
		__assert.Equal(RGB(10, 20, 30), BmpPixel(THIS.cFile, 0, 0), "the corner")
	ENDPROC

	*-- the bite of the moon is in its upper right: background there, ink lower left
	PROCEDURE Test_MoonHasItsBite() HELP [Fact, Trait("Category", "Icons")]
		LOCAL loFss
		loFss = CREATEOBJECT("FoxStyleSheet")
		__assert.True(loFss.DrawIcon(THIS.cFile, "moon", 20, RGB(255, 255, 255), RGB(0, 0, 0)))
		__assert.Equal(RGB(0, 0, 0), BmpPixel(THIS.cFile, 13, 7), "inside the bite")
		__assert.Equal(RGB(255, 255, 255), BmpPixel(THIS.cFile, 6, 12), "the crescent")
	ENDPROC

	PROCEDURE Test_UnknownIconIsRefused() HELP [Fact, Trait("Category", "Icons")]
		LOCAL loFss
		loFss = CREATEOBJECT("FoxStyleSheet")
		__assert.False(loFss.DrawIcon(THIS.cFile, "star", 20, 0, 0))
		__assert.False(FILE(THIS.cFile))
	ENDPROC

	PROCEDURE Test_IconPropertySetsThePicture() HELP [Fact, Trait("Category", "Icons")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loFss = CREATEOBJECT("FoxStyleSheet")
		__assert.True(loFss.link("CommandButton {" + CHR(13) + '  icon = "moon"' + CHR(13) + "}", loForm), loFss.cLastError)
		__assert.True("ICON_MOON_" $ UPPER(loForm.cmdOk.Picture), loForm.cmdOk.Picture)
		__assert.True(FILE(loForm.cmdOk.Picture))
	ENDPROC

	PROCEDURE Test_ToggleGoesToDarkAndBack() HELP [Fact, Trait("Category", "Icons")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loForm.NewObject("cmdTheme", "FssThemeToggle", FSS_PRG)
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("light", loForm)
		__assert.True("ICON_SUN_" $ UPPER(loForm.cmdTheme.Picture), "light shows the sun")
		__assert.Equal("dark", loForm.cmdTheme.Toggle())
		__assert.Equal(RGB(32, 32, 32), loForm.BackColor)
		__assert.True("ICON_MOON_" $ UPPER(loForm.cmdTheme.Picture), "dark shows the moon")
		__assert.Equal("light", loForm.cmdTheme.Toggle())
		__assert.Equal(RGB(243, 243, 243), loForm.BackColor)
	ENDPROC

	*-- a theme that does not know the toggle: the form decides, sun or moon
	PROCEDURE Test_ToggleUnderOtherThemesFollowsTheForm() HELP [Fact, Trait("Category", "Icons")]
		LOCAL loForm, loFss
		loForm = ThemeForm()
		loForm.NewObject("cmdTheme", "FssThemeToggle", FSS_PRG)
		loFss = CREATEOBJECT("FoxStyleSheet")
		loFss.link("Word", loForm)
		__assert.True("ICON_SUN_" $ UPPER(loForm.cmdTheme.Picture), "Word is light: " + loForm.cmdTheme.Picture)
		loFss.link("black", loForm)
		__assert.True("ICON_MOON_" $ UPPER(loForm.cmdTheme.Picture), "black is dark: " + loForm.cmdTheme.Picture)
		RAISEEVENT(loForm.cmdTheme, "MouseEnter", 0, 0, 0, 0)
		__assert.True("ICON_MOON_" $ UPPER(loForm.cmdTheme.Picture), "still a moon after the hover")
	ENDPROC

	PROCEDURE Test_ToggleWithoutAThemeLinksOne() HELP [Fact, Trait("Category", "Icons")]
		LOCAL loForm
		loForm = ThemeForm()
		loForm.NewObject("cmdTheme", "FssThemeToggle", FSS_PRG)
		__assert.Equal("dark", loForm.cmdTheme.Toggle())
		__assert.False(ISNULL(FssEngineOf(loForm)))
	ENDPROC

	PROCEDURE Test_ToggleTakesOtherThemes() HELP [Fact, Trait("Category", "Icons")]
		LOCAL loForm
		loForm = ThemeForm()
		loForm.NewObject("cmdTheme", "FssThemeToggle", FSS_PRG)
		loForm.cmdTheme.cLightTheme = "office-word-light"
		loForm.cmdTheme.cDarkTheme = "office-word-dark"
		__assert.Equal("office-word-dark", loForm.cmdTheme.Toggle())
		__assert.Equal("office-word-light", loForm.cmdTheme.Toggle())
	ENDPROC

ENDDEFINE

* ============================================================ *
* Helpers
* ============================================================ *
DEFINE CLASS TopLevelForm AS Form
	ShowWindow = 2
ENDDEFINE

FUNCTION ThemeForm
	LOCAL loForm
	loForm = CREATEOBJECT("Form")
	loForm.AddObject("txtName", "TextBox")
	loForm.AddObject("edtNotes", "EditBox")
	loForm.AddObject("cboKind", "ComboBox")
	loForm.AddObject("lstItems", "ListBox")
	loForm.AddObject("chkActive", "CheckBox")
	loForm.AddObject("lblName", "Label")
	loForm.AddObject("cmdOk", "CommandButton")
	loForm.cmdOk.Height = 30
	loForm.AddObject("cntCard", "Container")
	loForm.AddObject("pgf", "PageFrame")
	loForm.pgf.PageCount = 2
	loForm.AddObject("grd", "Grid")
	loForm.grd.ColumnCount = 2
	RETURN loForm
ENDFUNC

*-- The colours and fonts of every control, as one string
FUNCTION StyleSnapshot
	LPARAMETERS toContainer
	LOCAL lcOut, loControl, lcProps, lcProp, lnI
	lcOut = ""
	lcProps = "BackColor,ForeColor,BorderColor,FontName,ItemBackColor,ItemForeColor,SelectedItemBackColor,HighlightBackColor,GridLineColor,SpecialEffect,Picture"
	FOR lnI = 1 TO GETWORDCOUNT(lcProps, ",")
		lcProp = GETWORDNUM(lcProps, lnI, ",")
		IF PEMSTATUS(toContainer, lcProp, 5)
			lcOut = lcOut + toContainer.Name + "." + lcProp + "=" + TRANSFORM(EVALUATE("toContainer." + lcProp)) + ";"
		ENDIF
	ENDFOR
	IF PEMSTATUS(toContainer, "Objects", 5)
		FOR EACH loControl IN toContainer.Objects
			lcOut = lcOut + StyleSnapshot(loControl)
		ENDFOR
	ENDIF
	RETURN lcOut
ENDFUNC

*-- A theme without its values: the selectors and property names, in order
FUNCTION ThemeShape
	LPARAMETERS tcTheme
	LOCAL laLines[1], lnI, lcLine, lcOut
	lcOut = ""
	FOR lnI = 1 TO ALINES(laLines, tcTheme, 1)
		lcLine = laLines[lnI]
		DO CASE
		CASE LEFT(lcLine, 2) == "/*" OR LEFT(lcLine, 1) == "*" OR EMPTY(lcLine)
		CASE "{" $ lcLine OR "}" $ lcLine
			lcOut = lcOut + lcLine + CHR(10)
		CASE "=" $ lcLine
			lcOut = lcOut + ALLTRIM(LEFT(lcLine, AT("=", lcLine) - 1)) + CHR(10)
		ENDCASE
	ENDFOR
	RETURN lcOut
ENDFUNC

*-- The colour of the pixel (x, y) of a 24-bit BMP, counting from the top left
FUNCTION BmpPixel
	LPARAMETERS tcFile, tnX, tnY
	LOCAL lcBmp, lnWidth, lnHeight, lnRowBytes, lnOffset
	lcBmp = FILETOSTR(tcFile)
	lnWidth = CTOBIN(SUBSTR(lcBmp, 19, 4), "4RS")
	lnHeight = CTOBIN(SUBSTR(lcBmp, 23, 4), "4RS")
	lnRowBytes = CEILING(lnWidth * 3 / 4) * 4
	lnOffset = 54 + (lnHeight - 1 - tnY) * lnRowBytes + tnX * 3
	RETURN RGB(ASC(SUBSTR(lcBmp, lnOffset + 3, 1)), ASC(SUBSTR(lcBmp, lnOffset + 2, 1)), ASC(SUBSTR(lcBmp, lnOffset + 1, 1)))
ENDFUNC
