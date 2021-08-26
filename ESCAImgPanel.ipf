#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

// Written by: Håkon I. Røst, NTNU
// hakon.i.rost@ntnu.no

// v.1 July 2020: first incarnation, with image editing buttons
// V.2 August 2020: Added slider to image panel, IFF user selects a stack instead of single image
// V.3 April 2021: Display calibrated FOV in image panel with proper unit
// V.4 June 2021: Added functionality for re-defining ARPES px center position using cursor in ROI panel
// V.5 August 2021: Functions for rotating around the center px and also "rotational averaging" added to ROI panel

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
	ESCA_DispImage(waveFullPath)			// Display image
	ESCA_ImgCtrlSetup(waveFullPath)		// Link controls to global variables in parent folder
	ESCA_ImgSliderSetup()						// Update sliders to match image contrast extremes
	
EndMacro

//---------------------------------------------------------------------------

Function ESCA_DispImage(waveFullPath)
	String waveFullPath
	
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
Function ESCA_ImgCtrlSetup(waveFullPath)
	String waveFullPath
	
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
	
	If (numLayers > 1)
		Duplicate/O/RMD=[][][currLayer] img, $procImgName
	Else
		Duplicate/O img, $procImgName
	EndIf
	
	Wave imgNew = $procImgName
	
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
		NewPanel/K=2/W=(0,0,175,280)/N=$ROIPanelName/HOST=$parentWindowName/EXT=0
		ModifyPanel/W=$ROIPanelName fixedSize=0
		SetDrawLayer UserBack
		//DrawRect 5,5,170,170
		DrawRect 5,5,170,275
	
		// (2) Set up button controls
		CheckBox ActivateCircROI,pos={24.00,9.00},size={63.00,12.00},title="Circular "
		CheckBox ActivateCircROI,fStyle=1,value= 0,side= 1,proc=ESCA_ROItype
		CheckBox activateHorizROI,pos={94.00,9.00},size={55.00,16.00},title="Linear "
		CheckBox activateHorizROI,fStyle=1,value= 0,side= 1,proc=ESCA_ROItype
		SetVariable ROIwidth,pos={30,30},size={120.00,25},bodyWidth=50,title="Radius/Width"
		SetVariable ROIwidth fstyle=1,variable=radius
		Button calcCircCut,pos={10,55},size={75.00,50},title="Integrate\nROI through\nstack"
		Button calcCircCut,fStyle=1,fSize=10,fColor=(43690,43690,43690),proc=ESCA_ROICut
		Button CalcHorizCut,pos={90.00,55.00},size={75.00,50.00},title="Calculate\nlinear cut"
		Button CalcHorizCut,fSize=10,fColor=(43690,43690,43690),fStyle=1,proc=ESCA_ROICut
		Button RedefineCenter, pos={10.00,110.00},size={155,50.00}
		Button RedefineCenter, title="Redefine center of image\nbased on cursor position"
		Button RedefineCenter,fSize=10,fColor=(43690,43690,43690),fStyle=1,proc=ESCA_defineCenter
		Button Rotation, pos={10.00,165.00},size={155,50.00}
		Button Rotation, title="Rotate around center px"
		Button Rotation,fSize=10,fColor=(43690,43690,43690),fStyle=1,proc=ESCA_Rotation
		Button Symmetrize, pos={10.00,220.00},size={155,50.00}
		Button Symmetrize, title="Perform rotational averaging"
		Button Symmetrize,fSize=10,fColor=(43690,43690,43690),fStyle=1,proc=ESCA_symmRotation
		SetActiveSubwindow ##
	
		// (3) activate and display cursor
		activeCursor = 1
		csrx = cursors[0]	
		csry = cursors[1]
		Cursor /W=$SPPath/H=1/S=2/c=(red,green,blue)/P/I G $(nameOfWave(img)) csrx,csry
		SetWindow $panelName hook(myHook)=imgPanel_CursorMovedHook // Install hook function
		ShowInfo/W=$panelName/CP=3
	
		// (4) allocate ROI waves
		Make/D/O/N=(4000) $(DF+"ovalx") = 0, $(DF+"ovaly") = 0
		Make/O/D/N=(2) $(DF+"horizTopX") = {-INF,INF}, $(DF+"horizTopY") = 0
		Make/O/D/N=(2) $(DF+"horizBottomX") = {-INF,INF}, $(DF+"horizBottomY") = 0
			
	Else // Unchecked: Kill ROI control window
	
		activeCursor = 0
		HideInfo/W=$panelName
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

