#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

// Written by: Håkon I. Røst, NTNU
// hakon.i.rost@ntnu.no

// v.1 Oct 2020: first incarnation. Functions for generating DF and FF images for PEEM and ARPES background corrections
// v.2 Dec 2020: Include CCD image mask definition (based on code by S. Cooil, L. Bawden and A. Schenk)
// v.3 Jan 2021: Several function updates and a restructuring of how the background correction is performed
//					 i) CCD image mask functions moved to separate procedure
//					ii) Flatfield function now just "copies" a specified MCP image into the appropriate folder 
//				  iii) Darkfield function allows either a "median" or "average" DF image from a set of CCD images
//					iv) The background corr. function allow either simple DF corr. or a full DF + FF corr.

// ============================================================================================
// 								NanoESCA background correction procedures
// ============================================================================================
// Functions for generating darkfield and flatfield images for NanoESCA background corrections.


// Called from Menu: ESCAlab > Background corrections > Generate darkfield (CCD) background
// Allows user to select a desired 3D wave, used to generate a "bare" picture of the CCD
// Main assumption: same "darkfield" image taken in all layers of the wave, 
// but with different random (cosmic) noise. 
// Noise reduction is performed by: finding all systematic pixel variations that are consistent
// through all the the similar darkfield images stored in the different layers. For loops are
// used to extract a median value across all layers for each pixel (p,q). The median for each
// pixel is then stored as the "true" CCD pixel value in the final 2D darkfield image.
// The darfield/CCD image is stored in a common folder named "Darkfields".
Function ESCA_generateDF()

	DFREF saveDataFolder = GetDataFolderDFR()		// Save current data folder before doing anything
	
	// ====================================================
	// 		(1) Select darkfield stack wave
	// ====================================================
	CreateBrowser/M prompt="Select the NanoESCA image stack you want to use to generate you darkfield: "
	ModifyBrowser /M showModalBrowser, showVars=0, showWaves=1, showStrs=0, showInfo=0, showPlot=0
	string displayWaveName = StringFromList(0, S_BrowserList)
	Variable numberOfFoldersSelected = ItemsInLIst(S_BrowserList)
 	
 	// (i) Make sure ONE wave of the proper dimensions (2D or 3D) has been selected
	If (V_Flag == 0 || numberOfFoldersSelected != 1)
	
		SetDataFolder saveDataFolder							// Restore current data folder if user cancelled, or multiple files in S_BrowserList
		Abort "Jaizes, Anita! Something is wrong..."
	
	Else 	// ONE wave selected: obtain relevant wave info
		
		Wave DFsource = $displayWaveName
		String dispParentFolder = GetWavesDataFolder(DFsource,1)	// datafolder path	 
		
		// Check the dimensions of the wave selected
		If (DimSize(DFsource,1) == 0 || DimSize(DFsource,3) != 0) // trace or 4D wave selected
		
			Abort "ERROR! Did you select a 1D trace or a 4D wave instead of an image or an image stack?"
			
		EndIf	// Wave of the right dimensions selected
	
	EndIf // ONE wave only was selected
	
	// (ii) Next: make user input data name for the new DF image, and select 
	// between storing an average or median value for each px in the image plane
	
	// Name specification
	String NewDFName
	Prompt NewDFName,"Specify a name for the new darkfield image:"
	
	// Select median or averaging
	variable action
	String actionStr = "For each given pixel (p,q) in the image plane,\n"
	actionStr += "extract and store the following value from across all layers:"
	String optionStr = "median value;" 
	optionStr += "average value;"
	Prompt action, actionStr, popup, optionStr
	
	DoPrompt "Specify name and type of noise correction", NewDFName, action
		
	// Check whether user aborted the Prompt or not
	If(V_Flag)
		Abort "The user pressed Cancel"
	EndIf 
		
	// ====================================================
	// 		(2) Generate noise reduced DF wave
	// ====================================================	
	
	// Generate and navigate to newly assigned DF folder
	NewDataFolder/O/S root:Darkfields
	
	// Obtain relevant info from DF source wave, Allocate new 2D DF wave
	Variable pDim = DimSize(DFsource,0)
	Variable qDim = DimSize(DFsource,1)
	Variable rDim = DimSize(DFsource,2)
	string message
	sprintf message, "Source wave %s selected: p dim size is: %g, q dim size is: %g, r dim size is: %g",NameOfWave(DFsource), pDim, qDim, rDim
	print message
	
	// Allocate new DF image
	Make/O/N=(pDim,qDim) $NewDFName
	Wave newDFimage = $NewDFName
	
	If (rDim == 0)	// Only one image layer in the source wave -> no noise reduction performed
		
		newDFimage = DFsource[p][q]
		Abort "Only one layer in source wave! No noise removal has been performed,\nand the new wave is a direct copy of the old one."
	
	Else				// Multiple layers: for each pixel, extract intensity value in all layers, store median
		
		// Make temporary wave and relevant variables
		Make/O/N=(rDim) layerValues					// stores the value of each pixel across all layers r
		Variable ii,jj, medianPixelValue			// loop counting variables, temp median value
		string selectedAction
		
		// i. Iterate through all (p,q) pixels of each 2D image, 
		// ii. Extract the intensity value of each pixel across all layers,
		// iii. Store the median or average value in position (p,q) of the new DF image
		For (ii=0; ii< pDim; ii++)
			For (jj=0; jj<qDim; jj++)	// (i) pixel iteration
					
					// (ii) layer intensity wave for pixel (ii,jj)
					layerValues = DFsource[ii][jj][p]
					
					// (iii) Perform user requested action
					If(action == 1)			// store median
						selectedAction = StringFromList(0,optionStr,";")
						medianPixelValue = StatsMedian(layerValues)
						newDFimage[ii][jj] = medianPixelValue
					ElseIf(action == 2)		// store average
						selectedAction = StringFromList(1,optionStr,";")
						newDFimage[ii][jj] = mean(layerValues)
					EndIf
					
					layerValues = 0	// null out temp. wave vector
					
			EndFor	// column pixels (q)
		EndFor 	// row pixels (p)
		
	EndIf	// Dimensions of source wave

	
	// ====================================================
	// 		(3) Cleanup
	// ====================================================
	
	KillWaves/Z layerValues
	SetDataFolder root:
	String successMessage
	sprintf successMessage, "Successfully stored the %s for each pixel (p,q) of %s into the new DF wave %s.",selectedAction,NameOfWave(DFsource), NameOfWave(newDFimage)
	Print successMessage
	Return 0
	
