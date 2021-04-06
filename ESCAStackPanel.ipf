#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#include ":ESCAImgProcs"

// Written by: Håkon I. Røst, NTNU
// hakon.i.rost@ntnu.no

// v.1 June 2020: First slice panel, inspired by ImageJ slice panel and Igor Pro code from Elettra and S. Cooil 
// v.2 July 2020: Added "live slice" and slice export features
// v.3 October 2020: deactivate cursors individually to allow the use of keyboard arrows for single cursor placement
// v.4 October 2020: Added control for exporting energy surfaces
// v.5 November 2020: Added variable slice width (in pixels)

// ===========================================================================================
// 										Initialize NanoESCA stack panel
// ===========================================================================================
// Setup functions for NanoESCA stack slicer tool. Runs when "Open image stack slice panel" 
// is selected from "ESCAlab" menu

// Initialize global variables, open NanoESCA stack slicer panel

Function Init_ESCAStackPanel()
	
	// Navigate to folder for global variables
	SetDataFolder root:ESCAglobals
	
	// Initialize global strings in globals folder
	string/g PanelName = "ESCASlicer"
	string/g ES_stackName = ""
	string/g ES_stackAxisName
	string/g ES_stackParentFolder
	string/g ES_stackWindowName = "ESCA_enSurf"
	string/g ES_sliceWindowName = "ESCA_slice"
	string/g ES_stackFullPath = PanelName+"#"+ES_stackWindowName
	string/g ES_SliceFullPath = PanelName+"#"+ES_sliceWindowName
	
	// Initialize panel waves in globals folder
	Make/d/o/n=(1050,1050,100) w_stack = 0 		// Current Image wave
	Make/O/N=(1500,2500) w_ESCASlice = 0	  		// Extracted ARPES slice
	Make/O/N=(500) w_energies = 0					// Energy value wave
	
	// Image and color variables
	variable/g currEnSlice = 0
	variable/g currEnVal = 0
	variable/g varMax
	variable/g varMin
	Variable/g fixContrast = 0
	variable/g colourscaleReverse = 0
	String/g colourscaleName = ""
	
	// Initialize global cursor variables
	variable/g liveEnable = 0
	variable/g csrcx = 612
	variable/g csrcy= 300
	variable/g csrdx = 612
	variable/g csrdy = 400
	Make/O/N=(2,2) cursors			//Stores Cursor coordinates
	cursors[0][0]={csrcx, csrdx}
	cursors[0][1]={csrcy, csrdy}
	
	// Remaining global variables
	variable/g slicePxWidth = 5
	variable/g dispSumLines = 0
	
	// Cursor colors
	Make/O/N=(3) rgbColor = 0
	rgbColor[0] = 65535
	rgbColor[1] = 42405
	rgbColor[2] = 0
	
	
	Execute "ESCASlicer()" // Fire up this baby
	SetDataFolder root: // reset current directory to root
	
	Return 0
End

// ===========================================================================================
// 										Panel and button controls
// ===========================================================================================

// NanoESCA slice panel
Window ESCASlicer() : Panel

NewPanel /K=2 /W=(240,10,863,372)
PauseUpdate; Silent 1		// building window...

// Guides to define the layout, everything is relative to the window size.
DefineGuide /W=ESCASlicer EnSurfLeft = {FL, 0.01, FR}
DefineGuide /W=ESCASlicer EnSurfRight = {FL, 0.45, FR}
DefineGuide /W=ESCASlicer EvsKLeft = {FL, 0.55, FR}
DefineGuide /W=ESCASlicer EvsKRight = {FL,0.99, FR}
DefineGuide /W=ESCASlicer GraphTop = {FT, 0.25, FB}
DefineGuide /W=ESCASlicer GraphBottom = {FT, 0.99, FB}
DefineGuide /W=ESCASlicer EnSliderPanelLeft = {FT,0.46,FB}
DefineGuide /W=ESCASlicer EnSliderPanelright = {FT,0.5,FB}

// Buttons
Button DisplayStack,pos={9.00,11.00},size={129.00,21.00},proc=ESCA_openStack,title="Display NE Stack"	
Button DisplayStack,fStyle=1,fColor=(56797,56797,56797)
Button KillPanel,pos={526.00,11.00},size={75.00,20.00},proc=ESCA_killESPanel,title="Kill Panel"
Button KillPanel,fStyle=1,fColor=(65535,49151,49151)
Button SliceBetweenCursors,pos={321.00,12.00},size={54.60,18.00},proc=ESCA_sliceButton,title="Slice"
Button SliceBetweenCursors,help={"Slice ARPES stack between cursor C and D"}
Button SliceBetweenCursors,fStyle=1,fColor=(56797,56797,56797)
Button exportSurface,pos={9.00,37.80},size={102.00,18.60},proc=ESCA_exportSurface,title="Export surface"
Button exportSurface,fStyle=1,fColor=(56797,56797,56797)
Button exportSurface,help={"Make a copy wave of the current energy surface as displayed"}
Button EvsKexport,pos={321.60,37.80},size={96.60,18.60},proc=ESCA_exportSlice,title="Export E vs. K"
Button EvsKexport,fStyle=1,fColor=(56797,56797,56797)
Button EvsKexport,help={"Make a copy wave of the current E vs. K slice as displayed"}
	
// Sliders
TitleBox ContrastMaxTitle,pos={120.60,36.60},size={29.40,12.00},title="Max Int"
TitleBox ContrastMaxTitle,frame=0
Slider contrastMax,pos={162.00,39.00},size={120.00,6.00},proc=ESCA_adjustContrast
Slider contrastMax,limits={0,2,0},variable= root:ESCAglobals:varMax,side= 0,vert= 0,tkLblRot= -90,ticks= 0
TitleBox ContrastMinTitle,pos={120.60,57.00},size={27.60,12.00},title="Min Int"
TitleBox ContrastMinTitle,frame=0
Slider ContrastMin,pos={162.00,57.60},size={120.00,6.00},proc=ESCA_adjustContrast
Slider ContrastMin,limits={0,2,0},variable= root:ESCAglobals:varMin,side= 0,vert= 0,ticks= 0
	
