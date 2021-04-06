#pragma TextEncoding = "Windows-1252"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

// Written by: Håkon I. Røst, NTNU
// hakon.i.rost@ntnu.no

// v.1 Dec 2020: Basic functionality for allowing user to dynamically adjust fudge factor
// v.2 Jan 2021: Save mask functionality, proper allocation of temporary waves, code cleanup

// ===========================================================================================
// 										Initialize NanoESCA image panel
// ===========================================================================================
// Setup functions for NanoESCA CCD mask generation panel. Runs when "Generate CCD mask" 
// is selected from menu under "ESCAlab -> Background corrections"

// Initialize global variables, open NanoESCA CCD panel
Function Init_ESCACCDPanel()

	// Navigate to folder for global variables
	NewDataFolder/O/S root:Flatfields

	// Initialize global strings in folder
	String/g CCDPanelName = "CCDmaskPanel"
	String/g CCDImgSPName = "CCD_mask"
	String/g CCDMaskFullPath = CCDPanelName+"#"+CCDImgSPName
	String/g CCDtemplatePath		// Path reference to temporary CCD template
	String/g currImgName			// Name (reference) to image currently displayed in th panel
	
	// Initialize other global variables
	variable/g fudgeFactor = 0
	variable/g centerValue
	
	Execute "CCDmaskPanel()" // Fire up this baby
	SetDataFolder root: // reset current directory to root

End

// ===========================================================================================
// 							Panel macro, button controls and supporting functions
// ===========================================================================================

Window CCDmaskPanel() : Panel
	
	// Define subwindow geometry and labels
	PauseUpdate; Silent 1					// building window...
	NewPanel/K=1/W=(135,60,461,380)		// K=1 means you can cross out the window without any warnings
	SetDrawLayer UserBack
	SetDrawEnv fstyle= 1
	DrawText 262,27,"Threshold"
	
	// "Load" and "Save" buttons
	Button SaveMask,pos={135.00,10.00},size={120.00,20.00},title="Save CCD mask",proc=ESCA_saveCCDmask
	Button SaveMask,help={"Save the CCD mask currently displayed in the panel.\nBinary pixel values will be written: black = 0; White = 1."}
	Button SaveMask,fStyle=1,fColor=(39321,39321,39321)
	Button loadTemplate,pos={8.00,10.00},size={120.00,20.00},title="Load FF template",proc=ESCA_loadCCDtemplate
	Button loadTemplate,help={"Define MCP wave to be used for mask generation"}
	Button loadTemplate,fStyle=1,fColor=(39321,39321,39321)
	
	// "Fudge" factor slider
	Slider slider0,pos={301.00,77.00},size={10.00,234.00}
	Slider slider0,help={"Adjust slider to change threshold factor for CCD mask"}
	Slider slider0,limits={0,2,0},value= 0,side= 0, proc=ESCA_CCDthreshold
	
	// Display the fudge factor value selected using the slider
	ValDisplay ThresholdDisp,pos={289.00,41.00},size={30.00,23.00}
	ValDisplay ThresholdDisp,help={"Current intensity threshold set by user"}
	ValDisplay ThresholdDisp,fSize=12,fStyle=1,limits={0,0,0},barmisc={0,100}
	ValDisplay ThresholdDisp,value= #"0"
	
	// Subwindow displaying CCD mask with currently selected fudge factor
	Display/W=(10,40,280,310)/HOST=# 
	RenameWindow #,CCD_mask
	SetActiveSubwindow ##
	
EndMacro

//---------------------------------------------------------------------------