End

//=========================================================================================================//

// Called from Menu: ESCAlab > Background corrections > Define new flatfield (MCP) background
// i.  User selects a "defocused"/MCP image loaded into Igor,
// ii. A copy of this MCP image is stored in a common folder "root:Flatfields"
Function ESCA_defineFF()

	DFREF saveDataFolder = GetDataFolderDFR()		// Save current data folder before doing anything
	
	// ====================================================
	// 		(1) Select 2D flatfield wave
	// ====================================================
	CreateBrowser/M prompt="Select the two-dimensional NanoESCA image you want to use for flatfield corrections: "
	ModifyBrowser /M showModalBrowser, showVars=0, showWaves=1, showStrs=0, showInfo=0, showPlot=0
	string displayWaveName = StringFromList(0, S_BrowserList)
	Variable numberOfFoldersSelected = ItemsInLIst(S_BrowserList)
 	
	If (V_Flag == 0 || numberOfFoldersSelected != 1)		// something is wrong..
	
		SetDataFolder saveDataFolder							// Restore current data folder if user cancelled, or multiple files in S_BrowserList
		Abort "Jaizes, Anita! Something is wrong..."
	
	Else 	// ONE wave selected: obtain relevant wave info
		
		Wave FFsource = $displayWaveName
		String dispParentFolder = GetWavesDataFolder(FFsource,1)	// datafolder path	 
		
		// Make sure a 2D or 3D wave has been selected
		If (DimSize(FFsource,1) == 0 || DimSize(FFsource,3) != 0) // trace or 4D wave selected
		
			Abort "ERROR! Did you select a 1D trace or a 4D wave instead of an image or an image stack?"
			
		EndIf	// Wave of the right dimensions selected
	
	EndIf // ONE wave only was selected

	// ====================================================
	// 		(2) Store copy of FF wave in root:Flatfields
	// ====================================================	
		
	// Obtain relevant info from FF source wave, Allocate new 2D FF wave in folder "Flatfields"
	Variable pDim = DimSize(FFsource,0)
	Variable qDim = DimSize(FFsource,1)
	Variable rDim = DimSize(FFsource,2)
	
	// Check that a 2D wave was in fact selected
	If (rDim > 0)
		Abort "Damn ye torpedoes! Why ye select 3D stacks noe, eh? Pick a handy 2D one insted!"
	EndIf
		
	string message
	sprintf message, "Source %s selected: p dim size is: %g, q dim size is: %g.",NameOfWave(FFsource), pDim, qDim
	print message
	
	// Prompt: Let user specify the name of the new FF, 
	String NewFFName
	Prompt NewFFName,"New FF image name" 
	DoPrompt "Generate new flatfield (FF) image", NewFFName
	
	If( V_Flag )
		return 0 // user canceled
	EndIf
	
	// Flatfield generation
	// 3. Allocate FF image in folder "root:Flatfields"
	String FFfolderName = "root:Flatfields"
	NewDataFolder/O/S $FFfolderName
	Duplicate/O FFsource, $NewFFName
	Wave newFF = $NewFFName
	
	// Print info to command line
	Printf "New flatfield wave %s defined in folder %s", NewFFName, FFfolderName 

	SetDataFolder root:				// Finally, restore data folder to root

