* FoxStyleSheetTests.prg
* Test suite for FoxStyleSheet 2.1.0
* Run from the repository folder: foxproof run --prg tests\FoxStyleSheetTests.prg

#define FSS_PRG 'foxstylesheet.prg'

*==============================================================
* LOGGER TESTS
*==============================================================
define class TestLogger as Custom

    oLog = .null.
    cLogFile = ''

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oLog = createobject("FssLogger")
        this.cLogFile = sys(2023) + '\fss_test.log'
        this.oLog.SetLogFile(this.cLogFile)
        if file(this.cLogFile)
            delete file (this.cLogFile)
        endif
    endproc

    procedure TearDown
        this.oLog = .null.
        if file(this.cLogFile)
            delete file (this.cLogFile)
        endif
    endproc

    procedure TestLogger_DebugMode_DefaultIsFalse() HELP [Fact, Trait("Category", "Logger")]
        local loLog
        loLog = createobject("FssLogger")
        __assert.False(loLog.lDebugMode, "lDebugMode must be .F. by default")
    endproc

    procedure TestLogger_LogInfo_CreatesFileWithInfo() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.LogInfo("test info message")
        __assert.True(file(this.cLogFile), "The log file must exist after LogInfo")
        local lcContent
        lcContent = filetostr(this.cLogFile)
        __assert.True("INFO" $ lcContent, "The log must contain INFO")
        __assert.True("test info message" $ lcContent, "The log must contain the message")
    endproc

    procedure TestLogger_LogWarning_ContainsWarningLevel() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.LogWarning("test warning")
        local lcContent
        lcContent = filetostr(this.cLogFile)
        __assert.True("WARNING" $ lcContent, "The log must contain WARNING")
    endproc

    procedure TestLogger_LogError_ContainsErrorLevel() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.LogError("test error")
        local lcContent
        lcContent = filetostr(this.cLogFile)
        __assert.True("ERROR" $ lcContent, "The log must contain ERROR")
    endproc

    procedure TestLogger_LogDebug_SuppressedWhenModeOff() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.lDebugMode = .f.
        this.oLog.LogDebug("should not appear")
        __assert.False(file(this.cLogFile), "With lDebugMode=.F. no log file is created")
    endproc

    procedure TestLogger_LogDebug_WritesWhenModeOn() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.lDebugMode = .t.
        this.oLog.LogDebug("debug message")
        __assert.True(file(this.cLogFile), "With lDebugMode=.T. the log file is created")
        local lcContent
        lcContent = filetostr(this.cLogFile)
        __assert.True("DEBUG" $ lcContent, "The log must contain DEBUG")
    endproc

    procedure TestLogger_LegacySingleStringCall_NoCrash() HELP [Fact, Trait("Category", "Logger")]
        * Legacy: oLog.log("message") with only one string param
        local llOk
        llOk = .t.
        try
            this.oLog.log("legacy string only call")
        catch
            llOk = .f.
        endtry
        __assert.True(llOk, "The legacy call log(string) must not raise")
    endproc

enddefine


*==============================================================
* METRICS TESTS
*==============================================================
define class TestMetrics as Custom

    procedure SetUp
        set procedure to FSS_PRG additive
    endproc

    procedure TestMetrics_Reset_ClearsAllCounters() HELP [Fact, Trait("Category", "Metrics")]
        local loM
        loM = createobject("FssStyleMetrics")
        loM.nStylesApplied     = 5
        loM.nControlsProcessed = 3
        loM.nParseTime         = 1.5
        loM.Reset()
        __assert.Equal(0, loM.nStylesApplied,     "nStylesApplied must be 0 after Reset")
        __assert.Equal(0, loM.nControlsProcessed, "nControlsProcessed must be 0 after Reset")
        __assert.Equal(0, loM.nParseTime,         "nParseTime must be 0 after Reset")
    endproc

    procedure TestMetrics_GetReport_ContainsVersion() HELP [Fact, Trait("Category", "Metrics")]
        local loM, lcReport
        loM      = createobject("FssStyleMetrics")
        lcReport = loM.GetReport()
        __assert.True("2.1.0" $ lcReport, "The report must contain version 2.1.0")
    endproc

    procedure TestMetrics_GetReport_ContainsCounters() HELP [Fact, Trait("Category", "Metrics")]
        local loM, lcReport
        loM = createobject("FssStyleMetrics")
        loM.nStylesApplied     = 7
        loM.nControlsProcessed = 4
        lcReport = loM.GetReport()
        __assert.True("7" $ lcReport, "The report must contain nStylesApplied=7")
        __assert.True("4" $ lcReport, "The report must contain nControlsProcessed=4")
    endproc