// When ROI panel is active:
// 1. Takes the current position of the cursor G displayed on the image
// 2. Forms a duplicate wave with the cursor pos. used as the center px of each layer
// 3. Optional: Re-displays the updated/re-centered image in a new image panel
Function ESCA_defineCenter(ctrlName):ButtonControl
	string ctrlName

	// (i) Allocate reference to relevant global variables
	String panelName = WinName(0,64)
	String SPPath = ESCA_getSubPanelPath()
	String imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	String DF = GetWavesDataFolder(img,1)
	Nvar varMax = $(DF+"varMax")
	
	// (ii) Obtain cursor position defining ARPES center
	Variable pG = pcsr(G,SPPath)
	Variable qG = qcsr(G,SPPath)
	
	// (iii) Obtain dimensions for the ARPES wave in question
	Variable dimP = dimsize(img, 0)
	Variable dimQ = dimsize(img, 1)
	Variable dimR = dimsize(img, 2)

	// (iv) Determine offset between cursors position and image center
	Variable dP = round(pG - dimP/2 + 1) // +1 corrects for zero indexing
	Variable dQ = round(qG - dimQ/2 + 1) // +1 corrects for zero indexing
	Printf "New center is shifted by dx=%d and dy=%d \n", dP, dQ
	
	// (v) Re-center wave, obtain reference to the (new) corrected one
	Wave newImg = ESCA_newCenterPos(img,dimP,dimQ,dimR,dP,dQ)
	
	// (vi) If user clicks "Yes": kill existing img panel and display new wave in new img panel
	DoAlert 1, "Would you like to kill the current image and display\nthe image (stack) with the corrected center?"
	If(V_flag == 1)
				
		ESCA_ROIpanel("activateROIpanel",0)
		Removeimage/W=$SPPath $imgName
		AppendImage/W=$SPPath newImg
		ESCA_ROIpanel("activateROIpanel",1)
		ESCA_imgContrast("ContrastMax", varMax,0)
				
	EndIf	
	
End

//---------------------------------------------------------------------------

// This function takes in a 2D or 3D wave, its dimensions and the offset between
// the current image center and the "true" px position of the image center.
// A new wave is defined, with its center is set to match the corrected center pos.
// The corrected wave is returned as a reference.
Function/WAVE ESCA_newCenterPos(imgWave,dimP,dimQ,dimR,dP,dQ)
	Wave imgWave					// Wave to redefine center position for
	Variable dimP, dimQ, dimR	// Dimensionts of input wave
	Variable dP, dQ					// offset between current and true image center

	// (i) Allocate new wave (to be centered)
	String DF = GetWavesDataFolder(imgWave,1)
	String centeredWaveName = 	DF + NameOfWave(imgWave) + "_center"
	Duplicate/O/D imgWave, $centeredWaveName
	Wave centeredWave = $centeredWaveName
	
	Variable BckgIntensity = (imgWave[0][0]+imgWave[0][dimQ-1]+imgWave[dimP-1][0]+imgWave[dimP-1][dimQ-1]) / 4
	centeredwave = BckgIntensity
	
	// (ii) Define cursor position as wave center in p,q for all layers of the wave
	If((dimP > 0) && (dimQ > 0) && (dimR == 0))	// 2D wave input

		If((dP >= 0) && (dQ >= 0))			// Center in Q1
			centeredWave[0,(dimP-1)-dP][0,(dimQ-1)-dQ] = imgWave[p+dP][q+dQ]
		ElseIf((dP <= 0) && (dQ >= 0)) 	// Center in Q2
			centeredWave[-dP,dimP-1][0,(dimQ-1)-dQ] = imgWave[p+dP][q+dQ]
		ElseIf((dP <= 0) && (dQ <= 0)) 	// Center in Q3
			centeredWave[-dP,dimP-1][-dQ,dimQ-1] = imgWave[p+dP][q+dQ]
		ElseIf((dP >= 0) && (dQ <= 0)) 	// Center in Q4
			centeredWave[0,(dimP-1)-dP][-dQ,dimQ-1] = imgWave[p+dP][q+dQ]
		EndIf
		
	ElseIf((dimP > 0) && (dimQ > 0) && (dimR > 0))		// 3D wave input
	
		If((dP >= 0) && (dQ >= 0))			// Center in Q1
			centeredWave[0,(dimP-1)-dP][0,(dimQ-1)-dQ][] = imgWave[p+dP][q+dQ][r]
		ElseIf((dP <= 0) && (dQ >= 0)) 	// Center in Q2
			centeredWave[-dP,dimP-1][0,(dimQ-1)-dQ] = imgWave[p+dP][q+dQ][r]
		ElseIf((dP <= 0) && (dQ <= 0)) 	// Center in Q3
			centeredWave[-dP,dimP-1][-dQ,dimQ-1] = imgWave[p+dP][q+dQ][r]
		ElseIf((dP >= 0) && (dQ <= 0)) 	// Center in Q4
			centeredWave[0,(dimP-1)-dP][-dQ,dimQ-1] = imgWave[p+dP][q+dQ][r]
		EndIf
	
	Else
			
		Abort "Dimensionality of the experimental ARPES wave supplied is not 2D or 3D."
	
	EndIf

	Return centeredWave