End


//=========================================================================================================//

// Called from Menu: ESCAlab > Background corrections > Perform background correction on NE data
//	a. User selects source wave (to be corrected) and DF wave (and MCP wave for "full" normalization) 
// b. Source NE wave is duplicated within its parent folder, new NE wave is named by user
// c. The specified DF image is subtracted from the new NE wave
// d. Optionally: an intensity scaled (I_avg ~1) MCP flatfield with all spatial (x,y) variations intact is 
//    produced, and the new NE wave is divided by the (DF corrected and intensity scaled) MCP FF wave.
// IF one or more "CCD masks" has been defined before this function is called, the user has the option to 
// remove the intensity outside the MCP region.
Function ESCA_CorrectWaves()

	DFREF saveDataFolder = GetDataFolderDFR()		// Save current data folder before doing anything

	// ====================================================
	// 	(1) Select NE wave for background correction
	// ====================================================
	CreateBrowser/M prompt="Select the NanoESCA image (stack) you want to correct the background for: "
	ModifyBrowser /M showModalBrowser, showVars=0, showWaves=1, showStrs=0, showInfo=0, showPlot=0
	string displayWaveName = StringFromList(0, S_BrowserList)
	Variable numberOfFoldersSelected = ItemsInLIst(S_BrowserList)
 	
	If (V_Flag == 0 || numberOfFoldersSelected != 1)		// something is wrong..
	
		SetDataFolder saveDataFolder							// Restore current data folder if user cancelled, or multiple files in S_BrowserList
		Abort "Jaizes, Anita! Something is wrong..."
	
	Else 	// ONE wave selected: obtain relevant wave info
		
		Wave NEsourceWave = $displayWaveName
		String NEsourceParentFolder = GetWavesDataFolder(NEsourceWave,1)	// datafolder path	 
		
		// Make sure a 2D or 3D wave has been selected
		If (DimSize(NEsourceWave,1) == 0 || DimSize(NEsourceWave,3) != 0) // trace or 4D wave selected
		
			Abort "ERROR! Did you select a 1D trace or a 4D wave instead of an image or an image stack?"
		
		EndIf	// Wave of the right dimensions selected
		
	EndIf // ONE wave only was selected
	
	// Obtain relevant info from NE source wave
	Variable pDim = DimSize(NEsourceWave,0)
	Variable qDim = DimSize(NEsourceWave,1)
	Variable rDim = DimSize(NEsourceWave,2)
	Printf "NanoESCA source \"%s\" was selected: p dim size is: %g, q dim size is: %g, r dim size is: %g\n",NameOfWave(NEsourceWave), pDim, qDim, rDim
	
	// ====================================================
	// 	(2) Select DF and background wave, normalize
	// ====================================================
	
	variable action
	String optionStr = "Only darkfield (CCD) subtraction;" 
	optionStr += "Darkfield (CCD) and flatfield (MCP) correction;"
	
	Prompt action, "What background correction would you like to do?", popup, optionStr
	DoPrompt "Select the type of background correction you want to perform:", action
	
	If( V_Flag )
		Return 0 // user canceled
	EndIf
	
	// ====================================================
	// 	(3) Select DF (and background wave), normalize
	// ====================================================
	
	String DFwaveNames = AssembleAllWaveNames("root:Darkfields")
	String FFwaveNames = AssembleAllWaveNames("root:Flatfields")
	String CCmaskNames = "_NO_MASK_;" + AssembleAllWaveNames("root:Flatfields:CCDmasks:")
	
	String DFwaveName, FFwaveName, CCDwaveName, newWaveName
	
	If (action == 1)			// Only DF correction
		Prompt DFwaveName, "Select a darkfield (CCD) image to be subtracted from your image stack:", popup, DFwaveNames
		Prompt CCDwaveName, "Would you like to apply a CCD mask (if defined)?", popup, CCmaskNames
		Prompt newWaveName "Specify the name you want for the bacground normalized wave (avoid spaces):"
		DoPrompt "Background normalization", DFwaveName, CCDwaveName, newWaveName
	ElseIf (action == 2)	// DF and FF correction 
		Prompt DFwaveName, "Select a darkfield (CCD) image to be subtracted from your image stack:", popup, DFwaveNames
		Prompt FFwaveName,"Select a darkfield corrected flatfield (MCP) wave\nfrom folder \"root:Flatfields\":", popup, FFwaveNames	// popup, WaveList("*",";","DIMS:2")
		Prompt CCDwaveName, "Would you like to apply a CCD mask (if defined)?", popup, CCmaskNames
		Prompt newWaveName "Specify the name you want for the background normalized wave (avoid spaces):"
		DoPrompt "Background normalization", DFwaveName, FFWaveName, CCDwaveName, newWaveName
	EndIf
	
	If( V_Flag )
		Return 0 // user canceled
	EndIf
	
	// define full paths to selected waves and new data wave
	CCDwaveName = "root:Flatfields:CCDmasks:" + CCDwaveName
	DFwaveName = "root:Darkfields:" + DFwaveName
	String newWaveFullPath = NEsourceParentFolder + newWaveName
	
	// Check if is FFwaveName is defined (!<null>), i.e. action == 2 selected
	If(numtype(strlen(FFwaveName)) == 0)
		FFwaveName = "root:Flatfields:" + FFWaveName
	EndIf
	
	Printf "\"%s\" was selected as the darkfield (CCD) image\n", DFwaveName
	If (action == 2)
		Printf "\"%s\" was selected as the flatfield (MCP) image\n", FFWaveName
	EndIf
	Printf "\"%s\" is the name of the normalized NE image (stack)\n", newWaveName
	Printf "The normalized NE image (stack) will be placed in the source parent folder %s\n", NEsourceParentFolder
	
	// ====================================================
	// 	(4) Generate background corrected wave
	// ====================================================
	
	// i. Duplicate source wave 
	Duplicate/O NEsourceWave, $newWaveFullPath
	Wave NE_corr = $newWaveFullPath
	
	If (action == 1)			// Only DF correction
		ESCA_DFcorrect(NE_corr,$DFwaveName,CCDwave=$CCDwaveName)
	ElseIf (action == 2)
		ESCA_FullBckgCorrect(NE_corr,$FFwaveName,$DFwaveName,CCDwave=$CCDwaveName)
	EndIf
		
	Printf "Background normalization completed. Success!"
	
	SetDataFolder root:	// Navigate back to root:
	Return 0
