#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

// Written by: Håkon I. Røst, NTNU
// hakon.i.rost@ntnu.no

// v.1 October 2020: First slice panel, live EDC and MDC slicer
// v.2 November 2020: Average EDCs and MDCs over specified "width" around cursors
// v.3 April 2021: Fix bug with temporary waves being stored in root folder, clean up code

// ===========================================================================================
// 										Initialize NanoESCA DC panel
// ===========================================================================================
// Setup functions for NanoESCA stack slicer tool. Runs when "Open image stack slice panel" 
// is selected from "ESCAlab" menu

// Initialize global variables, open NanoESCA EDC and MDC slicer panel
Function Init_DCslicePanel()

	// Is the "panel" open already?
	DoWindow/F DCslicer
	If( V_Flag==1 )							
		Return 0
	Endif

	// Select stack wave to be displayed
	DFREF saveDF = GetDataFolderDFR()		// Save current data folder before
	
	CreateBrowser/M prompt="Select the NanoESCA E vs. K slice you want to work with: "
	ModifyBrowser /M showModalBrowser, showVars=0, showWaves=1, showStrs=0, showInfo=0, showPlot=0
	string displayWaveName = StringFromList(0, S_BrowserList)
	Variable numberOfFoldersSelected = ItemsInLIst(S_BrowserList)
 	
	If (V_Flag == 0 || numberOfFoldersSelected != 1)		// something is wrong..
	
		SetDataFolder saveDF		// Restore current data folder if user cancelled, or multiple files in S_BrowserList
		Return -1
	
	Else 	// ONE wave selected: obtain relevant wave info, display
		
		Wave dispWave = $displayWaveName
		String dispParentFolder = GetWavesDataFolder(dispWave,1)	// datafolder path	 
		
		// Make sure a 2D wave has been selected
		If (DimSize(dispWave,1) == 0 || DimSize(dispWave,2) != 0 || DimSize(dispWave,3) != 0) // trace, 3D or 4D wave selected
		
			Abort "ERROR! Did you select a 1D trace, a 3D or a 4D wave instead of a 2D E vs. K slice?"
		
		Else
		
			// Navigate to parent folder, create subfolder for globals
			String SFName = dispParentFolder + "DCglobals"
			NewDataFolder/O/S $SFName
			
			// Initialize relevant global strings
			string/g ARPESName = nameOfWave(dispWave)
			string/g waveFullPath = displayWaveName
			string/g PanelName = "DCslicer"
			string/g ARPESParentFolder = dispParentFolder
			string/g DCglobalsfolder = SFName
			string/g ARPESWindowName = "ARPES_img"
			string/g ARPESFullPath = PanelName+"#"+ARPESWindowName
			string/g EDCWindowName = "EDCslice"
			string/g EDCFullPath = PanelName+"#"+EDCWindowName
			string/g MDCWindowName = "MDCslice"
			string/g MDCFullPath = PanelName+"#"+MDCWindowName
			//string/g ARPESDestfolderName = "procImg"
			
			// Initialize relevant global variables
			variable/g np = DimSize(dispWave,0)
			variable/g nq = DimSize(dispWave,1)
			variable/g xMin = DimOffset(dispWave,0)
			variable/g xMax = DimOffset(dispWave,0) + np*DimDelta(dispWave,0)
			variable/g yMin = DimOffset(dispWave,1)
			variable/g yMax = DimOffset(dispWave,1) + nq*DimDelta(dispWave,1)
			variable/g EDCsliceWidth = 80
			variable/g MDCsliceWidth =  0
			variable/g activate_cursorE = 0
			variable/g activate_cursorF = 0
			variable/g varMax
			variable/g varMin
			Variable/g fixContrast = 0
			variable/g invertColour = 0
			String/g colourscaleName = ""
			
			// Initialize global waves
			Make/O/N=2 xTrace
			Make/O/N=2 yTrace
			
			Make/O/N=(np) MDC_cursorE = 0
			SetScale/P x, DimOffset(dispWave,0), DimDelta(dispWave,0), MDC_cursorE
			
			Make/O/N=(np) MDC_cursorF = 0
			SetScale/P x, DimOffset(dispWave,0), DimDelta(dispWave,0), MDC_cursorF
			
			Make/O/N=(nq) EDC_cursorE = 0
			SetScale/P x, DimOffset(dispWave,1), DimDelta(dispWave,1), EDC_cursorE
			
			Make/O/N=(nq) EDC_cursorF = 0
			SetScale/P x, DimOffset(dispWave,1), DimDelta(dispWave,1), EDC_cursorF
			
			Make/O/D/N=5 EDCLineProfileY, EDCLineProfileX, MDCLineProfileY, MDCLineProfileX
			
			// Initialize global cursor variables
			variable/g liveEnable = 0
			variable/g csrex = np/3
			variable/g csrey= nq/3
			variable/g csrfx = 2*np/3
			variable/g csrfy = 2*nq/3
			Make/O/N=(2,2) cursors			//Stores Cursor coordinates
			cursors[0][0]={csrex, csrfx}
			cursors[0][1]={csrey, csrfy}
			
			// Cursor colors
			Make/O/N=(3) rgbColor = 0
			rgbColor[0] = 65535
			rgbColor[1] = 42405
			rgbColor[2] = 0
			
			// Assemble "Execute" string with panel input name
			string cmd
			sprintf cmd, "DCslicer(\"%s\",\"%s\")", waveFullPath, SFName
			
			Execute cmd 				// Fire up this baby
			SetDataFolder root: 	// reset current directory to root
		
		EndIf	// Wave of the right dimensions selected

	EndIf	// Wave of the right dimensions selected
	Return 0