End

//---------------------------------------------------------------------------

// Take input wave and rotate by degrees N around the center position in the 
// (p,q) plane of the image (stack).
Function ESCA_Rotation(ctrlName):ButtonControl
	String ctrlName
	
	// (i) Check with user that the current image has a correct centering
	String alertStr = "NOTE: you are now rotating the image in the panel around the\n"
	alertStr += "current pixel center position (p,q) in the image subwindow.\n\n"
	alertStr += "YES = continue; NO and Cancel = abort."
	
	DoAlert/T="Is the image centered?" 2, alertStr
	
	If((V_flag == 2) || (V_flag == 3))
		Return -1		// User aborted
	EndIf
	
	// (ii) Allocate relevant references to global variables and related info
	String panelName = WinName(0,64)
	String SPPath = ESCA_getSubPanelPath()
	String imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	
	String DF = GetWavesDataFolder(img,1)
	Nvar varMax = $(DF+"varMax")
	Variable dimP = dimsize(img, 0)
	Variable dimQ = dimsize(img, 1)
	Variable dimR = dimsize(img, 2)
	
	// (iii) Allow user to specify the rotational symmetry degree N and a name for the new wave
	Variable degr
	String newWaveName
	
	Prompt degr, "Specify the number of degrees you wish to rotate around the origin\n(rotation is clockwise in the display):"
	Prompt newWaveName, "Specify the name of the new output wave"
	DoPrompt "Specify rotation and new wave name", degr, newWaveName
	
	String rotImgName = DF + newWaveName
	
	// (iv) Perform rotation averaging of image displayed
	If((dimP > 0) && (dimQ > 0) && (dimR == 0))		// 2D wave input
		
		// (a) make a local copy of "img" and center it:
		Duplicate/O img, img_center
		SetScale/I x -(dimP-1)/2, (dimP-1)/2, img_center
		SetScale/I y -(dimQ-1)/2, (dimQ-1)/2, img_center
		
		// (b) Rotate the image by the number of degrees specified by the user
		Wave tempImg = ESCA_Rotate2D(img_center,degr)
		
		// (c) Store the rotated wave generated in the same folder as "img",
		//		 under the name specified by the user
		Duplicate/O img_center, $rotImgName
		Wave rotWave = $rotImgName
		rotWave = tempImg(x)(y)
		
		// (d) Kill temporary waves
		KillWaves/Z tempImg, img_center
	
	ElseIf((dimP > 0) && (dimQ > 0) && (dimR > 0))	// 3D wave input
	
		// (a) Duplicate the input wave
		Duplicate/O img, $rotImgName
		Wave rotWave = $rotImgName
	
		// Extract each layer of the stack, rotate it and put it back into the stack
		Variable jj
		For (jj=0;jj<dimR;jj++)
		
			// (a) make a local copy of img[][][jj] and center it:
			Make/D/O/N=(dimP,dimQ) currLayer
			currLayer = img[p][q][jj]
			SetScale/I x -(dimP-1)/2, (dimP-1)/2, currLayer
			SetScale/I y -(dimQ-1)/2, (dimQ-1)/2, currLayer
			
			// (b) Rotate the image N times and add each rotation together
			Wave img_rot = ESCA_Rotate2D(currLayer,degr)
			
			// (c) Copy the rotated wave into currLayer for the relevant (centered) x,y range
			currLayer = img_rot(x)(y)
			
			// (d) Store current rotated image in layer jj of the new image stack, kill temporary waves
			ImageTransform/P=(jj)/PTYP=0/D=currLayer setPlane rotWave
			Printf "\nLayer %d out of %d has been rotated by %f degrees", (jj+1), dimR, degr
			KillWaves/Z currLayer, img_rot
		
		EndFor
			
	Else
	
		Abort "Dimensionality of the experimental ARPES wave supplied is not 2D or 3D."
	
	EndIf
	
	// (v) Reset the x and y axes of rotWave
	SetScale/I x 0, (dimP-1), rotWave
	SetScale/I y 0, (dimQ-1), rotWave
	
	// (vi) Signify success to the user
	String finalDestination = DF + NameOfWave(rotWave)
	Printf "\nSuccess! The rotated wave has been storen in %s\n", finalDestination
	
	// (vii) If user clicks "Yes": kill existing img panel and display new wave in new img panel
	DoAlert 1, "Would you like to kill the current image and display\nthe rotated image (stack) instead?"
	If(V_flag == 1)
				
		ESCA_ROIpanel("activateROIpanel",0)
		Removeimage/W=$SPPath $imgName
		AppendImage/W=$SPPath rotWave
		ESCA_ROIpanel("activateROIpanel",1)
		ESCA_imgContrast("ContrastMax", varMax,0)
				
	EndIf	