End

	// iii. Perform flatfield correction on the DF corrected wave copy
	//ESCA_FFcorrect(NE_corr,$FFWaveName,CCDcorrect)


//=========================================================================================================//

// Receives wave references to a NanoESCA (NE) data wave and a "darkfield" (DF) wave
// Subtracts the DF wave from the NE wave. If multiple layers in the NE wave, then  
// the DF is subtracted from each layer of the NE wave
Function ESCA_DFcorrect(NEWave,DFwave,[CCDwave])
	Wave NEWave			// source wave (to be corrected)
	Wave DFwave			// 2D DF wave
	Wave CCDwave 			// OPTIONAL: 2D binary ROI mask	
	
	// Perform DF correction
	NEWave -= DFwave[p][q]
	
	// If an existing wave is passed to the function, and its name does NOT contain
	// "_NO_MASK_", then multiply all pixels outside the MCP region defined by the
	// ROI in CCDwave by zero.
	// Note that if CCDwave is not defined (i.e. = <null>), then NameOfWave(CCDwave) = ""
	If( (!ParamIsDefault(CCDwave)) && (WaveExists(CCDwave)) && (!stringmatch(NameofWave(CCDwave),"*_NO_MASK_*")) ) 
		NEWave *= CCDwave[p][q]
		NEWave = NumType(NEWave) == 2 ? 0 : NEwave		// Replace NaNs with zeros        
   Endif
	
	
	Printf "CCD correction: \"%s\" was subtracted (from each layer of)  \"%s\"\n", NameOfWave(DFwave), NameOfWave(NEWave)
	Return 0	