// Lets the user specify a "flatfield"/MCP image to be used as a template for
// constructing a "binary" mask of the CCD region. The MCP image the mask will
// be based on must exist in the root:Flatfields folder already.
// A "template" CCD mask is generated from a flatfield corrected copy of the
// user-selected MCP wave, and used as a reference wave for regenerating new
// CCD masks every time the uses adjusts the slider in the CCD mask panel
// (see funtion "ESCA_CCDthreshold()" below for the CCD mask generation itself).
Function ESCA_loadCCDtemplate(ctrlName):ButtonControl
	string ctrlName
	
	// Initially, define global variables
	Svar CCDMaskFullPath = root:Flatfields:CCDMaskFullPath
	Svar CCDtemplatePath = root:Flatfields:CCDtemplatePath
	Svar currImgName = root:Flatfields:currImgName
	Nvar centerValue = root:Flatfields:centerValue			
	
	// (1) Let User select the template waves and define the name of the new CCD mask 
	String DFwaveNames = AssembleAllWaveNames("root:Darkfields")
	String FFwaveNames = AssembleAllWaveNames("root:Flatfields")
	
	String FFWaveName, DFWaveName
	
	Prompt FFWaveName,"Select a template MCP wave\nfrom folder \"root:Flatfields\":", popup, FFwaveNames
	Prompt DFwaveName, "Select a darkfield (CCD) image to be subtracted from your image stack:", popup, DFwaveNames
	DoPrompt "Background normalization", FFWaveName, DFwaveName
	
	If( V_Flag )
		Return 0 // user canceled
	EndIf
	
	// (2) Allocate wave references
	DFwaveName = "root:Darkfields:" + DFwaveName		// Reference to the darkfield wave selected
	FFWaveName = "root:Flatfields:" + FFWaveName		// Reference to the MCP wave selected
	Wave DFwave = $DFwaveName
	Wave FFwave = $FFWaveName
	
	// (3) Duplicate selected MCP image,
	// 		Make additional CCD template wave (used for generating masks in later steps)
	CCDtemplatePath = "root:Flatfields:CCDtemplate"	// Define and store template wave ref. in global string
	Duplicate/O FFwave, $CCDtemplatePath				// Duplicate the MCP wave selected into the template ref.
	Wave CCDtemplate = $CCDtemplatePath					// Make proper Wave ref. to ease readability
	
	CCDtemplate *= 1.5						// Slightly upscale intensity before background corrections
	
	BckgCorr(CCDtemplate,DFwave,FFwave)			// Perform background corrections on MCP image
	
	Imagefilter/p=1/N=(4) avg, CCDtemplate		// Remove hot pixels using average filter
	Imagefilter/p=1/N=(4) median, CCDtemplate	// Remove hot pixels using median filter
	
	centerValue = CCDtemplate[512][512]			// Store the center px value of the filtered image
	
	// (4) Display the CCD template wave (allows user to inspect it before doing anything further)
	Wave oldCCDImg = $currImgName														// Name of old image from panel (if any)
	RemoveImage/Z/W=$CCDMaskFullPath $Nameofwave(oldCCDImg)						// Remove old image from panel (if any)
	AppendImage/W=$CCDMaskFullPath CCDtemplate										// Append the template CCD image
	ModifyGraph/W=$CCDMaskFullPath nticks(left)=0, standoff(left)=0			// Remove ticks from left axis
	ModifyGraph/W=$CCDMaskFullPath nticks(bottom)=0, standoff(bottom)=0		// Remove ticks from bottom axis
	ModifyGraph/W=$CCDMaskFullPath margin=-1										// Fit image to subwindow
		
	currImgName = CCDtemplatePath	// After plotting the new mask template, store the name of current image in viewer.
										// This will allow the user to change the flatfield wave used for templating by
										// removing a wave (if any) with its name matching <currImgName> before displaying
										// an updated template based on the new wave.
	
	Return 0						// Fumction end	
	
End	

//---------------------------------------------------------------------------