End

//---------------------------------------------------------------------------

// Take input wave and correct for directionally dependent intensity variations 
// by performing an N-fold rotation and adding together each symmetric rotation
// of the image.
Function ESCA_symmRotation(ctrlName):ButtonControl
	String ctrlName
	
	// (i) Check with user that the current image has a correct centering
	String alertStr = "NOTE: you are now rotating the image in the panel around the\n"
	alertStr += "current pixel center position (p,q) in the image subwindow.\n\n"
	alertStr += "YES = continue; NO and Cancel = abort."
	
	DoAlert/T="Is the image centered?" 2, alertStr
	
	If((V_flag == 2) || (V_flag == 3))
		Return -1		// User aborted
	EndIf
	
	// (ii) Allocate relevant references to global variables and related info
	String panelName = WinName(0,64)
	String SPPath = ESCA_getSubPanelPath()
	String imgName = ESCA_topWaveDisplayed()
	Wave img = ImageNameToWaveRef(SPPath,imgName)
	
	String DF = GetWavesDataFolder(img,1)
	Variable dimP = dimsize(img, 0)
	Variable dimQ = dimsize(img, 1)
	Variable dimR = dimsize(img, 2)
	
	// (iii) Allow user to specify the rotational symmetry degree N and a name for the new wave
	Variable degN
	String newWaveName
	
	Prompt degN, "Specify the rotational symmetry around the origin: ", popup, "1;2;3;4;6"
	Prompt newWaveName, "Specify the name of the new output wave"
	DoPrompt "Specify symmetry and new wave name", degN, newWaveName
	
	String symmImgName = DF + newWaveName

	If(degN == 5)		// entry #5 on the list was chosen
		degN +=1
	EndIf
	
	// (iv) Perform rotation averaging of image displayed
	If((dimP > 0) && (dimQ > 0) && (dimR == 0))		// 2D wave input
		
		// (a) make a local copy of "img" and center it:
		Duplicate/O img, img_center
		SetScale/I x -(dimP-1)/2, (dimP-1)/2, img_center
		SetScale/I y -(dimQ-1)/2, (dimQ-1)/2, img_center
		
		// (b) Rotate the image N times and add each rotation together
		Wave img_rot = ESCA_symmetrize(img_center,degN)
		
		// (c) Store the symmetrized wave generated in the same folder as "img",
		//		 under the name specified by the user
		Duplicate/O img_rot, $symmImgName
		Wave symmRotWave = $symmImgName
		KillWaves/Z img_rot, img_center
	
	ElseIf((dimP > 0) && (dimQ > 0) && (dimR > 0))	// 3D wave input
	
		// (a) Duplicate the input wave
		Duplicate/O img, $symmImgName
		Wave symmRotWave = $symmImgName
	
		// Extract each layer of the stack, rotate it and put it back into the stack
		Variable jj
		For (jj=0;jj<dimR;jj++)
		
			// (a) make a local copy of img[][][jj] and center it:
			Make/D/O/N=(dimP,dimQ) currLayer
			currLayer = img[p][q][jj]
			SetScale/I x -(dimP-1)/2, (dimP-1)/2, currLayer
			SetScale/I y -(dimQ-1)/2, (dimQ-1)/2, currLayer
			
			// (b) Rotate the image N times and add each rotation together
			Wave img_rot = ESCA_symmetrize(currLayer,degN)
			
			// (c) Store current rotated image in layer jj of the new image stack
			ImageTransform/P=(jj)/PTYP=0/D=img_rot setPlane symmRotWave
			Printf "\nLayer %d out of %d has been symmetrized", (jj+1), dimR	
			KillWaves/Z currLayer, img_rot
		
		EndFor
	
	Else
	
		Abort "Dimensionality of the experimental ARPES wave supplied is not 2D or 3D."
	
	EndIf
	
	// (v) Signify success to the user
	String finalDestination = DF + NameOfWave(symmRotWave)
	Printf "\nSuccess! The rotationally averaged (symmetrized) wave has been storen in %s\n", finalDestination