End

//=========================================================================================================//

// Receives wave references to a NanoESCA (NE) data wave and a "flatfield" (FF) wave
// Divides the NE wave by the FF wave, and multiplies the resultant wave by the avg.
// Intensity of the FF wave.
// IF multiple layers in the NE wave, then the FF correction is applied to all layers.
Function ESCA_FullBckgCorrect(NEwave,FFwave,DFwave,[CCDwave])
	Wave NEwave				// NE wave, dark field corrected
	Wave FFwave				// 2D flat field MCP wave		
	Wave DFwave				// 2D darkfield CCD wave
	Wave CCDwave 			// OPTIONAL: 2D binary ROI mask
	
	// Obtain average value of flatfield wave
	variable ffw_avg
	Wavestats/Q FFwave
	ffw_avg = V_avg

	//Known algorithm for correcting for flat fields in image processing
	NEwave = ((NEwave[p][q][r]-DFwave[p][q])*ffw_avg) / (FFwave[p][q] - DFwave[p][q])
	
	// If an existing wave is passed to the function, and its name does NOT contain
	// "_NO_MASK_", then multiply all pixels outside the MCP region defined by the
	// ROI in CCDwave by zero.
	// Note that if CCDwave is not defined (i.e. = <null>), then NameOfWave(CCDwave) = ""
	 If( (!ParamIsDefault(CCDwave)) && (WaveExists(CCDwave)) && (!stringmatch(NameofWave(CCDwave),"*_NO_MASK_*")) ) 
	 	NEWave *= CCDwave[p][q]
		NEWave = NumType(NEWave) == 2 ? 0 : NEwave		// Replace NaNs with zeros        
    Endif
		
	// Cleanup, signify success
	Killwaves/Z FFscaled
	Printf "MCP correction: (each layer of)  \"%s\" was scaled by \"%s\"\n", NameOfWave(NEWave), NameOfWave(FFwave)
	Return 0
End

//=========================================================================================================//