End

// ===========================================================================================
// 										Panel and button controls
// ===========================================================================================


Window DCslicer(waveFullPath, subfolderName) : Panel

	String waveFullPath, subfolderName
	String MDCwidth = subfolderName + ":MDCsliceWidth"
	String EDCwidth = subfolderName + ":EDCsliceWidth"
	
PauseUpdate; Silent 1		// building window...
	NewPanel /W=(-862,121,-382,611)
	SetDrawLayer UserBack
	SetDrawEnv fillfgc= (56797,56797,56797)
	DrawRRect 3,3,477,487
	DrawLine 293,412,465,412
	SetDrawEnv fstyle= 1
	DrawText 291,305,"Colour: "
	SetDrawEnv fstyle= 1
	DrawText 293,338,"Activate cursor:"
	SetDrawEnv fstyle= 1
	DrawText 293,404,"Save:"
	DrawLine 293,315,465,315
	Button KillPanel,pos={412.00,289.00},size={50.00,20.00},proc=ESCA_killDCPanel,title="Kill"
	Button KillPanel,fStyle=1,fColor=(65535,16385,16385)
	PopupMenu colorTable,pos={339.00,289.00},size={65.00,23.00},bodyWidth=65,proc=ESCA_ARPESColorList
	PopupMenu colorTable,mode=1,value= #"\"*COLORTABLEPOPNONAMES*\""
	CheckBox ActivateE,pos={395.00,323.00},size={28.00,16.00},proc=ESCA_ActiveCursors,title="E "
	CheckBox ActivateE,fSize=12,fStyle=1,value= 0,side= 1
	CheckBox ActivateF,pos={432.00,323.00},size={27.00,16.00},proc=ESCA_ActiveCursors,title="F "
	CheckBox ActivateF,fSize=12,fStyle=1,value= 0,side= 1
	Button SaveMDCs,pos={334.00,388.00},size={60.00,20.00},title="MDC(s)",fStyle=1
	Button SaveMDCs,fColor=(2,39321,1)
	Button SaveEDCs,pos={402.00,388.00},size={60.00,20.00},title="EDC(s)",fStyle=1
	Button SaveEDCs,fColor=(52428,34958,1)
	SetVariable SetMDCwidth,pos={297.00,343.00},size={160.00,18.00},title="MDC linewidth",value=$MDCwidth
	SetVariable SetMDCwidth,fSize=12,fStyle=1,limits={-inf,inf,0.1}, bodyWidth=60, proc=ESCA_widthDCs
	SetVariable SetEDCwidth,pos={297.00,364.00},size={160.00,18.00},title="EDC linewidth",value=$EDCwidth
	SetVariable SetEDCwidth,fSize=12,fStyle=1,limits={-inf,inf,1}, bodyWidth=60, proc=ESCA_widthDCs
	Display/W=(10,10,280,280)/HOST=# 
	RenameWindow #,ARPES_img
	SetActiveSubwindow ##
	Display/W=(290,10,465,280)/HOST=# 
	ModifyGraph frameStyle=1
	RenameWindow #,EDCslice
	SetActiveSubwindow ##
	Display/W=(10,290,280,480)/HOST=# 
	ModifyGraph frameStyle=1
	RenameWindow #,MDCslice
	SetActiveSubwindow ##
	
	ESCA_DispARPES(waveFullPath,subFolderName)			// Display image
	//ESCA_DC_Cursors(waveFullPath,subFolderName)		// Generate cursors
	
	