// Color profile
PopupMenu imageColor,pos={142.80,12.60},size={49.80,14.40},bodyWidth=50,proc=ESCA_ColorListPopup
PopupMenu imageColor,fSize=10,fStyle=1
PopupMenu imageColor,mode=1,value= #"\"*COLORTABLEPOPNONAMES*\""
CheckBox Invert,pos={10.80,60.60},size={27.60,12.60},proc=ESCA_invert,title="Inv "
CheckBox Invert,fSize=10,fStyle=1
CheckBox Invert,variable= root:ESCAglobals:colourscaleReverse,side= 1

// Energy value display
ValDisplay enVal,pos={232.20,13.80},size={49.80,13.20},bodyWidth=50,format="%.2f",fStyle=1
ValDisplay enVal,limits={0,0,0},barmisc={0,1000},value= #"0"
	
// Slicer utilities
CheckBox LiveSlice,pos={523.20,40.20},size={32.40,12.00},proc=ESCA_liveSlice,title=" Live "
CheckBox LiveSlice,help={"If ticked, the E vs. K image updates automatically whenever a cursor is moved"}
CheckBox LiveSlice,fSize=9,fStyle=1,value= 0
CheckBox LockCursorD,pos={523.20,56.40},size={63.00,12.00},proc=ESCA_LockCursorD,title=" Fix cursor D"
CheckBox LockCursorD,fStyle=1,value= 0
Checkbox LockCursorD, help={"Self-explanatory"}
CheckBox LockCursorC,pos={423.60,56.40},size={61.80,12.00},proc=ESCA_LockCursorC,title=" Fix cursor C"
CheckBox LockCursorC,fStyle=1,value= 0
Checkbox LockCursorC, help={"Self-explanatory"}
CheckBox DispSumLines,pos={423.60,40.20},size={91.80,12.00},title=" Display width", proc=ESCA_dispSumLines
CheckBox DispSumLines,fStyle=1,value= 0
Checkbox DispSumLines,help={"If ticked, the width of the sampling (in px) normal to the\nslice direction is displayed on the energy surface (left)."}
SetVariable sliceWidth,pos={427.20,12.00},size={93.00,13.80},bodyWidth=45,title="Width (px)"
SetVariable sliceWidth,help={"Update the pixel width of adjacent ARPES slices to be summed together in the slice panel"}
SetVariable sliceWidth,fStyle=1,limits={0,inf,1},value=:ESCAglobals:slicePxWidth, proc=ESCA_EvsKsliceWidth//,proc=ESCA_EvsKsliceWidth
	
// Image subwindows
//When you use a * in the field guide it takes the position of /W=() so this has fixed the top axis of the graph to 80
Display /Hide=0 /HOST=ESCASlicer 	/W=(0.01,80,0.45,0.99) /FG = (EnSurfLeft, *, EnSurfRight, GraphBottom) /N=ESCA_EnSurf
SetActiveSubwindow ##
Display /Hide=0 /HOST=ESCASlicer 	/W=(0.55,80,0.99,0.99) /FG = (EvsKLeft, *, EvsKRight, GraphBottom) /N=ESCA_Slice
SetActiveSubwindow ##

//Panel to keep the slider next to the data window
NewPanel /Hide=0 /Host=ESCASlicer /FG = (EnSliderPanelLeft,GraphTop,EnSliderPanelRight,GraphBottom) /N=EnSliderPanel /W=(0.46,0.25,0.5,0.99)
ModifyPanel /W=ESCASlicer#EnSliderPanel framestyle =0
Slider EnergySlider,pos={1,1},size={17.00,261.00},proc=ESCA_ChangeLayer
Slider EnergySlider,help={"Slide to change which constant energy surface is displayed"}
Slider EnergySlider,limits={0,2,1},variable= root:ESCAglobals:currEnSlice,side= 0,ticks= 0
SetActiveSubWindow ##	
EndMacro

//---------------------------------------------------------------------------

// Kills NanoESCA stack panel, restores data folder to root
Function ESCA_killESPanel(ctrlName):ButtonControl
	string ctrlName
	
	Nvar slicePxWidth = root:ESCAglobals:slicePxWidth			
	
	
	// Extract name of panel, kill
	String winStr=WinName(0,64)
	DoWindow/k $winStr
	
	// Free up memory by killing display waves
	SetDataFolder root:ESCAglobals		// Navigate to globals folder
	Killwaves/A									// Kill off all waves in the globals folder
	slicePxWidth = 5							// Reset slice pixel with to 5 pixels (default)
	SetDataFolder root:						// Set path to root folder
	
End

//---------------------------------------------------------------------------

