#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#include ":ESCAImgProcs"

// Written by: Håkon I. Røst, NTNU
// hakon.i.rost@ntnu.no

// v.1 July 2020: first incarnation, with image editing buttons
// V.2 August 2020: Add slider to image panel, IFF user selects a stack instead of single image
// V.3 April 2021: Display calibrated FOV in image panel with proper unit

// ===========================================================================================
// 										Initialize NanoESCA image panel
// ===========================================================================================
// Setup functions for NanoESCA image tool. Runs when "Open single image panel" 
// is selected from "ESCAlab" menu

// Initialize global variables, open NanoESCA image panel


Function Init_ESCAImgPanel()

	// Select stack wave to be displayed
	DFREF saveDF = GetDataFolderDFR()		// Save current data folder before
	
	CreateBrowser/M prompt="Select the NanoESCA image you want to display: "
	ModifyBrowser /M showModalBrowser, showVars=0, showWaves=1, showStrs=0, showInfo=0, showPlot=0
	string displayWaveName = StringFromList(0, S_BrowserList)
	Variable numberOfFoldersSelected = ItemsInLIst(S_BrowserList)
 	
	If (V_Flag == 0 || numberOfFoldersSelected != 1)		// something is wrong..
	
		SetDataFolder saveDF		// Restore current data folder if user cancelled, or multiple files in S_BrowserList
	
	Else 	// ONE wave selected: obtain relevant wave info, display
		
		Wave dispWave = $displayWaveName
		String dispParentFolder = GetWavesDataFolder(dispWave,1)	// datafolder path	 
		
		// Make sure a 2D or 3D wave has been selected
		If (DimSize(dispWave,1) == 0 || DimSize(dispWave,3) != 0) // trace or 4D wave selected
		
			Abort "ERROR! Did you select a 1D trace or a 4D wave instead of an image or an image stack?"
		
		Else
		
			// Navigate to parent folder
			SetDataFolder dispParentFolder	
			
			// Initialize relevant global strings
			string/g ImgName = nameOfWave(dispWave)
			string/g waveFullPath = displayWaveName
			string/g PanelName = "ImgPanel" 
			string/g ImgParentFolder = dispParentFolder
			string/g ImgWindowName = "ESCA_img"
			string/g ImgFullPath = PanelName+"#"+ImgWindowName
			string/g imgDestfolderName = "procImg"
			String/g colourscaleName = ""

			// Initialize relevant global variables
			variable/g currLayer
			variable/g numLayers = DimSize(dispWave,2)
			variable/g np = DimSize(dispWave,0)
			variable/g nq = DimSize(dispWave,1)
			variable/g varMax
			variable/g varMin
			Variable/g fixContrast = 0
			variable/g invertColour = 0
			variable/g activate_cursor = 0
			
			// Initialize global cursor variables
			Variable/g csrx = np/2
			Variable/g csry= nq/2
			Variable/g ROIRadius = 100
			Make/O/N=(2) cursors
			cursors={csrx, csry}
			Make/O/N=(3) rgbColor = 0
			rgbColor[0] = 65535
			rgbColor[1] = 42405
			rgbColor[2] = 0
			
			// Assemble "Execute" string with panel input name
			string cmd
			sprintf cmd, "ESCAImg(\"%s\")", waveFullPath 

			Execute cmd 			  // Fire up this baby
			SetDataFolder root: // reset current directory to root
	
	
		EndIf	// Wave of the right dimensions selected
	
	EndIf // ONE wave selected
	
	Return 0

End

// ===========================================================================================
// 										Panel and button controls
// ===========================================================================================