EndMacro

//---------------------------------------------------------------------------

Function ESCA_DispARPES(waveFullPath,subFolderName)
	String waveFullPath, subFolderName
	
	// Obtain relevant wave info
	Wave ARPES = $waveFullPath
	Svar ARPESsubPanelPath = $(subFolderName+":ARPESFullPath")

	// Add image to graph subpanel
	AppendImage/W=$ARPESsubPanelPath ARPES												// Append ARPES wave to subpanel display
	ModifyGraph/W=$ARPESsubPanelPath nticks=0, standoff=0, margin=-1			// Remove ticks, standoff and margin
	
End

//---------------------------------------------------------------------------

// Returns path to the ARPES subwindow with the appropriate syntax
Function/S ESCA_DC_ARPESpath()
	
	string panelName = WinName(0,64)
	string subPanelName = panelName + "#ARPES_img"

	Return subPanelName
End

//---------------------------------------------------------------------------

// Returns the name of the top wave displayed in the "active" panel
Function/S ESCA_ARPESDisplayed()

	string SPPath = ESCA_DC_ARPESpath()
	string imageList = ImageNameList(SPPath,";")
	string displayWaveName = StringFromList(0, imageList)
	
	return displayWaveName
End

//---------------------------------------------------------------------------

// Kills NanoESCA DC slice panel, restores data folder to root
Function ESCA_killDCPanel(ctrlName):ButtonControl
	string ctrlName	

	// Establish references to subpanel wave and folder with global variables
	String panelName = WinName(0,64)
	String SPPath = ESCA_DC_ARPESpath()
	String ARPESName = ESCA_ARPESDisplayed()
	Wave ARPES = ImageNameToWaveRef(SPPath,ARPESName)
	String ARPES_DF = GetWavesDataFolder(ARPES,1)
	String globals_DF = ARPES_DF + "DCglobals:"
	
	DoWindow/K $panelName				// Kill panel
	KillDataFolder/Z $globals_DF		// Kill globals folder (+ contents)
	
	SetDataFolder root:					// Set path to root folder
	
End



//---------------------------------------------------------------------------