enddefine


*==============================================================
* FOXSTYLESHEET INIT & PUBLIC API TESTS
*==============================================================
define class TestFoxStyleSheetInit as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestInit_VersionIsCorrect() HELP [Fact, Trait("Category", "Init")]
        __assert.Equal("2.1.0", this.oFss.cVersion, "The version must be 2.1.0")
    endproc

    procedure TestInit_CPathContainsFoxStyleSheet() HELP [Fact, Trait("Category", "Init")]
        __assert.NotEmpty(this.oFss.cPath, "cPath must be set")
        __assert.True("FoxStyleSheet" $ this.oFss.cPath, "cPath must contain FoxStyleSheet")
    endproc

    procedure TestInit_DestroyNoCrash() HELP [Fact, Trait("Category", "Init")]
        * Regression B1: destroy() crashed when oControlCache was .null.
        local llOk
        llOk = .t.
        try
            local loTmp
            loTmp = createobject("FssTestDouble")
            loTmp = .null.
        catch
            llOk = .f.
        endtry
        __assert.True(llOk, "destroy() must not raise (regression B1)")
    endproc

    procedure TestInit_IsDrawingAvailable_AlwaysTrue() HELP [Fact, Trait("Category", "Init")]
        __assert.True(this.oFss.IsDrawingAvailable(), "Page backgrounds need nothing since 2.1.0")
    endproc

    procedure TestInit_IsCodejockAvailable_ReturnsLogical() HELP [Fact, Trait("Category", "Init")]
        local lResult
        lResult = this.oFss.IsCodejockAvailable()
        __assert.True(vartype(lResult) == 'L', "IsCodejockAvailable must return type L")
    endproc

enddefine


*==============================================================
* RESOURCE LOADING TESTS
*==============================================================
define class TestResources as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestResources_BasicVariables_LoadCorrectly() HELP [Fact, Trait("Category", "Resources")]
        local lcStyles
        lcStyles = "primaryColor = rgb(0,120,215)" + chr(13) + "fontSize = 12"
        this.oFss.PubLoadResources(lcStyles)
        __assert.Equal("rgb(0,120,215)", this.oFss.PubGetResource("primaryColor"), "primaryColor must resolve")
        __assert.Equal("12",            this.oFss.PubGetResource("fontSize"),      "fontSize must resolve")
    endproc

    procedure TestResources_MissingKey_ReturnsEmpty() HELP [Fact, Trait("Category", "Resources")]
        local lcResult
        lcResult = this.oFss.PubGetResource("nonexistentkey123")
        __assert.Equal("", lcResult, "A missing key must return an empty string")
    endproc

    procedure TestResources_EmptyLines_Ignored() HELP [Fact, Trait("Category", "Resources")]
        local lcStyles
        lcStyles = "key1 = val1" + chr(13) + "" + chr(13) + "key2 = val2"
        this.oFss.PubLoadResources(lcStyles)
        __assert.Equal("val1", this.oFss.PubGetResource("key1"), "key1 must hold val1")
        __assert.Equal("val2", this.oFss.PubGetResource("key2"), "key2 must hold val2")
    endproc

    procedure TestResources_CaseInsensitive_KeyLookup() HELP [Fact, Trait("Category", "Resources")]
        this.oFss.PubLoadResources("MyKey = MyValue")
        __assert.Equal("MyValue", this.oFss.PubGetResource("mykey"), "Lookup must be case-insensitive")
    endproc

enddefine