// This function is used to remove hot pixels.
// The user specifies a threshold value of maximum allowable intensity.
// The function then loops through all pixels, comparing them to this value
// Any pixel value found above the threshold will be corrected to an average
// of its surrounding pixel values
Function ESCA_removeHot([NEWave,threshold])
	Wave NEWave
	Variable threshold
	
	// (1) If no wave has been specified, use the wave from the top graph
	If( ParamIsDefault(NEWave) )
   	String graphName = WinName(0,1)
   	String imageList = ImageNameList(graphName, ";")
		Variable numberOfTraces = ItemsInLIst(imageList)
		
		If (numberOfTraces != 1)
			Abort "The topmost panel contains more/less than one wave!"
		EndIf
		
		String imgName = StringFromList(0, imageList)
		Wave NEWave = ImageNameToWaveRef(graphName,imgName)
		 
   Endif
   
   // (2) If No threshold value has been supplied ot the function, prompt user to specify one
   
   If( ParamIsDefault(threshold) )
   	Prompt threshold, "Specify the upper limit for what is considered real signal,\nand not hot pixels:"
   	DoPrompt "Specify the hot pixel threshold", threshold
   EndIf
   
   // (3) Loop through all pixels, set anything above the specified threshold 
   //     equal to an average of the neighbouring pixels
	Variable pDim = dimsize(NEWave,0)
	Variable qDim = dimsize(NEWave,1)
	
	Variable ii, jj, currPx, avgNeighbours
	
	For(ii=0;ii<pDim;ii++)
		
		For(jj=0;jj<qDim;jj++)
		
			currPx = NEWave[ii][jj]
		
			If(currPx >= threshold)
				
				// Evaluate corner cases
				If((ii == 0) && (jj == 0)) 								// Top left corner
					avgNeighbours = NeWave[ii+1][jj] + NeWave[ii][jj+1] + NeWave[ii+1][jj+1]
					avgNeighbours /= 3
				ElseIf((ii == pDim-1) && (jj == 0)) 					// Bottom left corner
					avgNeighbours = NeWave[ii-1][jj] + NeWave[ii][jj+1] + NeWave[ii-1][jj+1]
					avgNeighbours /= 3
				ElseIf((ii == 0) && (jj == qDim-1)) 					// Top right corner
					avgNeighbours = NeWave[ii][jj-1] + NeWave[ii+1][jj] + NeWave[ii+1][jj-1]
					avgNeighbours /= 3
				ElseIf((ii == pDim-1) && (jj == qDim-1)) 				// Bottom right corner
					avgNeighbours = NeWave[ii][jj-1] + NeWave[ii-1][jj] + NeWave[ii-1][jj-1]
					avgNeighbours /= 3
				ElseIf((ii > 0) && (ii < pDim-1) && (jj == 0))		// Left edge
					avgNeighbours = NeWave[ii+1][jj] + NeWave[ii-1][jj] +  NeWave[ii][jj+1]
					avgNeighbours += NeWave[ii+1][jj+1] + NeWave[ii-1][jj+1]
					avgNeighbours /= 5
				ElseIf((ii > 0) && (ii < pDim-1) && (jj == qDim-1))	// Right edge
					avgNeighbours = NeWave[ii+1][jj] + NeWave[ii-1][jj] +  NeWave[ii][jj-1]
					avgNeighbours += NeWave[ii+1][jj-1] + NeWave[ii-1][jj-1]
					avgNeighbours /= 5
				ElseIf((ii == 0) && (jj > 0) && (jj < qDim-1))		// Top edge
					avgNeighbours = NeWave[ii+1][jj] + NeWave[ii][jj+1] +  NeWave[ii][jj-1]
					avgNeighbours += NeWave[ii+1][jj+1] + NeWave[ii+1][jj-1]
					avgNeighbours /= 5
				ElseIf((ii == pDim-1) && (jj > 0) && (jj < qDim-1))	// Bottom edge
					avgNeighbours = NeWave[ii-1][jj] + NeWave[ii][jj+1] +  NeWave[ii][jj-1]
					avgNeighbours += NeWave[ii-1][jj-1] + NeWave[ii-1][jj+1]
					avgNeighbours /= 5
				Else	// Not near an edge or a corner
					avgNeighbours = NeWave[ii+1][jj] + NeWave[ii-1][jj]
					avgNeighbours += NeWave[ii][jj+1] + NeWave[ii][jj-1]
					avgNeighbours += NeWave[ii+1][jj+1] + NeWave[ii-1][jj+1]
					avgNeighbours += NeWave[ii+1][jj-1] + NeWave[ii-1][jj-1]
					avgNeighbours /= 8
				EndIf
				
				NeWave[ii][jj] = avgNeighbours	// Store average value in "hot" pixel
				avgNeighbours = 0					// Reset variable for avg. value
				
			EndIf	// IF above threshold value
			
		EndFor // For all jj (columns)
		
	EndFor // For all ii (rows)

	Return 0	
End


//=========================================================================================================//