// Opens displays NanoESCA image stack in the slicer panel
Function ESCA_openStack(ctrlname): buttoncontrol //browse path to load files
	String ctrlname
	
	// (1) allocate references to global variables
	Svar ESCAstackFullPath = root:ESCAglobals:ES_stackFullPath
	Svar PanelName = root:ESCAglobals:PanelName
	Svar ESCAstackName = root:ESCAglobals:ES_stackName
	Svar stackParentFolder = root:ESCAglobals:ES_stackParentFolder
	Svar ESCAstackAxisName = root:ESCAglobals:ES_stackAxisName
	Nvar EnVal = root:ESCAglobals:currEnVal
	Wave ESCAstack = root:ESCAglobals:w_stack
	Wave ESCAenergies = root:ESCAglobals:w_energies
	
	// (2) Select stack wave to be displayed
	DFREF saveDF = GetDataFolderDFR()		// Save current data folder before
	
	CreateBrowser/M prompt="Select folder containing NanoESCA image stack:"
	ModifyBrowser /M showModalBrowser, showVars=0, showWaves=0, showStrs=0, showInfo=0, showPlot=0
	string newFolder = StringFromList(0, S_BrowserList)
	Variable numberOfFoldersSelected = ItemsInLIst(S_BrowserList)
 	
	If (V_Flag == 0 || numberOfFoldersSelected != 1)		// something is wrong..
	
		SetDataFolder saveDF		// Restore current data folder if user cancelled, or multiple files in S_BrowserList
	
	Else 	// Folder selected: pick the right stack wave and energy wave, clone these into ESCAglobals
		
		SetDataFolder newFolder	
	
		// Let user select 3D stack and energy wave to be displayed
		String stackName, EnergyName	
		Prompt stackName, "Select 3D stack wave:", popup, WaveList("*",";","DIMS:3")
		Prompt EnergyName, "Select the corresponding energy wave:", popup, WaveList("*",";","DIMS:1")
		DoPrompt "Select data set (from current data folder)", stackName, EnergyName
	
		If (V_Flag)
			return -1	// User canceled
		Endif
	
		// Allocate references to the waves selected
		Wave stackRef = $stackName
		Wave EnRef = $EnergyName
		
		// Obtain relevant stack information
		ESCAstackName = stackName													// Name of ESCA stack wave
		stackParentFolder = GetWavesDataFolder(stackRef,1)					// datafolder path		
		
		// Duplicate scan waves, display stack in panel
		RemoveImage/Z/W=$ESCAstackFullPath $Nameofwave(ESCAStack) 		// Remove old stack wave from panel										
		Duplicate/O stackRef, ESCAstack											// Duplicate stack wave into ESCAglobals folder
		Duplicate/O EnRef, ESCAenergies											// Duplicate energy wave into ESCAglobals folder
		
		AppendImage/W=$ESCAstackFullPath ESCAstack											// Append new wave to subpanel display
		ModifyGraph/W=$ESCAstackFullPath nticks(left)=0, standoff(left)=0			// Remove ticks from left axis
		ModifyGraph/W=$ESCAstackFullPath nticks(bottom)=0, standoff(bottom)=0		// Remove ticks from bottom axis
		ModifyGraph/W=$ESCAstackFullPath margin=-1											// Fit stack to subwindow
		
		// Update layer axis display
		Svar axname												// Obtain reference to axis label in local data folder
		
		If(SVAR_Exists(axname))
			ESCAstackAxisName = axname						// Display this label in the panel, updating the axis name in ESCAglobals folder
		Else
			ESCAstackAxisName = "<N/A>"						// No name specified in local data folder
		EndIf
		
		EnVal = ESCAenergies[0]								// Update energy value to match that of the first NanoESCA slice
		
		ValDisplay enVal, title=ESCAstackAxisName 	// Update label to match dataset
		ValDisplay enVal, value=#num2Str(EnVal)		// Update energy to match dataset
		
		// update energy and contrast sliders to match wave
		ESCA_sliderUpdate()
		
		// Generate cursors on graph, slice between cursors								
		ESCA_GenerateCursors()
		
	
	Endif
	
End

//---------------------------------------------------------------------------

//Function for updating the sliders to match the intensity range of an image
// The function also sets the contrast of the image to be the max-min values initially
Function ESCA_sliderUpdate()

	Svar stackFullPath = root:ESCAglobals:ES_stackFullPath
	Svar PanelName = root:ESCAglobals:PanelName
	Svar colourscaleName = root:ESCAglobals:colourscaleName
	Nvar colourscaleReverse = root:ESCAglobals:colourscaleReverse
	Nvar varMin = root:ESCAglobals:varMin
	Nvar varMax = root:ESCAglobals:varMax
	Nvar fixContrast = root:ESCAglobals:fixContrast
	Nvar currentLayer = root:ESCAglobals:currEnSlice
	Wave ESCAStack = root:ESCAglobals:w_stack
	
	// obtain contrast information from stack wave
	wavestats /q ESCAStack
	
	Variable colorMin, colorMax, numlayers
	
	If (fixContrast)
		colorMin = varMin
		colorMax = varMax
	Else
		colorMin = V_min
		colorMax = V_max
	Endif
	
	// Update local and global variables
	varMin=V_min
	varMax=V_max
	numLayers = dimsize(ESCAstack,2) - 1
	
	
	// Update sliders
	Slider ContrastMin, win=$PanelName, limits={V_min,V_max,0},variable=VarMin, value=colorMin, ticks=0	
	Slider ContrastMax, win=$PanelName,limits={V_min,V_max,0},variable=VarMax, value=colorMax, ticks=0	
	Slider EnergySlider, win=$PanelName+"#EnSliderPanel", limits={0,numLayers,0}, variable=currentLayer, value=0, ticks=0
	
	Modifyimage/W=$stackFullPath $NameOfWave(ESCAStack) ctab={colorMin,colorMax,$colourscaleName,colourscaleReverse}
		
End

//---------------------------------------------------------------------------

// Adjust image contrast
Function ESCA_adjustContrast(name, value, event)
	String name	// name of this slider control
	Variable value	// value of slider
	Variable event	// bit field: bit 0: value set; 1: mouse down; 2: mouse up, 3: mouse moved
	
	Wave ESCAstack = root:ESCAglobals:w_stack
	Wave EvsKSlice = root:ESCAglobals:w_ESCASlice
	Svar stackFullPath = root:ESCAglobals:ES_stackFullPath
	Svar sliceFullPath = root:ESCAglobals:ES_SliceFullPath
	Svar PanelName = root:ESCAglobals:PanelName		
	Nvar varMin = root:ESCAglobals:varMin
	Nvar varMax = root:ESCAglobals:varMax
	
	Svar colourscaleName = root:ESCAglobals:colourscaleName
	Nvar colourscaleReverse = root:ESCAglobals:colourscaleReverse
	
	Modifyimage/W=$stackFullPath $NameOfWave(ESCAstack) ctab={varMin,varMax,$colourscaleName,colourscaleReverse}
	Modifyimage/Z/W=$sliceFullPath $NameOfWave(EvsKSlice) ctab={varMin,varMax,$colourscaleName,colourscaleReverse}
	
	return 0	// other return values reserved
End


//---------------------------------------------------------------------------