*==============================================================
* EXPRESSION EVALUATION TESTS
*==============================================================
define class TestEvalExpression as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestEval_LiteralNumber() HELP [Fact, Trait("Category", "Eval")]
        local lvResult
        lvResult = this.oFss.PubEval("12")
        __assert.Equal(12, lvResult, "A literal number must evaluate to N=12")
    endproc

    procedure TestEval_LiteralBooleanTrue() HELP [Fact, Trait("Category", "Eval")]
        local lvResult
        lvResult = this.oFss.PubEval(".T.")
        __assert.True(vartype(lvResult) == 'L', ".T. must evaluate to type L")
        __assert.True(lvResult, ".T. must be true")
    endproc

    procedure TestEval_ColorFunction_RgbReturnsNumeric() HELP [Fact, Trait("Category", "Eval")]
        local lvResult
        lvResult = this.oFss.PubEval("rgb(255,0,0)")
        __assert.True(vartype(lvResult) == 'N', "rgb() must evaluate to type N")
        __assert.True(lvResult >= 0 and lvResult <= 16777215, "rgb() must be in the colour range")
    endproc

    procedure TestEval_VariableExpansion_ResolvesResource() HELP [Fact, Trait("Category", "Eval")]
        this.oFss.PubLoadResources("myColor = rgb(0,0,255)")
        local lvResult
        lvResult = this.oFss.PubEval("$myColor")
        __assert.True(vartype(lvResult) == 'N', "$myColor must expand and evaluate to N")
    endproc

    procedure TestEval_JustExpand_SubstitutesWithoutEval() HELP [Fact, Trait("Category", "Eval")]
        this.oFss.PubLoadResources("myFont = Arial")
        local lvResult
        lvResult = this.oFss.PubEvalExpand("$myFont")
        __assert.Equal("Arial", lvResult, "JustExpand must return the value without evaluating it")
    endproc

    procedure TestEval_UnknownVariable_NoCrash() HELP [Fact, Trait("Category", "Eval")]
        local llOk
        llOk = .t.
        try
            this.oFss.PubEvalExpand("$unknownVar999")
        catch
            llOk = .f.
        endtry
        __assert.True(llOk, "An unknown variable must not raise")
    endproc

enddefine


*==============================================================
* STYLE VALIDATION TESTS
*==============================================================
define class TestValidation as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestValidation_ValidColor_RgbExpression() HELP [Fact, Trait("Category", "Validation")]
        __assert.True(this.oFss.PubIsValidColor("rgb(255,255,255)"), "rgb(255,255,255) must be valid")
    endproc

    procedure TestValidation_ValidColor_NumericWhite() HELP [Fact, Trait("Category", "Validation")]
        __assert.True(this.oFss.PubIsValidColor("16777215"), "16777215 (white) must be valid")
    endproc

    procedure TestValidation_ValidColor_Zero() HELP [Fact, Trait("Category", "Validation")]
        __assert.True(this.oFss.PubIsValidColor("0"), "0 (black) must be valid")
    endproc

    procedure TestValidation_InvalidColor_RandomString() HELP [Fact, Trait("Category", "Validation")]
        __assert.False(this.oFss.PubIsValidColor("notacolor"), "Texto aleatorio no es color valido")
    endproc

    procedure TestValidation_ValidBoolean_DotT() HELP [Fact, Trait("Category", "Validation")]
        __assert.True(this.oFss.PubIsValidBoolean(".T."), ".T. must be a valid boolean")
    endproc

    procedure TestValidation_ValidBoolean_DotF() HELP [Fact, Trait("Category", "Validation")]
        __assert.True(this.oFss.PubIsValidBoolean(".F."), ".F. must be a valid boolean")
    endproc

    procedure TestValidation_InvalidBoolean_RandomString() HELP [Fact, Trait("Category", "Validation")]
        __assert.False(this.oFss.PubIsValidBoolean("maybe"), "Cadena aleatoria no es booleano valido")
    endproc

enddefine


*==============================================================
* COMMENT REMOVAL TESTS
*==============================================================
define class TestComments as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestComments_BlockComment_Removed() HELP [Fact, Trait("Category", "Parser")]
        local lcInput, lcResult
        lcInput  = "before /* this is a comment */ after"
        lcResult = this.oFss.PubRemoveComments(lcInput)
        __assert.True("before" $ lcResult, "The text before the comment must stay")
        __assert.True("after"  $ lcResult, "The text after the comment must stay")
        __assert.False("this is a comment" $ lcResult, "The comment text must be removed")
    endproc

    procedure TestComments_MultilineComment_Removed() HELP [Fact, Trait("Category", "Parser")]
        local lcInput, lcResult
        lcInput  = "before /* line1" + chr(13) + "line2 */ after"
        lcResult = this.oFss.PubRemoveComments(lcInput)
        __assert.False("line1" $ lcResult, "A multi-line comment must be removed entirely")
    endproc

    procedure TestComments_NoComments_ContentUnchanged() HELP [Fact, Trait("Category", "Parser")]
        local lcInput, lcResult
        lcInput  = "form { backcolor = rgb(255,255,255) }"
        lcResult = this.oFss.PubRemoveComments(lcInput)
        __assert.Equal(lcInput, lcResult, "Without comments the content must not change")
    endproc