End

//---------------------------------------------------------------------------

Function/Wave ESCA_symmetrize(img2D,degN)
	Wave img2D		// input 2D image
	Variable degN	// N fold rotational symmetry degree
	
	// (i) obtain relevant dimensions for the image to be rotated
	Duplicate/O img2D, img2D_rot
	Variable dimP = DimSize (img2D,0)
	Variable dimQ = DimSize (img2D,1)
	SetScale/I x -(dimP-1)/2, (dimP-1)/2, img2D_rot
	SetScale/I y -(dimQ-1)/2, (dimQ-1)/2, img2D_rot
	Img2D_rot = 0								// start with an empty wave
	
	Variable anglePerRot = 360/degN		// (360 degrees)/(No. rotations)
	
	Variable ii
	For(ii=0;ii<degN;ii++)
		Wave tempImg = ESCA_Rotate2D(img2D,ii*anglePerRot)
		Img2D_rot += tempImg(x)(y)
	EndFor
	
	KillWaves/Z tempImg
	Return img2D_rot
				
End


//---------------------------------------------------------------------------

Function/Wave ESCA_Rotate2D(w,angle)
	Wave w
	Variable angle
	
	// ===================================================================================
	// (1) Obtain new x and y scale after rotation
	// ===================================================================================
	
	// (i) Define rotation matrix
	Make/O/N=(2,2) RotMatrix
	RotMatrix[0][0] = cos(angle*pi/180)
	RotMatrix[0][1] = - sin(angle*pi/180)
	RotMatrix[1][0] = sin(angle*pi/180)
	RotMatrix[1][1] = cos(angle*pi/180)
	
	// (ii) Define corners
	Variable kx_max = Max(DimOffset(w,0)+DimDelta(w,0)*(DimSize(w,0)-1),DimOffset(w,0))
	Variable kx_min = Min(DimOffset(w,0)+DimDelta(w,0)*(DimSize(w,0)-1),DimOffset(w,0))
	Variable ky_max = Max(DimOffset(w,1)+DimDelta(w,1)*(DimSize(w,1)-1),DimOffset(w,1))
	Variable ky_min = Min(DimOffset(w,1)+DimDelta(w,1)*(DimSize(w,1)-1),DimOffset(w,1))
	Make/O/N=(2) C1, C2, C3, C4
	C1 = {kx_max,ky_max}	// Q1
	C2 = {kx_min,ky_max}	// Q2
	C3 = {kx_min,ky_min}	// Q3
	C4 = {kx_max,ky_min}	// Q4
	
	// (iii) Rotate the current range, figure out the new max and min kx and ky values achieved
	MatrixOP/O C1_rot = RotMatrix x C1
	MatrixOP/O C2_rot = RotMatrix x C2
	MatrixOP/O C3_rot = RotMatrix x C3
	MatrixOP/O C4_rot = RotMatrix x C4
	Variable new_kx_max = Max(C1_rot[0],C2_rot[0],C3_rot[0],C4_rot[0])
	Variable new_kx_min = Min(C1_rot[0],C2_rot[0],C3_rot[0],C4_rot[0])
	Variable new_ky_max = Max(C1_rot[1],C2_rot[1],C3_rot[1],C4_rot[1])
	Variable new_ky_min = Min(C1_rot[1],C2_rot[1],C3_rot[1],C4_rot[1])
	
	// (iV) Find the new step size in kx and ky
	Make/O/N=(2) kSteps_old
	kSteps_old[0] = DimDelta(w,0)
	kSteps_old[1] = DimDelta(w,1)
	MatrixOP/O kSteps_new = RotMatrix x kSteps_old
	
	// ===================================================================================
	// (2) Rotate the 2D wave around the origin
	// ===================================================================================
	
	// (i) Allocate rotated wave 
	Make/O/N=(Round(Abs((new_kx_max-new_kx_min)/kSteps_new[0])),Round(Abs((new_ky_max-new_ky_min)/kSteps_new[1]))) w_rot
	SetScale/I x, new_kx_min, new_kx_max, w_rot
	SetScale/I y, new_ky_min, new_ky_max, w_rot
	//SetScale/I x, new_kx_max, new_kx_min, w_rot
	//SetScale/I y, new_ky_max, new_ky_min, w_rot
	
	w_rot = interp2d(w,x*rotMatrix[0][0]+y*rotMatrix[0][1],x*rotMatrix[1][0]+y*rotMatrix[1][1])
	correctNaNs(w_rot)

	// (ii) Kill temporary waves
	KillWaves/Z rotMatrix, C1, C2, C3, C4, C1_rot, C2_rot, C3_rot, C4_rot, kSteps_old, kSteps_new
	
	Return w_rot
	
