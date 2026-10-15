#define LOG_ERROR      16
#define LOG_INFO       64
#define LOG_WARNING    48
#define LOG_DEBUG      80
#define CRLF           chr(13) + chr(10)
#define FSS_SEPARATOR  ' _fss_lf '
#define FSS_KEY        '_'
#define FSS_VERSION    '2.2.0'
#define FSS_ENGINE_PROPERTY  'oFoxStyleSheet'
* DwmSetWindowAttribute: dark title bar (Windows 10 2004+; 19 before that),
* caption and caption text colours (Windows 11)
#define DWMWA_USE_IMMERSIVE_DARK_MODE        20
#define DWMWA_USE_IMMERSIVE_DARK_MODE_OLD    19
#define DWMWA_CAPTION_COLOR                  35
#define DWMWA_TEXT_COLOR                     36

* Entry point: DO foxstylesheet.prg WITH "Word", ThisForm
lparameters tcStyle, toThisform

local loFss
loFss = createobject("FoxStyleSheet")
loFss.link(tcStyle, toThisform)
return

*==============================================================
* CLASS: FoxStyleSheet
* Main engine. Zero mandatory external dependencies.
* Optional features:
*   - Page backgrounds (rgb): a BMP written by the library itself
*   - Custom title bar (frametheme): bring your own Codejock SkinFramework
*==============================================================
define class FoxStyleSheet as custom

    cVersion = FSS_VERSION

    * cPrgPath: folder where foxstylesheet.prg lives (auto-set in init)
    * cPath:    APPDATA temp folder for logs and generated images
    cPrgPath = ''
    cPath    = ''

    * Codejock SkinFramework is commercial: bring your own. Empty paths mean
    * the Fss\ folder beside foxstylesheet.prg, as in 2.0.
    cCodejockProgId = 'Codejock.SkinFramework.22.1.0'
    cCodejockOcx    = ''
    cSkinFile       = ''

    * Errors of the last link() and of the event styles since then. They are
    * kept by the logger; these read them (see the _Access methods).
    nErrors    = 0
    oErrors    = .null.
    cLastError = ''

    * The theme of the last link(), as it was given: "dark", a path, or the
    * text of a theme. FssThemeToggle reads it to know where to go next.
    cTheme = ''

    protected oLogger, oResources, oResourcesIndex, cFormProperty
    cFormProperty = ''
    protected oFunctions, oThisform, oImages, oControls, oMetrics
    * The properties link() hangs from the form and its controls, as
    * "path|property": a second link() takes them down before it starts.
    protected oAddedProperties, lLinked, lTitleBarSet
    oAddedProperties = .null.
    lLinked = .f.
    lTitleBarSet = .f.

    procedure init
        local lcPrgFile, lcPrgPath, lcPath

        * Capture PRG's own directory for auto-locating Fss\ (Codejock).
        * Inside a method SYS(16) is "PROCEDURE CLASS.METHOD <path>": the prefix
        * has exactly two spaces, and the path may have its own (rule 41).
        lcPrgFile = sys(16)
        if upper(left(lcPrgFile, 10)) == "PROCEDURE " and at(" ", lcPrgFile, 2) > 0
            lcPrgFile = substr(lcPrgFile, at(" ", lcPrgFile, 2) + 1)
        endif
        if !empty(lcPrgFile)
            lcPrgPath = addbs(justpath(lcPrgFile))
            this.cPrgPath = lcPrgPath
        endif

        with this
            .oLogger         = createobject("FssLogger")
            .oLogger.lDebugMode = .f.
            .oResources      = createobject("Collection")
            .oResourcesIndex = createobject("Collection")
            .oFunctions      = createobject("Collection")
            .oControls       = createobject("Collection")
            .oImages         = createobject("Collection")
            .oAddedProperties = createobject("Collection")
            .oMetrics        = createobject("FssStyleMetrics")
        endwith

        * APPDATA folder for temp images and log file
        lcPath = addbs(addbs(getenv("APPDATA")) + 'FoxStyleSheet')
        this.cPath = lcPath
        if !directory(lcPath)
            mkdir '&lcPath'
        endif
    endproc

    *----------------------------------------------------------
    * Feature detection (public)
    *----------------------------------------------------------

    * Page backgrounds (rgb()) need nothing since 2.1.0: always .T.
    function IsDrawingAvailable()
        return .t.
    endfunc

    * Returns .T. if Codejock SkinFramework is registered on this machine
    function IsCodejockAvailable()
        local loHelper, llResult
        llResult = .f.
        try
            loHelper = createobject("FssOCXHelper")
            llResult = loHelper.isClassRegistered(this.cCodejockProgId)
        catch
            llResult = .f.
        endtry
        return llResult
    endfunc

    * Returns performance report string from last link() call
    function GetPerformanceReport()
        return this.oMetrics.GetReport()
    endfunc

    procedure ClearErrors
        if vartype(this.oLogger) == 'O'
            this.oLogger.ClearErrors()
        endif
    endproc

    function nErrors_Access
        return iif(vartype(this.oLogger) == 'O', this.oLogger.nErrors, 0)
    endfunc

    function oErrors_Access
        return iif(vartype(this.oLogger) == 'O', this.oLogger.oErrors, .null.)
    endfunc

    function cLastError_Access
        return iif(vartype(this.oLogger) == 'O', this.oLogger.cLastError, '')
    endfunc

    *----------------------------------------------------------
    * Main entry point
    *----------------------------------------------------------
    function link(tcFile, toForm)
        local lcContent, loStyles, llRelink

        this.ClearErrors()
        this.oMetrics.Reset()
        this.oMetrics.StartTimer()

        * A second link() changes the theme: the event styles, functions and
        * resources of the first one go away before the new one is read.
        llRelink = this.lLinked
        if llRelink
            this.Unlink()
        endif
        this.oThisform = toForm
        this.cTheme = iif(vartype(tcFile) == 'C', tcFile, '')

        * The event bindings live as long as this object, so it hangs itself
        * from the form: an engine in a LOCAL of the form's Init keeps working.
        if empty(this.cFormProperty) and type('toForm') == 'O' and !isnull(toForm)
            this.cFormProperty = FSS_ENGINE_PROPERTY + sys(2015)
            =addproperty(toForm, this.cFormProperty, this)
        endif

        this.oLogger.SetLogFile(this.cPath + 'FoxStyleSheet.log')

        lcContent = this.LoadContent(tcFile)
        if !empty(lcContent)
            lcContent = this.RemoveComments(lcContent)
            this.ExtractFunctions(lcContent)
            loStyles = this.ParseStyles(lcContent)
            this.oMetrics.EndTimer('parse')

            this.oMetrics.StartTimer()
            this.ClearToggleIcons(toForm)
            this.ApplyAllStyles(loStyles, toForm)
            this.RefreshToggleIcons(toForm)
            this.oMetrics.EndTimer('apply')

            this.BindFormEvents()
            this.lLinked = .t.
            * a form already on screen will not fire Activate for the Init styles
            if llRelink and type('toForm.Visible') == 'L' and toForm.Visible
                this.onActivate()
            endif
        endif
        return this.oLogger.nErrors = 0
    endfunc

    *-- Takes down what the last link() left on the form: the bindings, the
    *-- event styles, the cached control lists, the functions and the resources.
    *-- The static properties stay as they are: the next theme sets its own.
    *-- The title bar goes back to the colours of Windows.
    protected procedure Unlink
        local lcEntry, lcPath, lcProperty, loObject, loEx
        try
            unbindevents(this)
        catch
        endtry
        for each lcEntry in this.oAddedProperties
            lcPath     = getwordnum(lcEntry, 1, '|')
            lcProperty = getwordnum(lcEntry, 2, '|')
            loObject   = this.GetCachedControl(lcPath)
            try
                if type('loObject') == 'O' and !isnull(loObject) and pemstatus(loObject, lcProperty, 5)
                    =removeproperty(loObject, lcProperty)
                endif
            catch to loEx
                this.oLogger.LogFromException(loEx)
            endtry
        endfor
        this.oAddedProperties = createobject("Collection")
        this.oControls        = createobject("Collection")
        this.oFunctions       = createobject("Collection")
        this.oResources       = createobject("Collection")
        this.oResourcesIndex  = createobject("Collection")
        * a title bar painted by the old theme goes back to Windows
        if this.lTitleBarSet and type('this.oThisform') == 'O' and !isnull(this.oThisform)
            this.SetTitleBar(this.oThisform, 'darktitlebar', .f.)
            this.SetTitleBar(this.oThisform, 'titlebarcolor', -1)
            this.SetTitleBar(this.oThisform, 'titlebartextcolor', -1)
            this.lTitleBarSet = .f.
        endif
        this.lLinked = .f.
    endproc

    *-- addproperty() that link() can take down again (see Unlink)
    protected procedure AddTrackedProperty(toObject, tcProperty, tvValue)
        =addproperty(toObject, tcProperty, tvValue)
        this.oAddedProperties.add(this.ControlPath(toObject) + '|' + tcProperty)
    endproc

    *-- The path of a control as GetCachedControl() evaluates it
    protected function ControlPath(toControl)
        local lcPath
        if toControl == this.oThisform
            return 'this.oThisform'
        endif
        lcPath = sys(1272, toControl)
        return 'this.oThisform' + substr(lcPath, at('.', lcPath))
    endfunc

    *----------------------------------------------------------
    * Lifecycle
    *----------------------------------------------------------
    procedure destroy
        this.UnbindAllEvents()
        try
            unbindevents(this)
        catch
        endtry
        this.CleanupTempFiles()
        this.CleanupScreenObjects()
        this.oControls       = .null.
        this.oResourcesIndex = .null.
    endproc

    protected procedure UnbindAllEvents
        local lcControl, loControl
        for each lcControl in this.oControls
            try
                loControl = this.GetCachedControl(lcControl)
                if type('loControl') == 'O' and !isnull(loControl)
                    unbindevents(loControl)
                endif
            catch
            endtry
        endfor
        if type('this.oThisform') == 'O' and !isnull(this.oThisform)
            unbindevents(this.oThisform)
        endif
    endproc

    protected procedure CleanupTempFiles
        local lcImage
        try
            for each lcImage in this.oImages
                if file(lcImage)
                    delete file (lcImage)
                endif
            endfor
        catch to loEx
            this.oLogger.LogFromException(loEx)
        endtry
        try
            local array laFiles[1]
            local i, lcFile
            if adir(laFiles, this.cPath + '*.bmp') > 0
                for i = 1 to alen(laFiles, 1)
                    try
                        lcFile = this.cPath + laFiles[i, 1]
                        if file(lcFile)
                            delete file (lcFile)
                        endif
                    catch
                    endtry
                endfor
            endif
        catch to loEx
            this.oLogger.LogFromException(loEx)
        endtry
    endproc

    protected procedure CleanupScreenObjects
        try
            if type('_screen.oFssTitleBar') == 'O'
                _screen.oFssTitleBar = .null.
                removeproperty(_screen, 'oFssTitleBar')
            endif
        catch
        endtry
    endproc

    *----------------------------------------------------------
    * Parsing pipeline
    *----------------------------------------------------------
    *-- The theme is read by a small scanner written in VFP: no regular
    *-- expressions, so no dependency on a COM component.

    *-- A theme is a file, the text of a theme (it has a "{"), or the name of
    *-- a built-in theme ("Word", "office-word-dark.fss": case and .fss do not matter).
    protected function LoadContent(tcTheme)
        local lcBuiltIn
        do case
        case vartype(tcTheme) != 'C' or empty(tcTheme)
            this.oLogger.LogError("link: no theme was given")
            return ''
        case file(tcTheme)
            return filetostr(tcTheme)
        case '{' $ tcTheme
            return tcTheme
        endcase
        lcBuiltIn = ''
        if !('\' $ tcTheme or '/' $ tcTheme or ':' $ tcTheme)
            lcBuiltIn = FssBuiltInTheme(juststem(alltrim(tcTheme)))
        endif
        if empty(lcBuiltIn)
            this.oLogger.LogError("link: theme not found: " + tcTheme + ". It is not a file, nor one of the built-in themes: " + FssBuiltInThemeNames())
        endif
        return lcBuiltIn
    endfunc

    *-- Removes every /* ... */ comment; one that is never closed runs to the end.
    protected function RemoveComments(tcContent)
        local lcOut, lcRest, lnOpen, lnClose
        lcOut  = ''
        lcRest = tcContent
        lnOpen = at('/*', lcRest)
        do while lnOpen > 0
            lcOut   = lcOut + left(lcRest, lnOpen - 1)
            lcRest  = substr(lcRest, lnOpen + 2)
            lnClose = at('*/', lcRest)
            if lnClose = 0
                lcRest = ''
            else
                lcRest = substr(lcRest, lnClose + 2)
            endif
            lnOpen = at('/*', lcRest)
        enddo
        return lcOut + lcRest
    endfunc

    *-- Splits a theme into its blocks, "head { body }": a Collection of
    *-- objects with Head and Body. Braces nest ({^2026-01-01} in a body is
    *-- fine), and braces inside quotes do not count.
    protected function ParseBlocks(tcContent)
        local loBlocks, loBlock, lnLen, lnI, lnStart, lnOpen, lnDepth, lcChar, lcQuote
        loBlocks = createobject("Collection")
        lnLen    = len(tcContent)
        lnStart  = 1
        lnI      = 1
        do while lnI <= lnLen
            if substr(tcContent, lnI, 1) != '{'
                lnI = lnI + 1
                loop
            endif
            lnOpen  = lnI
            lnDepth = 0
            lcQuote = ''
            do while lnI <= lnLen
                lcChar = substr(tcContent, lnI, 1)
                do case
                case !empty(lcQuote)
                    if lcChar == lcQuote
                        lcQuote = ''
                    endif
                case lcChar == '"' or lcChar == "'"
                    lcQuote = lcChar
                case lcChar == '{'
                    lnDepth = lnDepth + 1
                case lcChar == '}'
                    lnDepth = lnDepth - 1
                endcase
                if lnDepth = 0
                    exit
                endif
                lnI = lnI + 1
            enddo
            loBlock = createobject("Empty")
            =addproperty(loBlock, "Head", this.TrimAll(substr(tcContent, lnStart, lnOpen - lnStart)))
            =addproperty(loBlock, "Body", this.TrimAll(substr(tcContent, lnOpen + 1, lnI - lnOpen - 1)))
            if lnDepth > 0
                this.oLogger.LogWarning("The block '" + loBlock.Head + "' is never closed with }")
            endif
            loBlocks.add(loBlock)
            lnI     = lnI + 1
            lnStart = lnI
        enddo
        return loBlocks
    endfunc

    protected function ParseStyles(tcContent)
        local loBlocks, loBlock, loStyles, loResult
        loStyles = createobject("Collection")
        loBlocks = this.ParseBlocks(tcContent)
        for each loBlock in loBlocks
            if !this.IsFunctionHead(loBlock.Head)
                loResult = this.ExtractStyles(loBlock.Head, loBlock.Body)
                if !isnull(loResult)
                    loStyles.add(loResult)
                    this.oMetrics.nStylesApplied = this.oMetrics.nStylesApplied + 1
                endif
            endif
        endfor
        return loStyles
    endfunc

    *-- One block: the _res_ block loads the resources (and returns .null.);
    *-- any other gives a Collection with one selector per name of its list.
    protected function ExtractStyles(tcHead, tcBody)
        local loSelectorCollection, lcHead, lcSelector, i
        if empty(tcHead)
            this.oLogger.LogWarning("A block has no selector: { " + left(tcBody, 40) + " }")
            return .null.
        endif
        lcHead = chrtran(tcHead, chr(9) + chr(13) + chr(10), '   ')
        if lower(alltrim(lcHead)) == '_res_'
            if !empty(tcBody)
                this.loadResourcesOptimized(tcBody)
            endif
            return .null.
        endif

        loSelectorCollection = createobject("Collection")
        for i = 1 to getwordcount(lcHead, ',')
            lcSelector = alltrim(getwordnum(lcHead, i, ','))
            do case
            case empty(lcSelector)
            case ' ' $ lcSelector
                this.oLogger.LogWarning("Selector not understood (a selector has no spaces): '" + lcSelector + "'")
            otherwise
                loSelectorCollection.add(this.parseSelector(lcSelector, tcBody))
            endcase
        endfor
        if loSelectorCollection.count = 0
            return .null.
        endif
        return loSelectorCollection
    endfunc

    protected procedure loadResourcesOptimized(tcStyles)
        local i, lcProp, lcValue, lcResolved, lnPasses, laKeys[1], lnCount
        local loNewResources, loNewIndex
        this.oResources      = createobject("Collection")
        this.oResourcesIndex = createobject("Collection")

        local array laProp[1]
        =alines(laProp, tcStyles, 5)
        
        this.oLogger.LogDebug("loadResourcesOptimized: " + transform(alen(laProp)) + " lines")
        
        * First pass: load every variable as written
        for i = 1 to alen(laProp)
            lcProp  = lower(alltrim(chrtran(getwordnum(laProp[i], 1, '='), chr(9), ' ')))
            lcValue = alltrim(chrtran(getwordnum(laProp[i], 2, '='), chr(9), ' '))
            if empty(lcProp)
                loop
            endif
            try
                this.oResources.add(lcValue, lcProp)
                this.oResourcesIndex.add(this.oResources.count, lcProp)
                this.oLogger.LogDebug("Resource loaded: " + lcProp + " = " + lcValue)
            catch to loEx
                this.oLogger.LogFromException(loEx)
            endtry
        endfor
        
        * Second pass: resolve the variables that name others (5 levels at most)
        for lnPasses = 1 to 5
            lnCount = this.oResources.count
            dimension laKeys[lnCount]
            for i = 1 to lnCount
                laKeys[i] = this.oResources.getkey(i)
            endfor
            
            loNewResources = createobject("Collection")
            loNewIndex = createobject("Collection")
            
            for i = 1 to lnCount
                lcProp = laKeys[i]
                lcValue = this.oResources.item(lcProp)
                if '$' $ lcValue
                    lcResolved = this.EvalExpressionOptimized(lcValue, .t.)
                    this.oLogger.LogDebug("Resource resolved, pass " + transform(lnPasses) + ": " + lcProp + " = " + lcResolved)
                else
                    lcResolved = lcValue
                endif
                loNewResources.add(lcResolved, lcProp)
                loNewIndex.add(loNewResources.count, lcProp)
            endfor
            
            this.oResources = loNewResources
            this.oResourcesIndex = loNewIndex
        endfor
    endproc

    protected function GetResourceOptimized(tcKey)
        local lnIndex, lcResult
        lcResult = ''
        try
            lnIndex  = this.oResourcesIndex.item(lower(tcKey))
            lcResult = this.oResources.item(lnIndex)
        catch
            lcResult = ''
        endtry
        return lcResult
    endfunc

    protected procedure ApplyAllStyles(toStyles, toForm)
        local loStyle, loSelector
        for each loStyle in toStyles
            for each loSelector in loStyle
                if !empty(loSelector.ControlStyles)
                    this.ApplyStyles(loSelector, toForm)
                endif
            endfor
        endfor
    endproc

    protected procedure ApplyStyles(toSelector, toForm)
        local loStyles, lcClassProp, loClassCollection, lcClassStylesProp, loControl
        loStyles = this.loadStyles(toSelector.ControlStyles)

        if !empty(toSelector.ControlEvent)
            loClassCollection = createobject("Collection")
            lcClassStylesProp = ''

            do case
            case toSelector.ControlType == "class"
                lcClassProp       = toSelector.ControlName + 'ClassCollection'
                lcClassStylesProp = textmerge('o<<toSelector.ControlName>>Class<<toSelector.ControlEvent>>Styles')
                if !pemstatus(toForm, lcClassProp, 5)
                    this.getControlsByClass(toForm, lower(toSelector.ControlName), loClassCollection)
                    this.AddTrackedProperty(toForm, lcClassProp, loClassCollection)
                else
                    loClassCollection = evaluate('toForm.' + lcClassProp)
                endif
                this.bindControlStyles(lcClassStylesProp, loClassCollection, toSelector.ControlEvent, loStyles)
            case toSelector.ControlType == "name"
                loClassCollection.add('this.oThisform.' + toSelector.ControlName)
                this.bindControlStyles(lcClassStylesProp, loClassCollection, toSelector.ControlEvent, loStyles)
            case toSelector.ControlType == '*'
                lcClassProp       = 'StarClassCollection'
                lcClassStylesProp = textmerge('oStarClass<<toSelector.ControlEvent>>Styles')
                if !pemstatus(toForm, lcClassProp, 5)
                    this.getAllControls(toForm, loClassCollection)
                    this.AddTrackedProperty(toForm, lcClassProp, loClassCollection)
                else
                    loClassCollection = evaluate('toForm.' + lcClassProp)
                endif
                this.bindControlStyles(lcClassStylesProp, loClassCollection, toSelector.ControlEvent, loStyles)
            endcase
        else
            do case
            case toSelector.ControlType == "class"
                if toSelector.ControlName == "form"
                    this.applyStylesByControl(toForm, loStyles)
                else
                    this.applyStylesByClass(toForm, loStyles, toSelector.ControlName)
                endif
            case toSelector.ControlType == '*'
                this.applyStylesByClass(toForm, loStyles, .f.)
            case toSelector.ControlType == "name"
                try
                    loControl = evaluate("toForm." + toSelector.ControlName)
                    this.applyStylesByControl(loControl, loStyles)
                    this.oMetrics.nControlsProcessed = this.oMetrics.nControlsProcessed + 1
                catch to loEx
                    this.oLogger.LogFromException(loEx)
                endtry
            endcase
        endif
    endproc

    protected procedure applyStylesByControl(toControl, toStyles)
        local i, lcProp, lcValue, lcCleanProp, lcColorValues, lcImage
        local lnRed, lnGreen, lnBlue, lnW, lnH
        local laExec[1], lcExec, lnExec

        this.oLogger.LogDebug("Styling: " + toControl.Name + " (" + toControl.BaseClass + ")")

        for i = 1 to toStyles.count
            lcProp      = toStyles.getkey(i)
            lcValue     = toStyles.item(i)
            lcCleanProp = alltrim(strtran(lcProp, chr(9), ''))

            do case
            case lcCleanProp == FSS_KEY
                if left(lcValue, 1) != '$'
                    alines(laExec, lcValue, 5, FSS_SEPARATOR)
                    for lnExec = 1 to alen(laExec, 1)
                        lcExec = this.EvalExpressionOptimized(laExec[lnExec], .t.)
                        lcExec = this.RewriteThis(lcExec, 'toControl', 'this.oThisform')
                        try
                            &lcExec
                        catch to loEx
                            this.oLogger.LogFromException(loEx)
                        endtry
                    endfor
                endif
                loop

            case lower(lcCleanProp) == 'frametheme' and lower(toControl.baseclass) == 'form'
                this.addTitleBar(toControl, this.EvalExpressionOptimized(lcValue))
                loop

            case inlist(lower(lcCleanProp), 'darktitlebar', 'titlebarcolor', 'titlebartextcolor') and lower(toControl.baseclass) == 'form'
                this.SetTitleBar(toControl, lower(lcCleanProp), this.EvalExpressionOptimized(lcValue))
                loop

            case lower(lcCleanProp) == 'icon'
                this.ApplyIcon(toControl, lcValue)
                loop

            case lower(lcCleanProp) == 'picture' and lower(toControl.baseclass) == 'page'
                if 'rgb(' $ lower(lcValue)
                    lcColorValues = strextract(lcValue, 'rgb(', ')', 1)
                else
                    lcColorValues = strextract(lcValue, '(', ')', 1)
                endif
                if empty(lcColorValues)
                    this.oLogger.LogWarning("Could not extract RGB from: " + lcValue)
                    loop
                endif
                lnRed   = val(alltrim(getwordnum(lcColorValues, 1, ',')))
                lnGreen = val(alltrim(getwordnum(lcColorValues, 2, ',')))
                lnBlue  = val(alltrim(getwordnum(lcColorValues, 3, ',')))
                lnW = toControl.parent.width
                lnH = toControl.parent.height
                if lnW > 0 and lnH > 0
                    lcImage = this.cPath + sys(2015) + '.bmp'
                    if this.DrawImage(lcImage, lnW, lnH, lnRed, lnGreen, lnBlue)
                        try
                            toControl.picture = lcImage
                        catch to loEx
                            this.oLogger.LogFromException(loEx)
                        endtry
                    endif
                endif
                loop

            otherwise
                if !this.ValidateStyleProperty(lcCleanProp, lcValue, toControl)
                    loop
                endif
                try
                    if lower(toControl.baseclass) == "olecontrol"
                        toControl.Object. &lcCleanProp = this.EvalExpressionOptimized(lcValue)
                    else
                        toControl. &lcCleanProp = this.EvalExpressionOptimized(lcValue)
                    endif
                catch to loEx
                    this.oLogger.LogFromException(loEx)
                endtry
            endcase
        endfor
    endproc

    protected function ValidateStyleProperty(tcProp, tcValue, toControl)
        local llValid, lvEval
        llValid = .t.

        do case
        case lower(tcProp) == 'backcolor' or lower(tcProp) == 'forecolor'
            llValid = this.IsValidColor(tcValue)
        case lower(tcProp) == 'fontsize'
            lvEval  = this.EvalExpressionOptimized(tcValue)
            llValid = type('lvEval') == 'N' and lvEval > 0
        case lower(tcProp) == 'visible' or lower(tcProp) == 'enabled'
            llValid = this.IsValidBoolean(tcValue)
        case !pemstatus(toControl, tcProp, 5)
            if lower(toControl.baseclass) == "olecontrol"
                llValid = .t.
            else
                llValid = .f.
                this.oLogger.LogWarning("Property '" + tcProp + "' not found on " + toControl.Name)
            endif
        endcase

        if !llValid and lower(tcProp) != FSS_KEY
            this.oLogger.LogWarning("Invalid value '" + tcValue + "' for '" + tcProp + "'")
        endif

        return llValid
    endfunc

    protected function IsValidColor(tcValue)
        local lvEval
        lvEval = this.EvalExpressionOptimized(tcValue)
        return type('lvEval') == 'N' and lvEval >= 0 and lvEval <= 16777215
    endfunc

    protected function IsValidBoolean(tcValue)
        local lvEval, lcUpper
        lvEval = this.EvalExpressionOptimized(tcValue)
        if vartype(lvEval) == 'L'
            return .t.
        endif
        lcUpper = upper(alltrim(transform(lvEval)))
        return inlist(lcUpper, '.T.', '.F.', 'TRUE', 'FALSE', '1', '0')
    endfunc

    protected procedure applyStylesByClass(toForm, toStyles, tcClass)
        local i, lcProp, lcValue

        if vartype(tcClass) == 'C' and !empty(tcClass)
            this.applyStylesToMatching(toForm, toStyles, lower(tcClass))
            return
        endif

        for i = 1 to toStyles.count
            lcProp  = toStyles.getkey(i)
            lcValue = toStyles.item(i)
            if lcProp == FSS_KEY
                loop
            endif
            try
                toForm.setall(lcProp, this.EvalExpressionOptimized(lcValue))
            catch to loEx
                this.oLogger.LogFromException(loEx)
            endtry
        endfor
    endproc

    protected procedure applyStylesToMatching(toContainer, toStyles, tcClass)
        local loControl
        if type('toContainer') != 'O' or isnull(toContainer)
            return
        endif
        if !pemstatus(toContainer, "Objects", 5)
            return
        endif
        for each loControl in toContainer.Objects
            try
                if type('loControl') == 'O' and !isnull(loControl)
                    if lower(loControl.baseclass) == lower(tcClass) or lower(loControl.class) == lower(tcClass)
                        this.applyStylesByControl(loControl, toStyles)
                        this.oMetrics.nControlsProcessed = this.oMetrics.nControlsProcessed + 1
                    endif
                    this.applyStylesToMatching(loControl, toStyles, tcClass)
                endif
            catch to loEx
                this.oLogger.LogFromException(loEx)
            endtry
        endfor
    endproc

    *----------------------------------------------------------
    * Selector parsing
    *----------------------------------------------------------
    protected function parseSelector(tcSelectorArea, tcStyles)
        local loSelector
        loSelector = this.CreateEmptySelector(tcStyles)
        do case
        case left(tcSelectorArea, 1) == '.'
            this.ParseNameSelector(loSelector, tcSelectorArea)
        case left(tcSelectorArea, 1) == '*'
            this.ParseUniversalSelector(loSelector, tcSelectorArea)
        otherwise
            this.ParseClassSelector(loSelector, tcSelectorArea)
        endcase
        return loSelector
    endfunc

    protected function CreateEmptySelector(tcStyles)
        local loSelector
        loSelector = createobject("Empty")
        =addproperty(loSelector, "ControlName",   "")
        =addproperty(loSelector, "ControlType",   "")
        =addproperty(loSelector, "ControlEvent",  "")
        =addproperty(loSelector, "ControlStyles", tcStyles)
        return loSelector
    endfunc

    protected procedure ParseNameSelector(loSelector, tcSelectorArea)
        local lcArea, lcControlName, lcNameOrEvent, lnAt, i
        lcArea        = alltrim(substr(tcSelectorArea, 2))
        lcControlName = lcArea
        loSelector.ControlType = "name"

        lnAt = getwordcount(lcArea, '.')
        if lnAt >= 1
            lcNameOrEvent = alltrim(getwordnum(lcArea, lnAt, '.'))
            if lower(left(lcNameOrEvent, 2)) == 'on'
                loSelector.ControlEvent = substr(lcNameOrEvent, 3)
                lcControlName = ''
                for i = 1 to lnAt - 1
                    if !empty(lcControlName)
                        lcControlName = lcControlName + '.'
                    endif
                    lcControlName = lcControlName + alltrim(getwordnum(lcArea, i, '.'))
                endfor
            endif
        endif
        loSelector.ControlName = lcControlName
    endproc

    *-- "*" or "*.onGotFocus": every control, now or when the event fires
    protected procedure ParseUniversalSelector(loSelector, tcSelectorArea)
        local lcEvent
        loSelector.ControlName = "*"
        loSelector.ControlType = "*"
        if occurs('.', tcSelectorArea) = 1
            lcEvent = alltrim(getwordnum(tcSelectorArea, 2, '.'))
            if lower(left(lcEvent, 2)) == 'on'
                loSelector.ControlEvent = substr(lcEvent, 3)
            endif
        endif
    endproc

    protected procedure ParseClassSelector(loSelector, tcSelectorArea)
        loSelector.ControlName = lower(alltrim(tcSelectorArea))
        loSelector.ControlType = "class"
        if occurs('.', tcSelectorArea) = 1
            loSelector.ControlName  = lower(alltrim(getwordnum(tcSelectorArea, 1, '.')))
            loSelector.ControlEvent = substr(alltrim(getwordnum(tcSelectorArea, 2, '.')), 3)
        endif
    endproc

    protected function loadStyles(tcStyles)
        local loStyles, i, j, lcLine, lcProp, lcValue, lcOldVal
        loStyles = createobject("Collection")
        this.oLogger.LogDebug("loadStyles input: " + tcStyles)

        try
            local array laProp[1]
            =alines(laProp, tcStyles, 5)
            for i = 1 to alen(laProp)
                lcLine = alltrim(strtran(laProp[i], chr(9), ' '))
                if empty(lcLine) or !('=' $ lcLine)
                    loop
                endif
                lcProp  = alltrim(substr(lcLine, 1, at('=', lcLine) - 1))
                lcValue = alltrim(substr(lcLine, at('=', lcLine) + 1))
                try
                    j = loStyles.getkey(lcProp)
                    if j > 0
                        lcOldVal = loStyles.item(j)
                        lcValue  = lcOldVal + FSS_SEPARATOR + lcValue
                        loStyles.remove(j)
                    endif
                    loStyles.add(lcValue, lcProp)
                catch to loEx
                    this.oLogger.LogFromException(loEx)
                endtry
            endfor
        catch to loEx
            this.oLogger.LogFromException(loEx)
        endtry

        return loStyles
    endfunc

    *----------------------------------------------------------
    * Event binding
    *----------------------------------------------------------
    protected procedure BindFormEvents
        bindevent(this.oThisform, 'Activate', this, 'onActivate')
    endproc

    protected procedure onActivate
        try
            local lcControl, loControl
            if type('this.oControls') == 'O' and !isnull(this.oControls)
                for each lcControl in this.oControls
                    try
                        loControl = this.GetCachedControl(lcControl)
                        * the Init styles, without running the control's Init again
                        if type('loControl') == 'O' and !isnull(loControl)
                            this.ApplyEventFor(loControl, 'Init')
                        endif
                    catch to loEx
                        this.oLogger.LogFromException(loEx)
                    endtry
                endfor
            endif
            if type('this.oThisform') == 'O' and !isnull(this.oThisform)
                unbindevents(this.oThisform, 'Activate', this, 'onActivate')
            endif
        catch to loEx
            this.oLogger.LogFromException(loEx)
        endtry
    endproc

    protected function GetCachedControl(tcControlPath)
        local loControl
        loControl = .null.
        try
            if type('this.oThisform') == 'O' and !isnull(this.oThisform)
                loControl = evaluate(tcControlPath)
            endif
        catch
            loControl = .null.
        endtry
        return loControl
    endfunc

    protected procedure getControlsByClass(toControl, tcClass, toControlList)
        local loControl, lcControlPath
        if type('toControl') != 'O' or isnull(toControl)
            return
        endif
        if !pemstatus(toControl, "Objects", 5)
            return
        endif
        try
            for each loControl in toControl.Objects
                if type('loControl') == 'O' and !isnull(loControl)
                    if lower(loControl.baseclass) == lower(tcClass) or lower(loControl.class) == lower(tcClass)
                        lcControlPath = sys(1272, loControl)
                        lcControlPath = 'this.oThisform' + substr(lcControlPath, at('.', lcControlPath))
                        toControlList.add(lcControlPath)
                    endif
                    this.getControlsByClass(loControl, tcClass, toControlList)
                endif
            endfor
        catch
        endtry
    endproc

    protected procedure getAllControls(toControl, toControlList)
        local loControl, lcControlPath
        if type('toControl') != 'O' or isnull(toControl)
            return
        endif
        if !pemstatus(toControl, "Objects", 5)
            return
        endif
        try
            for each loControl in toControl.Objects
                if type('loControl') == 'O' and !isnull(loControl)
                    lcControlPath = sys(1272, loControl)
                    lcControlPath = 'this.oThisform' + substr(lcControlPath, at('.', lcControlPath))
                    toControlList.add(lcControlPath)
                    this.getAllControls(loControl, toControlList)
                endif
            endfor
        catch
        endtry
    endproc

    protected function bindControlStyles(tcClassStylesProp, toControls, tcEvent, toStyles)
        local llOk
        llOk = .t.
        try
            local lcControl, loControl, lcProp, lcKey, lvValue, y, loStyles2, lcPath2
            lcProp = textmerge("o<<tcEvent>>Styles")
            for each lcControl in toControls
                loControl = this.GetCachedControl(lcControl)
                if type('loControl') != 'O'
                    loop
                endif
                if !empty(tcClassStylesProp)
                    if type('this.oThisform') == 'O'
                        if !pemstatus(this.oThisform, tcClassStylesProp, 5)
                            this.AddTrackedProperty(this.oThisform, tcClassStylesProp, toStyles)
                        else
                            this.oThisform. &tcClassStylesProp = toStyles
                        endif
                    endif
                else
                    if !pemstatus(loControl, lcProp, 5)
                        this.AddTrackedProperty(loControl, lcProp, .null.)
                        loControl. &lcProp = toStyles
                    else
                        loStyles2 = evaluate("loControl." + lcProp)
                        for y = 1 to toStyles.count
                            lcKey   = toStyles.getkey(y)
                            lvValue = toStyles.item(y)
                            if !empty(loStyles2.getkey(lcKey))
                                if lcKey == FSS_KEY and lvValue != loStyles2.item(lcKey)
                                    local lcOldV
                                    lcOldV  = loStyles2.item(lcKey)
                                    lvValue = lcOldV + FSS_SEPARATOR + lvValue
                                endif
                                loStyles2.remove(y)
                            endif
                            loStyles2.add(lvValue, lcKey)
                        endfor
                    endif
                endif
                if inlist(pemstatus(loControl, tcEvent, 3), 'Event', 'Method')
                    bindevent(loControl, tcEvent, this, "ControlBehavior")
                    if lower(tcEvent) == 'init'
                        lcPath2 = sys(1272, loControl)
                        lcPath2 = 'this.oThisform' + substr(lcPath2, at('.', lcPath2))
                        this.oControls.add(lcPath2)
                    endif
                endif
            endfor
        catch to loEx
            this.oLogger.LogFromException(loEx)
        endtry
        return llOk
    endfunc

    *-- Runs on every bound event. The styles are applied from the least to the
    *-- most specific: "*", the base class, the class itself, the control's name.
    protected function ControlBehavior(tv1, tv2, tv3, tv4, tv5)
        local array laEvents[1]

        =aevents(laEvents, 0)
        if alen(laEvents) < 2 or type('laEvents[1]') != 'O' or type('this.oThisform') != 'O' or isnull(this.oThisform)
            return
        endif
        this.ApplyEventFor(laEvents[1], laEvents[2])
    endfunc

    protected procedure ApplyEventFor(loControl, lcEvent)
        local array laStyles[4]
        local lnS

        store .null. to laStyles
        laStyles[1] = this.FormStyles('oStarClass' + lcEvent + 'Styles')
        laStyles[2] = this.FormStyles('o' + loControl.BaseClass + 'Class' + lcEvent + 'Styles')
        if !(lower(loControl.Class) == lower(loControl.BaseClass))
            laStyles[3] = this.FormStyles('o' + loControl.Class + 'Class' + lcEvent + 'Styles')
        endif
        if pemstatus(loControl, 'o' + lcEvent + 'Styles', 5)
            laStyles[4] = evaluate('loControl.o' + lcEvent + 'Styles')
        endif

        for lnS = 1 to 4
            if !isnull(laStyles[lnS])
                this.ApplyEventStyles(loControl, laStyles[lnS])
            endif
        endfor
        * an icon the theme did not draw follows the colours the event gave
        if pemstatus(loControl, 'cAutoIcon', 5) and !empty(loControl.cAutoIcon)
            this.ApplyIcon(loControl, '"' + loControl.cAutoIcon + '"')
        endif
    endproc

    protected function FormStyles(tcProp)
        if pemstatus(this.oThisform, tcProp, 5)
            return evaluate('this.oThisform.' + tcProp)
        endif
        return .null.
    endfunc

    protected procedure ApplyEventStyles(toControl, toStyles)
        local i, j, lcProp, lcValue, lcLine, lcFuncBody, lcCtrlLoc, lcScript, lbResp
        local array laLines[1]
        for i = 1 to toStyles.count
            lcProp  = toStyles.getkey(i)
            lcValue = toStyles.item(i)
            try
                do case
                case lcProp == FSS_KEY and left(lcValue, 1) != '$'
                    alines(laLines, lcValue, 5, FSS_SEPARATOR)
                    for j = 1 to alen(laLines, 1)
                        lcLine = this.EvalExpressionOptimized(laLines[j], .t.)
                        lcLine = this.RewriteThis(lcLine, 'toControl', 'this.oThisform')
                        &lcLine
                    endfor
                case lcProp == FSS_KEY
                    lcFuncBody = this.oFunctions.item(lower(substr(lcValue, 2)))
                    lcFuncBody = this.RewriteThis(lcFuncBody, 'loControl', '_screen.ActiveForm')
                    lcCtrlLoc  = sys(1272, toControl)
                    text to lcScript noshow textmerge
                        Local loControl
                        loControl = _screen.ActiveForm<<Substr(lcCtrlLoc, At('.',lcCtrlLoc))>>
                        If Type('loControl') != 'O'
                            Return
                        EndIf
                        <<lcFuncBody>>
                    ENDTEXT
                    execscript(lcScript)
                case lower(alltrim(lcProp)) == 'editmenu'
                    lbResp = this.EvalExpressionOptimized(lcValue)
                    if type('lbResp') == 'L' and lbResp
                        this.popMenu()
                    endif
                case lower(alltrim(lcProp)) == 'icon'
                    this.ApplyIcon(toControl, lcValue)
                otherwise
                    toControl. &lcProp = this.EvalExpressionOptimized(lcValue)
                endcase
            catch to loEx
                this.oLogger.LogFromException(loEx)
            endtry
        endfor
    endproc

    *-- this and thisform in a line of theme code, rewritten as words and only
    *-- outside string literals: "this.Tag = 'this field'" keeps its text.
    protected function RewriteThis(tcCode, tcThis, tcThisform)
        local lcOut, lnI, lnLen, lcChar, lcQuote, lnStart, lcWord, lcPrev
        lcOut   = ''
        lcQuote = ''
        lnLen   = len(tcCode)
        lnI     = 1
        do while lnI <= lnLen
            lcChar = substr(tcCode, lnI, 1)
            do case
            case !empty(lcQuote)
                lcOut = lcOut + lcChar
                if lcChar == lcQuote
                    lcQuote = ''
                endif
                lnI = lnI + 1
            case lcChar == '"' or lcChar == "'"
                lcQuote = lcChar
                lcOut   = lcOut + lcChar
                lnI     = lnI + 1
            case lcChar == '['
                * a string, unless it is an array subscript: laX[1], loX.aItems[2]
                lcPrev = right(rtrim(lcOut), 1)
                if !(isalpha(lcPrev) or isdigit(lcPrev) or lcPrev == '_' or lcPrev == ')')
                    lcQuote = ']'
                endif
                lcOut = lcOut + lcChar
                lnI   = lnI + 1
            case isalpha(lcChar) or lcChar == '_'
                lnStart = lnI
                do while lnI <= lnLen and (isalpha(substr(tcCode, lnI, 1)) or isdigit(substr(tcCode, lnI, 1)) or substr(tcCode, lnI, 1) == '_')
                    lnI = lnI + 1
                enddo
                lcWord = substr(tcCode, lnStart, lnI - lnStart)
                do case
                case right(lcOut, 1) == '.'
                    * a member (loX.this) or a logical (.T.), not the keyword
                    lcOut = lcOut + lcWord
                case lower(lcWord) == 'thisform'
                    lcOut = lcOut + tcThisform
                case lower(lcWord) == 'this'
                    lcOut = lcOut + tcThis
                otherwise
                    lcOut = lcOut + lcWord
                endcase
            otherwise
                lcOut = lcOut + lcChar
                lnI   = lnI + 1
            endcase
        enddo
        return lcOut
    endfunc

    protected function ExtractFunctions(tcContent)
        local loBlocks, loBlock, lcName
        loBlocks = this.ParseBlocks(tcContent)
        for each loBlock in loBlocks
            if this.IsFunctionHead(loBlock.Head)
                lcName = lower(alltrim(substr(chrtran(loBlock.Head, chr(9) + chr(13) + chr(10), '   '), 9)))
                if this.oFunctions.getkey(lcName) > 0
                    this.oFunctions.remove(lcName)
                endif
                this.oFunctions.add(loBlock.Body, lcName)
            endif
        endfor
    endfunc

    protected function IsFunctionHead(tcHead)
        return lower(getwordnum(chrtran(tcHead, chr(9) + chr(13) + chr(10), '   '), 1)) == 'function'
    endfunc

    protected function TrimAll(tcText)
        return alltrim(tcText, 1, ' ', chr(9), chr(13), chr(10))
    endfunc

    *----------------------------------------------------------
    * Variable / expression evaluation
    *----------------------------------------------------------
    protected function EvalExpressionOptimized(tcValue, tbJustExpand)
        local lcValue, lcBefore, lnLevel, lvResult
        lcValue = tcValue
        if '$' $ lcValue
            lcValue = this.ExpandVariables(lcValue)
            * a resource may name another ($borderFocus = $accent), 5 levels at most
            lnLevel = 0
            do while left(lcValue, 1) == '$' and lnLevel < 5
                lcBefore = lcValue
                lcValue  = this.ExpandVariables(lcValue)
                if lcValue == lcBefore
                    exit
                endif
                lnLevel = lnLevel + 1
            enddo
        endif

        lvResult = lcValue
        if !tbJustExpand
            try
                lvResult = evaluate(lcValue)
            catch
            endtry
        endif
        return lvResult
    endfunc

    *-- Replaces each $name by its resource, as a whole word ($accent does not
    *-- touch $accentSoft); an unknown name stays as written.
    protected function ExpandVariables(tcText)
        local lcOut, lcRest, lnAt, lnEnd, lcName, lcValue
        lcOut  = ''
        lcRest = tcText
        lnAt   = at('$', lcRest)
        do while lnAt > 0
            lcOut  = lcOut + left(lcRest, lnAt - 1)
            lcRest = substr(lcRest, lnAt + 1)
            lnEnd  = 1
            do while lnEnd <= len(lcRest) and this.IsWordChar(substr(lcRest, lnEnd, 1))
                lnEnd = lnEnd + 1
            enddo
            lcName  = left(lcRest, lnEnd - 1)
            lcValue = iif(empty(lcName), '', this.GetResourceOptimized(lcName))
            if empty(lcValue)
                lcOut = lcOut + '$' + lcName
            else
                lcOut = lcOut + lcValue
            endif
            lcRest = substr(lcRest, lnEnd)
            lnAt   = at('$', lcRest)
        enddo
        return lcOut + lcRest
    endfunc

    protected function IsWordChar(tcChar)
        return isalpha(tcChar) or isdigit(tcChar) or tcChar == '_'
    endfunc

    *----------------------------------------------------------
    * DrawImage: a solid-colour 24-bit BMP, written byte by byte: it needs no
    * GDI+, no helper application and no COM. Returns .T. when the file is there.
    *----------------------------------------------------------
    function DrawImage(tcOutput, tnWidth, tnHeight, tnRed, tnGreen, tnBlue)
        local lnRowBytes, lnPixels, lcRow, lcBmp, lcSafety, llResult, loEx

        if tnWidth <= 0 or tnHeight <= 0
            this.oLogger.LogWarning("DrawImage: invalid dimensions.")
            return .f.
        endif
        if tnRed < 0 or tnRed > 255 or tnGreen < 0 or tnGreen > 255 or tnBlue < 0 or tnBlue > 255
            this.oLogger.LogWarning("DrawImage: RGB out of range.")
            return .f.
        endif

        * every row is padded to a multiple of 4 bytes; pixels go as B, G, R
        lnRowBytes = ceiling(tnWidth * 3 / 4) * 4
        lnPixels   = lnRowBytes * tnHeight
        lcRow = replicate(chr(tnBlue) + chr(tnGreen) + chr(tnRed), tnWidth) + replicate(chr(0), lnRowBytes - tnWidth * 3)
        lcBmp = 'BM' + bintoc(54 + lnPixels, '4RS') + bintoc(0, '4RS') + bintoc(54, '4RS') + ;
                bintoc(40, '4RS') + bintoc(tnWidth, '4RS') + bintoc(tnHeight, '4RS') + ;
                bintoc(1, '2RS') + bintoc(24, '2RS') + bintoc(0, '4RS') + bintoc(lnPixels, '4RS') + ;
                bintoc(2835, '4RS') + bintoc(2835, '4RS') + bintoc(0, '4RS') + bintoc(0, '4RS') + ;
                replicate(lcRow, tnHeight)

        * STRTOFILE over an existing file asks with SET SAFETY ON (rule 63)
        lcSafety = set("Safety")
        set safety off
        llResult = .f.
        try
            llResult = strtofile(lcBmp, tcOutput) = len(lcBmp)
        catch to loEx
            this.oLogger.LogFromException(loEx)
        endtry
        set safety &lcSafety

        if llResult
            this.oImages.add(tcOutput)
        endif
        return llResult
    endfunc

    *----------------------------------------------------------
    * Icons: "sun" and "moon", drawn here as a BMP like DrawImage.
    *----------------------------------------------------------
    *-- icon = "sun" in a block: the control's Picture gets the icon, in its
    *-- ForeColor over its BackColor, sized to the control. Set those two
    *-- before icon in the block, and repeat icon in the event blocks that
    *-- change them.
    protected procedure ApplyIcon(toControl, tcValue)
        local lcIcon, lnSize, lnColor, lnBack, lcFile, loEx
        lcIcon = this.EvalExpressionOptimized(tcValue)
        if vartype(lcIcon) != 'C'
            lcIcon = tcValue
        endif
        lcIcon = lower(alltrim(chrtran(lcIcon, ['"], '')))
        if !pemstatus(toControl, 'Picture', 5)
            this.oLogger.LogWarning("icon: " + toControl.Name + " has no Picture")
            return
        endif
        lnSize  = max(12, min(48, round(min(toControl.Height, toControl.Width) * 0.6, 0)))
        lnColor = iif(pemstatus(toControl, 'ForeColor', 5), toControl.ForeColor, 0)
        lnBack  = iif(pemstatus(toControl, 'BackColor', 5), toControl.BackColor, rgb(255, 255, 255))
        * one file per icon, size and colours: VFP keeps a picture by its name
        lcFile  = this.cPath + textmerge('icon_<<lcIcon>>_<<lnSize>>_<<lnColor>>_<<lnBack>>.bmp')
        if !file(lcFile) and !this.DrawIcon(lcFile, lcIcon, lnSize, lnColor, lnBack)
            return
        endif
        try
            toControl.Picture = lcFile
        catch to loEx
            this.oLogger.LogFromException(loEx)
        endtry
    endproc

    *-- FssThemeToggle shows the icon its theme gives it. Under a theme that
    *-- does not know it (Word, black...) it shows a moon when the form is
    *-- dark and a sun when it is light.
    protected procedure ClearToggleIcons(toForm)
        local loToggles, lcPath, loToggle
        loToggles = createobject("Collection")
        this.getControlsByClass(toForm, 'fssthemetoggle', loToggles)
        for each lcPath in loToggles
            loToggle = this.GetCachedControl(lcPath)
            if type('loToggle') == 'O' and !isnull(loToggle)
                loToggle.Picture = ''
                loToggle.cAutoIcon = ''
            endif
        endfor
    endproc

    protected procedure RefreshToggleIcons(toForm)
        local loToggles, lcPath, loToggle, lnBack, lnLight
        loToggles = createobject("Collection")
        this.getControlsByClass(toForm, 'fssthemetoggle', loToggles)
        if loToggles.count = 0
            return
        endif
        lnBack  = toForm.BackColor
        lnLight = 0.299 * bitand(lnBack, 255) + 0.587 * bitand(bitrshift(lnBack, 8), 255) + 0.114 * bitand(bitrshift(lnBack, 16), 255)
        for each lcPath in loToggles
            loToggle = this.GetCachedControl(lcPath)
            if type('loToggle') == 'O' and !isnull(loToggle) and empty(loToggle.Picture)
                loToggle.cAutoIcon = iif(lnLight < 128, 'moon', 'sun')
                this.ApplyIcon(loToggle, '"' + loToggle.cAutoIcon + '"')
            endif
        endfor
    endproc

    *-- Writes the icon tcIcon ("sun" or "moon") as a tnSize x tnSize 24-bit
    *-- BMP, in tnColor over tnBackColor, with smooth edges (each pixel is
    *-- sampled nine times). Returns .T. when the file is there.
    function DrawIcon(tcOutput, tcIcon, tnSize, tnColor, tnBackColor)
        local lcIcon, lnRowBytes, lcPixels, lcRow, lcBmp, lcSafety, llResult, loEx
        local lnX, lnY, lnSX, lnSY, lnHits, lnA
        local lnFR, lnFG, lnFB, lnBR, lnBG, lnBB

        lcIcon = lower(alltrim(iif(vartype(tcIcon) == 'C', tcIcon, '')))
        if !inlist(lcIcon, 'sun', 'moon')
            this.oLogger.LogWarning("DrawIcon: unknown icon '" + lcIcon + "'. There are: sun, moon")
            return .f.
        endif
        if vartype(tnSize) != 'N' or tnSize < 8 or tnSize > 256
            this.oLogger.LogWarning("DrawIcon: the size goes from 8 to 256 pixels.")
            return .f.
        endif
        tnSize = int(tnSize)
        lnFR = bitand(tnColor, 255)
        lnFG = bitand(bitrshift(tnColor, 8), 255)
        lnFB = bitand(bitrshift(tnColor, 16), 255)
        lnBR = bitand(tnBackColor, 255)
        lnBG = bitand(bitrshift(tnBackColor, 8), 255)
        lnBB = bitand(bitrshift(tnBackColor, 16), 255)

        * the rows of a BMP go from the bottom up, padded to 4 bytes, as B, G, R
        lnRowBytes = ceiling(tnSize * 3 / 4) * 4
        lcPixels = ''
        for lnY = tnSize - 1 to 0 step -1
            lcRow = ''
            for lnX = 0 to tnSize - 1
                lnHits = 0
                for lnSY = 1 to 3
                    for lnSX = 1 to 3
                        if this.IconCovers(lcIcon, (lnX + (lnSX - 0.5) / 3) / tnSize, (lnY + (lnSY - 0.5) / 3) / tnSize)
                            lnHits = lnHits + 1
                        endif
                    endfor
                endfor
                lnA = lnHits / 9
                lcRow = lcRow + chr(round(lnBB + (lnFB - lnBB) * lnA, 0)) + ;
                                chr(round(lnBG + (lnFG - lnBG) * lnA, 0)) + ;
                                chr(round(lnBR + (lnFR - lnBR) * lnA, 0))
            endfor
            lcPixels = lcPixels + lcRow + replicate(chr(0), lnRowBytes - tnSize * 3)
        endfor
        lcBmp = 'BM' + bintoc(54 + len(lcPixels), '4RS') + bintoc(0, '4RS') + bintoc(54, '4RS') + ;
                bintoc(40, '4RS') + bintoc(tnSize, '4RS') + bintoc(tnSize, '4RS') + ;
                bintoc(1, '2RS') + bintoc(24, '2RS') + bintoc(0, '4RS') + bintoc(len(lcPixels), '4RS') + ;
                bintoc(2835, '4RS') + bintoc(2835, '4RS') + bintoc(0, '4RS') + bintoc(0, '4RS') + ;
                lcPixels

        lcSafety = set("Safety")
        set safety off
        llResult = .f.
        try
            llResult = strtofile(lcBmp, tcOutput) = len(lcBmp)
        catch to loEx
            this.oLogger.LogFromException(loEx)
        endtry
        set safety &lcSafety

        if llResult
            this.oImages.add(tcOutput)
        endif
        return llResult
    endfunc

    *-- Whether the point (tnU, tnV) of the icon, from 0 to 1 with V going
    *-- down, is ink. The sun is a disc with eight rays; the moon, a disc
    *-- with a bite taken from its upper right.
    protected function IconCovers(tcIcon, tnU, tnV)
        local lnDX, lnDY, lnR, lnAngle, lnRay
        lnDX = tnU - 0.5
        lnDY = tnV - 0.5
        lnR  = sqrt(lnDX * lnDX + lnDY * lnDY)
        if tcIcon == 'sun'
            if lnR <= 0.21
                return .t.
            endif
            if lnR < 0.30 or lnR > 0.47
                return .f.
            endif
            lnAngle = atn2(lnDY, lnDX)
            lnRay   = round(lnAngle / (pi() / 4), 0) * pi() / 4
            return lnR * abs(sin(lnAngle - lnRay)) <= 0.055
        endif
        * moon
        if lnR > 0.40
            return .f.
        endif
        lnDX = tnU - 0.70
        lnDY = tnV - 0.33
        return sqrt(lnDX * lnDX + lnDY * lnDY) > 0.33
    endfunc

    *----------------------------------------------------------
    * Title bar without Codejock: Windows draws it (DWM)
    *----------------------------------------------------------
    *-- darkTitleBar = .T. (Windows 10 2004 and later), titleBarColor and
    *-- titleBarTextColor = rgb() (Windows 11; -1 gives the colour back to
    *-- Windows). Only a top-level form has a title bar of its own: on a form
    *-- inside _screen, and on older Windows, they do nothing.
    protected procedure SetTitleBar(toForm, tcProperty, tvValue)
        local lnValue, lnResult, loEx
        if type('toForm.HWnd') != 'N' or toForm.HWnd = 0
            return
        endif
        try
            declare integer DwmSetWindowAttribute in dwmapi.dll as FssDwmSetWindowAttribute ;
                integer hwnd, integer dwAttribute, integer @pvAttribute, integer cbAttribute
            declare integer SetWindowPos in user32 as FssSetWindowPos ;
                integer hWnd, integer hWndInsertAfter, integer x, integer y, integer cx, integer cy, integer uFlags
            do case
            case tcProperty == 'darktitlebar'
                lnValue = iif(vartype(tvValue) == 'L' and tvValue, 1, 0)
                lnResult = FssDwmSetWindowAttribute(toForm.HWnd, DWMWA_USE_IMMERSIVE_DARK_MODE, @lnValue, 4)
                if lnResult != 0
                    lnResult = FssDwmSetWindowAttribute(toForm.HWnd, DWMWA_USE_IMMERSIVE_DARK_MODE_OLD, @lnValue, 4)
                endif
            case vartype(tvValue) != 'N'
                this.oLogger.LogWarning(tcProperty + " needs a colour, rgb(r, g, b), or -1")
                return
            case tcProperty == 'titlebarcolor'
                lnValue = iif(tvValue < 0, -1, tvValue)
                lnResult = FssDwmSetWindowAttribute(toForm.HWnd, DWMWA_CAPTION_COLOR, @lnValue, 4)
            otherwise
                lnValue = iif(tvValue < 0, -1, tvValue)
                lnResult = FssDwmSetWindowAttribute(toForm.HWnd, DWMWA_TEXT_COLOR, @lnValue, 4)
            endcase
            * SWP_NOSIZE + SWP_NOMOVE + SWP_NOZORDER + SWP_FRAMECHANGED: repaint the frame now
            =FssSetWindowPos(toForm.HWnd, 0, 0, 0, 0, 0, 0x27)
            this.lTitleBarSet = .t.
            if lnResult != 0
                this.oLogger.LogDebug(tcProperty + ": Windows did not take it (" + transform(lnResult, '@0') + ")")
            endif
        catch to loEx
            this.oLogger.LogDebug(tcProperty + ": " + loEx.Message)
        endtry
    endproc

    *----------------------------------------------------------
    * Edit context menu
    *----------------------------------------------------------
    procedure popMenu
        define popup EditMenu from mrow(), mcol() margin relative shadow color scheme 4 SHORTCUT
        define bar _med_undo  of EditMenu prompt "\<Undo"            key CTRL+Z, "Ctrl+Z" PICTRES _med_undo  message "Undoes the last change"
        define bar _med_redo  of EditMenu prompt "\<Redo"            key CTRL+R, "Ctrl+R" PICTRES _med_redo  message "Redoes the last change"
        define bar _med_sp100 of EditMenu prompt "\-"                PICTRES _med_sp100
        define bar _med_cut   of EditMenu prompt "Cu\<t"             key CTRL+X, "Ctrl+X" PICTRES _med_cut   message "Moves the selection to the Clipboard"
        define bar _med_copy  of EditMenu prompt "\<Copy"            key CTRL+C, "Ctrl+C" PICTRES _med_copy  message "Copies the selection to the Clipboard"
        define bar _med_paste of EditMenu prompt "\<Paste"           key CTRL+V, "Ctrl+V" PICTRES _med_paste message "Pastes the contents of the Clipboard"
        define bar _med_pstlk of EditMenu prompt "Paste \<Special..."                   PICTRES _med_pstlk message "Pastes as a linked or embedded object"
        define bar _med_clear of EditMenu prompt "Cle\<ar"                              PICTRES _med_clear message "Removes the selection without copying it"
        define bar _med_sp200 of EditMenu prompt "\-"                PICTRES _med_sp200
        define bar _med_slcta of EditMenu prompt "Select \<All"      key CTRL+A, "Ctrl+A" PICTRES _med_slcta message "Selects everything"
        define bar _med_sp300 of EditMenu prompt "\-"                PICTRES _med_sp300
        activate popup EditMenu
    endproc

    *----------------------------------------------------------
    * Codejock title bar (optional feature)
    *----------------------------------------------------------
    protected procedure addTitleBar(toThisform, tcColor)
        local lcFssPath, lcSkinFile, lcOcxFile, lcSchema, llOk
        lcFssPath  = this.cPrgPath + 'Fss\'
        lcSkinFile = iif(empty(this.cSkinFile), lcFssPath + 'Windows10.cjstyles', this.cSkinFile)
        lcOcxFile  = iif(empty(this.cCodejockOcx), lcFssPath + 'Codejock.SkinFramework.v22.1.0.ocx', this.cCodejockOcx)

        if !file(lcSkinFile)
            this.oLogger.LogDebug("addTitleBar skipped: the skin file " + lcSkinFile + " is not there (see cSkinFile).")
            return
        endif

        * Auto-register OCX if not yet installed (requires admin)
        if !this.IsCodejockAvailable()
            if file(lcOcxFile)
                local loHelper
                loHelper = createobject("FssOCXHelper")
                loHelper.SetLogger(this.oLogger)
                if !loHelper.registerClass(lcOcxFile, this.cCodejockProgId)
                    this.oLogger.LogDebug("addTitleBar skipped: Codejock OCX found but registration failed (run as Administrator once).")
                    return
                endif
            else
                this.oLogger.LogDebug("addTitleBar skipped: " + this.cCodejockProgId + " is not registered and " + lcOcxFile + " is not there (see cCodejockOcx).")
                return
            endif
        endif

        llOk = .t.
        try
            lcSchema = this.getSchema(lower(tcColor))
            if empty(lcSchema)
                this.oLogger.LogWarning("addTitleBar: unknown theme '" + tcColor + "'")
                llOk = .f.
            endif
        catch to loEx
            this.oLogger.LogFromException(loEx)
            llOk = .f.
        endtry

        if !llOk
            return
        endif

        try
            if type('_screen.oFssTitleBar') == 'O' and vartype(_screen.oFssTitleBar) != 'X'
                _screen.oFssTitleBar.paintTitleBar(lcSkinFile, lcSchema, toThisform, this.cCodejockProgId)
            else
                =addproperty(_screen, 'oFssTitleBar', createobject('FssCustomTitleBar'))
                _screen.oFssTitleBar.paintTitleBar(lcSkinFile, lcSchema, toThisform, this.cCodejockProgId)
            endif
        catch to loEx
            this.oLogger.LogFromException(loEx)
        endtry
    endproc

    protected function getSchema(tcColor)
        local lcResult
        do case
        case tcColor == 'word'
            lcResult = 'Normal Microsoft Office Word.ini'
        case tcColor == 'excel'
            lcResult = 'Normal Microsoft Office Excel.ini'
        case tcColor == 'access'
            lcResult = 'Normal Microsoft Office Access.ini'
        case tcColor == 'powerpoint'
            lcResult = 'Normal Microsoft Office Powerpoint.ini'
        case tcColor == 'publisher'
            lcResult = 'Normal Microsoft Office Publisher.ini'
        case tcColor == 'onenote'
            lcResult = 'Normal Microsoft Office OneNote.ini'
        case tcColor == 'outlook'
            lcResult = 'Normal Microsoft Office Outlook.ini'
        case tcColor == 'red'
            lcResult = 'NormalRed.ini'
        case tcColor == 'gold'
            lcResult = 'NormalGold.ini'
        case tcColor == 'gray'
            lcResult = 'NormalGray.ini'
        case tcColor == 'black'
            lcResult = 'NormalBlack.ini'
        case tcColor == 'white'
            lcResult = 'NormalWhite.ini'
        otherwise
            lcResult = ''
        endcase
        return lcResult
    endfunc

    *----------------------------------------------------------
    * Logging facade (delegates to FssLogger)
    *----------------------------------------------------------
    procedure LogInfo(tcMessage)
        if vartype(this.oLogger) == 'O'
            this.oLogger.LogInfo(tcMessage)
        endif
    endproc

    procedure LogWarning(tcMessage)
        if vartype(this.oLogger) == 'O'
            this.oLogger.LogWarning(tcMessage)
        endif
    endproc

    procedure LogError(tcMessage)
        if vartype(this.oLogger) == 'O'
            this.oLogger.LogError(tcMessage)
        endif
    endproc

    procedure LogDebug(tcMessage)
        if vartype(this.oLogger) == 'O'
            this.oLogger.LogDebug(tcMessage)
        endif
    endproc

enddefine


*==============================================================
* CLASS: FssStyleMetrics
* Performance counters for a single link() call.
*==============================================================
define class FssStyleMetrics as custom
    nStylesApplied     = 0
    nControlsProcessed = 0
    nParseTime         = 0
    nApplyTime         = 0
    nStartTime         = 0

    procedure Reset
        this.nStylesApplied     = 0
        this.nControlsProcessed = 0
        this.nParseTime         = 0
        this.nApplyTime         = 0
        this.nStartTime         = 0
    endproc

    procedure StartTimer
        this.nStartTime = seconds()
    endproc

    procedure EndTimer(tcOperation)
        local lnElapsed
        lnElapsed = seconds() - this.nStartTime
        do case
        case tcOperation == 'parse'
            this.nParseTime = lnElapsed
        case tcOperation == 'apply'
            this.nApplyTime = lnElapsed
        endcase
    endproc

    function GetReport()
        local lcReport
        lcReport = "FoxStyleSheet v" + FSS_VERSION + " - Performance" + CRLF + ;
                   "  Styles   : " + transform(this.nStylesApplied)     + CRLF + ;
                   "  Controls : " + transform(this.nControlsProcessed)  + CRLF + ;
                   "  Parse    : " + transform(this.nParseTime)  + "s"  + CRLF + ;
                   "  Apply    : " + transform(this.nApplyTime)  + "s"  + CRLF + ;
                   "  Total    : " + transform(this.nParseTime + this.nApplyTime) + "s"
        return lcReport
    endfunc
enddefine


*==============================================================
* CLASS: FssOCXHelper
* COM registration helper for Codejock SkinFramework.
*==============================================================
define class FssOCXHelper as custom
    protected oLogger

    procedure SetLogger(toLogger)
        this.oLogger = toLogger
    endproc

    function isClassRegistered(tcProgID)
        local lbRegistered, nPos
        declare integer RegOpenKey  in Win32API integer nHKey, string @cSubKey, integer @nResult
        declare integer RegCloseKey in Win32API integer nHKey
        nPos = 0
        lbRegistered = RegOpenKey(-2147483648, tcProgID, @nPos) = 0
        if lbRegistered
            RegCloseKey(nPos)
        endif
        clear dlls RegOpenKey, RegCloseKey
        return lbRegistered
    endfunc

    function registerClass(tcOCXFile, tcProgID)
        if !this.isAdmin()
            if vartype(this.oLogger) == 'O'
                this.oLogger.LogError("Must run as Administrator to register Codejock OCX.")
            endif
            return .f.
        endif
        local lbOk, lnDeadline
        lbOk = .f.
        if this.RegOCX(tcOCXFile)
            lnDeadline = seconds() + 10
            lbOk = this.isClassRegistered(tcProgID)
            do while !lbOk and seconds() < lnDeadline
                lbOk = this.isClassRegistered(tcProgID)
                if lbOk
                    exit
                endif
            enddo
        endif
        return lbOk
    endfunc

    function RegOCX(tcOCXFile)
        local lnErr
        lnErr = 0
        try
            declare long DllRegisterServer in (tcOCXFile)
        catch
            lnErr = 1
        endtry
        if lnErr = 0
            try
                lnErr = DllRegisterServer()
            catch
                lnErr = 2
            endtry
        endif
        clear dlls DllRegisterServer
        return lnErr == 0
    endfunc

    function isAdmin()
        local lnResult
        declare integer IsUserAnAdmin in Shell32
        try
            lnResult = IsUserAnAdmin()
        catch
            lnResult = 1
        endtry
        clear dlls IsUserAnAdmin
        return lnResult != 0
    endfunc
enddefine


*==============================================================
* CLASS: FssLogger
* Structured logging: Info / Warning / Error / Debug levels.
* lDebugMode = .F. by default; set .T. for verbose output.
*==============================================================
define class FssLogger as custom
    protected cLogFile
    lDebugMode   = .f.
    nMaxLogBytes = 1048576
    nErrors    = 0
    oErrors    = .null.
    cLastError = ''

    procedure init
        this.oErrors = createobject("Collection")
    endproc

    procedure ClearErrors
        this.nErrors    = 0
        this.oErrors    = createobject("Collection")
        this.cLastError = ''
    endproc

    procedure SetLogFile(tcLogFile)
        this.cLogFile = tcLogFile
    endproc

    procedure LogFromException(toEx as exception)
        local lcMsg
        lcMsg = "Error " + transform(toEx.ErrorNo) + ;
                " line "  + transform(toEx.LineNo)  + ;
                ": "      + toEx.Message            + ;
                " in "    + toEx.Procedure
        this.log(LOG_ERROR, lcMsg)
    endproc

    procedure LogInfo(tcMessage)
        this.log(LOG_INFO, tcMessage)
    endproc

    procedure LogWarning(tcMessage)
        this.log(LOG_WARNING, tcMessage)
    endproc

    procedure LogError(tcMessage)
        this.log(LOG_ERROR, tcMessage)
    endproc

    procedure LogDebug(tcMessage)
        if !this.lDebugMode
            return
        endif
        this.log(LOG_DEBUG, tcMessage)
    endproc

    procedure log(tnType, tcMessage)
        local lcType, lcLine

        * Support legacy single-string call: log("message")
        if type('tnType') == 'C'
            tcMessage = tnType
            tnType    = LOG_INFO
        endif
        if empty(this.cLogFile)
            this.cLogFile = addbs(addbs(getenv("APPDATA")) + 'FoxStyleSheet') + 'FoxStyleSheet.log'
        endif

        if tnType = LOG_ERROR
            this.nErrors    = this.nErrors + 1
            this.oErrors.add(tcMessage)
            this.cLastError = tcMessage
        endif

        do case
        case tnType = LOG_ERROR
            lcType = "ERROR  "
        case tnType = LOG_WARNING
            lcType = "WARNING"
        case tnType = LOG_DEBUG
            lcType = "DEBUG  "
        otherwise
            lcType = "INFO   "
        endcase

        * ISO date and time: it does not depend on SET DATE, and does not touch it
        lcLine = ttoc(datetime(), 3) + " | " + lcType + " | " + tcMessage + CRLF
        try
            if !directory(justpath(this.cLogFile))
                md (justpath(this.cLogFile))
            endif
            this.CapLogFile()
            =strtofile(lcLine, this.cLogFile, 1)
        catch
        endtry
    endproc

    * Past nMaxLogBytes the log moves to .old (replacing the previous one) and
    * starts again; 0 means no cap. ADIR gives the size (FSIZE needs SET COMPATIBLE).
    protected procedure CapLogFile
        local laInfo[1], lcOld
        if this.nMaxLogBytes > 0 and adir(laInfo, this.cLogFile) = 1 and laInfo[1, 2] > this.nMaxLogBytes
            lcOld = forceext(this.cLogFile, 'old')
            if file(lcOld)
                erase (lcOld)
            endif
            rename (this.cLogFile) to (lcOld)
        endif
    endproc
enddefine


*==============================================================
* CLASS: FssCustomTitleBar
* Codejock SkinFramework integration. Only instantiated when
* IsCodejockAvailable() returns .T.; the OLE control is created with the
* ProgId the engine was given (cCodejockProgId).
*==============================================================
define class FssCustomTitleBar as custom
    * At run time only a Form takes an OleControl (a Custom or _screen give
    * error 1744), so the control lives on a Form that is never shown.
    oHost = .null.

    procedure paintTitleBar(tcStyleFile, tcIniFile, toForm, tcProgId)
        if isnull(this.oHost)
            this.oHost = createobject('Form')
            this.oHost.AddObject('oSkin', 'OleControl', evl(tcProgId, 'Codejock.SkinFramework.22.1.0'))
        endif
        with this.oHost.oSkin
            .loadSkin(tcStyleFile, tcIniFile)
            .applyWindow(toForm.hwnd)
            .ApplyOptions = 2
        endwith
    endproc
enddefine


*==============================================================
* CLASS: FssThemeToggle
* A button that switches the form between two themes, "light" and
* "dark" unless you say otherwise. The themes draw it: the built-in
* light and dark give it a sun and a moon (icon = "sun").
*
*   ThisForm.NewObject("cmdTheme", "FssThemeToggle", "foxstylesheet.prg")
*
* Click links the other theme with the engine already on the form (or a
* new one), and then calls ThemeChanged(cTheme): bind to it, or subclass
* it, to save the choice of the user.
*==============================================================
define class FssThemeToggle as CommandButton
    Caption         = ""
    Width           = 32
    Height          = 32
    PicturePosition = 13
    ToolTipText     = "Switch between the light and the dark theme"
    cLightTheme     = "light"
    cDarkTheme      = "dark"
    * the icon link() chose because the theme did not draw one
    cAutoIcon       = ""

    procedure Click
        this.Toggle()
    endproc

    * Links the other theme. Returns the one it linked.
    function Toggle
        local loFss, lcTheme
        loFss = FssEngineOf(thisform)
        if isnull(loFss)
            loFss = createobject("FoxStyleSheet")
        endif
        lcTheme = iif(lower(juststem(loFss.cTheme)) == lower(juststem(this.cDarkTheme)), this.cLightTheme, this.cDarkTheme)
        loFss.link(lcTheme, thisform)
        this.ThemeChanged(lcTheme)
        return lcTheme
    endfunc

    * Called after every switch, with the theme now on the form
    procedure ThemeChanged(tcTheme)
    endproc
enddefine


*==============================================================
* FssEngineOf(oForm): the FoxStyleSheet engine that link() hung from the
* form, or .NULL. when no theme was linked to it.
*==============================================================
FUNCTION FssEngineOf
    LPARAMETERS toForm
    LOCAL laMembers[1], lnI, loEngine
    loEngine = .null.
    IF VARTYPE(toForm) != 'O'
        RETURN loEngine
    ENDIF
    FOR lnI = 1 TO AMEMBERS(laMembers, toForm, 0)
        IF UPPER(LEFT(laMembers[lnI], LEN(FSS_ENGINE_PROPERTY))) == UPPER(FSS_ENGINE_PROPERTY) ;
                AND TYPE('toForm.' + laMembers[lnI]) == 'O'
            loEngine = EVALUATE('toForm.' + laMembers[lnI])
            IF !ISNULL(loEngine)
                EXIT
            ENDIF
        ENDIF
    ENDFOR
    RETURN loEngine
ENDFUNC


*==============================================================
* FssSystemTheme(): "dark" when Windows is set to dark mode for
* applications, "light" otherwise (and on Windows without the setting).
*   loFss.link(FssSystemTheme(), ThisForm)
*==============================================================
FUNCTION FssSystemTheme
    LOCAL lnKey, lnType, lnValue, lnSize, lcTheme
    lcTheme = "light"
    TRY
        DECLARE INTEGER RegOpenKeyEx IN advapi32 AS FssRegOpenKeyEx ;
            INTEGER hKey, STRING lpSubKey, INTEGER ulOptions, INTEGER samDesired, INTEGER @phkResult
        DECLARE INTEGER RegQueryValueEx IN advapi32 AS FssRegQueryValueEx ;
            INTEGER hKey, STRING lpValueName, INTEGER lpReserved, INTEGER @lpType, INTEGER @lpData, INTEGER @lpcbData
        DECLARE INTEGER RegCloseKey IN advapi32 AS FssRegCloseKey INTEGER hKey
        lnKey = 0
        * HKEY_CURRENT_USER, KEY_READ
        IF FssRegOpenKeyEx(-2147483647, "Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", 0, 131097, @lnKey) = 0
            lnType  = 0
            lnValue = 1
            lnSize  = 4
            IF FssRegQueryValueEx(lnKey, "AppsUseLightTheme", 0, @lnType, @lnValue, @lnSize) = 0 AND lnValue = 0
                lcTheme = "dark"
            ENDIF
            =FssRegCloseKey(lnKey)
        ENDIF
    CATCH
        lcTheme = "light"
    ENDTRY
    RETURN lcTheme
ENDFUNC

*==============================================================
*-- BEGIN BUILT-IN THEMES
*-- Generated by tools\build-themes.ps1 from themes\*.fss: do not edit by hand,
*-- change the .fss and run the script again.
*==============================================================
FUNCTION FssBuiltInTheme
    LPARAMETERS tcName
    LOCAL lcTheme
    lcTheme = ""
    DO CASE
    CASE LOWER(tcName) == "access"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Access (Burgundy Red) */

_res_ {
    white           = rgb(255, 255, 255)
    black           = rgb(0, 0, 0)
    accent          = rgb(175, 30, 35)
    accentDark      = rgb(130, 20, 25)
    accentSoft      = rgb(255, 232, 234)
    accentFocus     = rgb(255, 222, 226)
    surface         = rgb(252, 243, 244)
    surfaceAlt      = rgb(255, 255, 255)
    textPrimary     = rgb(30, 30, 30)
    textSecondary   = rgb(80, 85, 95)
    border          = rgb(175, 180, 188)
    borderFocus     = $accent
    selection       = rgb(255, 200, 205)
    selectionText   = $black
    disabled        = rgb(242, 242, 242)
    disabledText    = rgb(158, 158, 158)
    header          = $accent
    headerText      = $white
    font            = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "Powerpoint"
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "black"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Black (Sleek Dark) */

_res_ {
    white                = rgb(255, 255, 255)
    black                = rgb(0, 0, 0)
    bg                   = rgb(30, 30, 30)
    surface              = rgb(45, 45, 45)
    surfaceRaised        = rgb(55, 55, 55)
    border               = rgb(70, 70, 70)
    accent               = rgb(100, 180, 255)
    accentDark           = rgb(60, 140, 220)
    accentSoft           = rgb(35, 55, 75)
    accentFocus          = rgb(35, 50, 65)
    textPrimary          = rgb(230, 230, 230)
    textSecondary        = rgb(160, 160, 160)
    selection            = rgb(40, 70, 110)
    selectionText        = $white
    disabled             = rgb(40, 40, 40)
    disabledText         = rgb(100, 100, 100)
    disabledBorder       = rgb(55, 55, 55)
    header               = rgb(50, 55, 65)
    headerText           = $textPrimary
    font                 = "Segoe UI"
}

form {
    backColor   = $bg
    frameTheme  = "Black"
}

EditBox, TextBox, Spinner {
    backColor           = $surface
    foreColor           = $textPrimary
    borderColor         = $border
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    borderStyle         = 1
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $accent
    backColor   = $accentFocus
    foreColor   = $white
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surface
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surface
    itemForeColor           = $textPrimary
    itemBackColor           = $surface
    borderStyle             = 1
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surface
    borderStyle             = 1
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $bg
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceRaised
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $surface
    borderColor     = $border
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceRaised
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $white
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "dark"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Dark: the dark twin of light.fss, in Segoe UI.
   Its twin is light.fss: the two set the same properties, so a form can
   go from one to the other with FssThemeToggle. Change both together. */

_res_ {
    white           = rgb(255, 255, 255)
    accent          = rgb(76, 160, 240)
    accentText      = rgb(16, 16, 16)
    surface         = rgb(32, 32, 32)
    surfaceAlt      = rgb(45, 45, 45)
    button          = rgb(58, 58, 58)
    surfaceHover    = rgb(58, 58, 58)
    card            = rgb(39, 39, 39)
    textPrimary     = rgb(240, 240, 240)
    textSecondary   = rgb(190, 190, 190)
    border          = rgb(72, 72, 72)
    borderFocus     = $accent
    focus           = rgb(52, 52, 52)
    selection       = rgb(0, 84, 153)
    selectionText   = rgb(255, 255, 255)
    disabled        = rgb(40, 40, 40)
    disabledText    = rgb(110, 110, 110)
    header          = rgb(55, 55, 55)
    headerText      = $textPrimary
    iconColor       = rgb(196, 214, 255)
    font            = "Segoe UI"
}

form {
    backColor           = $surface
    darkTitleBar        = .t.
    titleBarColor       = $surface
    titleBarTextColor   = $textPrimary
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $focus
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor = $border
    backColor   = $surfaceAlt
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    backColor               = $surfaceAlt
    foreColor               = $textPrimary
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    itemBackColor           = $surfaceAlt
    itemForeColor           = $textPrimary
    disabledBackColor       = $disabled
    disabledForeColor       = $disabledText
    fontName                = $font
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    itemBackColor           = $surfaceAlt
    itemForeColor           = $textPrimary
    fontName                = $font
    specialEffect           = 1
}

CheckBox, OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle = 0
    backStyle   = 0
}

CommandButton {
    backColor       = $button
    foreColor       = $textPrimary
    fontName        = $font
    themes          = .f.
    specialEffect   = 1
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $accentText
}

CommandButton.onMouseLeave {
    backColor   = $button
    foreColor   = $textPrimary
}

FssThemeToggle {
    backColor   = $surface
    foreColor   = $iconColor
    icon        = "moon"
}

FssThemeToggle.onMouseEnter {
    backColor   = $surfaceHover
    foreColor   = $iconColor
    icon        = "moon"
}

FssThemeToggle.onMouseLeave {
    backColor   = $surface
    foreColor   = $iconColor
    icon        = "moon"
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor       = $card
    borderColor     = $border
    borderWidth     = 1
    specialEffect   = 2
}

Shape {
    backColor       = $card
    borderColor     = $border
    specialEffect   = 1
}

Line {
    borderColor = $border
}

PageFrame {
    themes  = .f.
}

Page {
    backColor   = $card
    foreColor   = $textPrimary
    fontName    = $font
}

Grid {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    gridLineColor       = $border
    highlightStyle      = 2
    highlightBackColor  = $selection
    highlightForeColor  = $selectionText
    deleteMark          = .f.
    recordMark          = .f.
    headerHeight        = 28
    fontName            = $font
    themes              = .f.
}

Column {
    backColor   = $surfaceAlt
    foreColor   = $textPrimary
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

        ENDTEXT
    CASE LOWER(tcName) == "excel"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Excel (Fresh Green) */

_res_ {
    white           = rgb(255, 255, 255)
    black           = rgb(0, 0, 0)
    accent          = rgb(33, 115, 50)
    accentDark      = rgb(20, 80, 30)
    accentSoft      = rgb(225, 245, 230)
    accentFocus     = rgb(210, 242, 220)
    surface         = rgb(240, 247, 242)
    surfaceAlt      = rgb(255, 255, 255)
    textPrimary     = rgb(30, 30, 30)
    textSecondary   = rgb(80, 85, 95)
    border          = rgb(175, 180, 188)
    borderFocus     = $accent
    selection       = rgb(195, 230, 200)
    selectionText   = $black
    disabled        = rgb(242, 242, 242)
    disabledText    = rgb(158, 158, 158)
    header          = $accent
    headerText      = $white
    font            = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "Excel"
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "light"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Light: a clean light theme in Segoe UI.
   Its twin is dark.fss: the two set the same properties, so a form can
   go from one to the other with FssThemeToggle. Change both together. */

_res_ {
    white           = rgb(255, 255, 255)
    accent          = rgb(0, 95, 184)
    accentText      = rgb(255, 255, 255)
    surface         = rgb(243, 243, 243)
    surfaceAlt      = rgb(255, 255, 255)
    button          = rgb(229, 229, 229)
    surfaceHover    = rgb(229, 229, 229)
    card            = rgb(251, 251, 251)
    textPrimary     = rgb(27, 27, 27)
    textSecondary   = rgb(92, 92, 92)
    border          = rgb(209, 209, 209)
    borderFocus     = $accent
    focus           = rgb(255, 255, 255)
    selection       = rgb(204, 228, 247)
    selectionText   = rgb(0, 0, 0)
    disabled        = rgb(245, 245, 245)
    disabledText    = rgb(160, 160, 160)
    header          = rgb(235, 235, 235)
    headerText      = $textPrimary
    iconColor       = rgb(222, 145, 0)
    font            = "Segoe UI"
}

form {
    backColor           = $surface
    darkTitleBar        = .f.
    titleBarColor       = $surface
    titleBarTextColor   = $textPrimary
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $focus
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor = $border
    backColor   = $surfaceAlt
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    backColor               = $surfaceAlt
    foreColor               = $textPrimary
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    itemBackColor           = $surfaceAlt
    itemForeColor           = $textPrimary
    disabledBackColor       = $disabled
    disabledForeColor       = $disabledText
    fontName                = $font
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    itemBackColor           = $surfaceAlt
    itemForeColor           = $textPrimary
    fontName                = $font
    specialEffect           = 1
}

CheckBox, OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle = 0
    backStyle   = 0
}

CommandButton {
    backColor       = $button
    foreColor       = $textPrimary
    fontName        = $font
    themes          = .f.
    specialEffect   = 1
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $accentText
}

CommandButton.onMouseLeave {
    backColor   = $button
    foreColor   = $textPrimary
}

FssThemeToggle {
    backColor   = $surface
    foreColor   = $iconColor
    icon        = "sun"
}

FssThemeToggle.onMouseEnter {
    backColor   = $surfaceHover
    foreColor   = $iconColor
    icon        = "sun"
}

FssThemeToggle.onMouseLeave {
    backColor   = $surface
    foreColor   = $iconColor
    icon        = "sun"
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor       = $card
    borderColor     = $border
    borderWidth     = 1
    specialEffect   = 2
}

Shape {
    backColor       = $card
    borderColor     = $border
    specialEffect   = 1
}

Line {
    borderColor = $border
}

PageFrame {
    themes  = .f.
}

Page {
    backColor   = $card
    foreColor   = $textPrimary
    fontName    = $font
}

Grid {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    gridLineColor       = $border
    highlightStyle      = 2
    highlightBackColor  = $selection
    highlightForeColor  = $selectionText
    deleteMark          = .f.
    recordMark          = .f.
    headerHeight        = 28
    fontName            = $font
    themes              = .f.
}

Column {
    backColor   = $surfaceAlt
    foreColor   = $textPrimary
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

        ENDTEXT
    CASE LOWER(tcName) == "neon"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Neon (Cyberpunk) */

_res_ {
    white                = rgb(255, 255, 255)
    black                = rgb(0, 0, 0)
    bg                   = rgb(13, 17, 23)
    surface              = rgb(22, 27, 34)
    surfaceRaised        = rgb(33, 38, 45)
    border               = rgb(48, 54, 61)
    accent               = rgb(88, 166, 255)
    accentDark           = rgb(56, 120, 200)
    accentSoft           = rgb(25, 40, 55)
    accentFocus          = rgb(22, 32, 45)
    textPrimary          = rgb(230, 237, 243)
    textSecondary        = rgb(139, 148, 158)
    selection            = rgb(31, 65, 111)
    selectionText        = $white
    disabled             = rgb(22, 27, 34)
    disabledText         = rgb(72, 79, 88)
    disabledBorder       = rgb(38, 43, 50)
    header               = rgb(22, 27, 34)
    headerText           = $accent
    font                 = "Segoe UI"
}

form {
    backColor   = $bg
    frameTheme  = "Black"
}

EditBox, TextBox, Spinner {
    backColor           = $surface
    foreColor           = $textPrimary
    borderColor         = $border
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    borderStyle         = 1
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $accent
    backColor   = $accentFocus
    foreColor   = $accent
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surface
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surface
    itemForeColor           = $textPrimary
    itemBackColor           = $surface
    borderStyle             = 1
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surface
    borderStyle             = 1
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $surfaceRaised
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $bg
}

CommandButton.onMouseLeave {
    backColor   = $surfaceRaised
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surface
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $surface
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceRaised
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accent
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "office-word-dark"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Office Dark (Word Dark Mode) */

_res_ {
    white                = rgb(255, 255, 255)
    black                = rgb(0, 0, 0)
    bg                   = rgb(43, 43, 43)
    surface              = rgb(55, 55, 55)
    surfaceRaised        = rgb(63, 63, 63)
    border               = rgb(80, 80, 80)
    accent               = rgb(86, 156, 214)
    accentDark           = rgb(56, 120, 180)
    accentSoft           = rgb(45, 58, 72)
    accentFocus          = rgb(45, 52, 64)
    textPrimary          = rgb(212, 212, 212)
    textSecondary        = rgb(150, 150, 150)
    selection            = rgb(38, 79, 120)
    selectionText        = $white
    disabled             = rgb(50, 50, 50)
    disabledText         = rgb(100, 100, 100)
    disabledBorder       = rgb(65, 65, 65)
    header               = rgb(50, 55, 65)
    headerText           = $textPrimary
    font                 = "Segoe UI"
}

form {
    backColor   = $bg
    frameTheme  = "Word"
}

EditBox, TextBox, Spinner {
    backColor           = $surface
    foreColor           = $textPrimary
    borderColor         = $border
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    borderStyle         = 1
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $accent
    backColor   = $accentFocus
    foreColor   = $white
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surface
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surface
    itemForeColor           = $textPrimary
    itemBackColor           = $surface
    borderStyle             = 1
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surface
    borderStyle             = 1
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $bg
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceRaised
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $surface
    borderColor     = $border
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceRaised
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $white
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "office-word-light"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Word (Classic Blue) */

_res_ {
    white           = rgb(255, 255, 255)
    black           = rgb(0, 0, 0)
    accent          = rgb(43, 87, 154)
    accentDark      = rgb(25, 60, 120)
    accentSoft      = rgb(230, 240, 250)
    accentFocus     = rgb(218, 234, 252)
    surface         = rgb(243, 246, 250)
    surfaceAlt      = rgb(255, 255, 255)
    textPrimary     = rgb(30, 32, 38)
    textSecondary   = rgb(95, 102, 112)
    border          = rgb(190, 198, 210)
    borderFocus     = $accent
    selection       = rgb(195, 214, 238)
    selectionText   = $black
    disabled        = rgb(235, 238, 242)
    disabledText    = rgb(140, 146, 155)
    header          = $accent
    headerText      = $white
    font            = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "Word"
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "onenote"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - OneNote (Deep Purple) */

_res_ {
    white           = rgb(255, 255, 255)
    black           = rgb(0, 0, 0)
    accent          = rgb(100, 25, 148)
    accentDark      = rgb(70, 15, 110)
    accentSoft      = rgb(242, 226, 255)
    accentFocus     = rgb(236, 215, 255)
    surface         = rgb(247, 243, 250)
    surfaceAlt      = rgb(255, 255, 255)
    textPrimary     = rgb(30, 30, 30)
    textSecondary   = rgb(80, 85, 95)
    border          = rgb(175, 180, 188)
    borderFocus     = $accent
    selection       = rgb(224, 188, 230)
    selectionText   = $black
    disabled        = rgb(242, 242, 242)
    disabledText    = rgb(158, 158, 158)
    header          = $accent
    headerText      = $white
    font            = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "OneNote"
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "outlook"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Outlook (Ocean Blue) */

_res_ {
    white           = rgb(255, 255, 255)
    black           = rgb(0, 0, 0)
    accent          = rgb(0, 110, 182)
    accentDark      = rgb(0, 80, 140)
    accentSoft      = rgb(224, 242, 254)
    accentFocus     = rgb(210, 236, 255)
    surface         = rgb(242, 248, 254)
    surfaceAlt      = rgb(255, 255, 255)
    textPrimary     = rgb(30, 30, 30)
    textSecondary   = rgb(80, 85, 95)
    border          = rgb(175, 180, 188)
    borderFocus     = $accent
    selection       = rgb(185, 220, 250)
    selectionText   = $black
    disabled        = rgb(242, 242, 242)
    disabledText    = rgb(158, 158, 158)
    header          = $accent
    headerText      = $white
    font            = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "Outlook"
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "powerpoint"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Powerpoint (Warm Orange) */

_res_ {
    white           = rgb(255, 255, 255)
    black           = rgb(0, 0, 0)
    accent          = rgb(210, 60, 20)
    accentDark      = rgb(170, 40, 10)
    accentSoft      = rgb(255, 240, 226)
    accentFocus     = rgb(255, 232, 212)
    surface         = rgb(255, 245, 240)
    surfaceAlt      = rgb(255, 255, 255)
    textPrimary     = rgb(30, 30, 30)
    textSecondary   = rgb(80, 85, 95)
    border          = rgb(175, 180, 188)
    borderFocus     = $accent
    selection       = rgb(255, 222, 178)
    selectionText   = $black
    disabled        = rgb(242, 242, 242)
    disabledText    = rgb(158, 158, 158)
    header          = $accent
    headerText      = $white
    font            = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "Powerpoint"
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "publisher"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Publisher (Teal Green) */

_res_ {
    white           = rgb(255, 255, 255)
    black           = rgb(0, 0, 0)
    accent          = rgb(0, 121, 132)
    accentDark      = rgb(0, 90, 95)
    accentSoft      = rgb(222, 247, 250)
    accentFocus     = rgb(208, 244, 248)
    surface         = rgb(242, 249, 250)
    surfaceAlt      = rgb(255, 255, 255)
    textPrimary     = rgb(30, 30, 30)
    textSecondary   = rgb(80, 85, 95)
    border          = rgb(175, 180, 188)
    borderFocus     = $accent
    selection       = rgb(176, 234, 242)
    selectionText   = $black
    disabled        = rgb(242, 242, 242)
    disabledText    = rgb(158, 158, 158)
    header          = $accent
    headerText      = $white
    font            = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "Publisher"
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "white"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - White (Clean Blue) */

_res_ {
    white           = rgb(255, 255, 255)
    black           = rgb(0, 0, 0)
    accent          = rgb(51, 103, 214)
    accentDark      = rgb(30, 75, 170)
    accentSoft      = rgb(230, 238, 254)
    accentFocus     = rgb(218, 232, 255)
    surface         = rgb(245, 247, 250)
    surfaceAlt      = rgb(255, 255, 255)
    textPrimary     = rgb(30, 30, 30)
    textSecondary   = rgb(80, 85, 95)
    border          = rgb(175, 180, 188)
    borderFocus     = $accent
    selection       = rgb(208, 226, 252)
    selectionText   = $black
    disabled        = rgb(242, 242, 242)
    disabledText    = rgb(158, 158, 158)
    header          = rgb(55, 60, 70)
    headerText      = $white
    font            = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "White"
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "white2"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - White2 (Warm Earth) */

_res_ {
    white           = rgb(255, 255, 255)
    black           = rgb(0, 0, 0)
    accent          = rgb(175, 110, 45)
    accentDark      = rgb(135, 80, 30)
    accentSoft      = rgb(248, 238, 226)
    accentFocus     = rgb(252, 235, 218)
    surface         = rgb(253, 250, 245)
    surfaceAlt      = rgb(255, 255, 255)
    textPrimary     = rgb(55, 40, 25)
    textSecondary   = rgb(120, 100, 80)
    border          = rgb(210, 200, 185)
    borderFocus     = $accent
    selection       = rgb(235, 212, 180)
    selectionText   = $black
    disabled        = rgb(248, 245, 240)
    disabledText    = rgb(175, 165, 150)
    header          = rgb(65, 50, 35)
    headerText      = rgb(248, 238, 226)
    font            = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "White"
}

EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "windev1"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - WinDev (Dark Professional Blue) */

_res_ {
    white                = rgb(255, 255, 255)
    black                = rgb(0, 0, 0)
    bg                   = rgb(31, 36, 45)
    surface              = rgb(42, 48, 59)
    surfaceRaised        = rgb(52, 59, 72)
    border               = rgb(62, 70, 85)
    accent               = rgb(94, 175, 255)
    accentDark           = rgb(64, 140, 220)
    accentSoft           = rgb(32, 42, 58)
    accentFocus          = rgb(32, 40, 55)
    textPrimary          = rgb(226, 231, 238)
    textSecondary        = rgb(143, 152, 168)
    selection            = rgb(30, 60, 100)
    selectionText        = $white
    disabled             = rgb(38, 43, 53)
    disabledText         = rgb(80, 88, 102)
    disabledBorder       = rgb(52, 58, 70)
    header               = rgb(38, 50, 70)
    headerText           = $white
    font                 = "Segoe UI"
}

form {
    backColor   = $bg
    frameTheme  = "Black"
}

EditBox, TextBox, Spinner {
    backColor           = $surface
    foreColor           = $textPrimary
    borderColor         = $border
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    borderStyle         = 1
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $accent
    backColor   = $accentFocus
    foreColor   = $white
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surface
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

ComboBox {
    borderColor             = $border
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surface
    itemForeColor           = $textPrimary
    itemBackColor           = $surface
    borderStyle             = 1
    specialEffect           = 1
}

ListBox {
    borderColor             = $border
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surface
    borderStyle             = 1
    specialEffect           = 1
}

CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $bg
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

Container {
    backColor   = $surface
    borderColor = $border
    specialEffect = 1
}

Shape {
    backColor       = $surfaceRaised
    borderColor     = $accent
    specialEffect   = 1
}

pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceRaised
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $white
    fontBold    = .t.
}

Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    CASE LOWER(tcName) == "word"
        TEXT TO lcTheme NOSHOW
/* FoxStyleSheet - Word (Professional Blue) */

_res_ {
    white                = rgb(255, 255, 255)
    black                = rgb(0, 0, 0)
    accent               = rgb(43, 87, 154)
    accentDark           = rgb(25, 60, 120)
    accentSoft           = rgb(227, 237, 250)
    accentFocus          = rgb(210, 228, 252)
    surface              = rgb(240, 243, 248)
    surfaceAlt           = rgb(255, 255, 255)
    textPrimary          = rgb(30, 30, 30)
    textSecondary        = rgb(80, 85, 95)
    textPlaceholder      = rgb(158, 158, 158)
    border               = rgb(175, 180, 188)
    borderFocus          = $accent
    selection            = rgb(190, 210, 240)
    selectionText        = $black
    disabled             = rgb(242, 242, 242)
    disabledText         = rgb(158, 158, 158)
    disabledBorder       = rgb(220, 220, 220)
    header               = $accent
    headerText           = $white
    font                 = "Segoe UI"
}

form {
    backColor   = $surface
    frameTheme  = "Word"
}

/* === Inputs === */
EditBox, TextBox, Spinner {
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    borderColor         = $border
    borderStyle         = 1
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
    fontName            = $font
    specialEffect       = 1
}

EditBox.onGotFocus, TextBox.onGotFocus, ComboBox.onGotFocus, Spinner.onGotFocus {
    borderColor = $borderFocus
    backColor   = $accentFocus
    foreColor   = $textPrimary
}

EditBox.onLostFocus, TextBox.onLostFocus, ComboBox.onLostFocus, Spinner.onLostFocus {
    borderColor         = $border
    backColor           = $surfaceAlt
    foreColor           = $textPrimary
    selectedBackColor   = $selection
    selectedForeColor   = $selectionText
    fontName            = $font
    disabledBackColor   = $disabled
    disabledForeColor   = $disabledText
}

TextBox.onRightClick, EditBox.onRightClick {
    editMenu = .t.
}

/* === ComboBox === */
ComboBox {
    borderColor             = $border
    borderStyle             = 1
    selectedBackColor       = $selection
    selectedForeColor       = $selectionText
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    foreColor               = $textPrimary
    fontName                = $font
    backColor               = $surfaceAlt
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

/* === ListBox === */
ListBox {
    borderColor             = $border
    borderStyle             = 1
    selectedItemBackColor   = $selection
    selectedItemForeColor   = $selectionText
    fontName                = $font
    itemForeColor           = $textPrimary
    itemBackColor           = $surfaceAlt
    specialEffect           = 1
}

/* === CheckBox === */
CheckBox {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

/* === CommandButton === */
CommandButton {
    foreColor       = $accent
    fontName        = $font
    specialEffect   = 1
    themes          = .f.
    backColor       = $accentSoft
    mousePointer    = 15
}

CommandButton.onMouseEnter {
    backColor   = $accent
    foreColor   = $white
}

CommandButton.onMouseLeave {
    backColor   = $accentSoft
    foreColor   = $accent
}

/* === Label === */
Label {
    foreColor   = $textSecondary
    fontName    = $font
    backStyle   = 0
}

/* === OptionGroup === */
OptionGroup {
    borderStyle     = 0
    themes          = .f.
    backStyle       = 0
    specialEffect   = 1
}

/* === OptionButton === */
OptionButton {
    foreColor   = $textPrimary
    fontName    = $font
    backStyle   = 0
}

/* === Container === */
Container {
    backColor   = $surfaceAlt
    borderColor = $border
    specialEffect = 1
}

/* === Shape === */
Shape {
    backColor       = $accentSoft
    borderColor     = $accent
    specialEffect   = 1
}

/* === PageFrame === */
pageFrame {
    themes  = .f.
    tabs    = .f.
}

page {
    foreColor   = $accent
    backColor   = $surfaceAlt
    fontName    = $font
}

pageFrame {
    tabs = .t.
}

Page.onClick {
    _           = this.parent.setAll('FontBold', .f., 'Page')
    foreColor   = $accentDark
    fontBold    = .t.
}

/* === Grid === */
Header {
    backColor   = $header
    foreColor   = $headerText
    fontName    = $font
    fontBold    = .t.
}

Grid {
    deleteMark          = .f.
    fontName            = $font
    headerHeight        = 28
    highLightStyle      = 2
    highLightBackColor  = $selection
    highLightForeColor  = $selectionText
    recordMark          = .f.
    themes              = .f.
    gridLineColor       = $border
}

        ENDTEXT
    ENDCASE
    RETURN lcTheme
ENDFUNC

FUNCTION FssBuiltInThemeNames
    RETURN "Access,black,dark,Excel,light,neon,office-word-dark,office-word-light,OneNote,Outlook,Powerpoint,Publisher,white,white2,windev1,Word"
ENDFUNC
*-- END BUILT-IN THEMES