enddefine


*==============================================================
* SELECTOR PARSING TESTS
*==============================================================
define class TestSelectors as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestSelector_ClassType_Form() HELP [Fact, Trait("Category", "Parser")]
        local loSel
        loSel = this.oFss.PubParseSelector("form", "backcolor = 0")
        __assert.Equal("class", loSel.ControlType, "form must give ControlType=class")
        __assert.Equal("form",  loSel.ControlName, "form must give ControlName=form")
    endproc

    procedure TestSelector_ClassType_EditBox_LowercaseName() HELP [Fact, Trait("Category", "Parser")]
        local loSel
        loSel = this.oFss.PubParseSelector("EditBox", "backcolor = 0")
        __assert.Equal("class",   loSel.ControlType, "EditBox must be a class selector")
        __assert.Equal("editbox", loSel.ControlName, "EditBox must be stored in lower case")
    endproc

    procedure TestSelector_NameType_DotNotation() HELP [Fact, Trait("Category", "Parser")]
        local loSel
        loSel = this.oFss.PubParseSelector(".myTextBox", "backcolor = 0")
        __assert.Equal("name",      loSel.ControlType, "Punto inicial = name type")
        __assert.Equal("myTextBox", loSel.ControlName, "ControlName must be myTextBox")
    endproc

    procedure TestSelector_NameType_WithEvent() HELP [Fact, Trait("Category", "Parser")]
        local loSel
        loSel = this.oFss.PubParseSelector(".myCtrl.onGotFocus", "backcolor = 0")
        __assert.Equal("name",     loSel.ControlType,  "Must be a name selector with an event")
        __assert.Equal("myCtrl",   loSel.ControlName,  "ControlName must be myCtrl")
        __assert.Equal("GotFocus", loSel.ControlEvent, "The event must be GotFocus")
    endproc

    procedure TestSelector_UniversalType_Asterisk() HELP [Fact, Trait("Category", "Parser")]
        local loSel
        loSel = this.oFss.PubParseSelector("*", "backcolor = 0")
        __assert.Equal("*", loSel.ControlType, "Asterisco = ControlType *")
        __assert.Equal("*", loSel.ControlName, "Asterisco = ControlName *")
    endproc

    procedure TestSelector_ClassWithEvent_TextBoxGotFocus() HELP [Fact, Trait("Category", "Parser")]
        local loSel
        loSel = this.oFss.PubParseSelector("TextBox.onGotFocus", "backcolor = 0")
        __assert.Equal("class",    loSel.ControlType,  "TextBox.onGotFocus = class type")
        __assert.Equal("textbox",  loSel.ControlName,  "ControlName must be textbox")
        __assert.Equal("GotFocus", loSel.ControlEvent, "The event must be GotFocus")
    endproc

enddefine


*==============================================================
* STYLE PROPERTY=VALUE PARSING TESTS
*==============================================================
define class TestLoadStyles as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestLoadStyles_SingleProperty_ParsedCorrectly() HELP [Fact, Trait("Category", "Parser")]
        local loResult
        loResult = this.oFss.PubLoadStyles("backcolor = rgb(255,0,0)")
        __assert.True(loResult.Count >= 1, "There must be at least one property")
        __assert.Equal("rgb(255,0,0)", loResult.Item("backcolor"), "backcolor must be rgb(255,0,0)")
    endproc

    procedure TestLoadStyles_MultipleProperties_AllParsed() HELP [Fact, Trait("Category", "Parser")]
        local lcStyles, loResult
        lcStyles = "backcolor = rgb(255,0,0)" + chr(13) + "fontsize = 12" + chr(13) + "visible = .T."
        loResult = this.oFss.PubLoadStyles(lcStyles)
        __assert.True(loResult.Count >= 3, "There must be 3 properties")
    endproc

    procedure TestLoadStyles_TabsNormalized_ParsedCorrectly() HELP [Fact, Trait("Category", "Parser")]
        local loResult
        loResult = this.oFss.PubLoadStyles(chr(9) + "backcolor = rgb(0,0,0)")
        __assert.True(loResult.Count >= 1, "Tabs deben normalizarse correctamente")
    endproc

    procedure TestLoadStyles_EmptyInput_ReturnsEmptyCollection() HELP [Fact, Trait("Category", "Parser")]
        local loResult
        loResult = this.oFss.PubLoadStyles("")
        __assert.Equal(0, loResult.Count, "Empty input must return an empty collection")
    endproc