Window ESCAImg(waveFullPath) : Panel

	String waveFullPath

	PauseUpdate; Silent 1		// building window...
	NewPanel /W=(294,48,584,408)
	SetDrawLayer UserBack
	SetDrawEnv fstyle= 1
	DrawText 114,25,"Max."
	SetDrawEnv fstyle= 1
	DrawText 114,49,"Min."
	Slider contrastMax,pos={7.00,10.00},size={100.00,15.00}
	Slider contrastMax,limits={0,2,1},vert= 0,ticks= 0
	Slider contrastMin,pos={7.00,34.00},size={100.00,15.00}
	Slider contrastMin,limits={0,2,1},side= 2,vert= 0,ticks= 0
	CheckBox Invert,pos={191,31},size={36.00,16.00},title="Inv",fStyle=1
	CheckBox Invert,value= 0
	CheckBox activateROIpanel,pos={148,31},size={39.00,16.00},title="ROI"
	CheckBox activateROIpanel,fStyle=1,proc=ESCA_ROIpanel
	PopupMenu colorTable,pos={231.00,28.00},size={50.00,24.00},bodyWidth=50
	PopupMenu colorTable,mode=1,value= #"\"*COLORTABLEPOPNONAMES*\""
	Button KillButton,pos={231.00,5.00},size={50.00,20.00},title="Kill",fStyle=1
	Button KillButton,fColor=(48059,48059,48059),proc=ESCA_killImgPanel
	Button SaveButton,pos={147.00,5.00},size={80.00,20.00},title="Save image",fStyle=1
	Button SaveButton,fColor=(48059,48059,48059)
	
	// Set up the image display window
	String ImgWindowName = "ESCA_img"
	Display/W=(10,80,280,350)/HOST=# 
	RenameWindow #,$ImgWindowName
	SetActiveSubwindow ##
	
	// Finally, activate buttons and display image
	ESCA_DispImage(imgWindowName,waveFullPath)			// Display image
	ESCA_ImgCtrlSetup(imgWindowName,waveFullPath)		// Link controls to global variables in parent folder
	ESCA_ImgSliderSetup()										// Update sliders to match image contrast extremes
	
EndMacro

//---------------------------------------------------------------------------

Function ESCA_DispImage(imgWindowName,waveFullPath)
	String imgWindowName,waveFullPath
	
	// Obtain relevant wave info
	Wave img = $waveFullPath
	String subPanelPath = ESCA_getSubPanelPath()
	string DF = GetWavesDataFolder(img,1)
	
	Nvar numLayers = $(DF+"numLayers")
	Nvar detSize = $(DF+"DET_SIZE")
	Nvar mag = $(DF+"M_FOV")
	Nvar FOVmode = $(DF+"FOV_MODE")
	Wave FOVs = $(DF+"FOVs")

	// Add image to graph subpanel
	AppendImage/W=$subPanelPath img												// Append new wave to subpanel display
	ModifyGraph/W=$subPanelPath nticks=0, standoff=0, margin=-1			// Remove ticks, standoff and margin
	
	// If meta info on FOV exists, add this to the image as well
	string currentPanel = WinName(0,64)
	String FOVstr
	
	If ( WaveExists(FOVs) && (FOVs[0] != 0) )	// Opt. 1: wave with corrected FOV values
		
		If (FOVmode == 1)
			Sprintf FOVstr, "FOV: %s um", num2str(FOVs[0])
		ElseIf (FOVmode == 2)
			Sprintf FOVstr, "FOV: %s / Å", num2str(FOVs[0])
		EndIf
		
		SetDrawLayer/W=$currentPanel Overlay; DelayUpdate
		SetDrawEnv/W=$currentPanel textrgb= (65535,49157,16385),fstyle= 1,xcoord=rel,ycoord=rel;DelayUpdate
		DrawText/W=$currentPanel 0.05, 0.96, FOVstr
	
	ElseIf ( NVAR_EXISTS(detSize) && NVAR_EXISTS(mag) )	// Opt. 2: Static FOV calculated from meta data
	
		If (FOVmode == 1)
			Sprintf FOVstr, "FOV: %s um", num2str(detSize/mag)
		ElseIf (FOVmode == 2)
			Sprintf FOVstr, "FOV: %s / Å", num2str(detSize/mag)
		EndIf	
		
		SetDrawLayer/W=$currentPanel Overlay; DelayUpdate
		SetDrawEnv/W=$currentPanel textrgb= (65535,49157,16385),fstyle= 1,xcoord=rel,ycoord=rel;DelayUpdate
		DrawText/W=$currentPanel 0.05, 0.96, FOVstr
		
	EndIf
	
End

//---------------------------------------------------------------------------

// Returns path to the image subwindow with the appropriate syntax
Function/S ESCA_getSubPanelPath()
	
	string panelName = WinName(0,64)
	string subPanelName = panelName + "#ESCA_img"

	Return subPanelName
End

//---------------------------------------------------------------------------

// Returns the name of the top wave displayed in the "active" panel
Function/S ESCA_topWaveDisplayed()

	string SPPath = ESCA_getSubPanelPath()
	string imageList = ImageNameList(SPPath,";")
	string displayWaveName = StringFromList(0, imageList)
	
	return displayWaveName
