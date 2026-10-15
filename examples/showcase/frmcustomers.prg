*==============================================================================
* frmCustomers: the screen of the showcase. Nothing in it knows about colours:
* FoxStyleSheet paints it and VFPStretch stretches it, from Init.
*==============================================================================
#Define SETTINGS_FILE	Addbs(Getenv("APPDATA")) + "FoxShowcase\theme.txt"

Define Class frmCustomers As Form
	Caption     = "Customers - FoxStyleSheet + VFPStretch"
	Width       = 760
	Height      = 540
	ShowWindow  = 2
	AutoCenter  = .T.
	DataSession = 2
	FontName    = "Segoe UI"
	Name        = "frmCustomers"

	Add Object lblTitle As Label With ;
		Caption = "Customers", FontSize = 18, FontBold = .T., ;
		Left = 20, Top = 14, AutoSize = .T., Name = "lblTitle"

	Add Object lblSubtitle As Label With ;
		Caption = "One screen, any theme. Drag the border: it stretches.", ;
		Left = 22, Top = 48, AutoSize = .T., Name = "lblSubtitle"

	Add Object lblTheme As Label With ;
		Caption = "Theme", Left = 520, Top = 24, AutoSize = .T., Name = "lblTheme"

	Add Object cboTheme As ComboBox With ;
		Left = 566, Top = 20, Width = 130, Height = 26, Style = 2, ;
		RowSourceType = 1, Name = "cboTheme"

	Add Object cmdTheme As FssThemeToggle With ;
		Left = 708, Top = 17, Width = 32, Height = 32, Name = "cmdTheme"

	Add Object pgfMain As PageFrame With ;
		Left = 20, Top = 80, Width = 720, Height = 390, PageCount = 3, ;
		Page1.Caption = "General", Page2.Caption = "Orders", Page3.Caption = "Notes", ;
		Name = "pgfMain"

	Add Object cmdSave As CommandButton With ;
		Caption = "\<Save", Left = 536, Top = 486, Width = 96, Height = 32, Name = "cmdSave"

	Add Object cmdClose As CommandButton With ;
		Caption = "\<Close", Left = 644, Top = 486, Width = 96, Height = 32, Cancel = .T., Name = "cmdClose"

	Add Object lblStatus As Label With ;
		Caption = "", Left = 22, Top = 494, Width = 480, Name = "lblStatus"

	Procedure Load
		* a private data session starts with the defaults of VFP
		Set Talk Off
		Set Safety Off
		Set Deleted On
		Set Century On
		Create Cursor customer (code C(6), name C(40), email C(50), country C(20), credit N(10,2), active L, kind N(1), folder C(200), notes M)
		Insert Into customer Values ("C00042", "Müller & Söhne GmbH", "einkauf@mueller-soehne.example", "Germany", 25000, .T., 1, ;
			Addbs(Getenv("USERPROFILE")) + "Documents\", ;
			"Pays at 30 days. Prefers deliveries on Tuesday mornings." + Chr(13) + "Contact: Frau Jäger.")

		Create Cursor orders (number C(8), ordered D, product C(30), qty N(5), amount N(10,2), status C(10))
		Insert Into orders Values ("SO-1001", Date() - 40, "Annual licence", 1, 1200, "Paid")
		Insert Into orders Values ("SO-1007", Date() - 33, "Support pack (10 h)", 2, 900, "Paid")
		Insert Into orders Values ("SO-1015", Date() - 25, "Extra seats", 5, 1750, "Paid")
		Insert Into orders Values ("SO-1022", Date() - 18, "Training day", 1, 650, "Invoiced")
		Insert Into orders Values ("SO-1030", Date() - 12, "Migration service", 1, 3400, "Invoiced")
		Insert Into orders Values ("SO-1036", Date() - 6, "Annual licence", 1, 1200, "Open")
		Insert Into orders Values ("SO-1041", Date() - 2, "Extra seats", 3, 1050, "Open")
		Go Top In orders
	Endproc

	Procedure Init
		Local loFss
		This.BuildPages()
		This.cboTheme.RowSource = FssBuiltInThemeNames()

		* The theme first (it sets the grid header height), then VFPStretch,
		* which takes the screen as it is now as its original size.
		This.ApplyTheme(This.SavedTheme())
		=Bindevent(This.cmdTheme, "ThemeChanged", This, "OnThemeChanged", 1)
		_Screen.oVfpStretch.Do(This)
		loFss = FssEngineOf(This)
		This.lblStatus.Caption = "Theme: " + This.cboTheme.Value + ". FoxStyleSheet " + ;
			loFss.cVersion + ", VFPStretch " + _Screen.oVfpStretch.cVersion
	Endproc

	Procedure Destroy
		Clear Events
	Endproc

	*--------------------------------------------------------------------------
	* Themes
	*--------------------------------------------------------------------------
	Procedure ApplyTheme(tcTheme)
		Local loFss
		loFss = FssEngineOf(This)
		If Isnull(m.loFss)
			loFss = Createobject("FoxStyleSheet")
		Endif
		loFss.link(m.tcTheme, This)
		This.cboTheme.Value = m.tcTheme
		This.SaveTheme(m.tcTheme)
		* a theme sets sizes as designed (headerHeight): scale them again
		If Type("This.oVfpStretch") == "O"
			This.oVfpStretch.Stretch()
		Endif
	Endproc

	* The sun and moon button switched the theme on its own
	Procedure OnThemeChanged(tcTheme)
		This.cboTheme.Value = m.tcTheme
		This.SaveTheme(m.tcTheme)
		If Type("This.oVfpStretch") == "O"
			This.oVfpStretch.Stretch()
		Endif
		This.lblStatus.Caption = "Theme: " + m.tcTheme
	Endproc

	Procedure cboTheme.InteractiveChange
		Thisform.ApplyTheme(This.Value)
		Thisform.lblStatus.Caption = "Theme: " + This.Value
	Endproc

	* What the user chose last time, or what Windows uses
	Function SavedTheme
		Local lcTheme
		lcTheme = ""
		If File(SETTINGS_FILE)
			lcTheme = Alltrim(Filetostr(SETTINGS_FILE))
		Endif
		If Empty(m.lcTheme) Or !("," + Lower(m.lcTheme) + ",") $ ("," + Lower(FssBuiltInThemeNames()) + ",")
			lcTheme = FssSystemTheme()
		Endif
		Return m.lcTheme
	Endfunc

	Procedure SaveTheme(tcTheme)
		Local lcFolder
		lcFolder = Justpath(SETTINGS_FILE)
		Try
			If !Directory(m.lcFolder)
				Mkdir (m.lcFolder)
			Endif
			=Strtofile(m.tcTheme, SETTINGS_FILE)
		Catch
		Endtry
	Endproc

	*--------------------------------------------------------------------------
	* The pages
	*--------------------------------------------------------------------------
	Procedure BuildPages
		With This.pgfMain.Page1
			.AddObject("lblCode", "Label")
			.AddObject("txtCode", "TextBox")
			.AddObject("lblName", "Label")
			.AddObject("txtName", "TextBox")
			.AddObject("lblEmail", "Label")
			.AddObject("txtEmail", "TextBox")
			.AddObject("lblCountry", "Label")
			.AddObject("cboCountry", "ComboBox")
			.AddObject("lblCredit", "Label")
			.AddObject("spnCredit", "Spinner")
			.AddObject("chkActive", "CheckBox")
			.AddObject("opgKind", "OptionGroup")
			.AddObject("cntSummary", "Container")
			.AddObject("lstTags", "ListBox")
			.AddObject("lblTags", "Label")
			.AddObject("lblFolder", "Label")
			.AddObject("txtFolder", "TextBox")
			.AddObject("cmdFolder", "CommandButton")
		Endwith
		With This.pgfMain.Page1
			This.PlaceLabel(.lblCode, "Code", 24)
			This.PlaceBox(.txtCode, "customer.code", 20, 90)
			This.PlaceLabel(.lblName, "Name", 60)
			This.PlaceBox(.txtName, "customer.name", 56, 300)
			This.PlaceLabel(.lblEmail, "Email", 96)
			This.PlaceBox(.txtEmail, "customer.email", 92, 300)
			This.PlaceLabel(.lblCountry, "Country", 132)
			With .cboCountry
				.Left = 120
				.Top = 128
				.Width = 180
				.Height = 26
				.Style = 2
				.RowSourceType = 1
				.RowSource = "Germany,Spain,Mexico,Colombia,Argentina,United States,United Kingdom"
				.ControlSource = "customer.country"
				.Visible = .T.
			Endwith
			This.PlaceLabel(.lblCredit, "Credit limit", 168)
			With .spnCredit
				.Left = 120
				.Top = 164
				.Width = 120
				.Height = 26
				.Increment = 500
				.InputMask = "999,999.99"
				.ControlSource = "customer.credit"
				.Visible = .T.
			Endwith
			With .chkActive
				.Caption = "Active customer"
				.Left = 120
				.Top = 204
				.AutoSize = .T.
				.ControlSource = "customer.active"
				.Visible = .T.
			Endwith
			With .opgKind
				.ButtonCount = 2
				.Left = 116
				.Top = 232
				.Width = 220
				.Height = 30
				.Buttons(1).Caption = "Company"
				.Buttons(1).Left = 4
				.Buttons(1).Top = 5
				.Buttons(1).AutoSize = .T.
				.Buttons(2).Caption = "Person"
				.Buttons(2).Left = 110
				.Buttons(2).Top = 5
				.Buttons(2).AutoSize = .T.
				.ControlSource = "customer.kind"
				.Visible = .T.
			Endwith
			With .cntSummary
				.Left = 450
				.Top = 20
				.Width = 240
				.Height = 140
				.AddObject("lblHead", "Label")
				.AddObject("lblOrders", "Label")
				.AddObject("lblTotal", "Label")
				.AddObject("lblOpen", "Label")
				.lblHead.Caption = "This year"
				.lblHead.FontBold = .T.
				.lblHead.FontSize = 11
				.lblHead.Left = 14
				.lblHead.Top = 12
				.lblHead.AutoSize = .T.
				This.Summary(.lblOrders, 44)
				This.Summary(.lblTotal, 72)
				This.Summary(.lblOpen, 100)
				.Visible = .T.
				.SetAll("Visible", .T.)
			Endwith
			* the folder of the documents: GetDirPro, with the theme of this screen
			This.PlaceLabel(.lblFolder, "Documents", 284)
			This.PlaceBox(.txtFolder, "customer.folder", 280, 246)
			With .cmdFolder
				.Caption = "..."
				.ToolTipText = "Choose the folder (GetDirPro)"
				.Left = 372
				.Top = 280
				.Width = 48
				.Height = 26
				.Visible = .T.
			Endwith
			=Bindevent(.cmdFolder, "Click", This, "ChooseFolder")
			This.PlaceLabel(.lblTags, "Tags", 184)
			.lblTags.Left = 450
			With .lstTags
				.Left = 450
				.Top = 204
				.Width = 240
				.Height = 120
				.ColumnCount = 2
				.ColumnWidths = "150,70"
				.RowSourceType = 1
				.RowSource = "Reseller,since 2019,Priority support,yes,Newsletter,monthly,Language,German"
				.Visible = .T.
			Endwith
		Endwith

		With This.pgfMain.Page2
			.AddObject("grdOrders", "Grid")
			With .grdOrders
				.Left = 16
				.Top = 16
				.Width = 684
				.Height = 320
				.ColumnCount = 6
				.RecordSource = "orders"
				.ReadOnly = .T.
				.Column1.Header1.Caption = "Order"
				.Column1.Width = 90
				.Column2.Header1.Caption = "Date"
				.Column2.Width = 100
				.Column3.Header1.Caption = "Product"
				.Column3.Width = 210
				.Column4.Header1.Caption = "Qty"
				.Column4.Width = 60
				.Column5.Header1.Caption = "Amount"
				.Column5.Width = 100
				.Column6.Header1.Caption = "Status"
				.Column6.Width = 90
				.Visible = .T.
			Endwith
		Endwith

		With This.pgfMain.Page3
			.AddObject("edtNotes", "EditBox")
			With .edtNotes
				.Left = 16
				.Top = 16
				.Width = 684
				.Height = 320
				.ControlSource = "customer.notes"
				.Visible = .T.
			Endwith
		Endwith
	Endproc

	Procedure PlaceLabel(toLabel, tcCaption, tnTop)
		With m.toLabel
			.Caption = m.tcCaption
			.Left = 20
			.Top = m.tnTop
			.AutoSize = .T.
			.Visible = .T.
		Endwith
	Endproc

	Procedure PlaceBox(toBox, tcSource, tnTop, tnWidth)
		With m.toBox
			.Left = 120
			.Top = m.tnTop
			.Width = m.tnWidth
			.Height = 26
			.ControlSource = m.tcSource
			.Visible = .T.
		Endwith
	Endproc

	Procedure Summary(toLabel, tnTop)
		Local laTotals[2], laOpen[1]
		Select Count(*), Sum(amount) From orders Into Array laTotals
		Select Count(*) From orders Where status = "Open" Into Array laOpen
		Do Case
		Case m.tnTop = 44
			toLabel.Caption = Transform(laTotals[1]) + " orders"
		Case m.tnTop = 72
			toLabel.Caption = Transform(laTotals[2], "999,999.99") + " invoiced"
		Otherwise
			toLabel.Caption = Transform(laOpen[1]) + " still open"
		Endcase
		toLabel.Left = 14
		toLabel.Top = m.tnTop
		toLabel.AutoSize = .T.
	Endproc

	*--------------------------------------------------------------------------
	* The folder picker takes the theme this screen has now
	*--------------------------------------------------------------------------
	Procedure ChooseFolder
		Local loDir, loFss, lcFolder
		loDir = Createobject("GetDirPro")
		loFss = FssEngineOf(This)
		If !Isnull(m.loFss)
			loDir.cTheme = m.loFss.cTheme
		Endif
		lcFolder = loDir.GetDir(Alltrim(customer.folder), "Where are the documents of this customer?")
		If !Empty(m.lcFolder)
			Replace folder With m.lcFolder In customer
			This.pgfMain.Page1.txtFolder.Refresh()
		Endif
	Endproc

	Procedure cmdSave.Click
		Thisform.lblStatus.Caption = "Saved at " + Time() + " (in a cursor: this is a showcase)."
	Endproc

	Procedure cmdClose.Click
		Thisform.Release()
	Endproc
Enddefine