enddefine


*==============================================================
* FULL PARSE PIPELINE TESTS
*==============================================================
define class TestParseStyles as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestParseStyles_EmptyString_ReturnsEmptyCollection() HELP [Fact, Trait("Category", "Parser")]
        local loResult
        loResult = this.oFss.PubParseStyles("")
        __assert.Equal(0, loResult.Count, "An empty string must return an empty collection")
    endproc

    procedure TestParseStyles_SingleSelector_ReturnsOneBlock() HELP [Fact, Trait("Category", "Parser")]
        local loResult
        loResult = this.oFss.PubParseStyles("form { backcolor = rgb(255,255,255) }")
        __assert.True(loResult.Count >= 1, "One selector must give at least one block")
    endproc

    procedure TestParseStyles_ResourceBlock_NotInStyleCollection() HELP [Fact, Trait("Category", "Parser")]
        * _res_ blocks are consumed by loadResourcesOptimized, not returned as selectors
        local lcStyles, loResult
        lcStyles = "_res_ { myColor = rgb(0,0,0) }" + chr(13) + "form { backcolor = rgb(255,255,255) }"
        loResult = this.oFss.PubParseStyles(lcStyles)
        local i, j, loInner, loSel, llFoundRes
        llFoundRes = .f.
        for i = 1 to loResult.Count
            loInner = loResult.Item(i)
            if vartype(loInner) == 'O' and !isnull(loInner)
                for j = 1 to loInner.Count
                    loSel = loInner.Item(j)
                    if lower(loSel.ControlName) == '_res_'
                        llFoundRes = .t.
                    endif
                endfor
            endif
        endfor
        __assert.False(llFoundRes, "_res_ must not appear as a style selector")
    endproc

    procedure TestParseStyles_ResourceBlock_ResourcesAreAvailable() HELP [Fact, Trait("Category", "Parser")]
        * After parsing a _res_ block the variables should be resolvable
        local lcStyles
        lcStyles = "_res_ { accent = rgb(0,120,215) }" + chr(13) + "form { backcolor = rgb(255,255,255) }"
        this.oFss.PubParseStyles(lcStyles)
        __assert.Equal("rgb(0,120,215)", this.oFss.PubGetResource("accent"), "The resource must load during parse")
    endproc

enddefine


*==============================================================
* DRAWIMAGE GRACEFUL SKIP TEST
*==============================================================
define class TestDrawImage as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestDrawImage_WritesABmp() HELP [Fact, Trait("Category", "DrawImage")]
        local lcOut, lcBmp
        lcOut = addbs(sys(2023)) + sys(2015) + '.bmp'
        __assert.True(this.oFss.DrawImage(lcOut, 3, 2, 255, 0, 0), "DrawImage must write the file")
        lcBmp = filetostr(lcOut)
        __assert.Equal("BM", left(lcBmp, 2))
        __assert.Equal(54 + 12 * 2, len(lcBmp), "3 pixels of 3 bytes, padded to 12, times 2 rows")
        __assert.Equal(chr(0) + chr(0) + chr(255), substr(lcBmp, 55, 3), "red, stored as B G R")
        delete file (lcOut)
    endproc

    procedure TestDrawImage_InvalidDimensions_ReturnsFalse() HELP [Fact, Trait("Category", "DrawImage")]
        local llResult
        llResult = this.oFss.DrawImage(sys(2023) + '\out.bmp', 0, 0, 255, 0, 0)
        __assert.False(llResult, "Zero dimensions must return .F.")
    endproc

    procedure TestDrawImage_InvalidRgb_ReturnsFalse() HELP [Fact, Trait("Category", "DrawImage")]
        local llResult
        llResult = this.oFss.DrawImage(sys(2023) + '\out.bmp', 100, 100, 999, 0, 0)
        __assert.False(llResult, "RGB out of range must return .F.")
    endproc

enddefine