End

//---------------------------------------------------------------------------

// Loop runds over a 2D wave and changes all values of NaN to zeros
Function correctNaNs(w)
	Wave w

	Variable dimP = dimsize(w,0)
	Variable dimQ = dimsize(w,1)
	Variable ii, jj, value
	
	For(ii=0;ii<dimP;ii++)
		For(jj=0;jj<dimQ;jj++)
		
			value = w[ii][jj] 
		
			If(numtype(value) == 2)
				w[ii][jj] = 0
			EndIf
		
		EndFor
	EndFor
	
	Return 1
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
	Wave ovalx = $(DF+"ovalx")
	Wave ovaly = $(DF+"ovaly")
	Wave ROImask = $(DF+"ROImask")
	Wave horizTopX = $(DF+"horizTopX")
	Wave horizTopY = $(DF+"horizTopY")
	Wave horizBottomX = $(DF+"horizBottomX")
	Wave horizBottomY = $(DF+"horizBottomY")
	
	// Extract name of panel, kill
	String winStr=WinName(0,64)
	DoWindow/k $winStr
	
	// Kill supporting waves from subfolder
	KillWaves/Z cursors, color 
	Killwaves/Z ovalx, ovaly, ROImask, horizTopX, horizTopY, horizBottomX, horizBottomY
	
	SetDataFolder root:					// Set path to root folder
	
End

//---------------------------------------------------------------------------