// Allows the user to change the color theme of the NanoESCA images
Function ESCA_ARPESColorList(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	// Obtain relevant global variable and wave references
	String SPPath = ESCA_DC_ARPESpath()
	String ARPESName = ESCA_ARPESDisplayed()
	Wave ARPES = ImageNameToWaveRef(SPPath,ARPESName)
	String ARPES_DF = GetWavesDataFolder(ARPES,1)
	String globals_DF = ARPES_DF + "DCglobals"
	
	Nvar varMin = $(globals_DF+":varMin")
	Nvar varMax = $(globals_DF+":varMax")
	Svar colourscaleName = $(globals_DF+":colourscaleName")
	Nvar invert = $(globals_DF+":invertColour")
				
	StrSwitch (ctrlname)
		Case "colorTable": //if drop down is clicked
				colourscaleName = popStr
				Modifyimage/W=$SPPath $NameOfWave(ARPES) ctab={*,*,$colourscaleName,invert}
				Break
	EndSwitch

End

//---------------------------------------------------------------------------

Function ESCA_ActiveCursors(DisplaySettings,checked) : CheckBoxControl
	string DisplaySettings
	variable checked
	variable disp
	
	// Establish references to subpanel wave and folder with global variables
	String panelName = WinName(0,64)
	String SPPath = ESCA_DC_ARPESpath()
	String ARPESName = ESCA_ARPESDisplayed()
	Wave ARPES = ImageNameToWaveRef(SPPath,ARPESName)
	String ARPES_DF = GetWavesDataFolder(ARPES,1)
	String globals_DF = ARPES_DF + "DCglobals:"
	
	// Establish reference to global variables
	Nvar activeE = $(globals_DF + "activate_cursorE")
	Nvar activeF = $(globals_DF + "activate_cursorF")
	
	// Remaining waves
	Wave cursors = $(globals_DF+"cursors")
	Wave color = $(globals_DF+"rgbColor")
	Wave MDC_LPX = $(globals_DF+"MDCLineProfileX")
	Wave MDC_LPY = $(globals_DF+"MDCLineProfileY")
	Wave EDC_LPX = $(globals_DF+"EDCLineProfileX")
	Wave EDC_LPY = $(globals_DF+"EDCLineProfileY")
	
	// Cursor variables
	Nvar csrex = $(globals_DF+"csrex")
	Nvar csrey = $(globals_DF+"csrey")
	Nvar csrfx = $(globals_DF+"csrfx")
	Nvar csrfy = $(globals_DF+"csrfy")
	Nvar MDCwidth = $(globals_DF + "MDCsliceWidth")
	Nvar EDCwidth = $(globals_DF + "EDCsliceWidth")
	
	// Extract colors to be used on cursors
	Variable red, green, blue
	red = color[0]
	green = color[1]
	blue = color[2]
	
	CheckDisplayed/W=$SPPath ARPES		//Checks that there is ARPES displayed, else does not generate cursors
	
	//This checks which tab is currently selected and changes the cursors accordingly
	If (V_Flag==1)
	
		// Figure out what tick box was activated/deactivated
		strswitch(DisplaySettings)	
			case "ActivateE":	
				If(checked)
					
					// Set global logic variable for cursor E to "active"
					activeE = 1
					
					// (i) Add cursor E
					csrex = cursors[0][0]	
					csrey = cursors[0][1]
					Cursor /W=$SPPath /H=1/c=(red,green,blue)/P/I E $(nameOfWave(ARPES)) csrex,csrey
					SetWindow $panelName hook(myHook)=DCPanel_CursorMovedHook // Install hook function on the slicer panel
					
					// Update and plot sample width lines around cursor	
					Variable xE = hcsr(E,SPPath)
					Variable yE = vcsr(E,SPPath)	
					MDC_LPY= {yE+MDCwidth,yE+MDCwidth,NaN,yE-MDCwidth,yE-MDCwidth}
					MDC_LPX={-INF,INF,NaN,-INF,INF}
					EDC_LPY={-INF,INF,NaN,-INF,INF}
					EDC_LPX= {xE+EDCwidth,xE+EDCwidth,NaN,xE-EDCwidth,xE-EDCwidth}
					AppendToGraph/W=$SPPath MDC_LPY vs MDC_LPX
					AppendToGraph/W=$SPPath EDC_LPY vs EDC_LPX
					
				Else
					activeE = 0
					Cursor/W=$SPPath/K E
					RemoveFromGraph/W=$SPPath/Z $NameOfWave(MDC_LPX), $NameOfWave(MDC_LPY), $NameOfWave(EDC_LPX), $NameOfWave(EDC_LPY)
				EndIf
				Break		
			case "ActivateF":	
				If(checked)
					activeF = 1
					csrfx = cursors[1][0]
					csrfy = cursors[1][1]
					Cursor /W=$SPPath /H=1/c=(red,green,blue)/P/I F $(nameOfWave(ARPES)) csrfx,csrfy
					SetWindow $panelName hook(myHook)=DCPanel_CursorMovedHook // Install hook function on the slicer panel
				Else
					activeF = 0
					Cursor/W=$SPPath/K F
				EndIf
				Break
			default:			
				break		
		endswitch
	
	Else
	
		Abort "Something went wrong! Is there an image displayed in the panel?"
	
	EndIf
	
	//Wave MDC_E = $(globals_DF + "MDC_cursorE")
	//Wave MDC_F = $(globals_DF + "MDC_cursorF")
	//Wave EDC_E = $(globals_DF + "EDC_cursorE")
	//Wave EDC_F = $(globals_DF + "EDC_cursorF")
	
	
End	

//---------------------------------------------------------------------------

// Hook function that responds to cursor movement on the energy surface subpanel,
// and updates the ARPES slice accordingly
Function DCPanel_CursorMovedHook(s)
	STRUCT WMWinHookStruct &s
	Variable statusCode= 0
	
	// Global variables
	String SPPath = ESCA_DC_ARPESpath()
	String ARPESName = ESCA_ARPESDisplayed()
	Wave ARPES = ImageNameToWaveRef(SPPath,ARPESName)
	String ARPES_DF = GetWavesDataFolder(ARPES,1)
	String globals_DF = ARPES_DF + "DCglobals:"
	
	Nvar activeE = $(globals_DF + "activate_cursorE")
	Nvar activeF = $(globals_DF + "activate_cursorF")
	
	// (1) See if the right subwindow is active in the panel
	GetWindow $s.winName activeSW
	String activeSubwindow = S_value
	
	If (CmpStr(activeSubwindow,SPPath) != 0)
		return 0
	EndIf
	
	// (2) IF activity in the right subwindow, check if one of the cursors has moved.
	// 	 IF the cursor moved, then update the slice
	StrSwitch( s.eventName )
		Case "cursormoved":	
			String cursorName = s.cursorName													// Figure out what cursor was moved by the user
			ESCA_DCslice(ARPES,SPPath,cursorName,activeE,activeF,globals_DF)		// Update the slices for the appropriate cursor
			break
	EndSwitch

	return statusCode
End

//---------------------------------------------------------------------------

Function ESCA_DCslice(ARPESwave,ARPES_SPPath,cursorName,activeCursorE,activeCursorF,globalsFolder)
	Wave ARPESwave
	String ARPES_SPPath, cursorName, globalsFolder
	Variable activeCursorE, activeCursorF
	
	// Define references to all relevant global variables
	Svar SPPath_MDCs = $(globalsFolder+"MDCFullPath")
	Svar SPPath_EDCs = $(globalsFolder+"EDCFullPath")
	Nvar xMin = $(globalsFolder+"xMin")
	Nvar xMax = $(globalsFolder+"xMax")
	Nvar yMin = $(globalsFolder+"yMin")
	Nvar yMax = $(globalsFolder+"yMax")
	Nvar MDCwidth = $(globalsFolder + "MDCsliceWidth")
	Nvar EDCwidth = $(globalsFolder + "EDCsliceWidth")
	Wave cursors = $(globalsFolder+"cursors")
	Wave xTrace = $(globalsFolder+"xTrace")
	Wave yTrace = $(globalsFolder+"yTrace")
	Wave MDC_LPX = $(globalsFolder+"MDCLineProfileX")
	Wave MDC_LPY = $(globalsFolder+"MDCLineProfileY")
	Wave EDC_LPX = $(globalsFolder+"EDCLineProfileX")
	Wave EDC_LPY = $(globalsFolder+"EDCLineProfileY")
	
	
	// (1) Define relevant local variables
	Variable MDCw2 = MDCwidth/2
	Variable EDCw2 = EDCwidth/2 
	Variable MDCwp = abs(MDCwidth/DimDelta(ARPESwave,1))
	Variable EDCwp = abs(EDCwidth/DimDelta(ARPESwave,0))
	
	If (MDCw2 < 0)
		MDCw2 = 0
	EndIf
	
	If (EDCw2 < 0)
		EDCw2 = 0
	EndIf
	
	Variable NotCursorE = CmpStr(cursorName,"E") // = 0 if the strings match
	
	// (2) Decide which cursor, update cursor position and DCs accordingly
	If ((!NotCursorE) && (activeCursorE))			// Cursor E moved AND cursor E activated
	
		// (i) update cursors
		Nvar pE = $(globalsFolder+"csrex")
		Nvar qE = $(globalsFolder+"csrey")
		cursors[0][0] = pcsr(E,ARPES_SPPath)
		cursors[0][1] = qcsr(E,ARPES_SPPath)
		pE = cursors[0][0]
		qE = cursors[0][1]
		Variable xE = hcsr(E,ARPES_SPPath)
		Variable yE = vcsr(E,ARPES_SPPath)
		
		// (ii) Remove old DCs
		Wave MDC_E = $(globalsFolder + "MDC_cursorE")
		Wave EDC_E = $(globalsFolder + "EDC_cursorE")
		RemoveFromGraph/Z/W=$SPPath_MDCs $NameOfWave(MDC_E)
		RemoveFromGraph/Z/W=$SPPath_EDCs $NameOfWave(EDC_E)
		
		// (iii) Generate new MDC
		xTrace={xMin,xMax}
		yTrace={yE,yE}
		ImageLineProfile srcWave=ARPESwave, xWave=xTrace, yWave=yTrace, width=MDCwp
		Wave W_ImageLineProfile
		MDC_E = W_ImageLineProfile
		AppendToGraph/W=$SPPath_MDCs MDC_E
		
		// (iv) Generate new EDC
		xTrace={xE,xE}
		yTrace ={yMin,yMax}
		ImageLineProfile srcWave=ARPESwave, xWave=xTrace, yWave=yTrace, width=EDCwp
		Wave W_ImageLineProfile
		EDC_E = W_ImageLineProfile
		AppendToGraph/VERT/W=$SPPath_EDCs EDC_E
		
		// (v) Remove old width lines, update, and replot
		RemoveFromGraph/W=$ARPES_SPPath/Z $NameOfWave(MDC_LPX), $NameOfWave(MDC_LPY), $NameOfWave(EDC_LPX), $NameOfWave(EDC_LPY)
		
		MDC_LPY= {yE+MDCwidth,yE+MDCwidth,NaN,yE-MDCwidth,yE-MDCwidth}
		MDC_LPX={-INF,INF,NaN,-INF,INF}
		
		EDC_LPY={-INF,INF,NaN,-INF,INF}
		EDC_LPX= {xE+EDCwidth,xE+EDCwidth,NaN,xE-EDCwidth,xE-EDCwidth}
		
		AppendToGraph/W=$ARPES_SPPath MDC_LPY vs MDC_LPX
		AppendToGraph/W=$ARPES_SPPath EDC_LPY vs EDC_LPX
		
		// (vi) Finally, kill temporary waves
		KillWaves/Z W_ImageLineProfile, W_LineProfileX, W_LineProfileY		
	
	ElseIf ((NotCursorE) && (activeCursorF)) 		// Cursor F moved AND cursor F activated
	
	Else
		Return 0
	EndIf
	


End

//---------------------------------------------------------------------------

// Updates the sample width of the MDC slice (i.e. range of adjacent slices averaged together)
Function ESCA_widthMDC(ctrlName,varNum,varName): SetVariableControl
	String ctrlName
	Variable varNum
	String varName
	
	// Establish references to subpanel wave and folder with global variables
	String panelName = WinName(0,64)
	String SPPath = ESCA_DC_ARPESpath()
	String ARPESName = ESCA_ARPESDisplayed()
	Wave ARPES = ImageNameToWaveRef(SPPath,ARPESName)
	String ARPES_DF = GetWavesDataFolder(ARPES,1)
	String globals_DF = ARPES_DF + "DCglobals:"
	
	// Establish reference to global variables
	Nvar MDCwidth = $(globals_DF + "MDCsliceWidth")		// This one is linked to the value on the panel, updates automatically
	Nvar activeE = $(globals_DF + "activate_cursorE")
	Nvar activeF = $(globals_DF + "activate_cursorF")
	Svar SPPath_MDCs = $(globals_DF+"MDCFullPath")
	
	// If cursor E is activated, update MDC slice and lines displayed
	If(activeE)
		
		// Establish relevant global variable references
		Wave cursors = $(globals_DF+"cursors")
		Wave MDC_E = $(globals_DF + "MDC_cursorE")
		Wave MDC_LPX = $(globals_DF+"MDCLineProfileX")
		Wave MDC_LPY = $(globals_DF+"MDCLineProfileY")
		Wave xTrace = $(globals_DF+"xTrace")
		Wave yTrace = $(globals_DF+"yTrace")
		Nvar csrex = $(globals_DF+"csrex")
		Nvar csrey = $(globals_DF+"csrey")
		
		//ESCA_DCslice(ARPES,SPPath,cursorName,activeE,activeF,globals_DF)		// Update the slices for the appropriate cursor
		
		
	Else	
			
	EndIf
	
	If(activeF)
	
	EndIf
		
End	

//---------------------------------------------------------------------------

// Updates the sample width of the EDC slice (i.e. range of adjacent slices averaged together)
Function ESCA_widthEDC(ctrlName,varNum,varStr,varName): SetVariableControl
	String ctrlName
	Variable varNum
	String varStr
	String varName
	
	
	
	
	
End	

//---------------------------------------------------------------------------

// Updates the sample width of the DC slices (i.e. range of adjacent slices averaged together)
// Note that the value for MDC and EDC with updates automatically from the panel, and so 
// the updated values are not explicitly passed to the function "ESCA_DCslice" 
// (i.e. only a reference to the global variable value is used within the function)
Function ESCA_widthDCs(ctrlName,varNum,varStr,varName) : SetVariableControl
	String ctrlName
	Variable varNum
	String varStr
	String varName
	
	// Establish references to subpanel wave and folder with global variables
	String panelName = WinName(0,64)
	String SPPath = ESCA_DC_ARPESpath()
	String ARPESName = ESCA_ARPESDisplayed()
	Wave ARPES = ImageNameToWaveRef(SPPath,ARPESName)
	String ARPES_DF = GetWavesDataFolder(ARPES,1)
	String globals_DF = ARPES_DF + "DCglobals:"
	
	// Establish reference to global variables
	Nvar activeE = $(globals_DF + "activate_cursorE")
	Nvar activeF = $(globals_DF + "activate_cursorF")
	
	String cursorName = ""
	
	// Update the slices for the appropriate cursor
	ESCA_DCslice(ARPES,SPPath,cursorName,activeE,activeF,globals_DF)

		
End	


//---------------------------------------------------------------------------

//Function for making and reloading cursors on the ARPES image
Function ESCA_DC_Cursors(waveFullPath,subFolderName,cursorBox)
	String waveFullPath, subFolderName, cursorBox
	
	// Image wave and location
	Wave ARPES = $waveFullPath
	Svar ARPESsubPanelPath = $(subFolderName+":ARPESFullPath")

	// Remaining waves
	Wave cursors = $(subFolderName+":cursors")
	Wave color = $(subFolderName+":rgbColor")
	
	// Cursor positions
	Nvar csrex = $(subFolderName+":csrex")
	Nvar csrey = $(subFolderName+":csrey")
	Nvar csrfx = $(subFolderName+":csrfx")
	Nvar csrfy = $(subFolderName+":csrfy")
	
	// Extract colors to be used on cursors
	Variable red, green, blue
	red = color[0]
	green = color[1]
	blue = color[2]
	
	CheckDisplayed/W=$ARPESsubPanelPath ARPES		//Checks that there is ARPES displayed, else does not generate cursors
	
	//This checks which tab is currently selected and changes the cursors accordingly
	If (V_Flag==1)
	
		csrex = cursors[0][0]	//Reading coordinates of cursor E and F from coordstore
		csrey = cursors[0][1]
		csrfx = cursors[1][0]
		csrfy = cursors[1][1]
		Cursor /W=$ARPESsubPanelPath /H=1/c=(red,green,blue)/P/I E $(nameOfWave(ARPES)) csrex,csrey
		Cursor /W=$ARPESsubPanelPath /H=1/c=(red,green,blue)/P/I F $(nameOfWave(ARPES)) csrfx,csrfy
			
	Else
	
		Abort "Something went wrong! Is there an image displayed in the panel?"
	
	EndIf
	
End




	//Variable isWin= CmpStr(IgorInfo(2)[0,2],"Win")==0
	//Variable fsize=12
	//if( isWin )
	//	fsize=10
	//endif
	
	
	
//		if( profileMode==1 )
//		LineProfileY= {position+w2,position+w2,NaN,position-w2,position-w2}
//		LineProfileX={-INF,INF,NaN,-INF,INF}
//	else
//		if( profileMode==2 )
//			LineProfileX= {position+w2,position+w2,NaN,position-w2,position-w2}
//			LineProfileY={-INF,INF,NaN,-INF,INF}
//		endif
//	endif