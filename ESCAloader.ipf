#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.

//______________________________________________________________________________________________________________________________________

Function Init_ESCALoader() // Initialize global  NanoESCA variables, open loader panel

	Execute "ESCAloader()" // Fire up this baby
	Return 0

End

//______________________________________________________________________________________________________________________________________
// Loader panel for importing NanoESCA files as properly scaled Igor waves

Window ESCAloader() : Panel
	PauseUpdate; Silent 1		// building window...
	NewPanel /W=(437,53,784,179)
	SetDrawLayer UserBack
	SetDrawEnv fsize= 14,fstyle= 1
	DrawText 24,29,"NanoESCA Loader Panel"
	Button KillPanel,pos={250.00,11.00},size={70.00,20.00},proc=KillESCALoader,title="Kill Panel"
	Button LButton,pos={223.00,94.00},size={100.00,20.00},proc=ESCA_Load,title="Load file(s)"
	SetVariable DFName,pos={23.00,68.00},size={300.00,19.00},title="Destination Folder"
	SetVariable DFName,limits={-inf,inf,0},value= root:ESCAglobals:dataDest
	Button BwrPath,pos={144.00,94.00},size={70.00,20.00},proc=ESCA_BrwPath,title="Set Path"
	PopupMenu WaveType,pos={22.00,41.00},size={197.00,17.00},bodyWidth=75,proc=ESCADTPopup,title="What are you loading?"
	PopupMenu WaveType,mode=1,popvalue="Single Image ",value= #"\"Single Image;Image Stack\""
	PopupMenu fileForomat,pos={228.00,42.00},size={92.00,17.00},proc=ESCAFFPopup,title="File format"
	PopupMenu fileForomat,mode=1,popvalue=".tif",value= #"\".tif;.ibw;.JPG;.jpeg;.bmp; \""
EndMacro

//=========================================================================================================//

Function KillESCALoader(killButton) : ButtonControl
	String killButton
	
	String winStr = WinName(0,64)
	KillWindow/Z $winStr

End

//=========================================================================================================//