End

//---------------------------------------------------------------------------


// Links sliders and buttons to the right global variables
Function ESCA_ImgCtrlSetup(imgWindowName,waveFullPath)
	String imgWindowName, waveFullPath
	
	wave imgWave = $waveFullPath
	string DF = GetWavesDataFolder(imgWave,1)
	string SPPath = ESCA_getSubPanelPath()
	Nvar numLayers = $(DF+"numLayers")
	
	// Activate buttons, sliders ane checkboxes by linking them to functions
	Slider contrastMax, variable=$(DF+"varMax"),proc=ESCA_imgContrast
	Slider contrastMin, variable=$(DF+"varMin"),proc=ESCA_imgContrast
	CheckBox Invert, variable=$(DF+"invertColour"),proc=ESCA_ImgInvert
	PopupMenu colorTable, proc=ESCA_ImgColorList
	Button SaveButton,proc=ESCA_savePEEMImg

	// If image is a stack, add ROI controls and adjust panel appearance
	//If(numLayers > 1)
	
		// Update style and appearance of existing controls
		//PopupMenu colorTable,pos={231.00,28.00},size={50.00,24.00},bodyWidth=50
		//CheckBox Invert,pos={191,31},size={36.00,16.00}
		
		// Add checkbox for activating ROI side panel
		//CheckBox activateROIpanel,pos={148,31},size={39.00,16.00},title="ROI"
		//CheckBox activateROIpanel,fStyle=1,proc=ESCA_ROIpanel
	
	//EndIf


End

//---------------------------------------------------------------------------

Function ESCA_ImgSliderSetup()

	// Obtain relevant global variable and wave info
	string SPPath = ESCA_getSubPanelPath()
	string imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	string DF = GetWavesDataFolder(img,1)
	
	Nvar varMin = $(DF+"varMin")
	Nvar varMax = $(DF+"varMax")
	Svar colourscaleName = $(DF+"colourscaleName")
	Nvar invert = $(DF+"invertColour")
	Nvar layer = $(DF+"currLayer")
	Nvar numLayers = $(DF+"numLayers")

	// obtain contrast information from image wave
	wavestats /q img
	
	Variable colorMin, colorMax, lastLayer
	
		colorMin = V_min
		colorMax = V_max

	// Update local and global variables
	varMin=V_min
	varMax=V_max
	lastLayer = numLayers - 1
	
	// Update contrast sliders
	Slider ContrastMin, win=$WinName(0,64), limits={V_min,V_max,0},variable=VarMin, value=colorMin, ticks=0	
	Slider ContrastMax, win=$WinName(0,64),limits={V_min,V_max,0},variable=VarMax, value=colorMax, ticks=0	
	Modifyimage/W=$SPPath $NameOfWave(img) ctab={colorMin,colorMax,$colourscaleName,invert}
	
	// If image is a stack, add slider for changing what layer is displayed
	If(numLayers > 1)
			
			// Slider setup
			Slider currentImg, pos={8.00,61.00},size={204.00,10.00},proc=ESCA_ImageUpdate
			Slider currentImg, help={"Slide to change which layer is displayed"}
			Slider currentImg, limits={0,lastLayer,1},variable=layer,value= 0,ticks=0,side= 0,vert= 0
			
			// Add value display box showing the current layer
			ValDisplay currImgVal,pos={216.00,55.00},size={65.00,18.00},title="Img: ",fStyle=1
			ValDisplay currImgVal,limits={0,0,0},barmisc={0,1000},value= #"0",variable=layer
	
	EndIf
	
End

//---------------------------------------------------------------------------

// Adjust image contrast
Function ESCA_imgContrast(name, value, event)
	String name	// name of this slider control
	Variable value	// value of slider
	Variable event	// bit field: bit 0: value set; 1: mouse down; 2: mouse up, 3: mouse moved
	
	// Obtain relevant global variable and wave references
	string SPPath = ESCA_getSubPanelPath()
	string imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	string DF = GetWavesDataFolder(img,1)
	
	Nvar varMin = $(DF+"varMin")
	Nvar varMax = $(DF+"varMax")
	Svar colourscaleName = $(DF+"colourscaleName")
	Nvar invert = $(DF+"invertColour")
	
	Modifyimage/W=$SPPath $NameOfWave(img) ctab={varMin,varMax,$colourscaleName,invert}
	
	return 0	// other return values reserved
End


