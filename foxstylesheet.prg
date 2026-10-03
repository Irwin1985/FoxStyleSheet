#define LOG_ERROR      16
#define LOG_INFO       64
#define LOG_WARNING    48
#define LOG_DEBUG      80
#define CRLF           chr(13) + chr(10)
#define FSS_SEPARATOR  ' _fss_lf '
#define FSS_KEY        '_'
#define FSS_VERSION    '2.0.0'

* Entry point: DO foxstylesheet.prg WITH "theme.fss", ThisForm
lparameters tcStyle, toThisform

local lcPropName
lcPropName = sys(2015)
=addproperty(toThisform, lcPropName, createobject("FoxStyleSheet"))
toThisform. &lcPropName..link(tcStyle, toThisform)
return

*==============================================================
* CLASS: FoxStyleSheet
* Main engine. Zero mandatory external dependencies.
* Optional features:
*   - Page backgrounds (rgb): a BMP written by the library itself
*   - Custom title bar (frametheme): requires Codejock OCX + resources.dbf
*==============================================================
define class FoxStyleSheet as custom

    cVersion = FSS_VERSION

    * cPrgPath: folder where foxstylesheet.prg lives (auto-set in init)
    * cPath:    APPDATA temp folder for logs and generated images
    cPrgPath = ''
    cPath    = ''

    * Errors of the last link() and of the event styles since then. They are
    * kept by the logger; these read them (see the _Access methods).
    nErrors    = 0
    oErrors    = .null.
    cLastError = ''

    protected oLogger, oResources, oResourcesIndex
    protected oFunctions, oThisform, oImages, oControls, oMetrics

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
            llResult = loHelper.isClassRegistered("Codejock.SkinFramework.22.1.0")
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
        local lcContent, loStyles

        this.ClearErrors()
        this.oMetrics.Reset()
        this.oMetrics.StartTimer()
        this.oThisform = toForm

        this.oLogger.SetLogFile(this.cPath + 'FoxStyleSheet.log')

        lcContent = this.LoadContent(tcFile)
        if !empty(lcContent)
            lcContent = this.RemoveComments(lcContent)
            this.ExtractFunctions(lcContent)
            loStyles = this.ParseStyles(lcContent)
            this.oMetrics.EndTimer('parse')

            this.oMetrics.StartTimer()
            this.ApplyAllStyles(loStyles, toForm)
            this.oMetrics.EndTimer('apply')

            this.BindFormEvents()
        endif
        return this.oLogger.nErrors = 0
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

    *-- A theme is a file, or the text of a theme (it has a "{").
    protected function LoadContent(tcTheme)
        do case
        case vartype(tcTheme) != 'C' or empty(tcTheme)
            this.oLogger.LogError("link: no theme was given")
            return ''
        case file(tcTheme)
            return filetostr(tcTheme)
        case '{' $ tcTheme
            return tcTheme
        endcase
        this.oLogger.LogError("link: theme file not found: " + tcTheme)
        return ''
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
        
        this.oLogger.LogInfo("loadResourcesOptimized: " + transform(alen(laProp)) + " lineas")
        
        * Primera pasada: cargar todas las variables sin resolver
        for i = 1 to alen(laProp)
            lcProp  = lower(alltrim(chrtran(getwordnum(laProp[i], 1, '='), chr(9), ' ')))
            lcValue = alltrim(chrtran(getwordnum(laProp[i], 2, '='), chr(9), ' '))
            if empty(lcProp)
                loop
            endif
            try
                this.oResources.add(lcValue, lcProp)
                this.oResourcesIndex.add(this.oResources.count, lcProp)
                this.oLogger.LogInfo("Resource cargada: " + lcProp + " = " + lcValue)
            catch to loEx
                this.oLogger.LogFromException(loEx)
            endtry
        endfor
        
        * Segunda pasada: resolver referencias cruzadas (max 5 niveles)
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
                    this.oLogger.LogInfo("Resource resuelta pasada " + transform(lnPasses) + ": " + lcProp + " = " + lcResolved)
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
                    =addproperty(toForm, lcClassProp, loClassCollection)
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
                    =addproperty(toForm, lcClassProp, loClassCollection)
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
            this.ParseUniversalSelector(loSelector)
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

    protected procedure ParseUniversalSelector(loSelector)
        loSelector.ControlName = "*"
        loSelector.ControlType = "*"
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
                        if type('loControl') == 'O' and !isnull(loControl)
                            loControl.init()
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
                            =addproperty(this.oThisform, tcClassStylesProp, toStyles)
                        else
                            this.oThisform. &tcClassStylesProp = toStyles
                        endif
                    endif
                else
                    if !pemstatus(loControl, lcProp, 5)
                        =addproperty(loControl, lcProp, .null.)
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
        local array laStyles[4]
        local loControl, lcEvent, lnS

        store .null. to laStyles
        =aevents(laEvents, 0)
        if alen(laEvents) < 2 or type('laEvents[1]') != 'O' or type('this.oThisform') != 'O' or isnull(this.oThisform)
            return
        endif
        loControl = laEvents[1]
        lcEvent   = laEvents[2]

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
    endfunc

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
    * Edit context menu
    *----------------------------------------------------------
    procedure popMenu
        define popup EditMenu from mrow(), mcol() margin relative shadow color scheme 4 SHORTCUT
        define bar _med_undo  of EditMenu prompt "\<Deshacer"         key CTRL+Z, "Ctrl+Z" PICTRES _med_undo  message "Deshace el ultimo comando"
        define bar _med_redo  of EditMenu prompt "Re\<hacer"          key CTRL+R, "Ctrl+R" PICTRES _med_redo  message "Repite el ultimo comando"
        define bar _med_sp100 of EditMenu prompt "\-"                 PICTRES _med_sp100
        define bar _med_cut   of EditMenu prompt "Cor\<tar"           key CTRL+X, "Ctrl+X" PICTRES _med_cut   message "Elimina la seleccion y la coloca en el Portapapeles"
        define bar _med_copy  of EditMenu prompt "\<Copiar"           key CTRL+C, "Ctrl+C" PICTRES _med_copy  message "Copia la seleccion en el portapapeles"
        define bar _med_paste of EditMenu prompt "\<Pegar"            key CTRL+V, "Ctrl+V" PICTRES _med_paste message "Pega el contenido del Portapapeles"
        define bar _med_pstlk of EditMenu prompt "Pegado \<Especial..."                    PICTRES _med_pstlk message "Pega como objeto vinculado o incrustado"
        define bar _med_clear of EditMenu prompt "\<Limpiar"                               PICTRES _med_clear message "Elimina la seleccion sin copiarla"
        define bar _med_sp200 of EditMenu prompt "\-"                 PICTRES _med_sp200
        define bar _med_slcta of EditMenu prompt "Se\<leccionar Todo" key CTRL+A, "Ctrl+A" PICTRES _med_slcta message "Selecciona todo"
        define bar _med_sp300 of EditMenu prompt "\-"                 PICTRES _med_sp300
        activate popup EditMenu
    endproc

    *----------------------------------------------------------
    * Codejock title bar (optional feature)
    *----------------------------------------------------------
    protected procedure addTitleBar(toThisform, tcColor)
        local lcFssPath, lcSkinFile, lcOcxFile, lcSchema, llOk
        lcFssPath = this.cPrgPath + 'Fss\'
        lcSkinFile = lcFssPath + 'Windows10.cjstyles'
        lcOcxFile  = lcFssPath + 'Codejock.SkinFramework.v22.1.0.ocx'

        if !file(lcSkinFile)
            this.oLogger.LogInfo("addTitleBar skipped: Windows10.cjstyles not found in Fss\ folder beside foxstylesheet.prg.")
            return
        endif

        * Auto-register OCX if not yet installed (requires admin)
        if !this.IsCodejockAvailable()
            if file(lcOcxFile)
                local loHelper
                loHelper = createobject("FssOCXHelper")
                loHelper.SetLogger(this.oLogger)
                if !loHelper.registerClass(lcOcxFile, "Codejock.SkinFramework.22.1.0")
                    this.oLogger.LogInfo("addTitleBar skipped: Codejock OCX found but registration failed (run as Administrator once).")
                    return
                endif
            else
                this.oLogger.LogInfo("addTitleBar skipped: Codejock SkinFramework not registered and OCX not found in Fss\ folder.")
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
                _screen.oFssTitleBar.paintTitleBar(lcSkinFile, lcSchema, toThisform)
            else
                =addproperty(_screen, 'oFssTitleBar', createobject('FssCustomTitleBar'))
                _screen.oFssTitleBar.paintTitleBar(lcSkinFile, lcSchema, toThisform)
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
    lDebugMode = .f.
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
        if empty(this.cLogFile)
            this.cLogFile = fullpath('FoxStyleSheet.log')
        endif
        * Support legacy single-string call: log("message")
        if type('tnType') == 'C'
            tcMessage = tnType
            tnType    = LOG_INFO
        endif

        local lcType, lcDateAct, lcCenturyAct, lnHour, lcLogText
        if tnType = LOG_ERROR
            this.nErrors    = this.nErrors + 1
            this.oErrors.add(tcMessage)
            this.cLastError = tcMessage
        endif
        lcDateAct    = set("Date")
        lcCenturyAct = set("Century")
        lnHour       = set("Hours")
        set date italian
        set century on
        set hours to 24

        do case
        case tnType = LOG_ERROR
            lcType = "ERROR  "
        case tnType = LOG_INFO
            lcType = "INFO   "
        case tnType = LOG_WARNING
            lcType = "WARNING"
        case tnType = LOG_DEBUG
            lcType = "DEBUG  "
        otherwise
            lcType = "INFO   "
        endcase

        try
            lcLogText = ttoc(datetime()) + " | " + lcType + " | " + tcMessage + CRLF
            =strtofile(lcLogText, this.cLogFile, 1)
        catch
        endtry

        set century &lcCenturyAct
        set date &lcDateAct
        set hours to (lnHour)
    endproc
enddefine


*==============================================================
* CLASS: FssCustomTitleBar
* Codejock SkinFramework integration. Only instantiated when
* IsCodejockAvailable() returns .T.
*==============================================================
define class FssCustomTitleBar as custom
    add object skinframework as olecontrol with ;
        top      = 0, ;
        left     = 0, ;
        oleclass = "Codejock.SkinFramework.22.1.0", ;
        height   = 26, ;
        width    = 26, ;
        name     = "skinframework"

    procedure paintTitleBar(tcStyleFile, tcIniFile, toForm)
        with this.skinframework
            .loadSkin(tcStyleFile, tcIniFile)
            .applyWindow(toForm.hwnd)
            .ApplyOptions = 2
        endwith
    endproc
enddefine