Function ESCAFFPopup(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum	// which item is currently selected (1-based)
	String popStr	

	svar dataFormat = root:ESCAglobals:dataFormat
	dataFormat = popStr // Set string containing file format info equal to drop-down selection

return 0
End

//=========================================================================================================//

Function ESCADTPopup(ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum	// which item is currently selected (1-based)
	String popStr	

	svar dataType = root:ESCAglobals:dataType
	dataType = popStr // Set string containing file format info equal to drop-down selection

return 0
End

//=========================================================================================================//

Function ESCA_BrwPath(ctrlname): buttoncontrol //browse path to load files
	String ctrlname
	
	//enter path
	newPath/Q/M="please specify a path"/O dataPath //data path is the symbolic name of that path
	
	ESCA_UpdatePath(1) 
End

//=========================================================================================================//

Function ESCA_UpdatePath(verbose) 	// Update path folder for LEED files to be loaded
	variable verbose
	SVAR dataPathStr=root:ESCAglobals:dataPathStr
	PathInfo dataPath //Simbolic path used by Igor
	if (V_flag==1) //ok
		dataPathStr = S_Path
		if (verbose==1)
			print "Input data path has been set to: ", dataPathStr
		endif
	else
		print "Input data path has not been set"
	endif
End

//=========================================================================================================//

Function ESCA_Load(LButton) : ButtonControl
	String LButton

	Svar dataType = root:ESCAglobals:dataType
	Svar dataDest = root:ESCAglobals:dataDest
	Svar fileFormat = root:ESCAglobals:dataFormat
	Svar dataPath = root:ESCAglobals:dataPathStr
	Svar ImageString = root:ESCAglobals:lastImageStr
	
	String dfStr		// Temporary string containing the (trimmed) destination folder name
	String imageName  // Name of 1) single image to be loaded, or 2) common name part for all images in a stack
	String destPath	// Full path string to destination wave within Igor 
	
	// ---------------------- Load either a single image or a stack ----------------------
	
	If (stringMatch(dataType,"Single Image")) // Single image selected
	
		// Select file to be loaded, return full path string
		String tempPath = ESCADoOpenFileDialog() 
		
		// IF cancelled the file dialog -> break out of the function
		If(stringmatch(tempPath,""))
			Return -1
		EndIf
	
		// Get file info: Extract and store data folder and format, return file name WITH ending
		imageString = ESCA_getImgInfo(tempPath,fileFormat,0)
		
		// Make destination folder, Access the .DAT file and retrieve the relevant info
		dfStr = ESCA_makeDestFolder(dataDest)
		Wave/T fileNames =  ESCA_ReadTrace(dataPath,dataDest,1) //  Returns a text wave containing the name of the image (not used here)
		
		//  Load image file, assemble full path to destinatio wave
		String message = "Opening image " + ImageString + " from " + dataPath
		ImageName = ESCA_openImage(imageString,dataPath,dataDest,fileFormat,message) //  returns name of 2D igor wave WITHOUT ending
		destPath = ESCA_fullDestPath(ImageName,dataDest)
		
		// Obtain and print wave stats to command prompt
		String imgSizeStr = ESCA_ImgStats(dataDest,imageName) // 0 indicates single image
		Print imgSizeStr	// Print data size to command prompt
		
		// Remove darkfield from image wave, if global variable darkfield = 1
		//destPath = "root:" + dataDest + ":" + ImageName	// Assemble path to image estination	
		wave singleImg = $destPath
		ESCA_removeDF(singleImg,dataDest,1)
		
	ElseIf (stringMatch(dataType,"Image Stack")) // Image stack selected
			
		// Make destination folder for stack
		dfStr = ESCA_makeDestFolder(dataDest)
	
		// Access the .DAT file and retrieve the relevant info, including image file names and energies.
		// Return reference to a text wave containing the name of the images to be loaded into a stack.
		Wave/T fileNames =  ESCA_ReadTrace(dataPath,dataDest,1) 
		
		// Extract "common" name for all images of the stack found in the "sum" folder (minus indexing and format tag) 
		imageName = ESCA_getImgInfo("",fileFormat,1) // 1 means image stack common name is returned.

		//Load the first image of the folder to get the array dimension
		String tmpStr = fileNames[0] //Name + data tag of the first image
		String tmpName = ESCA_openImage(tmpStr,dataPath,dataDest,fileFormat,"Open image")

		// Allocate stack wave, based in dimensions of 1st image and # of images listed in .DAT file
		Wave stackWave = ESCA_allocateStack(dataDest,tmpName,imageName,fileNames)
		Variable numImages = DimSize(fileNames, 0) // Number of images in stack
		
		// Assemble stack wave
		Variable j
		
		For (j=0;j<numImages;j++)
		
			tmpStr = fileNames[j]		// Extract current file name
			tmpName = ESCA_openImage(tmpStr,dataPath,dataDest,fileFormat,"Open image")	// load image j, return wave name
			destPath = "root:" + dataDest + ":" + tmpName		// Assemble path to image estination
			
			Wave currImg = $destPath				// Generate wave reference to current image j
			
			ESCA_removeDF(currImg,dataDest,0)		// If global darkfield = 1. perform background intensity correction
			
			// TO BE INSERTED: If normalize = 1, perform normalization

			ImageTransform/P=(j)/PTYP=0/D=currImg setPlane stackWave	// Store current image in stack wave
			Killwaves currImg														// Kill reference to current image
		
		Endfor
		
		// HERE: update the energy axis to match the input values
		
		String windowName = "ST_"+ imageName 
		//ESCA_imageToFront(windowName,stackWave)
		//ESCA_StackControls()
	
	Else // Something is wrong!
	
		Abort "Something went wrong! Did you remember to select the right data type?"
	
	EndIf
	
	// -------------------------- Cleanup --------------------------
	
	KillWaves fileNames	//Kill the wave containing the file names	
	
End

//=========================================================================================================//

// If type = 0 (single image):
// Extracts the file name, format and path from a "full path string" and stores the info in input variables.
// Returns the name of the file as a string variable, including the format tag

// If type = 1 (image stack):
// The common name of all image files (minus indexing) is taken from the folder name, minus the date signature 
// set by the ProNanoESCA software. The common name is returned as a string variable.
Function/S ESCA_getImgInfo(fullPathString,format,type)
	String fullPathString,format
	Variable type		// 0 = single image, 1 = stack
	
	sVar dataPath = root:ESCAglobals:dataPathStr
	
	String fileName // name of single file, or "common" name part (minus indexing) for all stack images
	
		If (type == 0)			// single image
			dataPath = ParseFilePath(1, fullPathString, ":", 1, 0) // Get path to folder containing the file.
			format = "." + ParseFilePath(4, fullPathString, ":", 0, 0)	// Extract file format (e.g. .tif)
			fileName = ParseFilePath(0, fullPathString, ":", 1, 0) // Extract file name
			//fileName = RemoveEnding(fileName,format)
		ElseIf (type == 1)	// image stack
			Variable dateSignature = 14; // Number of characters in date and time signature on data folder generated by FOCUS software
			String DFname = ParseFilePath(0, dataPath, ":", 1, 1) // Extracts the name of the folder in which "sum" is placed
			fileName = DFname[0,strlen(DFname)-dateSignature-1] // Cut of date signature. Extra -1 due to zero indexing in Igor Pro. 
		EndIf

	Return fileName
	
End

//=========================================================================================================//

// Inputs name of 2D Igor wave (image), returns an info string describing the image size
Function/S ESCA_ImgStats(IgorDatafolder,waveStr)
	String IgorDataFolder, waveStr
	
	SetDataFolder root:$(IgorDataFolder)		// Navigate to destination folder
	variable nump = dimsize($waveStr,0) 		// # rows
   variable numq = dimsize($waveStr,1)		// # columns
   
	String sizeStr = "Image Size: (" + num2str(nump) + ";" + num2str(numq) + ")"
	
	SetDataFolder root: 
	
	Return sizeStr
End

//=========================================================================================================//

// Takes in a chosen name string, a text wave of images, a reference image from the
// list and a destination folder. Allocates an empty "stack"/3D cube based on the
// dimensions of the reference wave and the number of images listed in the text wave.
// Empty stack is stored in the destination folder, and a string describing its
// dimensions is printed to the command line.
Function/WAVE ESCA_allocateStack(IgorDatafolder,firstWaveStr,commonName,imageNames)
	String IgorDataFolder, firstWaveStr, commonName
	Wave imageNames
	
	Svar DFname = root:ESCAglobals:dataDest
	
	SetDataFolder root:$(IgorDataFolder)				// Navigate to destination folder
	variable/G np = dimsize($firstWaveStr,0) 		// # rows
   variable/G nq = dimsize($firstWaveStr,1)		// # columns
	Variable/G stkN = DimSize(imageNames,0)			//	# of images in stack
	
	Variable/G layer = 0 									// Layer of the stack
	Variable/G valdis = 0  								// Variable related to the image layer
	Variable/G layeradjust = 1
	
	String stackName										// Name of 3D Igor cube
	
	// Check length of "common" file name
	If(strlen(commonName)>26) // Too long file name, cut to 25 characters
			stackName =  commonName[0,25] + "_STK"
	Else
			stackName = commonName + "_STK"
	EndIf		

	Make/N=(np,nq,stkN)/O/W $stackName		// Create the image stack wave
	Wave ImgStack = $stackName

	// Print stack size stats to command line
	String stkSizeStr = ESCA_ImgStats(IgorDatafolder,firstWaveStr) // 1 indicates image stack
	stkSizeStr += ", No. of layers: " + num2str(stkN)
	Print stkSizeStr

	Return imgStack

End


//=========================================================================================================//

// Allocates a destination folder for NanoESCA data with name given in dataDest.
// Alerts the user if a destination folder of the same name exists, asking whether
// the user wants to overwrite waves/variables in the folder of choose a different
// folder name.
Function/S ESCA_makeDestFolder(dataDest)
	String dataDest
	
	// making the data folder where the stack wave is placed
	If(DataFolderExists(dataDest))
		
	String alertStr = "WARNING!\n\nThe Specified destination folder already exists and may contain other waves.\nAre you sure you want to place your image/stack here?\n\nThis may overwrite essential global variables..."
	DoAlert/T="Data folder warning" 1, alertStr
			
		If(V_flag==2) // User cancelled
			Abort
		EndIf
		
	EndIf // Existing data folder	
			
	String dfStr
			
	//If the name exceed 30 characters, The last couple of characters get cut off
	If(strlen(dataDest) > 30)
		dfStr = dataDest[0, 25]
		Print "Original folder name was too long. Destination folder name was trimmed to 26 characters."
	Else
		dfStr = dataDest
	EndIf
		
	NewDataFolder/S/O root:$(dfStr)	// Make destination folder
	SetDataFolder root:					// reset current data folder to root
	Return dfStr

End

//=========================================================================================================//

// Opens the requested image file as a single precision wave and return its name string.
// In case the image were not found it returns the string "null".
Function/S ESCA_openImage(fileName,dataPath,dataDest,fileFormat,messageStr)
	String fileName		// Name of file to be loaded, with file format ending
	String dataPath 		// Full path to folder containing the image file
	String dataDest		// Destination folder inside Igor
	String fileFormat		// Image file format
	String messageStr 	// Prompt message text in the dialog used to select the file (used in Open/M)
	variable i
	
	// Define symbolic path reference to where data is stored
	NewPath/O/Q dataFolder dataPath

	// file dialog to select single image
	Variable refNum
	Open/P=dataFolder/R/M=messageStr/Z=2 refNum as fileName
	
	// check if file exists and was loaded successfully
	If (V_flag<-1)	
		printf "File %s not found in the given folder\r",fileName
		Abort
	ElseIf (V_flag==-1)
		Abort "Load file operation cancelled by user."
	EndIf

	// Define a string variable containing the full path name for the loaded file within Igor
	String imageStr
	String dfStr // name of data folder
	
	// Determine if Image exists, load wave
	If (stringMatch(S_fileName,"")!=1) // read image, if exists

		// Check length of fileName
		If(strlen(fileName)>30) // Too long file name, cut to 25 characters
			imageStr =  fileName[0,25]
		Else
			imageStr = RemoveEnding(fileName,fileFormat) // Keep fileName as it is, but remove the .<format>
		EndIf

		// Make new data folder for waves to be loaded, navigate here
		NewDataFolder/S/O $dataDest
		
		string format 
		// Make sure to specify right formatting at /T=type. Igor allows the following graphic formats:
		// type:			Loads this type of image:
		//------------------------------------------------------
		// any			Any graphic file type
		// bmp			Windows bitmap file
		// jpeg			JPEG file
		// png			PNG file
		// rpng			raw PNG file (see Details)
		// sunraster	SUN Raster file
		// tiff			TIFF file
		If (stringMatch(fileFormat,".jpg"))
			format = "jpeg" // Igor specifically only allows the following 
		ElseIf (stringMatch(fileFormat,".tif"))
			format = "tiff" // Igor specifically only allows the following 
		Else
			format = fileFormat[1,strlen(fileFormat)-1] // Remove punctuation from format
		Endif
		
		// Load image into wave
		ImageLoad/T=$format/O/Q/N=$imageStr S_fileName
			
		Close refNum // Close loaded image			
		
		If (V_flag==0)		// No waves loaded. Perhaps user canceled
			
			SetDataFolder root:	// Restore current data folder to "root"				.
			Return "null"
			
		Else	// Wave loaded successfully: update lastImageStr and return ImageStr
			
			SVAR lastImage = root:ESCAglobals:lastImageStr
			lastImage = S_filename	
			SetDataFolder root:	// Restore current data folder to "root"
					
			Return imageStr // Return name of loaded file within Igor, excluding format tag
			
		EndIf // V_flag!=0, aka successful wave load
	
	Else // NO image exists, return null string
		
		SetDataFolder root:	// Restore current data folder to "root"
		Return "null"
	
	Endif // Image exists?
	
End

//=========================================================================================================//

Function/S ESCA_fullDestPath(imageName,dataDest)
	String imageName, dataDest
	
	Return "root:" + dataDest + ":" + imageName

End


//=========================================================================================================//


Function/WAVE ESCA_ReadTrace(dataPath,dataDest,mode)
	String dataPath
	String dataDest
	Variable mode		//mode = 1 ==> trace from image or from stack
							//mode = 2 ==> trace from XPS
							//mode = 3 ==> trace from XAS data (photon energy and mesh)
							//mode = 4 ==> trace from single image
	

	//----------------------------------------------------------
	// Part I: find the .DAT file containing the scan info
	//----------------------------------------------------------
	
	String traceStr, DATtraceList // (1) name of .DAT file belonging to the measurements (2) list of .DAT files in folder
	
	NewPath/O symbolic_DF, dataPath // Create symbolic path of imagePathStr for use with IndexedFile()
	DATtraceList = IndexedFile(symbolic_DF, -1, ".dat") // list of all .DAT files in folder
	
	If (ItemsInList(DATtraceList)==1)		// ONE .DAT file in the folder, as expected
		traceStr = StringFromList(0,DATtraceList)
	Else
		Abort "ERROR: Either no .DAT file or more than one .DAT file is present in the data folder!"
	EndIf
	
	//----------------------------------------------------------
	// Part II: Open the .DAT file, Obtain relevant scan info
	//----------------------------------------------------------
	
	Variable refnum
	Open/P=symbolic_DF/R/Z=1 refnum as traceStr	// Open .Dat file
	
	SetDataFolder dataDest								// Navigate to the destination folder of the image data
	
	String sftwStr = ESCA_GetSoftwareVersion(refNum)					 	// Get the software version
	String axisName = ESCA_GetAxisName(refNum) 						 		// Get the name of the axis (i.e. type of measuremets) 
	Variable DET_SiZE = ESCA_GetDetectorSize(refNum) 				 		// Get the diameter of the detector (um) 
	Variable M_FOV = ESCA_GetMagnification(refNum)					 		// Get the magnification of the image
	Variable FOV_MODE = ESCA_GetFOVMode(refNum)								// Get the FOV mode of the scans (1 = R space, 2 = K space)
	Variable contrastAperture = ESCA_GetContrastAperture(refNum)	 	// Get the value of contrast aperture
	Variable binning = ESCA_GetBinning(refNum) 						 		// Get the CCD binning
	Variable N_SCAN = ESCA_GetNumScans(refNum)							 	// Get the Number of scans performed
	
	//------------------------------------------------------------------------------------------------
	// Part III: Load all image file names and corresp. KE/"image number" and FOV from the .DAT file
	//------------------------------------------------------------------------------------------------
	
	String tmpStr = ""				// string where a read line of .DAT file is temporarily stored
	Variable lineNumber = 0		// Line index
			
	Do //Read the Trace file until find [SCAN* or [DataSum*
		FReadLine refNum, tmpStr 
		If (StringMatch(tmpStr, "[SCAN*") == 1 || StringMatch(tmpStr, "[DataSum*") == 1)
			Variable mv = StringMatch(tmpStr, "[DataSum*")
			Break // No more lines to be read
		Endif		
		lineNumber += 1
	While (1)
	
	Variable fl = lineNumber + 1 //First line with file names to be read
	Print "Reading Trace From Line:", fl
			
	Variable nt 		// Total number of columns to read in .DAT file
	Variable nsk_FN 	// Columns (to be skipped) between energy values and fileName
	Variable nsk_FOV	// Columns (to be skipped) between energy values and FOV
	Variable npx_FOV	// No. pixels comprising the full FOV imaged in the given version of the NanoESCA
		
	// Set nt and nsk based on the version of the ProNanoESCA software
	If(stringMatch(sftwStr, "2.10.20") == 1) // Old
		nsk_FN = 7
		nsk_FOV = -1 
		nt = 9 
	ElseIf(stringMatch(sftwStr, "2.10.62") == 1) // Olivier
		nsk_FN = 9
		nsk_FOV = -1
		nt = 11 
	ElseIf(stringMatch(sftwStr, "2.10.64") == 1) // New
		nsk_FN = 9
		nsk_FOV = -1 
		nt = 11 
	ElseIf(stringMatch(sftwStr, "2.10.75") == 1) // Bristol
		nsk_FN = 10 
		nsk_FOV = -1
		nt = 12
	ElseIf(stringMatch(sftwStr, "2.15.99") == 1) // NTNU QuSpin
		nsk_FN = 10
		nsk_FOV = 7
		nt = 12
		npx_FOV = 990
	Endif
	
	// Extract the name of folder the image(s) is/are in, NOT the full path	
	String DFname = ParseFilePath(0, dataPath, ":", 1, 0)
		
	// Figure out whether the folder contains a simple set of images or a stack where each image has an associated KE.
	//Assemble delimited text commands to pass to "LoadWave" in the string variable "coInfoStr"
	
	String coInfoStr = ""
	
	If(stringMatch(DFname, "image") == 1)				// image (number) series
		coInfoStr += "C=1,F=0,N=IMG_" + DFname + ";" // Image number of the stack
	Else															// KE series
		coInfoStr += "C=1,F=0,N=En_" + DFName + ";" 	// KE of the stack
	Endif	
	
	coInfoStr += "C=" + num2str(7) + ",N='_skip_';"							// "C" and "N" flags here specify the number of columns to be skipped
	coInfoStr += "C=1,F=0,N=FOVs;"					 							// Calibrated FOV	values are stored here
	coInfoStr += "C=" + num2str(nsk_FN-(nsk_FOV+1)) + ",N='_skip_';"	// "C" and "N" flags here specify the number of columns to be skipped
	coInfoStr += "C=1,F=-2,N=FileNames;" 										// File names are stored here
	
	
	// Figure out what loading style to use, based on the formating style of the .DAT file
	If (StringMatch(DFname, "image") == 1 || StringMatch(DFname, "Sum") == 1)	// Loaded from "Image" or "Sum" folder, lines of data are consecutive (no line skips)
	
		// Loops through all lines of the .DAT file starting from "fl" and until the end (no line skip between consecutive data lines).
		// The ";"-separated flags in "coInfoStr" specifies what to load for each of the "nt" columns.
		// Each column is loaded into a wave stored in the current data folder. flag "F" signals the type of wave
		// Each wave generated contains the same number of rows equal to the num. of rows in the .DAT minus fl 
		// The name of the .DAT file is specified by "traceStr"
		LoadWave/B=coInfoStr/L={0,fl,0,0,nt}/A/J/O/Q/P=symbolic_DF traceStr //Load the trace
	
		// Generate wave reference to the text wave containing the names of the files to be loaded.
		//	As each image name is specified within quotation marks in the .DAT file, remove these
		// quotation marks form the name of each text element in the wave
		Wave/T FileNames								// Reference to the wave of image names
		
#If (IgorVersion() < 8.00) 
	ESCA_RemoveQuoteFromWaves(FileNames)			// for versions earlier than Igor 8: loop through each element and remove quotation marks
#EndIf

		// For the Later versions of ProNanoESCA: store the unit length per Ångstrøm conversion factor for each given energy
		If(stringMatch(sftwStr, "2.15.99") == 1)  // NTNU QuSpin
			Wave FOVs										// Obtain wave reference to the FOVs (default is microns)
			Duplicate/O FOVs, micronsPerPx			// Store the conversion factor between FOV (in um) and pixels for each FOV value
			micronsPerPx /= npx_FOV						// No. micrometer or pixel for each given scan
			
			// If ARPES, rename wave
			If(FOV_MODE == 2)								
				Rename micronsPerPx, InvAngstromPerPx
			EndIf
		EndIf
		
	ElseIf (StringMatch(DFname, "Scan") == 1)		// Individual scans are loaded, i.e. from folder "Scans" and NOT "Sum" or "Image".
	
		Make/O/T/N=(N_SCAN) allNames		// Allocate a text wave to store all the file names in
		Make/O/D/N=(N_SCAN) allFOVs		// Allocate wave to store all FOV values in
		Variable jj
		Variable dataLine = fl
	
		// Loop through all images (number=N_SCAN), load one by one, skip lines in between
		For (jj=0;jj<N_SCAN;jj++)			
		
			LoadWave/B=coInfoStr/L={0,dataLine,1,0,nt}/A/J/O/Q/P=symbolic_DF traceStr 	// Load the trace
			Wave/T FileNames																				// Wave reference to file name
			allNames[jj] =  FileNames[0]																// Store file name in text wave imgNames
			Wave FOVs																						// Wave reference to FOV value
			allFOVs[jj] =  FOVs[0]																		// Store FOV value in wave allFOVs
		
			// Now, skip lines until the next actual data line is reached
			Do
				FReadLine refNum, tmpStr 
				dataLine += 1																						// Update line value
				If (StringMatch(tmpStr, "[SCAN*") == 1 || strlen(tmpStr) == 0)						// Read the Trace file until you find [SCAN*
					Break 																							// No more lines to be read, break
				Endif			
			While (1)
			
		EndFor	// All N_SCAN file names obtained and stored in "allNames"
		
		Wave/T FileNames = allNames					// Rename text wave containing all file names to be loaded
		KillWaves/Z FOVs									// Kill the one entry wave containing the last FOV value
		Rename allFOVs, FOVs								// Rename the wave containing all FOV values
		
#If (IgorVersion() < 8.00) 
	ESCA_RemoveQuoteFromWaves(FileNames)			// for versions earlier than Igor 8: loop through each element and remove quotation marks
#EndIf

		// For the Later versions of ProNanoESCA: store the unit length per Ångstrøm conversion factor for each given scan
		If(stringMatch(sftwStr, "2.15.99") == 1) 	// NTNU QuSpin
			Wave FOVs										// Obtain wave reference to the FOVs (default is microns)
			Duplicate/O FOVs, micronsPerPx			// Store the conversion factor between FOV (in um) and pixels for each FOV value
			micronsPerPx /= npx_FOV						// No. micrometer or pixel for each given scan
			
			// If ARPES, rename wave
			If(FOV_MODE == 2)								
				Rename micronsPerPx, InvAngstromPerPx
			EndIf
				
		EndIf

	EndIf	// END: type of loading style ("Image" or "Sum" vs. "Scan")
	
	//-------------------------------------------------------------------------------------------
	// Part IV: Get rid of potential space at the beginning of each file name
	//-------------------------------------------------------------------------------------------
			
	String fnstr = FileNames[0]	
	
	String tempd
	Variable t	

	If (stringmatch(fnstr, " *") == 1) // Any space in front of the name
		Print "PAY ATTENTION, SPACE IN THE FILE NAME"
		For(t=0; t<dimsize(FileNames,0); t+=1)
			tempd = FileNames[t]
			FileNames[t] = tempd[1, strlen(tempd) -1]
		Endfor
	Endif
	
	//-------------------------------------------------------------------------------------------
	// Part V: Clean up, return a reference to the wave containing the file names
	//-------------------------------------------------------------------------------------------
		
	Close/A //Close the refnumber

	String trcStr = "Trace loaded:" + traceStr
	Print trcStr
	
	SetDataFolder root:		// Return to root folder
	Return FileNames
	
End

//=========================================================================================================//

Function/S ESCADoOpenFileDialog() // Open file dialog, return path string
	Variable refNum
	String message = "Select a file"
	String outputPath
	String fileFilters = "Data Files (*.txt,*.dat,*.csv,*.ibw,*.JPG,*.jpeg,*.bmp,*.tif):.txt,.dat,.csv,.ibw,.JPG,.jpeg,.bmp,.tif;"
	fileFilters += "All Files:.*;"

	Open /D /R /F=fileFilters /M=message refNum
	outputPath = S_fileName
		
	Return outputPath		// Will be empty if user canceled
End

//=========================================================================================================//

Function/S ESCA_GetSoftwareVersion(refNum)
	Variable refNum
			
	String tmpStr = ""
	String/G Software
			
	Do //Read the Trace file until find PROGRAM_VERSION*
		FReadLine refNum, tmpStr 
			If (StringMatch(tmpStr, "PROGRAM_VERSI*") == 1 || strlen(tmpStr) == 0)
				Break // No more lines to be read
			Endif
	While (1)

	Variable var
	Sscanf tmpStr, "PROGRAM_VERSION = \"%s", tmpStr // sscanf ==> find num into string expression
	software = tmpStr[0,StrLen(tmpStr)-2]
	FSetPos refNum, 0 // Set the file position to 0 (beginning)
	String printstr = "Software version: " + software
	Return software
			
End

//=========================================================================================================//


Function ESCA_GetContrastAperture(refNum)
	Variable refNum
	String tmpStr
	Variable/G ContrastAperture

	Do //Read the Trace file until find CONTRAST_APERTURE*
		FReadLine refNum, tmpStr 
		If (StringMatch(tmpStr, "CONTRAST_APER*") == 1 || strlen(tmpStr) == 0)
			Break // No more lines to be read
		Endif
	While (1)
			
	Sscanf tmpStr, "CONTRAST_APERTURE = %f", ContrastAperture // sscanf ==> find num into string expression
	String nsStr =  "Contrast Aperture: " + num2str(ContrastAperture) + "um"
	Print nsStr
	FSetPos refNum, 0 // Set the file position to 0 (beginning)		
	
	Return ContrastAperture
			
End

//=========================================================================================================//


Function ESCA_GetBinning(refNum)
	Variable refNum
	String tmpStr
	String/G Binning
	Variable BinningVar

	Do //Read the Trace file until find BINNING*
		FReadLine refNum, tmpStr 
		If (StringMatch(tmpStr, "BINNI*") == 1 || strlen(tmpStr) == 0)
			Break // No more lines to be read
		Endif
	While (1)
			
	Sscanf tmpStr, "BINNING = %f", BinningVar // sscanf ==> find num into string expression
	Binning = num2str(BinningVar) + "x" + num2str(BinningVar)
	String nsStr =  "Binning: " + Binning
	Print nsStr
	FSetPos refNum, 0 // Set the file position to 0 (beginning)		
	
	Return BinningVar
End

//=========================================================================================================//

Function/S ESCA_GetAxisName(refNum)
	Variable refNum
			
	String tmpStr = ""
	String/G axname
			
	Do //Read the Trace file until find AXIS_NAME*
		FReadLine refNum, tmpStr 
			If (StringMatch(tmpStr, "AXIS_NAM*") == 1 || strlen(tmpStr) == 0)
				Break // No more lines to be read
			Endif
	While (1)

	Variable var
	Sscanf tmpStr, "AXIS_NAME = \"%s", tmpStr // sscanf ==> find num into string expression
	axname = tmpStr[0,StrLen(tmpStr)-2]
	FSetPos refNum, 0 // Set the file position to 0 (beginning)
	String printstr = "Axis name: " + axname
	Print printstr
	
	Return axname
			
End

//=========================================================================================================//

Function ESCA_GetMagnification(refNum)
	Variable refNum
	String tmpStr
	Variable/G M_FOV

	Do //Read the Trace file until find M_FOV
		FReadLine refNum, tmpStr 
		If (StringMatch(tmpStr, "M_FO*") == 1 || strlen(tmpStr) == 0)
			Break // No more lines to be read
		Endif
	While (1)
			
	Sscanf tmpStr, "M_FOV = %f", M_FOV // sscanf ==> find num into string expression
	String printstr =  "M_FOV: " + num2str(M_FOV)
	Print printstr
	FSetPos refNum, 0 // Set the file position to 0 (beginning)		
	
	Return M_FOV
End

//=========================================================================================================//

Function ESCA_GetFOVMode(refNum)
	Variable refNum
	String tmpStr
	Variable/G FOV_MODE

	Do //Read the Trace file until find FOV_MODE
		FReadLine refNum, tmpStr 
		If (StringMatch(tmpStr, "FOV_MO*") == 1 || strlen(tmpStr) == 0)
			Break // No more lines to be read
		Endif
	While (1)
			
	Sscanf tmpStr, "FOV_MODE = %f", FOV_MODE // sscanf ==> find num into string expression
	String printstr =  "FOV_MODE: " + num2str(FOV_MODE)
	Print printstr
	FSetPos refNum, 0 // Set the file position to 0 (beginning)		
	
	Return FOV_MODE
End

//=========================================================================================================//

Function ESCA_GetDetectorSize(refNum)
	Variable refNum
	String tmpStr
	Variable/G DET_SIZE

	Do //Read the Trace file until find DET_SIZE*
		FReadLine refNum, tmpStr 
		If (StringMatch(tmpStr, "DET_SI*") == 1 || strlen(tmpStr) == 0)
			Break // No more lines to be read
		Endif
	While (1)
			
	Sscanf tmpStr, "DET_SIZE = %f", DET_SIZE // sscanf ==> find num into string expression
	String printstr =  "DET_SIZE: " + num2str(DET_SIZE)
	Print printstr
	FSetPos refNum, 0 // Set the file position to 0 (beginning)		
	
	Return DET_SIZE
End

//=========================================================================================================//

Function ESCA_GetNumScans(refNum)
	Variable refNum
	String tmpStr
	Variable/G N_SCAN

	Do //Read the Trace file until you find N_SCAN*
		FReadLine refNum, tmpStr 
		If (StringMatch(tmpStr, "N_SCA*") == 1 || strlen(tmpStr) == 0)
			Break // No more lines to be read
		Endif
	While (1)
			
	Sscanf tmpStr, "N_SCAN = %f", N_SCAN // sscanf ==> find num into string expression
	String printstr =  "N_SCAN: " + num2str(N_SCAN)
	Print printstr
	FSetPos refNum, 0 // Set the file position to 0 (beginning)		
	
	Return N_SCAN
End
//=========================================================================================================

// Takes in a text wave generated from 
Function ESCA_RemoveQuoteFromWaves(w)
//Local variable
Wave/T w
Variable j = 0
String wstr, removestr
Variable maxL = DimSize(w, 0)

	Do
	 	If (j == maxL) 
			break						// No more points in the wave
		Endif
		wstr = w[j]
		variable n=strlen(wstr)
		wstr = wstr[0,n-2]
		wstr = wstr[1,n-1]
		w[j] = wstr
		j += 1
	While (1)
End

//=========================================================================================================

// =========================== Image Normalization and corrections upon loading ============================

// Removes darkfield for input wave w, if global variable darkfield == 1	
Function ESCA_removeDF(w,dataDest,notify)
	Wave w // Input wave
	String dataDest
	Variable notify		// 1 = print message to command line, 0 = suppress message
	Nvar darkfield = root:ESCAglobals:darkfield
	
	String oldDF = GetDataFolder(1)
	
	SetDataFolder root:$(dataDest)		// Navigate to data folder
	Variable np = dimsize(w,0) 			// Number of x pixels = rows of w
	Variable nq = dimsize(w,1) 			// Number of y pixels = columns of w
	
	If(darkfield)
		
		// Define 2D ROI wave with same dimensions as image, set all points= 1
		make/N=(np,nq)/o/b/u tmpROI
		tmpROI = 1
		
		// Define four corners of the ROI and set their value = 0
		variable rp=round(np/32)
		variable rq=round(np/32)
		tmpROI[0,rp][0,rq]=0
		tmpROI[np-1-rp,np-1][0,rq]=0
		tmpROI[0,rp][nq-1-rq,nq-1]=0
		tmpROI[np-1-rp,np-1][nq-1-rq,nq-1]=0
		
		// Fnid average intensity in the four corners of W,
		// overlapping with where ROI has been set to zero
		ImageStats/R=tmpROI w
		variable darkfieldvalue = V_avg
			
      w = max(w,darkfieldvalue)  // go through all pixels, setting the lower intensity to darkfieldvalue
		w = (w - darkfieldvalue)		// Subtract darkfield background
		
		If(notify)
			Printf "Darkfield correction performed on input wave %s", nameOfWave(w)	
		EndIF
		
		KillWaves/Z tmpROI // Kill temporary ROI wave
		
	Endif
	 
	// Restore data folder to root upon completion
	SetDataFolder $oldDF 

End

//=========================================================================================================



// =========================== Cutouts ==========================================


//doupdate!!!!


		// Get file info: Extract and store data folder and format, return file name without ending
		//String imageName = ESCA_getImgInfo(tempPath,dataPath,fileFormat)
		//dataPath = ParseFilePath(1, tempPath, ":", 1, 0) // Get path to folder containing the file.
		//fileFormat = "." + ParseFilePath(4, tempPath, ":", 0, 0)	// Extract file format (e.g. .tif)
		//String imageName = ParseFilePath(0, tempPath, ":", 1, 0) // Extract file name
		
		// Load image file, return name of 2D igor wave without ending
		//String message = "Opening image " + ImageName + fileFormat + " from " + dataPath
		//ImageString = ESCA_openImage(ImageName,dataPath,dataDest,fileFormat,message)
		
		// Obtain and print wave stats to command prompt
		//SetDataFolder $dataDest	// Navigate to destination folder
		//variable np=dimsize($ImageString,0) // Extract pixel dimensions
      //variable nq=dimsize($ImageString,1)	// Extract pixel dimensions
		//String imgSizeStr = "Image Size: (" + num2str(np) + ";" + num2str(nq) + ") px"
		//String imgSizeStr = ESCA_ImgStats(dataDest,ImageString)
		//Print imgSizeStr	// Print data size to command prompt