//---------------------------------------------------------------------------

// Invert the color theme of the image displayed in a NanoESCA image panel
Function ESCA_ImgInvert(DisplaySettings,checked) : CheckBoxControl
	string DisplaySettings
	variable checked
	variable disp

	// Obtain relevant global variable and wave references
	string SPPath = ESCA_getSubPanelPath()
	string imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	string DF = GetWavesDataFolder(img,1)
	
	Nvar varMin = $(DF+"varMin")
	Nvar varMax = $(DF+"varMax")
	Svar colourscaleName = $(DF+"colourscaleName")
	Nvar invert = $(DF+"invertColour")
	
	If (checked == 1)
		invert = 1
	Else
		invert = 0
	EndIf
	
	Modifyimage/W=$SPPath $NameOfWave(img) ctab={varMIN,varMAX,$colourscaleName,invert}
	
	return 0	// other return values reserved

End

//---------------------------------------------------------------------------

// Allows the user to change the color theme of the NanoESCA images
Function ESCA_ImgColorList(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum
	String popStr
	
	// Obtain relevant global variable and wave references
	string SPPath = ESCA_getSubPanelPath()
	string imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	string DF = GetWavesDataFolder(img,1)
	
	Nvar varMin = $(DF+"varMin")
	Nvar varMax = $(DF+"varMax")
	Svar colourscaleName = $(DF+"colourscaleName")
	Nvar invert = $(DF+"invertColour")
				
	StrSwitch (ctrlname)
		Case "colorTable": //if drop down is clicked
				colourscaleName = popStr
				Modifyimage/W=$SPPath $NameOfWave(img) ctab={varMin,varMax,$colourscaleName,invert}
				Break
	EndSwitch

End


//---------------------------------------------------------------------------

Function ESCA_ImageUpdate(name, value, event)
	String name			// name of this slider control
	Variable value		// value of slider
	Variable event		// bit field: bit 0: value set; 1: mouse down, //   2: mouse up, 3: mouse moved

	// Obtain relevant global variable and wave references
	String panelName = WinName(0,64)
	String SPPath = ESCA_getSubPanelPath()
	String imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	String DF = GetWavesDataFolder(img,1)
	
	// Update global layer variable from slider
	Nvar gLayer = $(DF+"currLayer")
	gLayer = value
	
	// Update image and value display
	ModifyImage/W=$SPPath $NameOfWave(img) plane=gLayer
	ValDisplay currImgVal,value=#num2Str(gLayer)
	
	// If meta info wave with FOVs exists, update the current FOV displayed in the panel
	Nvar FOVmode = $(DF+"FOV_MODE")
	Wave FOVs = $(DF+"FOVs")
		
	If ( WaveExists(FOVs) && (FOVs[0] != 0) )	// Opt. 1: wave with corrected FOV values
		
		String FOVstr
		
		If (FOVmode == 1)
			Sprintf FOVstr, "FOV: %s um", num2str(FOVs[gLayer])
		ElseIf (FOVmode == 2)
			Sprintf FOVstr, "FOV: %s / Å", num2str(FOVs[gLayer])
		EndIf
		
		SetDrawLayer/K/W=$panelName Overlay; DelayUpdate
		SetDrawEnv/W=$panelName textrgb= (65535,49157,16385),fstyle= 1,xcoord=rel,ycoord=rel;DelayUpdate
		DrawText/W=$panelName 0.05, 0.96, FOVstr
	
	EndIf

End

//---------------------------------------------------------------------------

Function ESCA_savePEEMImg(ctrlName):ButtonControl
	string ctrlName
	
	// 1: Obtain relevant global variable and wave references
	string SPPath = ESCA_getSubPanelPath()
	string imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	string oldDF = GetWavesDataFolder(img,1)
	
	Nvar varMin = $(oldDF+"varMin")
	Nvar varMax = $(oldDF+"varMax")
	Svar colourscaleName = $(oldDF+"colourscaleName")
	Svar destFolderName = $(oldDF+"imgDestfolderName")
	Nvar invert = $(oldDF+"invertColour")
	Nvar currLayer = $(oldDF+"currLayer")
	Nvar numLayers = $(oldDF+"numLayers")
	Nvar np = $(oldDF+"np")
	Nvar nq = $(oldDF+"nq")
	Nvar detSize = $(oldDF+"DET_SIZE")
	Nvar mag = $(oldDF+"M_FOV")

	// 2: Generate new file name and folder name
	String procImgDest = OldDF + destfolderName
	String procImgName
	
	variable test = strlen(imgName)
	
	If(strlen(imgName)>=28) // Too long file name, cut to 24 characters
			procImgName =  imgName[0,24] + "_proc" 
	Else
			procImgName = imgName + "_proc"
	EndIf		

	// 3: Navigate to destination data folder, duplicate image wave
	NewDataFolder/O/S  $procImgDest
	
	If (numLayers > 0)
		Make/O/N=(np,nq) $procImgName
		Wave imgNew = $procImgName
		imgNew = img[p][q][currLayer]
	Else
		Duplicate/O img, $procImgName
		Wave imgNew = $procImgName
	EndIf
	
	// 4: display new image wave, including FOV if info is available
	NewImage/K=1/F/S=0 imgNew
	Modifyimage $NameOfWave(imgNew) ctab={varMIN,varMAX,$colourscaleName,invert}
	
	// If meta info on FOV exists, add this to the image as well
	If (NVAR_EXISTS(detSize) && NVAR_EXISTS(mag))
		string FOVstr, currentPanel
		sprintf FOVstr, "FOV: %s um", num2str(detSize/mag) 
		currentPanel = WinName(0,1)
		
		SetDrawLayer/W=$currentPanel Overlay; DelayUpdate
		SetDrawEnv/W=$currentPanel textrgb= (65535,49157,16385),fstyle= 1,xcoord=rel,ycoord=rel;DelayUpdate
		DrawText/W=$currentPanel 0.05, 0.96, FOVstr
	EndIf
	
	// 5: Finally, restore data folder to root
	SetDataFolder root:
	
End


//---------------------------------------------------------------------------

// Set up ROI side panel if ROI checkbox in Image panel is ticked AND numLayers > 1
Function ESCA_ROIpanel(DisplaySettings,checked) : CheckBoxControl
	string DisplaySettings
	variable checked
	variable disp
	
	// Obtain relevant global variable and wave references
	String panelName = WinName(0,64)
	String SPPath = ESCA_getSubPanelPath()
	String imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	String DF = GetWavesDataFolder(img,1)
	Nvar activeCursor = $(DF + "activate_cursor")
	Nvar csrx = $(DF+"csrx")
	Nvar csry = $(DF+"csry")
	Nvar radius = $(DF+"ROIRadius")
	Wave cursors = $(DF+"cursors")
	Wave color = $(DF+"rgbColor")
	
	// Extract colors to be used for cursor
	Variable red, green, blue
	red = color[0]
	green = color[1]
	blue = color[2]
	
	// Define subpanel name
	String parentWindowName = WinName(0,64)
	String ROIPanelName = "ROI_controls"
	String ROIpanelPath = parentWindowName + "#" + ROIPanelName
	
	// Allocate ROI wave references
	Wave ovalx = $(DF+"ovalx")
	Wave ovaly = $(DF+"ovaly")
	Wave ROImask = $(DF+"ROImask")
	Wave horizTopX = $(DF+"horizTopX")
	Wave horizTopY = $(DF+"horizTopY")
	Wave horizBottomX = $(DF+"horizBottomX")
	Wave horizBottomY = $(DF+"horizBottomY")
	
	// If checked: generate additional ROI subwindow
	If (checked == 1)
	
		// (1) Define subwindow
		NewPanel/K=2/W=(0,0,175,120)/N=$ROIPanelName/HOST=$parentWindowName/EXT=0
		ModifyPanel/W=$ROIPanelName fixedSize=0
		SetDrawLayer UserBack
		DrawRect 5,5,170,115
	
		// (2) Set up button controls
		CheckBox ActivateCircROI,pos={24.00,9.00},size={63.00,12.00},title="Circular "
		CheckBox ActivateCircROI,fStyle=1,value= 0,side= 1,proc=ESCA_ROItype
		CheckBox activateHorizROI,pos={94.00,9.00},size={55.00,16.00},title="Linear "
		CheckBox activateHorizROI,fStyle=1,value= 0,side= 1,proc=ESCA_ROItype
		SetVariable ROIwidth,pos={30,30},size={120.00,25},bodyWidth=50,title="Radius/Width"
		SetVariable ROIwidth fstyle=1,variable=radius
		Button calcCircCut,pos={10,55},size={75.00,50},title="Integrate\nROI through\nstack"
		Button calcCircCut,fStyle=1,fSize=10,fColor=(43690,43690,43690),proc=ESCA_ROICut
		Button CalcHorizCut,pos={90.00,55.00},size={75.00,50.00},title="Calculate\nlinear ROI"
		Button CalcHorizCut,fSize=10,fColor=(43690,43690,43690),fStyle=1,proc=ESCA_ROICut
		SetActiveSubwindow ##
	
		// (3) activate and display cursor
		activeCursor = 1
		csrx = cursors[0]	
		csry = cursors[1]
		Cursor /W=$SPPath/H=1/S=2/c=(red,green,blue)/P/I G $(nameOfWave(img)) csrx,csry
		SetWindow $panelName hook(myHook)=imgPanel_CursorMovedHook // Install hook function
	
		// (4) allocate ROI waves
		Make/D/O/N=(4000) $(DF+"ovalx") = 0, $(DF+"ovaly") = 0
		Make/O/D/N=(2) $(DF+"horizTopX") = {-INF,INF}, $(DF+"horizTopY") = 0
		Make/O/D/N=(2) $(DF+"horizBottomX") = {-INF,INF}, $(DF+"horizBottomY") = 0
			
	Else // Unchecked: Kill ROI control window
	
		activeCursor = 0
		Cursor/W=$SPPath/K G
		RemoveFromGraph/w=$SPPath/Z ovalx, ovaly, horizTopX, horizTopY, horizBottomX, horizBottomY
		ovalx = 0				// Release dependcy function
		ovaly = 0				// Release dependcy function
		horizTopX = 0		// Release dependcy function
		horizTopY = 0		// Release dependcy function
		horizBottomX = 0		// Release dependcy function
		horizBottomY = 0		// Release dependcy function
		Killwaves/Z ovalx, ovaly, ROImask, horizTopX, horizTopY, horizBottomX, horizBottomY
		KillWindow/Z $ROIpanelPath
		
	EndIf

End

//---------------------------------------------------------------------------

// Hook function that responds to cursor movement on the energy surface subpanel,
// and updates the position of the ROI accordingly
Function imgPanel_CursorMovedHook(s)
	STRUCT WMWinHookStruct &s
	Variable statusCode= 0
	
	// Global variables
	String SPPath = ESCA_getSubPanelPath()
	String imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	String DF = GetWavesDataFolder(img,1)
	Wave cursors = $(DF+"cursors")
	Nvar activeCursor = $(DF + "activate_cursor")
	
	// (1) See if the right subwindow is active in the panel
	GetWindow $s.winName activeSW
	String activeSubwindow = S_value
	
	If (CmpStr(activeSubwindow,SPPath) != 0)
		return 0
	EndIf
	
	// (2) IF activity in the right subwindow, check if the cursor has moved.
	// 	 Update the variables csrx and csry accordingly
	StrSwitch( s.eventName )
		Case "cursormoved":													
			// update cursor values
			// (this will trigger the ROI to be redrawn)
			If(activeCursor)
				Nvar pPos = $(DF+"csrx")
				Nvar qPos = $(DF+"csry")
				cursors[0] = pcsr(G,SPPath)
				cursors[1] = qcsr(G,SPPath)
				pPos = cursors[0]
				qPos = cursors[1]
			EndIf
			
			Break
	EndSwitch

	return statusCode
End


//---------------------------------------------------------------------------

// Activates the ROI cursor from the checkboxes in the ROI control panel
Function ESCA_ROItype(DisplaySettings,checked) : CheckBoxControl
	string DisplaySettings
	variable checked
	variable disp
	
	// (1) Obtain relevant global variable and wave references
	String panelName = WinName(0,64)
	String SPPath = ESCA_getSubPanelPath()
	String imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	String DF = GetWavesDataFolder(img,1)
	Nvar activeCursor = $(DF + "activate_cursor")
	Nvar csrx = $(DF+"csrgx")
	Nvar csry = $(DF+"csrgy")
	Wave cursors = $(DF+"cursors")
	Wave color = $(DF+"rgbColor")
	
	// Extract colors to be used on cursor
	Variable red, green, blue
	red = color[0]
	green = color[1]
	blue = color[2]
	
	StrSwitch(DisplaySettings)	
		Case "ActivateCircROI":	
		
		Wave ovalx = $(DF+"ovalx")
		Wave ovaly = $(DF+"ovaly")
		
			If(checked)
				ESCA_CalcCircle(DF)
				Appendtograph/w=$SPPath/C=(red,green,blue) ovaly vs ovalx							
			Else
				RemoveFromGraph/w=$SPPath/Z ovalx, ovaly	
			EndIf
		
		Break
		
		Case "activateHorizROI":
		
		Wave horizTopX = $(DF+"horizTopX")
		Wave horizTopY =$(DF+"horizTopY")
		Wave horizBottomX = $(DF+"horizBottomX")
		Wave horizBottomY = $(DF+"horizBottomY")
		
		
			If(checked)
				ESCA_CalcLines(DF)
				Appendtograph/w=$SPPath/C=(red,green,blue) horizTopY vs horizTopX
				Appendtograph/w=$SPPath/C=(red,green,blue) horizBottomY vs horizBottomX								
			Else
				RemoveFromGraph/w=$SPPath/Z horizTopX, horizTopY, horizBottomX, horizBottomY
			EndIf
		
		Break	
			
		Default:			
		Break		
	EndSwitch
		
End	

//---------------------------------------------------------------------------

//Set up dependency formula so that ovalx and ovaly are updated if any of the 
// numbers in it are changed, e.g csrx/y or ovalradius
Function ESCA_CalcCircle(DF)
	String DF
	
	DFREF dfSav = GetDataFolderDFR()		// current data folder
	SetDatafolder $DF
	
	// Set up dependencies for waves ovalx and ovaly
	string cmd1 = "ovalx := ROIRadius*cos(p*2*pi/dimsize(ovalx, 0))+csrx"
	string cmd2 = "ovaly := ROIRadius*sin(p*2*pi/dimsize(ovaly, 0))+csry"
	Execute cmd1
	Execute cmd2
	
	SetDataFolder dfSav

End

//---------------------------------------------------------------------------

//Set up dependency formula so that ovalx and ovaly are updated if any of the 
// numbers in it are changed, e.g csrx/y or ovalradius
Function ESCA_CalcLines(DF)
	String DF
	
	DFREF dfSav = GetDataFolderDFR()		// current data folder
	SetDatafolder $DF
	
	// Set up dependencies for waves ovalx and ovaly
	String cmd1 = "horizTopY := csry+ROIRadius"
	String cmd2 = "horizBottomY := csry-ROIRadius"
	
	Execute cmd1
	Execute cmd2
	
	SetDataFolder dfSav

End

//---------------------------------------------------------------------------

// Calculates the dispersive cut within the ROI specified using the cursor
Function ESCA_ROICut(ctrlName):ButtonControl
	string ctrlName
	
	// Allocate reference to relevant global variables
	String panelName = WinName(0,64)
	String SPPath = ESCA_getSubPanelPath()
	String imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	String DF = GetWavesDataFolder(img,1)
	Wave ox = $(DF+"ovalx")
	Wave oy = $(DF+"ovaly")
	Nvar pDim = $(DF+"np")
	Nvar qDim = $(DF+"nq")
	Nvar lDim = $(DF+"numLayers")
	Nvar csrx = $(DF+"csrx")
	Nvar csry = $(DF+"csry")
	Nvar ROIRadius = $(DF+"ROIRadius")
	
	Strswitch(ctrlname)	// string switch
		Case "calcCircCut":
			
			// (1) Allocate names of new waves 
			String ROImaskName = DF + "ROImask"
			String layerCutWaveName = DF + "ROI_layerCut"
	
			// (2) Check that circular ROI has been specified
			If ( (waveexists(ox)) && (waveexists(oy)) )
	
				// (i) Generate ROI mask
				ImageBoundaryToMask ywave=oy, xwave=ox, height=qDim, width=pDim, scalingwave=$imgName, seedx=csrx+1, seedy=csry+1
				Wave ROI = M_ROIMask
				Duplicate/O ROI, $ROImaskName
		
				// (ii) Allocate dispersive cut wave
				Make/O/D/N=(lDim) $layerCutWaveName
				Wave layerCut = $layerCutWaveName
		
				// (iii) Loop through all layers of the stack wave
				Make/O/D/N=(pDim,qDim) temp2DWave
				Variable ii
				For(ii=0;ii<lDim;ii++)
		
					// For each layer of the image, set everything outside ROI
					// to zero and store the ROI selected in "temp2Dwave"
					temp2Dwave = img[p][q][ii]*ROI[p][q]
		
					Integrate/T/DIM=0 temp2Dwave /D=temp2Dwave //integrate over rows
					Integrate/T/DIM=1 temp2Dwave /D=temp2Dwave //integrate over cols
		
					layerCut[ii] = waveMax(temp2Dwave)
		
				EndFor	// Looping through all layers
		
			EndIf		// If circular ROI is defined
			
			// (3) Display the dispersive cut in an exterior subpanel
			ESCA_displayCut(panelName,layerCutWaveName,DF)
	
			// (4) Finally, kill temporary waves
			KillWaves/Z M_ROIMask, temp2DWave
	
			Break		// Exit from switch
			
		Case "calcHorizCut":
			
			If(lDim != 0)
			
				Abort "Horizontal cuts only work for two-dimensional waves!"
			
			Else
			
				// (1) Define destination wave
				String horizCutWaveName = DF + "ROI_horizCut"
				Make/D/O/N=(pDim) $horizCutWaveName
				Wave horizCut = $horizCutWaveName
				
				// (2) Define cut region
				Variable xMin = DimOffset(img,0)
				Variable xMax = DimOffset(img,0) + pDim*DimDelta(img,0)	
				Make/O/N=(2) xTrace = {xMin,xMax}
				Make/O/N=(2) yTrace = {csry,csry}
			
				// (3) Perform horizontal cut and display
				ImageLineProfile srcWave=img, xWave=xTrace, yWave=yTrace, width=ROIRadius
				Wave W_ImageLineProfile
				horizCut = W_ImageLineProfile
				ESCA_displayCut(panelName,horizCutWaveName,DF)
			
				// (4) Finally, kill temporary waves
				KillWaves/Z xTrace, yTrace, W_ImageLineProfile, W_LineProfileX, W_LineProfileY
			
			EndIf
			
			Break
		Default:			// optional default expression executed
			Break		// when no case matches
	Endswitch
	
End	

//---------------------------------------------------------------------------

// Displays ROI cut(s) in subpanel below the parent image panel
Function ESCA_displayCut(parentWindowName,cutFullPath,DF)
	String parentWindowName,cutFullPath, DF
	
	// Obtain references to relevant global variables
	Wave cut = $cutFullPath				// Wave reference to dispersive cut
	Wave energyAxis = $(DF+"KE_Sum")		// Energy axis values, if any
	Nvar lDim = $(DF+"numLayers")			// No. layer for the img wave samples from
	
	// Generate subpanel
	String cutPanelName = "ROI_cut"
	String cutPanelPath = parentWindowName + "#" + cutPanelName
	NewPanel/K=1/W=(0,0,290,150)/N=$cutPanelName/HOST=$parentWindowName/EXT=2
	ModifyPanel/W=$cutPanelName fixedSize=0
	Display/W=(10,10,280,140)/HOST=#
	RenameWindow #,cutGraph
	String dispCutGraphFullPath = cutPanelPath + "#cutGraph"
	
	// Display cut graph
	AppendToGraph/W=$dispCutGraphFullPath cut
	
	// Determine if the ROI cut wave is a "layer cut" or
	// a "horizontal" cut. laber axes accordingly 
	If(lDim == 0)
	
		Label/W=$dispCutGraphFullPath left "Intensity"
	
	ElseIf(lDim > 0)
	
		// If an energy axis wave exists in the folder,
		// then scale dispCut to have this as the x axis
		If(waveexists(energyAxis))
			variable cutDim = DimSize(cut,0)
			SetScale/I x, energyAxis[0], energyAxis[cutDim-1], cut
		EndIf

		Label/W=$dispCutGraphFullPath left "Intensity"
		Label/W=$dispCutGraphFullPath bottom "E-EF [eV]"
		
	EndIf	

End

//---------------------------------------------------------------------------

// Kills NanoESCA image panel, restores data folder to root
Function ESCA_killImgPanel(ctrlName):ButtonControl
	string ctrlName
	
	// Obtain relevant global variable and wave info
	string SPPath = ESCA_getSubPanelPath()
	string imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	String DF = GetWavesDataFolder(img,1)
	Wave cursors = $(DF+"cursors")
	Wave color = $(DF+"rgbColor")
	
	// Extract name of panel, kill
	String winStr=WinName(0,64)
	DoWindow/k $winStr
	
	// Kill supporting waves from subfolder
	KillWaves/Z cursors, color 
	
	SetDataFolder root:					// Set path to root folder
	
End

//---------------------------------------------------------------------------