// Allows the user to change the color theme of the NanoESCA images
Function ESCA_ColorListPopup(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	Svar stackfullPath = root:ESCAglobals:ES_stackFullPath
	Svar sliceFullPath = root:ESCAglobals:ES_SliceFullPath 
	Wave ESCAStack =  root:ESCAglobals:w_stack
	Wave EvsKSlice = root:ESCAglobals:w_ESCASlice
	Nvar varMin = root:ESCAglobals:varMin
	Nvar varMax = root:ESCAglobals:varMax
	Svar colourscaleName = root:ESCAglobals:colourscaleName
	Nvar colourscaleReverse = root:ESCAglobals:colourscaleReverse
				
	StrSwitch (ctrlname)
		Case "imageColor": //if drop down is clicked
				colourscaleName = popStr
				Modifyimage/W=$stackFullPath $NameOfWave(ESCAStack) ctab={varMIN,varMAX,$colourscaleName,colourscaleReverse}
				Modifyimage/Z/W=$sliceFullPath $NameOfWave(EvsKSlice) ctab={varMin,varMax,$colourscaleName,colourscaleReverse}
			Break
	EndSwitch

End

//---------------------------------------------------------------------------

// Invert the color theme of the NanoESCA images displayed in the slicer panel
Function ESCA_invert(DisplaySettings,checked) : CheckBoxControl
	string DisplaySettings
	variable checked
	variable disp

	Svar colourscaleName = root:ESCAglobals:colourscaleName
	Svar stackfullPath = root:ESCAglobals:ES_stackFullPath
	Svar sliceFullPath = root:ESCAglobals:ES_SliceFullPath
	Wave ESCAStack = root:ESCAglobals:w_stack
	Wave EvsKSlice = root:ESCAglobals:w_ESCASlice
	Nvar varMin = root:ESCAglobals:varMin
	Nvar varMax = root:ESCAglobals:varMax
	Nvar invertColors = root:ESCAglobals:colourscaleReverse

	If (checked == 1)
		invertColors = 1
	Else
		invertColors = 0
	EndIf
	
	Modifyimage/W=$stackfullPath $NameOfWave(ESCAstack) ctab={varMIN,varMAX,$colourscaleName,invertColors}
	Modifyimage/Z/W=$sliceFullPath $NameOfWave(EvsKSlice) ctab={varMIN,varMAX,$colourscaleName,invertColors}
	
	
	return 0	// other return values reserved

End


//---------------------------------------------------------------------------

 Function ESCA_ChangeLayer(name, value, event) : SetVariableControl
	String name			// name of this slider control
	Variable value		// value of slider
	Variable event		// bit field: bit 0: value set; 1: mouse down, //   2: mouse up, 3: mouse moved

	// Global variables
	NVAR currentLayer = root:ESCAglobals:currEnSlice	
	NVAR energyValue = root:ESCAglobals:currEnVal
	Svar stackfullPath = root:ESCAglobals:ES_stackFullPath
	Wave ESCAStack =  root:ESCAglobals:w_stack
	Wave ESCAenergies = root:ESCAglobals:w_energies

	//Change the layer in the stack and the energy displayed
	currentLayer = value
	ModifyImage/W=$stackFullPath $NameOfWave(ESCAStack) plane=currentLayer 
	energyValue = ESCAenergies[currentLayer]
	ValDisplay enVal,value=#num2Str(energyValue)
	
	// Layer auto adjust
	//NVAR layeradjust=root:$(dfStr):layeradjust
	//if (layeradjust==1)
	//	ImageStats/P=(layer) $stackStr
	//	ModifyImage $stackStr ctab= {max(0,V_min),V_max,,0}
	//endif
	//DoUpdate
End

//---------------------------------------------------------------------------

//Function for making and reloading cursors on the constant energy surface
Function ESCA_GenerateCursors()
	
	// Image wave and location
	Svar stackfullPath = root:ESCAglobals:ES_stackFullPath
	Wave ESCAStack =  root:ESCAglobals:w_stack
	
	// Remaining waves
	Wave cursors = root:ESCAglobals:cursors
	Wave color = root:ESCAglobals:rgbColor
	
	// Cursor positions
	Nvar csrcx = root:ESCAglobals:csrcx
	Nvar csrcy = root:ESCAglobals:csrcy
	Nvar csrdx = root:ESCAglobals:csrdx
	Nvar csrdy = root:ESCAglobals:csrdy
	
	// Extract colors to be used on cursors
	Variable red, green, blue
	red = color[0]
	green = color[1]
	blue = color[2]
	
	CheckDisplayed/W=$stackfullPath ESCAStack		//Checks that there is an energy stack being displayed, else does not generate cursors
	
	//This checks which tab is currently selected and changes the cursors accordingly
	If (V_Flag==1)

		csrcx = cursors[0][0]	//Reading coordinates of cursor C and D from coordstore
		csrcy = cursors[0][1]
		csrdx = cursors[1][0]
		csrdy = cursors[1][1]
		Cursor /W=$stackfullPath /s=2/c=(red,green,blue)/P/I/H=0 C $(nameOfWave(ESCAstack)) csrcx,csrcy
		Cursor /W=$stackfullPath /s=2/c=(red,green,blue)/P/I/H=0 D $(nameOfWave(ESCAstack)) csrdx,csrdy
			
	Else
	
		Abort "Something went wrong! Is there an image displayed in the panel?"
	
	EndIf
	
End

//---------------------------------------------------------------------------

Function ESCA_LockCursorC(DisplaySettings,checked) : CheckBoxControl
	string DisplaySettings
	variable checked
	//variable disp
	
	// Image wave and location
	Svar stackfullPath = root:ESCAglobals:ES_stackFullPath
		
	If (checked == 1)
		Cursor/W=$stackfullPath/P/I/S=1/M/A=0 C
	ElseIf(checked == 0)
		Cursor/W=$stackfullPath/P/I/S=2/M/A=1 C
	EndIf
	
End

//---------------------------------------------------------------------------

Function ESCA_LockCursorD(DisplaySettings,checked) : CheckBoxControl
	string DisplaySettings
	variable checked
	//variable disp
	
	// Image wave and location
	Svar stackfullPath = root:ESCAglobals:ES_stackFullPath
		
	If (checked == 1)
		Cursor/W=$stackfullPath/P/I/S=1/M/A=0 D
	ElseIf(checked == 0)
		Cursor/W=$stackfullPath/P/I/S=2/M/A=1 D
	EndIf
	
End

//---------------------------------------------------------------------------

Function ESCA_sliceButton(ctrlName):ButtonControl
	string ctrlName

	// If button is clicked, run the E vs. K slicer function
	ESCA_EvsKSlicer()
	
	Return 0
End

//---------------------------------------------------------------------------


Function ESCA_EvsKSlicer()

	// Global variables
	NVAR currentLayer = root:ESCAglobals:currEnSlice	
	NVAR energyValue = root:ESCAglobals:currEnVal
	NVAR sliceWidth =	root:ESCAglobals:SlicePxWidth
	Svar stackFullPath = root:ESCAglobals:ES_stackFullPath
	Svar sliceFullPath = root:ESCAglobals:ES_SliceFullPath
	Wave ESCAStack =  root:ESCAglobals:w_stack
	Wave EvsKSlice = root:ESCAglobals:w_ESCASlice
	Wave ESCAenergies = root:ESCAglobals:w_energies
	
	// Global contrast and color variables
	Svar colourscaleName = root:ESCAglobals:colourscaleName
	Nvar varMin = root:ESCAglobals:varMin
	Nvar varMax = root:ESCAglobals:varMax
	Nvar invertColors = root:ESCAglobals:colourscaleReverse
		
	// Global Cursor variables
	Nvar pC = root:ESCAglobals:csrcx
	Nvar qC = root:ESCAglobals:csrcy
	Nvar pD = root:ESCAglobals:csrdx
	Nvar qD = root:ESCAglobals:csrdy
	Wave cursors = root:ESCAglobals:cursors
	
	variable dimEn = dimsize(ESCAStack, 2)
	
	// (1) Store cursor positions
	cursors[0][0] = pcsr(C,stackFullPath)
	cursors[0][1] = qcsr(C,stackFullPath)
	cursors[1][0] = pcsr(D,stackFullPath)
	cursors[1][1] = qcsr(D,stackFullPath)
	pC = pcsr(C,stackFullPath)
	qC = qcsr(C,stackFullPath)
	pD = pcsr(D,stackFullPath)
	qD = qcsr(D,stackFullPath)
	
	// (2) Remove old slice image from panel (if any)
	RemoveImage/Z/W=$sliceFullPath $Nameofwave(EvsKSlice) 								// Remove old slice image from panel (if any)										
	
	// (3) Calculate line profile between cursors on energy surface
	variable npx = round(sqrt((pD-pC)^2+(qD-qC)^2 ))+1 									//number of pixels
	Make/O/N=(npx) ptmp,qtmp
	ptmp[]=pC+(pD-pC)/(npx-1)*p 																// x wave of the profile
	qtmp[]=qC+(qD-qC)/(npx-1)*p 																// y wave of the profile	
	
	// (4) Extract Line Profile from energy stack
	ImageLineProfile/P=-2 srcWave=ESCAstack, xWave=ptmp, yWave=qtmp, width=sliceWidth
	Wave M_ImageLineProfile
	//Display M_ImageLineProfile
	Duplicate/O M_ImageLineProfile, EvsKSlice
		
	// (5) Display E vs. k slice wave in panel
	AppendImage/W=$sliceFullPath EvsKSlice													// Append new wave to subpanel display
	ModifyGraph/W=$sliceFullPath nticks(left)=0, standoff(left)=0						// Remove ticks from left axis
	ModifyGraph/W=$sliceFullPath nticks(bottom)=0, standoff(bottom)=0				// Remove ticks from bottom axis
	ModifyGraph/W=$sliceFullPath margin=-1													// Fit stack to subwindow
	
	If(ESCAenergies[1] > ESCAenergies[Dimsize(ESCAenergies,0)-1])
		SetAxis/W=$sliceFullPath/A/R left															// Reverse energy axis if data was recorded with descending energy steps
	EndIf
	
	
	// (6) Update color and contrast to match that of the const. energy slices
	Modifyimage/W=$sliceFullPath $NameOfWave(EvsKSlice) ctab={varMIN,varMAX,$colourscaleName,invertColors}

	// (7) cleanup
	KillWaves/Z M_imageLineProfile, W_LineProfileX, W_LineProfileY, ptmp, qtmp

End

//---------------------------------------------------------------------------

Function ESCA_liveSlice(DisplaySettings,checked) : CheckBoxControl
	string DisplaySettings
	variable checked
	variable disp
	
	Svar panelName = root:ESCAglobals:panelName
	Svar stackFullPath = root:ESCAglobals:ES_StackFullPath
	Nvar live = root:ESCAglobals:liveEnable
	
	If (checked) // The user has set "Live" to active
		live = 1
		SetWindow $panelName hook(myHook)=myCursorMovedHook // Install hook function on the slicer panel
	Else
		live = 0
	EndIf

End

//---------------------------------------------------------------------------

// Hook function that responds to cursor movement on the energy surface subpanel,
// and updates the ARPES slice accordingly
Function myCursorMovedHook(s)
	STRUCT WMWinHookStruct &s
	Variable statusCode= 0
	
	// Global variables
	Svar subWindowName = root:ESCAglobals:ES_stackFullPath
	Nvar live = root:ESCAglobals:liveEnable
	
	// (1) See if the right subwindow is active in the panel
	GetWindow $s.winName activeSW
	String activeSubwindow = S_value
	
	If (CmpStr(activeSubwindow,subWindowName) != 0)
		return 0
	EndIf
	
	// (2) IF activity in the right subwindow, check if one of the cursors has moved.
	// 	 IF the cursor moved, then update the slice
	strswitch( s.eventName )
		case "cursormoved":	
			// see "Members of WMWinHookStruct Used with cursormoved Code"
			//UpdateControls(s.traceName, s.cursorName, s.pointNumber)
			If (live)
				ESCA_EvsKSlicer()
			Else
				Return 0				// Do nothing
			EndIF
			
			break
	endswitch

	return statusCode
End


//---------------------------------------------------------------------------

// Exports the current slice image with the color + contrast settings currently set in the panel.
// The exported image is stored in subfolder EvsKslices of the parent folder
// Finally the slice is opened in a Display window, plotted as a E-EF vs. "pixel" plot. 
Function ESCA_exportSlice(ctrlName):ButtonControl
	string ctrlName
		
	Svar stackFullPath = root:ESCAglobals:ES_stackFullPath
	Svar sliceFullPath = root:ESCAglobals:ES_SliceFullPath
	Svar ESCAstackName = root:ESCAglobals:ES_stackName
	Svar ESCAaxisName = root:ESCAglobals:ES_stackAxisName
	Svar stackParentFolder = root:ESCAglobals:ES_stackParentFolder
	NVAR currentLayer = root:ESCAglobals:currEnSlice	
	NVAR energyValue = root:ESCAglobals:currEnVal
	Wave ESCAStack =  root:ESCAglobals:w_stack
	Wave EvsKSlice = root:ESCAglobals:w_ESCASlice
	Wave ESCAenergies = root:ESCAglobals:w_energies
	
	// Color & contrast variables
	Svar colourscaleName = root:ESCAglobals:colourscaleName
	Nvar varMin = root:ESCAglobals:varMin
	Nvar varMax = root:ESCAglobals:varMax
	Nvar invertColors = root:ESCAglobals:colourscaleReverse

	// Generate new folder name
	String procSliceName, procSliceDest
	procSliceDest = stackParentFolder + "EvsKslices"
	
	// If waves exist in the folder already, allow user to custom name the new slice 
	If (CountObjects(procSliceDest,1) != 0) 
		
		Prompt procSliceName, "Name the new slice wave (in between the quotes): " // Set slice wave name
		DoPrompt "Name wave to be exported", procSliceName
		
		If (V_Flag)
			Return -1 // User canceled
		EndIf
		
	Else	// Use name of stack + "_slice" as default name for the fist wave in the folder 							
		If (strlen(ESCAstackName)>24) 								// Too long file name, cut to 25 characters
			procSliceName =  ESCAstackName[0,19] + "_slice"
		Else
			procSliceName = ESCAstackName + "_slice"
		EndIf
	EndIf // IF folder is empty or not

	// Navigate to destination data folder, duplicate image wave
	NewDataFolder/O/S  $procSliceDest
	Duplicate/O EvsKSlice, $procSliceName
	Wave sliceNew = $procSliceName
	
	// Set energy scale for the E vs. K slice
	variable n, dE, Emin, Emax
	n = DimSize(ESCAenergies,0)
	Emin = min(ESCAenergies[n-1],ESCAenergies[0])
	Emax = max(ESCAenergies[n-1],ESCAenergies[0])
	SetScale/I y, Emin, Emax, sliceNew
	
	// If the global axis name variable is empty, allow user to pick the label name
	If (stringMatch(ESCAaxisName,""))		
		
		string newAxisName
		Prompt newAxisName, "What kind of energy axis are you using? ", popup, "E-EF;KE;BE"
		DoPrompt "Select energy axis label", newAxisName
		
		If( V_Flag )
			Return 0 // user canceled
		Endif
		
		ESCAaxisName = newAxisName
	
	EndIf
	
	// Finally, display slice with labels and axis box
	Display/W=(100,80,400,380); AppendImage sliceNew
	Modifyimage $NameOfWave(sliceNew) ctab={varMIN,varMAX,$colourscaleName,invertColors}
	ModifyGraph standoff=0,mirror=1
	
	Label left ESCAaxisName + " [eV]"
	Label bottom "pixels"
	
	SetDataFolder root:		// Restore data folder to root
	
End

//---------------------------------------------------------------------------


// Update the orthogonal width of the ARPES slice (in pixels).
// The width effectively changes the number of parallel slices averaged together.
Function ESCA_EvsKsliceWidth(ctrlName,varNum,varStr,varName) : SetVariableControl
	String ctrlName
	Variable varNum
	String varStr
	String varName

	Nvar dispLines = root:ESCAglobals:dispSumLines
		
	// If the value is updated, run the E vs. K slice function
	ESCA_EvsKSlicer()
	
	
	If (dispLines)
	
		// Load relevant global variables
		Wave ESCAStack =  root:ESCAglobals:w_stack
		Svar stackFullPath = root:ESCAglobals:ES_stackFullPath
		Nvar sliceWidth = root:ESCAglobals:slicePxWidth
		
		// Global Cursor variables
		Nvar pC = root:ESCAglobals:csrcx
		Nvar qC = root:ESCAglobals:csrcy
		Nvar pD = root:ESCAglobals:csrdx
		Nvar qD = root:ESCAglobals:csrdy
		Wave cursors = root:ESCAglobals:cursors
	
		// Update cursors
		cursors[0][0] = pcsr(C,stackFullPath)
		cursors[0][1] = qcsr(C,stackFullPath)
		cursors[1][0] = pcsr(D,stackFullPath)
		cursors[1][1] = qcsr(D,stackFullPath)
		pC = pcsr(C,stackFullPath)
		qC = qcsr(C,stackFullPath)
		pD = pcsr(D,stackFullPath)
		qD = qcsr(D,stackFullPath)
		Variable xC = hcsr(C,stackFullPath)
		Variable yC = vcsr(C,stackFullPath)
		Variable xD = hcsr(D,stackFullPath)
		Variable yD = vcsr(D,stackFullPath)
		
		ESCA_drawLines(ESCAStack,stackFullPath,sliceWidth,pC,qC,pD,qD)
	
	EndIf

End

//---------------------------------------------------------------------------

// Display the width over which the ARPES slice is averaged from on the
// constant energy surface
Function ESCA_dispSumLines(DisplaySettings,checked) : CheckBoxControl
	string DisplaySettings
	variable checked
	variable disp
	
	// First, load variables from globals folder
	Nvar dispLines = root:ESCAglobals:dispSumLines
	Nvar sliceWidth = root:ESCAglobals:slicePxWidth
	Svar stackFullPath = root:ESCAglobals:ES_stackFullPath
	
	// Load relevant waves
	Wave ESCAStack =  root:ESCAglobals:w_stack
	Wave sumLine1_X
	Wave sumLine1_Y
	Wave sumLine2_X
	Wave sumLine2_Y
	
	// Global Cursor variables
	Nvar pC = root:ESCAglobals:csrcx
	Nvar qC = root:ESCAglobals:csrcy
	Nvar pD = root:ESCAglobals:csrdx
	Nvar qD = root:ESCAglobals:csrdy
	Wave cursors = root:ESCAglobals:cursors
	
	If (checked)
	
		// Set boolean for drawing lines to active
		dispLines = 1
		
		// Load/update cursors
		cursors[0][0] = pcsr(C,stackFullPath)
		cursors[0][1] = qcsr(C,stackFullPath)
		cursors[1][0] = pcsr(D,stackFullPath)
		cursors[1][1] = qcsr(D,stackFullPath)
		pC = pcsr(C,stackFullPath)
		qC = qcsr(C,stackFullPath)
		pD = pcsr(D,stackFullPath)
		qD = qcsr(D,stackFullPath)
		Variable xC = hcsr(C,stackFullPath)
		Variable yC = vcsr(C,stackFullPath)
		Variable xD = hcsr(D,stackFullPath)
		Variable yD = vcsr(D,stackFullPath)
		
		ESCA_drawLines(ESCAStack,stackFullPath,sliceWidth,pC,qC,pD,qD)
		
		
	Else
		// Set boolean for drawing lines to inactive, then remove the previous lines
		dispLines = 0
		RemoveFromGraph/W=$stackFullPath/Z $NameOfWave(sumLine1_X), $NameOfWave(sumLine1_Y), $NameOfWave(sumLine2_X), $NameOfWave(sumLine2_Y)
		KillWaves/Z sumLine1_X, sumLine1_Y, sumLine2_X, sumLine2_Y
	EndIf

End



//---------------------------------------------------------------------------


Function ESCA_drawLines(stackWave,stackFullPath,sumWidth,pC,qC,pD,qD)
	Wave stackWave
	String stackFullPath
	variable sumWidth, pC, qC, pD, qD
	
	Wave sumLine1_X, sumLine1_Y, sumLine2_X, sumLine2_Y
	RemoveFromGraph/W=$stackFullPath/Z $NameOfWave(sumLine1_X), $NameOfWave(sumLine1_Y), $NameOfWave(sumLine2_X), $NameOfWave(sumLine2_Y)
	
	// Calculate variables related to the line profile between cursors
	variable npx = round(sqrt((pD-pC)^2+(qD-qC)^2 ))+1 									//number of pixels along line
	variable sinValue = (qD-qC)/(npx-1)															// sin value of polar angle of line
	variable cosValue = (pD-pC)/(npx-1)															// cos value of polar angle of line
	variable dP = sumWidth*sinValue																// Offset in rows
	variable dQ = sumWidth*cosValue																// Offset in columns
	
	Make/O/N=(npx) sumLine1_X, sumLine1_Y, sumLine2_X, sumLine2_Y
	sumLine1_X[] = (pC-dP) + cosValue*p
	sumLine1_Y[] = (qC+dQ) + sinValue*p
	sumLine2_X[] = (pC+dP) + cosValue*p
	sumLine2_Y[] = (qC-dQ) + sinValue*p
	
	AppendToGraph/W=$stackFullPath sumLine1_Y vs sumLine1_X
	AppendToGraph/W=$stackFullPath sumLine2_Y vs sumLine2_X
	
	
	
	
	//Variable xC = hcsr(C,stackFullPath)
	//Variable yC = vcsr(C,stackFullPath)
	//Variable xD = hcsr(D,stackFullPath)
	//Variable yD = vcsr(D,stackFullPath)
		
	
	

End



//---------------------------------------------------------------------------

// Exports the current energy surface with the color + contrast settings currently set in the panel.
// The iage is stored in subfolder 
// Added annotation is the energy and FOV at which the image was recorded
Function ESCA_exportSurface(ctrlName):ButtonControl
	string ctrlName
	
	// 1: Obtain relevant global string variables and wave references
	Svar stackFullPath = root:ESCAglobals:ES_stackFullPath
	Svar ESCAstackName = root:ESCAglobals:ES_stackName
	Svar stackParentFolder = root:ESCAglobals:ES_stackParentFolder
	Svar EnergyLabel = $(stackParentFolder+"axname")
	Wave ESCAStack =  root:ESCAglobals:w_stack
	Wave ESCAenergies = root:ESCAglobals:w_energies
	
	// 2. Obtain meta data
	Nvar currLayer = root:ESCAglobals:currEnSlice	
	Nvar detSize = $(stackParentFolder+"DET_SIZE")
	Nvar mag = $(stackParentFolder+"M_FOV")
	Variable currentEnergy = ESCAenergies[currLayer]
	
	// 3: Color & contrast variables
	Nvar varMin = root:ESCAglobals:varMin
	Nvar varMax = root:ESCAglobals:varMax
	Nvar invert = root:ESCAglobals:colourscaleReverse
	Svar colourscaleName = root:ESCAglobals:colourscaleName

	// 4: Generate subfolder name and wave name
	String surfaceDest = stackParentFolder + "EnSurfaces"
	String surfaceName
	
	// i. If waves exist in the subfolder already, allow user to custom name the new slice 
	If (CountObjects(surfaceDest,1) != 0) 
		Prompt surfaceName, "Name the new energy surface (in between the quotes).\nEnergy value is automatically added as suffix:" // Set energy surface name
		DoPrompt "Name wave to be exported", surfaceName
		If (V_Flag)
			Return -1 // User canceled
		EndIf
	Else				// No waves in subfolder
		surfaceName = ESCAstackName
	EndIf
		
	// ii. Add suffix with energy value to all names
	String energySyffix = "_" + num2str(currentEnergy) + "eV" 									
	If(strlen(surfaceName)>=28) // Too long file name, cut to 22 characters then add suffix
			surfaceName =  surfaceName[0,22] + energySyffix 
	Else
			surfaceName += energySyffix
	EndIf		

	// 5: Navigate to destination data folder, duplicate image wave
	NewDataFolder/O/S  $surfaceDest
	Duplicate/O/RMD=[][][currLayer] ESCAStack, $surfaceName
	Wave surfNew = $surfaceName
	
	// 6: Display new image wave, including FOV if info is available
	NewImage/K=1/F/S=0 surfNew
	Modifyimage $NameOfWave(surfNew) ctab={varMIN,varMAX,$colourscaleName,invert}
	
	// If meta info on FOV exists, add this to the image as well
	If (NVAR_EXISTS(detSize) && NVAR_EXISTS(mag))
		string FOVstr, currentPanel
		sprintf FOVstr, "FOV: %s / Å", num2str(detSize/mag) 
		currentPanel = WinName(0,1)
		
		SetDrawLayer/W=$currentPanel Overlay; DelayUpdate
		SetDrawEnv/W=$currentPanel textrgb= (65535,49157,16385),fstyle= 1,xcoord=rel,ycoord=rel;DelayUpdate
		DrawText/W=$currentPanel 0.05, 0.96, FOVstr
	EndIf
	
	// 5: Finally, restore data folder to root
	SetDataFolder root:
	
End



// ===========================================================================================
// 												Supporting functions
// ===========================================================================================

Function  ESCA_ImageToFront(graphNameStr,stackWave) 
	String graphNameStr
	wave stackWave

	Dowindow $graphNameStr
	If (V_flag==0)
		NewImage/S=2/G=1/N=$(graphNameStr) stackWave
		ModifyGraph width=270
		ModifyGraph height={Plan,1,left,top}
		MoveWindow 30,0,300,270
		ModifyGraph nticks=0
	Else
		DoWindow/F $graphNameStr
		MoveWindow 30,0,300,270
	Endif
	//ShowInfo
End

//=========================================================================================================

Function ESCA_StackControls()
	ControlBar 85
	String dfStr = ESCA_GetImageDfStrFromWin()
	String stackStr = ESCA_GetStackName()
	String axisStr
	Variable r = dimsize($stackStr,2)
	NVAR layer=root:$(dfStr):layer
	
	SetDataFolder root:$(dfStr)
	//First Line
	Slider layerSlider,pos = {5,13},size = {280,22},proc=IMP_ChangeLayer
	Slider layerSlider,limits = {0,r -1,1},value= 0,vert= 0,ticks=0,side=0,variable = root:$(dfStr):layer
	layer = 0
	Button playButton,pos={300, 5},size={30,22},proc=NE_ShowMovie,title="\W549"
	// 
	//Second line
	Button killButton,pos={5, 28},size={90,22},proc=NE_KillStack_ctrl,title="Kill"
	Button sumUpButton,pos={102, 28},size={90,22},proc=PR_SumImages_ctrl,title="Sum Up Img"
	//Third Line
	Button ROIextrButton,pos={5, 58},size={90,22},proc=PROI_ExtractROI_ctrl,title="Extract ROI"
	Button MeasureAngleButton,pos={102, 58},size={90,22},proc=IPR_MeasureAngle,title="Measure Angle"

	// set layer
	SetVariable sl,pos={198,30},size={78,22},proc=IMP_SetLayerVar,title=""
	SetVariable sl,font="Arial",limits={0,r -1,1},value=root:$(dfStr):layer
	// Auto adjust
	CheckBox adjcb,pos={300,33},size={90,22},title="Auto-adj"
	CheckBox adjcb, variable = root:$(dfStr):layeradjust	
	// Variable 
	SVAR axname=root:$(dfStr):axname
	if (!SVAR_Exists(axname))	// No such global numeric variable?
		//Do nothing
	else
		ValDisplay vd, pos={198,60} , size={78,22}, frame=2, font="Helvetica",title=axname ,value= #"foo"
		ValDisplay vd,format="%.2f",limits={0,0,0},barmisc={0,1000}, disable=2
		ValDisplay vd, value=0
	endif
	
End

//=========================================================================================================

Function/S ESCA_GetImageDfStrFromWin() //Get the datafolder of the top graph, obtained from the WIN name

	String winStr =  ESCA_getWinName()
	Variable strL = strlen(winStr)
	String dfStr = winStr[3,StrL] // prefix takes the first three characters of the window name

	Return dfStr

End

//=========================================================================================================

Function/S ESCA_GetStackName() //Get the NAME of the stack/image displayed

String info= ImageInfo("","",0)
String imgStr = StringByKey("ZWAVE",info) // image wave name

Return imgStr

End

//=========================================================================================================


Function/S ESCA_GetWinName() // Get the name of the top graph
	String winStr=WinName(0,1)
	winStr = ESCA_RemoveQuotes(winStr)
	return winStr
end 

//=========================================================================================================

Function/S ESCA_RemoveQuotes(str)
	String str
	variable n=strlen(str)
	if (stringMatch(str[n-1],"'")==1)
		str=str[0,n-2]
	endif
	// get rid of first ' 
	n=strlen(str)
	if (stringMatch(str[0],"'")==1)
		str=str[1, n-1]
	endif
	return str
end

//=========================================================================================================


 Function/S ESCA_SelectWavePar(dfStr)
 	String dfStr
 	String Vstr
 	String stackStr = ESCA_getStackName()
 	
 	SVAR axname=root:$(dfStr):axname
	If(StringMatch(WaveList("*",";",""),"*KE*")) //("*","",""),";KE*"))
		vStr = "KE" + dfStr
	elseif(StringMatch(WaveList("*",";",""),"*IMG*")) //("*","",""),";IMG*"))
		vStr = "IMG" + dfStr
		axname = "Img#"
	elseif(StringMatch(WaveList("*",";",""),"*;ANG*")) // Here we need ";" 
		vStr = "ANG" + dfStr
		axname = "deg"
	Endif
	
	If(StringMatch(stackStr, "*NST"))
		vStr = dfstr +  "NST" + "_P"
		axname = "Img#"
	Endif
	
	Return vstr
 End
 
 //=========================================================================================================
 