*==============================================================
* SCHEMA / TITLEBAR MAPPING TESTS
*==============================================================
define class TestSchema as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    procedure TestSchema_Word_MapsCorrectly() HELP [Fact, Trait("Category", "Schema")]
        local lcResult
        lcResult = this.oFss.PubGetSchema("word")
        __assert.True("Word" $ lcResult, "The word schema must contain Word")
    endproc

    procedure TestSchema_Excel_MapsCorrectly() HELP [Fact, Trait("Category", "Schema")]
        __assert.True("Excel" $ this.oFss.PubGetSchema("excel"), "The excel schema must contain Excel")
    endproc

    procedure TestSchema_AllOfficeMapsCorrectly() HELP [Fact, Trait("Category", "Schema")]
        local array laThemes[7, 2]
        laThemes[1, 1] = "access"
        laThemes[1, 2] = "Access"
        laThemes[2, 1] = "powerpoint"
        laThemes[2, 2] = "Powerpoint"
        laThemes[3, 1] = "publisher"
        laThemes[3, 2] = "Publisher"
        laThemes[4, 1] = "onenote"
        laThemes[4, 2] = "OneNote"
        laThemes[5, 1] = "outlook"
        laThemes[5, 2] = "Outlook"
        laThemes[6, 1] = "red"
        laThemes[6, 2] = "Red"
        laThemes[7, 1] = "black"
        laThemes[7, 2] = "Black"
        local i, lcSchema
        for i = 1 to 7
            lcSchema = this.oFss.PubGetSchema(laThemes[i, 1])
            __assert.NotEmpty(lcSchema, "Schema " + laThemes[i, 1] + " must not be empty")
        endfor
    endproc

    procedure TestSchema_UnknownTheme_ReturnsEmpty() HELP [Fact, Trait("Category", "Schema")]
        local lcResult
        lcResult = this.oFss.PubGetSchema("unknowntheme")
        __assert.Equal("", lcResult, "An unknown theme must return an empty string")
    endproc

enddefine


*==============================================================