Function/S AssembleAllWaveNames(subFolderPath)
	String subFolderPath
	String objName = ""
	String waveNames = ""
	Variable index = 0
	do
		objName = GetIndexedObjName(subFolderPath, 1, index)
		If (strlen(objName) == 0)
			//Print waveNames
			Return waveNames
		Endif
		objName += ";"
		waveNames += objName
		index += 1
	while(1)
	
	
End

//=========================================================================================================//


//=========================================================================================================//
//=========================================================================================================//
//													OLD AND OBSOLETE FUNCTIONS
//=========================================================================================================//
//=========================================================================================================//


// NOTE: THIS FUNCTION IS NOW OBSOLETE!
// Receives wave references to a NanoESCA (NE) data wave and a "flatfield" (FF) wave
// Divides the NE wave by the FF wave, and multiplies the resultant wave by the avg.
// Intensity of the FF wave.
// IF multiple layers in the NE wave, then the FF correction is applied to all layers.
Function ESCA_FFcorrect(NEWave,FFwave,CCDcorrect)
	Wave NEWave				// NE wave, dark field corrected
	Wave FFwave				// 2D flat field MCP wave		
	Variable CCDcorrect 	// 1 = correct for CCD width; 0 = do NOT correct for CCD width
	
	// Duplicate DF wave, scale by average value
	Duplicate /O FFwave, FFscaled
	wavestats/Q FFwave
	variable FF_avg = V_avg
	FFscaled = FF_avg/FFwave
		
	// Perform flatfield correction
	NEWave *= FFscaled[p][q]
	
	// IF a CCD mask has been defined, the user can remove intensity outside
	// the CCD region by setting CCDcorrect == 1 before calling the function
	String FFfolderName = GetWavesDataFolder(FFwave,1)
	String CCDmaskPath = FFfolderName + "CCD_mask"
	
	If((waveexists($CCDmaskPath)) && CCDcorrect)
		
		Wave CCDmask = $CCDmaskPath
		NEWave *= CCDmask[p][q]
		NEWave = NumType(NEWave) == 2 ? 0 : NEwave		// Replace NaNs with zero
		
	EndIf
	
	// Cleanup, signify success
	Killwaves/Z FFscaled
	Printf "MCP correction: (each layer of)  \"%s\" was scaled by \"%s\"\n", NameOfWave(NEWave), NameOfWave(FFwave)
	Return 0
End

//=========================================================================================================//

