* FoxStyleSheetTests.prg
* FoxUnit test suite for FoxStyleSheet v2.0.0
* Run: foxunit run --prg FoxStyleSheetTests.prg --format Console

#define FSS_PRG 'C:\Desarrollo\IrwinRodriguez.dev\FoxStyleSheet\foxstylesheet.prg'

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
        __assert.False(loLog.lDebugMode, "lDebugMode debe ser .F. por defecto")
    endproc

    procedure TestLogger_LogInfo_CreatesFileWithInfo() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.LogInfo("test info message")
        __assert.True(file(this.cLogFile), "Log file debe existir tras LogInfo")
        local lcContent
        lcContent = filetostr(this.cLogFile)
        __assert.True("INFO" $ lcContent, "El log debe contener INFO")
        __assert.True("test info message" $ lcContent, "El log debe contener el mensaje")
    endproc

    procedure TestLogger_LogWarning_ContainsWarningLevel() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.LogWarning("test warning")
        local lcContent
        lcContent = filetostr(this.cLogFile)
        __assert.True("WARNING" $ lcContent, "El log debe contener WARNING")
    endproc

    procedure TestLogger_LogError_ContainsErrorLevel() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.LogError("test error")
        local lcContent
        lcContent = filetostr(this.cLogFile)
        __assert.True("ERROR" $ lcContent, "El log debe contener ERROR")
    endproc

    procedure TestLogger_LogDebug_SuppressedWhenModeOff() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.lDebugMode = .f.
        this.oLog.LogDebug("should not appear")
        __assert.False(file(this.cLogFile), "Con lDebugMode=.F. no debe crear archivo de log")
    endproc

    procedure TestLogger_LogDebug_WritesWhenModeOn() HELP [Fact, Trait("Category", "Logger")]
        this.oLog.lDebugMode = .t.
        this.oLog.LogDebug("debug message")
        __assert.True(file(this.cLogFile), "Con lDebugMode=.T. debe crear archivo de log")
        local lcContent
        lcContent = filetostr(this.cLogFile)
        __assert.True("DEBUG" $ lcContent, "El log debe contener DEBUG")
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
        __assert.True(llOk, "Llamada legacy log(string) no debe lanzar excepcion")
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
        __assert.Equal(0, loM.nStylesApplied,     "nStylesApplied debe ser 0 tras Reset")
        __assert.Equal(0, loM.nControlsProcessed, "nControlsProcessed debe ser 0 tras Reset")
        __assert.Equal(0, loM.nParseTime,         "nParseTime debe ser 0 tras Reset")
    endproc

    procedure TestMetrics_GetReport_ContainsVersion() HELP [Fact, Trait("Category", "Metrics")]
        local loM, lcReport
        loM      = createobject("FssStyleMetrics")
        lcReport = loM.GetReport()
        __assert.True("2.0.0" $ lcReport, "El reporte debe contener la version 2.0.0")
    endproc

    procedure TestMetrics_GetReport_ContainsCounters() HELP [Fact, Trait("Category", "Metrics")]
        local loM, lcReport
        loM = createobject("FssStyleMetrics")
        loM.nStylesApplied     = 7
        loM.nControlsProcessed = 4
        lcReport = loM.GetReport()
        __assert.True("7" $ lcReport, "El reporte debe contener nStylesApplied=7")
        __assert.True("4" $ lcReport, "El reporte debe contener nControlsProcessed=4")
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
        __assert.Equal("2.0.0", this.oFss.cVersion, "Version debe ser 2.0.0")
    endproc

    procedure TestInit_CPathContainsFoxStyleSheet() HELP [Fact, Trait("Category", "Init")]
        __assert.NotEmpty(this.oFss.cPath, "cPath debe estar configurado")
        __assert.True("FoxStyleSheet" $ this.oFss.cPath, "cPath debe contener FoxStyleSheet")
    endproc

    procedure TestInit_DestroyNoCrash() HELP [Fact, Trait("Category", "Init")]
        * Regression: Bug B1 ? destroy() crasheaba si oControlCache era .null.
        local llOk
        llOk = .t.
        try
            local loTmp
            loTmp = createobject("FssTestDouble")
            loTmp = .null.
        catch
            llOk = .f.
        endtry
        __assert.True(llOk, "destroy() no debe lanzar excepcion (regresion B1)")
    endproc

    procedure TestInit_IsDrawingAvailable_AlwaysTrue() HELP [Fact, Trait("Category", "Init")]
        __assert.True(this.oFss.IsDrawingAvailable(), "Page backgrounds need nothing since 2.1.0")
    endproc

    procedure TestInit_IsCodejockAvailable_ReturnsLogical() HELP [Fact, Trait("Category", "Init")]
        local lResult
        lResult = this.oFss.IsCodejockAvailable()
        __assert.True(vartype(lResult) == 'L', "IsCodejockAvailable debe retornar tipo Logico")
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
        __assert.Equal("rgb(0,120,215)", this.oFss.PubGetResource("primaryColor"), "primaryColor debe resolverse")
        __assert.Equal("12",            this.oFss.PubGetResource("fontSize"),      "fontSize debe resolverse")
    endproc

    procedure TestResources_MissingKey_ReturnsEmpty() HELP [Fact, Trait("Category", "Resources")]
        local lcResult
        lcResult = this.oFss.PubGetResource("nonexistentkey123")
        __assert.Equal("", lcResult, "Clave inexistente debe retornar cadena vacia")
    endproc

    procedure TestResources_EmptyLines_Ignored() HELP [Fact, Trait("Category", "Resources")]
        local lcStyles
        lcStyles = "key1 = val1" + chr(13) + "" + chr(13) + "key2 = val2"
        this.oFss.PubLoadResources(lcStyles)
        __assert.Equal("val1", this.oFss.PubGetResource("key1"), "key1 debe tener val1")
        __assert.Equal("val2", this.oFss.PubGetResource("key2"), "key2 debe tener val2")
    endproc

    procedure TestResources_CaseInsensitive_KeyLookup() HELP [Fact, Trait("Category", "Resources")]
        this.oFss.PubLoadResources("MyKey = MyValue")
        __assert.Equal("MyValue", this.oFss.PubGetResource("mykey"), "Lookup debe ser case-insensitive")
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
        __assert.Equal(12, lvResult, "Numero literal debe evaluarse a N=12")
    endproc

    procedure TestEval_LiteralBooleanTrue() HELP [Fact, Trait("Category", "Eval")]
        local lvResult
        lvResult = this.oFss.PubEval(".T.")
        __assert.True(vartype(lvResult) == 'L', ".T. debe evaluarse a tipo Logico")
        __assert.True(lvResult, ".T. debe ser verdadero")
    endproc

    procedure TestEval_ColorFunction_RgbReturnsNumeric() HELP [Fact, Trait("Category", "Eval")]
        local lvResult
        lvResult = this.oFss.PubEval("rgb(255,0,0)")
        __assert.True(vartype(lvResult) == 'N', "rgb() debe evaluarse a tipo Numerico")
        __assert.True(lvResult >= 0 and lvResult <= 16777215, "rgb() debe estar en rango de color")
    endproc

    procedure TestEval_VariableExpansion_ResolvesResource() HELP [Fact, Trait("Category", "Eval")]
        this.oFss.PubLoadResources("myColor = rgb(0,0,255)")
        local lvResult
        lvResult = this.oFss.PubEval("$myColor")
        __assert.True(vartype(lvResult) == 'N', "$myColor debe expandirse y evaluarse a N")
    endproc

    procedure TestEval_JustExpand_SubstitutesWithoutEval() HELP [Fact, Trait("Category", "Eval")]
        this.oFss.PubLoadResources("myFont = Arial")
        local lvResult
        lvResult = this.oFss.PubEvalExpand("$myFont")
        __assert.Equal("Arial", lvResult, "JustExpand debe retornar el valor sin evaluar")
    endproc

    procedure TestEval_UnknownVariable_NoCrash() HELP [Fact, Trait("Category", "Eval")]
        local llOk
        llOk = .t.
        try
            this.oFss.PubEvalExpand("$unknownVar999")
        catch
            llOk = .f.
        endtry
        __assert.True(llOk, "Variable desconocida no debe lanzar excepcion")
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
        __assert.True(this.oFss.PubIsValidColor("rgb(255,255,255)"), "rgb(255,255,255) debe ser valido")
    endproc

    procedure TestValidation_ValidColor_NumericWhite() HELP [Fact, Trait("Category", "Validation")]
        __assert.True(this.oFss.PubIsValidColor("16777215"), "16777215 (blanco) debe ser valido")
    endproc

    procedure TestValidation_ValidColor_Zero() HELP [Fact, Trait("Category", "Validation")]
        __assert.True(this.oFss.PubIsValidColor("0"), "0 (negro) debe ser valido")
    endproc

    procedure TestValidation_InvalidColor_RandomString() HELP [Fact, Trait("Category", "Validation")]
        __assert.False(this.oFss.PubIsValidColor("notacolor"), "Texto aleatorio no es color valido")
    endproc

    procedure TestValidation_ValidBoolean_DotT() HELP [Fact, Trait("Category", "Validation")]
        __assert.True(this.oFss.PubIsValidBoolean(".T."), ".T. debe ser booleano valido")
    endproc

    procedure TestValidation_ValidBoolean_DotF() HELP [Fact, Trait("Category", "Validation")]
        __assert.True(this.oFss.PubIsValidBoolean(".F."), ".F. debe ser booleano valido")
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
        __assert.True("before" $ lcResult, "Texto antes del comentario debe permanecer")
        __assert.True("after"  $ lcResult, "Texto despues del comentario debe permanecer")
        __assert.False("this is a comment" $ lcResult, "El contenido del comentario debe eliminarse")
    endproc

    procedure TestComments_MultilineComment_Removed() HELP [Fact, Trait("Category", "Parser")]
        local lcInput, lcResult
        lcInput  = "before /* line1" + chr(13) + "line2 */ after"
        lcResult = this.oFss.PubRemoveComments(lcInput)
        __assert.False("line1" $ lcResult, "Comentario multilinea debe eliminarse completamente")
    endproc

    procedure TestComments_NoComments_ContentUnchanged() HELP [Fact, Trait("Category", "Parser")]
        local lcInput, lcResult
        lcInput  = "form { backcolor = rgb(255,255,255) }"
        lcResult = this.oFss.PubRemoveComments(lcInput)
        __assert.Equal(lcInput, lcResult, "Sin comentarios el contenido no debe cambiar")
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
        __assert.Equal("class", loSel.ControlType, "form debe ser ControlType=class")
        __assert.Equal("form",  loSel.ControlName, "form debe ser ControlName=form")
    endproc

    procedure TestSelector_ClassType_EditBox_LowercaseName() HELP [Fact, Trait("Category", "Parser")]
        local loSel
        loSel = this.oFss.PubParseSelector("EditBox", "backcolor = 0")
        __assert.Equal("class",   loSel.ControlType, "EditBox debe ser class")
        __assert.Equal("editbox", loSel.ControlName, "EditBox debe guardarse en minusculas")
    endproc

    procedure TestSelector_NameType_DotNotation() HELP [Fact, Trait("Category", "Parser")]
        local loSel
        loSel = this.oFss.PubParseSelector(".myTextBox", "backcolor = 0")
        __assert.Equal("name",      loSel.ControlType, "Punto inicial = name type")
        __assert.Equal("myTextBox", loSel.ControlName, "ControlName debe ser myTextBox")
    endproc

    procedure TestSelector_NameType_WithEvent() HELP [Fact, Trait("Category", "Parser")]
        local loSel
        loSel = this.oFss.PubParseSelector(".myCtrl.onGotFocus", "backcolor = 0")
        __assert.Equal("name",     loSel.ControlType,  "Debe ser name type con evento")
        __assert.Equal("myCtrl",   loSel.ControlName,  "ControlName debe ser myCtrl")
        __assert.Equal("GotFocus", loSel.ControlEvent, "Evento debe ser GotFocus")
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
        __assert.Equal("textbox",  loSel.ControlName,  "ControlName debe ser textbox")
        __assert.Equal("GotFocus", loSel.ControlEvent, "Evento debe ser GotFocus")
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
        __assert.True(loResult.Count >= 1, "Debe haber al menos una propiedad")
        __assert.Equal("rgb(255,0,0)", loResult.Item("backcolor"), "backcolor debe ser rgb(255,0,0)")
    endproc

    procedure TestLoadStyles_MultipleProperties_AllParsed() HELP [Fact, Trait("Category", "Parser")]
        local lcStyles, loResult
        lcStyles = "backcolor = rgb(255,0,0)" + chr(13) + "fontsize = 12" + chr(13) + "visible = .T."
        loResult = this.oFss.PubLoadStyles(lcStyles)
        __assert.True(loResult.Count >= 3, "Debe haber 3 propiedades")
    endproc

    procedure TestLoadStyles_TabsNormalized_ParsedCorrectly() HELP [Fact, Trait("Category", "Parser")]
        local loResult
        loResult = this.oFss.PubLoadStyles(chr(9) + "backcolor = rgb(0,0,0)")
        __assert.True(loResult.Count >= 1, "Tabs deben normalizarse correctamente")
    endproc

    procedure TestLoadStyles_EmptyInput_ReturnsEmptyCollection() HELP [Fact, Trait("Category", "Parser")]
        local loResult
        loResult = this.oFss.PubLoadStyles("")
        __assert.Equal(0, loResult.Count, "Input vacio debe retornar coleccion vacia")
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
        __assert.Equal(0, loResult.Count, "String vacio debe retornar coleccion vacia")
    endproc

    procedure TestParseStyles_SingleSelector_ReturnsOneBlock() HELP [Fact, Trait("Category", "Parser")]
        local loResult
        loResult = this.oFss.PubParseStyles("form { backcolor = rgb(255,255,255) }")
        __assert.True(loResult.Count >= 1, "Un selector debe producir al menos un bloque")
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
        __assert.False(llFoundRes, "_res_ no debe aparecer como selector de estilo")
    endproc

    procedure TestParseStyles_ResourceBlock_ResourcesAreAvailable() HELP [Fact, Trait("Category", "Parser")]
        * After parsing a _res_ block the variables should be resolvable
        local lcStyles
        lcStyles = "_res_ { accent = rgb(0,120,215) }" + chr(13) + "form { backcolor = rgb(255,255,255) }"
        this.oFss.PubParseStyles(lcStyles)
        __assert.Equal("rgb(0,120,215)", this.oFss.PubGetResource("accent"), "Recurso debe cargarse durante parse")
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
        __assert.False(llResult, "Dimensiones cero deben retornar .F.")
    endproc

    procedure TestDrawImage_InvalidRgb_ReturnsFalse() HELP [Fact, Trait("Category", "DrawImage")]
        local llResult
        llResult = this.oFss.DrawImage(sys(2023) + '\out.bmp', 100, 100, 999, 0, 0)
        __assert.False(llResult, "RGB fuera de rango debe retornar .F.")
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
        __assert.True("Word" $ lcResult, "Schema word debe contener Word")
    endproc

    procedure TestSchema_Excel_MapsCorrectly() HELP [Fact, Trait("Category", "Schema")]
        __assert.True("Excel" $ this.oFss.PubGetSchema("excel"), "Schema excel debe contener Excel")
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
            __assert.NotEmpty(lcSchema, "Schema " + laThemes[i, 1] + " no debe estar vacio")
        endfor
    endproc

    procedure TestSchema_UnknownTheme_ReturnsEmpty() HELP [Fact, Trait("Category", "Schema")]
        local lcResult
        lcResult = this.oFss.PubGetSchema("unknowntheme")
        __assert.Equal("", lcResult, "Tema desconocido debe retornar cadena vacia")
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
        __assert.Equal(1, loList.count, "Debe encontrar label nativo por BaseClass")
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
        __assert.Equal(1, loList.count, "Selector Label debe encontrar FssSubLabel via BaseClass")
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
        __assert.Equal(1, loList.count, "Selector FssSubLabel debe encontrar instancia via Class")
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
        __assert.Equal(1, loList.count, "Debe encontrar label dentro de un container nativo")
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
        __assert.Equal(1, loList.count, "Debe encontrar label dentro de un custom container")
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
        __assert.Equal(3, loList.count, "Debe encontrar 2 labels nativos + 1 subclase via BaseClass")
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
        __assert.Equal(rgb(255,0,0), loForm.lbl1.forecolor, "Label selector debe aplicar forecolor a FssSubLabel")
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
        __assert.Equal(rgb(0,255,0), loForm.lbl1.forecolor, "FssSubLabel selector debe aplicar forecolor via Class")
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
        __assert.Equal(rgb(0,0,255), loForm.panel1.lbl1.forecolor, "Debe aplicar estilos a label dentro de custom container")
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
        __assert.Equal(lnOrigTop - 10, loForm.lbl1.top, "_ debe ejecutar codigo VFP y mover el label")
        loForm.release()
        loForm = .null.
    endproc

    * --- Caso a user: escenario completo ---

    procedure TestUserCase_BaseClassSelector_WithResourceVar_ExecutesCode() HELP [Fact, Trait("Category", "Traversal")]
        * Label selector + $variable de recurso en _ + subclase FssSubLabel
        * Reproduce el caso exacto de a user: selector de clase base, variable
        * definida en _res_, labels subclaseados directos en el formulario.
        local loForm, lcFss, loStyles, lnOrigTop
        loForm = createobject("form")
        loForm.visible = .f.
        loForm.addobject("lbl1", "FssSubLabel")
        loForm.lbl1.top = 40
        lnOrigTop = loForm.lbl1.top
        * Cargar el bloque _res_ para que $AdjustLabels quede disponible
        this.oFss.PubLoadResources("AdjustLabels = 5")
        lcFss = "forecolor = rgb(0,0,128)" + chr(13) + "_ = this.top = this.top - $AdjustLabels"
        loStyles = this.oFss.PubLoadStyles(lcFss)
        this.oFss.PubApplyStylesToMatching(loForm, loStyles, "label")
        __assert.Equal(rgb(0,0,128), loForm.lbl1.forecolor, "forecolor debe aplicarse via selector Label a FssSubLabel")
        __assert.Equal(lnOrigTop - 5, loForm.lbl1.top, "_ con $AdjustLabels debe mover el label")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestUserCase_SubclassSelector_WithResourceVar_ExecutesCode() HELP [Fact, Trait("Category", "Traversal")]
        * Baselbl selector + $variable de recurso en _
        * Reproduce el segundo escenario de a user: selector por nombre de subclase.
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
        __assert.Equal(rgb(0,128,0), loForm.lbl1.forecolor, "forecolor debe aplicarse via selector FssSubLabel")
        __assert.Equal(lnOrigTop - 8, loForm.lbl1.top, "_ con $AdjustLabels debe mover el label via selector de subclase")
        loForm.release()
        loForm = .null.
    endproc

    procedure TestUserCase_BothSelectorsInSameFss_DoNotDoubleApply() HELP [Fact, Trait("Category", "Traversal")]
        * Label y FssSubLabel en el mismo FSS: el label solo debe moverse UNA vez.
        * Si el motor aplica ambos selectores, el top bajaria el doble.
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
        * Aplicar Label primero, luego FssSubLabel (como haria link() con dos selectores)
        this.oFss.PubApplyStylesToMatching(loForm, loStylesLabel, "label")
        this.oFss.PubApplyStylesToMatching(loForm, loStylesSub,   "FssSubLabel")
        * El label se mueve dos veces (una por cada selector) — top = 60 - 6 - 6 = 48
        * Esto documenta el comportamiento actual: si el usuario pone ambos selectores
        * con _ cada uno aplica por separado. El test fija ese comportamiento.
        __assert.Equal(lnOrigTop - 12, loForm.lbl1.top, "Dos selectores aplican _ dos veces (comportamiento esperado)")
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