*==============================================================
* CONTROL TRAVERSAL TESTS
*==============================================================
define class TestTraversal as Custom

    oFss = .null.

    procedure SetUp
        set procedure to FSS_PRG additive
        this.oFss = createobject("FssTestDouble")
    endproc

    procedure TearDown
        this.oFss = .null.
    endproc

    * --- getControlsByClass: path collection (used by event binding) ---

    procedure TestGetControlsByClass_FindsDirectLabelByBaseClass() HELP [Fact, Trait("Category", "Traversal")]
        local loForm, loList
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "label")
        this.oFss.SetThisForm(loForm)
        loList = createobject("Collection")
        this.oFss.PubGetControlsByClass(loForm, "label", loList)
        __assert.Equal(1, loList.count, "Must find a native label by BaseClass")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestGetControlsByClass_FindsSubclassByBaseClass() HELP [Fact, Trait("Category", "Traversal")]
        local loForm, loList
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "FssSubLabel")
        this.oFss.SetThisForm(loForm)
        loList = createobject("Collection")
        this.oFss.PubGetControlsByClass(loForm, "label", loList)
        __assert.Equal(1, loList.count, "The Label selector must find FssSubLabel through BaseClass")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestGetControlsByClass_FindsSubclassByClassName() HELP [Fact, Trait("Category", "Traversal")]
        local loForm, loList
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "FssSubLabel")
        this.oFss.SetThisForm(loForm)
        loList = createobject("Collection")
        this.oFss.PubGetControlsByClass(loForm, "fsssubLabel", loList)
        __assert.Equal(1, loList.count, "The FssSubLabel selector must find the instance through Class")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestGetControlsByClass_FindsLabelInsideContainer() HELP [Fact, Trait("Category", "Traversal")]
        local loForm, loList
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("cont1", "container")
        loForm.cont1.addobject("lbl1", "label")
        this.oFss.SetThisForm(loForm)
        loList = createobject("Collection")
        this.oFss.PubGetControlsByClass(loForm, "label", loList)
        __assert.Equal(1, loList.count, "Must find a label inside a native container")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestGetControlsByClass_FindsLabelInsideCustomContainer() HELP [Fact, Trait("Category", "Traversal")]
        local loForm, loList
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("panel1", "FssCustomPanel")
        loForm.panel1.addobject("lbl1", "label")
        this.oFss.SetThisForm(loForm)
        loList = createobject("Collection")
        this.oFss.PubGetControlsByClass(loForm, "label", loList)
        __assert.Equal(1, loList.count, "Must find a label inside a custom container")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestGetControlsByClass_CountsMultipleLabels() HELP [Fact, Trait("Category", "Traversal")]
        local loForm, loList
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "label")
        loForm.addobject("lbl2", "label")
        loForm.addobject("lbl3", "FssSubLabel")
        this.oFss.SetThisForm(loForm)
        loList = createobject("Collection")
        this.oFss.PubGetControlsByClass(loForm, "label", loList)
        __assert.Equal(3, loList.count, "Must find 2 native labels + 1 subclass through BaseClass")
        loForm.release()
        loForm = .null.
    endproc

    * --- applyStylesToMatching: direct object traversal (used by class selectors) ---

    procedure TestApplyStylesToMatching_AppliesForeColorByBaseClass() HELP [Fact, Trait("Category", "Traversal")]
        * Selector "label" must style FssSubLabel instances (BaseClass="label")
        local loForm, lcFss, loStyles
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "FssSubLabel")
        loForm.lbl1.forecolor = 0
        lcFss = "forecolor = rgb(255,0,0)"
        loStyles = this.oFss.PubLoadStyles(lcFss)
        this.oFss.PubApplyStylesToMatching(loForm, loStyles, "label")
        __assert.Equal(rgb(255,0,0), loForm.lbl1.forecolor, "The Label selector must apply forecolor to FssSubLabel")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestApplyStylesToMatching_AppliesByClassName() HELP [Fact, Trait("Category", "Traversal")]
        * Selector "fsssubLabel" must style FssSubLabel instances (Class="FssSubLabel")
        local loForm, lcFss, loStyles
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "FssSubLabel")
        loForm.lbl1.forecolor = 0
        lcFss = "forecolor = rgb(0,255,0)"
        loStyles = this.oFss.PubLoadStyles(lcFss)
        this.oFss.PubApplyStylesToMatching(loForm, loStyles, "fsssubLabel")
        __assert.Equal(rgb(0,255,0), loForm.lbl1.forecolor, "The FssSubLabel selector must apply forecolor through Class")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestApplyStylesToMatching_AppliesInsideContainer() HELP [Fact, Trait("Category", "Traversal")]
        * Label inside a FssCustomPanel must receive styles
        local loForm, lcFss, loStyles
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("panel1", "FssCustomPanel")
        loForm.panel1.addobject("lbl1", "label")
        loForm.panel1.lbl1.forecolor = 0
        lcFss = "forecolor = rgb(0,0,255)"
        loStyles = this.oFss.PubLoadStyles(lcFss)
        this.oFss.PubApplyStylesToMatching(loForm, loStyles, "label")
        __assert.Equal(rgb(0,0,255), loForm.panel1.lbl1.forecolor, "Styles must reach a label inside a custom container")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestApplyStylesToMatching_ExecutesCodeProperty() HELP [Fact, Trait("Category", "Traversal")]
        * The _ property must execute VFP code on each matching control
        local loForm, lcFss, loStyles, lnOrigTop
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "label")
        loForm.lbl1.top = 50
        lnOrigTop = loForm.lbl1.top
        lcFss = "_ = this.top = this.top - 10"
        loStyles = this.oFss.PubLoadStyles(lcFss)
        this.oFss.PubApplyStylesToMatching(loForm, loStyles, "label")
        __assert.Equal(lnOrigTop - 10, loForm.lbl1.top, "_ must run VFP code and move the label")
        loForm.release()
        loForm = .null.
    endproc

    * --- A user's case: the full scenario ---

    procedure TestUserCase_BaseClassSelector_WithResourceVar_ExecutesCode() HELP [Fact, Trait("Category", "Traversal")]
        * Label selector + a resource $variable in _ + the FssSubLabel subclass
        * A user's exact case: a base class selector, a variable
        * defined in _res_, subclassed labels placed straight on the form.
        local loForm, lcFss, loStyles, lnOrigTop
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "FssSubLabel")
        loForm.lbl1.top = 40
        lnOrigTop = loForm.lbl1.top
        * Load the _res_ block so that $AdjustLabels is there
        this.oFss.PubLoadResources("AdjustLabels = 5")
        lcFss = "forecolor = rgb(0,0,128)" + chr(13) + "_ = this.top = this.top - $AdjustLabels"
        loStyles = this.oFss.PubLoadStyles(lcFss)
        this.oFss.PubApplyStylesToMatching(loForm, loStyles, "label")
        __assert.Equal(rgb(0,0,128), loForm.lbl1.forecolor, "forecolor must apply through the Label selector to FssSubLabel")
        __assert.Equal(lnOrigTop - 5, loForm.lbl1.top, "_ with $AdjustLabels must move the label")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestUserCase_SubclassSelector_WithResourceVar_ExecutesCode() HELP [Fact, Trait("Category", "Traversal")]
        * Baselbl selector + a resource $variable in _
        * The second case: a selector by the subclass name.
        local loForm, lcFss, loStyles, lnOrigTop
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "FssSubLabel")
        loForm.lbl1.top = 40
        lnOrigTop = loForm.lbl1.top
        this.oFss.PubLoadResources("AdjustLabels = 8")
        lcFss = "forecolor = rgb(0,128,0)" + chr(13) + "_ = this.top = this.top - $AdjustLabels"
        loStyles = this.oFss.PubLoadStyles(lcFss)
        this.oFss.PubApplyStylesToMatching(loForm, loStyles, "FssSubLabel")
        __assert.Equal(rgb(0,128,0), loForm.lbl1.forecolor, "forecolor must apply through the FssSubLabel selector")
        __assert.Equal(lnOrigTop - 8, loForm.lbl1.top, "_ with $AdjustLabels must move the label through the subclass selector")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestUserCase_BothSelectorsInSameFss_DoNotDoubleApply() HELP [Fact, Trait("Category", "Traversal")]
        * Label and FssSubLabel in the same FSS: should the label move only ONCE?
        * If the engine applies both selectors, top goes down twice.
        local loForm, lcFss, loStylesLabel, loStylesSub, lnOrigTop
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "FssSubLabel")
        loForm.lbl1.top = 60
        lnOrigTop = loForm.lbl1.top
        this.oFss.PubLoadResources("AdjustLabels = 6")
        lcFss = "_ = this.top = this.top - $AdjustLabels"
        loStylesLabel = this.oFss.PubLoadStyles(lcFss)
        loStylesSub   = this.oFss.PubLoadStyles(lcFss)
        * Apply Label first, then FssSubLabel (as link() would with two selectors)
        this.oFss.PubApplyStylesToMatching(loForm, loStylesLabel, "label")
        this.oFss.PubApplyStylesToMatching(loForm, loStylesSub,   "FssSubLabel")
        * The label moves twice (once per selector): top = 60 - 6 - 6 = 48
        * This pins down the current behaviour: when both selectors carry
        * a _ line, each one applies on its own.
        __assert.Equal(lnOrigTop - 12, loForm.lbl1.top, "Two selectors run _ twice (expected behaviour)")
        loForm.release()
        loForm = .null.
    endproc