// NOTE: THIS FUNCTION IS NOW OBSOLETE!
// Called from Menu: ESCAlab > Background corrections > Define new flatfield (MCP) background
// i. 	User selects a "defocused image" loaded into Igor,
// ii. 	This image is corrected for Darkfield (CCD) variations,
// The DF corrected MCP image is stored in a common folder named "Flatfields".
Function ESCA_generateFF()

	DFREF saveDataFolder = GetDataFolderDFR()		// Save current data folder before doing anything
	
	// ====================================================
	// 		(1) Select 2D flatfield wave
	// ====================================================
	CreateBrowser/M prompt="Select the two-dimensional NanoESCA image you want to use for your flatfield: "
	ModifyBrowser /M showModalBrowser, showVars=0, showWaves=1, showStrs=0, showInfo=0, showPlot=0
	string displayWaveName = StringFromList(0, S_BrowserList)
	Variable numberOfFoldersSelected = ItemsInLIst(S_BrowserList)
 	
	If (V_Flag == 0 || numberOfFoldersSelected != 1)		// something is wrong..
	
		SetDataFolder saveDataFolder							// Restore current data folder if user cancelled, or multiple files in S_BrowserList
		Abort "Jaizes, Anita! Something is wrong..."
	
	Else 	// ONE wave selected: obtain relevant wave info
		
		Wave FFsource = $displayWaveName
		String dispParentFolder = GetWavesDataFolder(FFsource,1)	// datafolder path	 
		
		// Make sure a 2D or 3D wave has been selected
		If (DimSize(FFsource,1) == 0 || DimSize(FFsource,3) != 0) // trace or 4D wave selected
		
			Abort "ERROR! Did you select a 1D trace or a 4D wave instead of an image or an image stack?"
			
		EndIf	// Wave of the right dimensions selected
	
	EndIf // ONE wave only was selected

	// ====================================================
	// 		(2) Generate noise reduced FF wave
	// ====================================================	
		
	// Obtain relevant info from FF source wave, Allocate new 2D FF wave in folder "Flatfields"
	Variable pDim = DimSize(FFsource,0)
	Variable qDim = DimSize(FFsource,1)
	Variable rDim = DimSize(FFsource,2)
	
	// Check that a 2D wave was in fact selected
	If (rDim > 0)
		Abort "Damn ye torpedoes! Why ye select 3D stacks noe, eh? Pick a handy 2D one insted!"
	EndIf
		
	string message
	sprintf message, "Source %s selected: p dim size is: %g, q dim size is: %g.",NameOfWave(FFsource), pDim, qDim
	print message
	
	// Prompt:
	// 1. Let user specify the name of the new FF, 
	// 2. Let the user pick an appropriate darkfield to subtract
	String NewFFName, DFwaveName
	Variable numScans = 1
	NewDataFolder/O/S root:Darkfields			// Navigate to DF data folder
	
	Prompt NewFFName,"New FF image name"
	Prompt DFwaveName, "Select DF wave to be subtracted from the FF", popup, WaveList("*",";","DIMS:2") 
	DoPrompt "Generate new flatfield (FF) image", NewFFName, DFWaveName
	
	If( V_Flag )
		return 0 // user canceled
	EndIf
	
	Wave DFwave = $DFWaveName		// Save reference to the DF wave selected by user

	// Flatfield generation
	// 3. Allocate FF image in folder "root:Flatfields"
	NewDataFolder/O/S root:Flatfields
	Duplicate/O FFsource, $NewFFName
	Wave newFF = $NewFFName
	
	// 4. Subtract specified darkfield
	newFF -= DFwave	[p][q]					// subtract DF times the number of scans

	// Print info to command line
	Printf "New flat field wave %s defined\n", NewFFName 
	Printf "Darkfield correction: %s - %s\n", NameOfWave(FFsource), DFWaveName
	Print "Flatfield generation successful!"

	SetDataFolder root:				// Finally, restore data folder to root

End


//=========================================================================================================//

// NOTE: THIS FUNCTION IS NOW OBSOLETE!
// Updated function can be found in "ESCACCDMaskPanel.ipf"
Function ESCA_generateCCDmask_OLD(mcpw,dfw)
	Wave mcpw // Specified flat field wave
	Wave dfw // Darkfield wave for noise corrections
	
	// Define new wave for the CCD mask
	String destPath = "root:Flatfields:CCD_mask"
	Duplicate/O mcpw, $destPath
	Wave CCD = $destPath
	CCD *= 1.1					// Scale to have different intensity than the "raw" MCP image
	
	Display; AppendImage CCD
	
	// Perform background corrections on the CCD mask
	ESCA_DFcorrect(CCD,dfw)		// first, subtract darkfield
	ESCA_FFcorrect(CCD,mcpw,0)	// Do flatfield correction on MCP mask
	
	// Set a threshold at 60% intensity of the center pixel (may need adjustment)
	Variable thresh = 0.38*CCD[512][512]
	
	// Filter out random hot pixels not captured by image threshold
	Imagefilter/p=1/N=(4) avg, CCD
	Imagefilter/p=1/N=(4) median, CCD
	
	// Generate ccd image mask and make all values on phosphor screen 1, and outside screen 0
	Imagethreshold/O/T=(thresh) CCD
	CCD /= 255

End

// Old CCD mask evaluation:

	// IF a CCD mask has been defined, the user can remove intensity outside
	// the CCD region by setting CCDcorrect == 1 before calling the function
	
	//String FFfolderName = GetWavesDataFolder(FFwave,1)
	//String CCDmaskPath = FFfolderName + "CCD_mask"
	
	//If((waveexists($CCDmaskPath)) && CCDcorrect)
		
	//	Wave CCDmask = $CCDmaskPath
	//	NEWave *= CCDmask[p][q]
	//	NEWave = NumType(NEWave) == 2 ? 0 : NEwave		// Replace NaNs with zero
		
	//EndIf