// Function is called whenever user adjusts the "threshold" slider in the panel.
// A copy of the CCD template wave is generated and every pixel is evaluated against
// a threshold set as the <slider value>*<center pixel intensity>. Every pixel with
// higher intensity than the threshold is set to 0, all pixels with intensity lower
// than the threshold are set to 1. The output/displayed wave is thus a binary wave
// of 0's and 1's that can be used to define ROIs in further background normalizations.
Function ESCA_CCDthreshold(name, value, event) : SetVariableControl
	String name			// name of this slider control
	Variable value		// value of slider
	Variable event		// bit field: bit 0: value set; 1: mouse down, //   2: mouse up, 3: mouse moved

	// Global variables, strings and waves
	Nvar centerPx = root:Flatfields:centerValue					// Intensity of center pixel
	Nvar fudge = root:Flatfields:fudgeFactor						// Threshold factor (matched with "value" of slider)
	Svar CCDMaskFullPath = root:Flatfields:CCDMaskFullPath 		// Ref. to the subpanel where the image is displayed
	Svar CCDtemplatePath = root:Flatfields:CCDtemplatePath		// Ref. to the CCD template made from the user selected MCP image
	Svar currImgName = root:Flatfields:currImgName				// Name of image displayed
	Wave CCDtemplate = $CCDtemplatePath								// Wave ref. to the template CCD image generated upon loading 
	Wave currImg = $currImgName										// Image wave currently displayed in the subpanel
	
	// Update the fudge factor to match the slider value
	fudge = value
	
	// Define a temporary wave to edit with the fudge factor
	String tempWavepath = "root:Flatfields:tempWave"
	Duplicate/O CCDtemplate, $tempWavepath
	Wave tempWave =  $tempWavepath
	
	// Set a threshold intensity from the center pixel (may need adjustment)
	Variable thresh = fudge*centerPx
	Imagethreshold/O/I/T=(thresh) tempWave
	tempWave /= 255
	
	RemoveImage/Z/W=$CCDMaskFullPath $Nameofwave(currImg)
	AppendImage/W=$CCDMaskFullPath tempWave
	ModifyGraph/W=$CCDMaskFullPath nticks(left)=0, standoff(left)=0			// Remove ticks from left axis
	ModifyGraph/W=$CCDMaskFullPath nticks(bottom)=0, standoff(bottom)=0		// Remove ticks from bottom axis
	ModifyGraph/W=$CCDMaskFullPath margin=-1											// Fit image to subwindow

	// Make display the current fucde factor applied in the value box (top right)
	ValDisplay ThresholdDisp, value=#num2Str(fudge)		// Update energy to match dataset

	// Finally, update the string specifying which wave is currently displayed
	currImgName = tempWavepath

	Return 0		// Function end

End

//---------------------------------------------------------------------------

// Saves an displays a copy of the currently displayd CCD mask in subfolder root:Flatfields:CCDmasks.
// Finally, the panel is kiled and the temporary waves "tempWave" and "CCDtemplate" with it.
Function ESCA_saveCCDmask(ctrlName):ButtonControl
	string ctrlName
	
	Svar CCDMaskFullPath = root:Flatfields:CCDMaskFullPath 		// Ref. to the subpanel where the image is displayed
	Svar CCDtemplatePath = root:Flatfields:CCDtemplatePath		// Ref. to the CCD template made from the user selected MCP image
	Svar currImgName = root:Flatfields:currImgName				// Name of image displayed
	Wave CCDtemplate = $CCDtemplatePath								// Wave ref. to the template CCD image generated upon loading 
	Wave currImg = $currImgName										// Image wave currently displayed in the subpanel
	
	String CCDmaskName
	Prompt CCDmaskName, "What would you like to name your new CCD mask?\nThe wave will be stored in subfolder ::Flatfields:CCD_masks"
	DoPrompt "Save the CCD binary mask currently displayed:", CCDmaskName
	
	If( V_Flag )
		Return 0 // user canceled
	EndIf
	
	String subfolderName = "root:Flatfields:CCDmasks"
	NewDataFolder/O $subfolderName
	CCDmaskName = subfolderName + ":" + CCDmaskName				// Reference to the new CCD mask to be produced
	Duplicate/O currImg, $CCDmaskName
	Wave newCCDmask = $CCDmaskName
	
	// Display new image wave
	NewImage/F/K=1/S=0 newCCDmask
	
	// Finally, kill the CCD editor and the temporary waves
	String winStr=WinName(0,64)		// Extract name of panel, kill
	DoWindow/k $winStr
	Killwaves/Z currImg, CCDtemplate
	
	SetDataFolder root:					// Set path to root folder
	
	Return 0	// Function end
	
End	

//---------------------------------------------------------------------------

// Perform flat field correction of input wave "rawdata", using the waves
// "dfw" and "ffw" for the darkfield (CCD) and faltfield (MCP), respectively. 
Function BckgCorr(rawdata,dfw,ffw)
	Wave rawdata
	Wave dfw
	Wave ffw
	
	// Obtain average value of flatfield wave
	variable ffw_avg
	Wavestats/Q ffw
	ffw_avg = V_avg

	//Known algorithm for correcting for flat fields in image processing
	rawdata = ((rawdata-dfw)*ffw_avg)/(ffw-dfw)

	Return 0
End

//---------------------------------------------------------------------------