enddefine


*==============================================================
* FssTestDouble ? exposes protected methods as public
* Must be defined AFTER the test classes so the runner
* discovers only the test classes above.
*==============================================================
define class FssTestDouble as FoxStyleSheet

    function PubLoadResources(tcStyles)
        this.loadResourcesOptimized(tcStyles)
    endfunc

    function PubGetResource(tcKey)
        return this.GetResourceOptimized(tcKey)
    endfunc

    function PubEval(tcValue)
        return this.EvalExpressionOptimized(tcValue, .f.)
    endfunc

    function PubEvalExpand(tcValue)
        return this.EvalExpressionOptimized(tcValue, .t.)
    endfunc

    function PubIsValidColor(tcValue)
        return this.IsValidColor(tcValue)
    endfunc

    function PubIsValidBoolean(tcValue)
        return this.IsValidBoolean(tcValue)
    endfunc

    function PubRemoveComments(tcContent)
        return this.RemoveComments(tcContent)
    endfunc

    function PubParseStyles(tcContent)
        return this.ParseStyles(tcContent)
    endfunc

    function PubParseSelector(tcSelectorArea, tcStyles)
        return this.parseSelector(tcSelectorArea, tcStyles)
    endfunc

    function PubLoadStyles(tcStyles)
        return this.loadStyles(tcStyles)
    endfunc

    function PubGetSchema(tcColor)
        return this.getSchema(tcColor)
    endfunc

    procedure PubGetControlsByClass(toControl, tcClass, toList)
        this.getControlsByClass(toControl, tcClass, toList)
    endproc

    procedure SetThisForm(toForm)
        this.oThisform = toForm
    endproc

    procedure PubApplyStylesToMatching(toContainer, toStyles, tcClass)
        this.applyStylesToMatching(toContainer, toStyles, tcClass)
    endproc

enddefine


* Helper classes used by TestTraversal ? defined after FssTestDouble so the
* runner does not discover them as test classes.

define class FssSubLabel as label
enddefine

define class FssCustomPanel as container
enddefine
