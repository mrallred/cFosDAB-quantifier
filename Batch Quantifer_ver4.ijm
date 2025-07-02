// ImageJ Macro to batch process images through cell-quantifcation workflows. Optimized for cFos DAB stained tissue. 
// Project directory must be set up properly before use. Use ROIProcessor Workflow to set up project and define the Regions of Interest, then run this macro to do the quantification.

// =============================================================================
// FUNCTIONS
// =============================================================================




// PROGRAM INITALIZATION

// Colors for ROI overlays
colors = newArray("#FF0000", "#0000FF", "#00FF00", "#FFFF00", "#FF00FF", "#00FFFF","#B300FF","48FF00");

// Prompt users to select working project directory and sets up files
waitForUser("Select Your Project directory", "Press OK and select the project folder where your files will be saved");

project_dir = getDirectory("Save");
project_csv_path = project_dir + "cell_counts.csv";
roi_dir = project_dir + File.separator + "ROI_files" + File.separator;
File.makeDirectory(roi_dir);


                



// MAIN PROCESSING LOOP

while (true) {
    // Prompt user to select the first image, stores file, path, directory and filename, and a list of files in dir. 
	open();
	path = getInfo("image.directory") + getInfo("image.filename");
	dir = getInfo("image.directory");
	file_name = getInfo("image.filename");
	roi_file_path = roi_dir + File.getNameWithoutExtension(file_name) + "_ROIs.zip";
	
    
	// Stores ID for first window and selects this image
	og_imageID = getImageID();
	selectImage(og_imageID);
	run("RGB Color");
	
	
	// Checks if an ROI exists and open the ROI manager
	if (File.exists(roi_file_path)) {
		roiManager("reset")
    	roiManager("Open", roi_file_path);
	} 
	run("ROI Manager...");
	
	
	// Prep ROI attributes
	setTool("polygon");
	RoiManager.useNamesAsLabels(true);
	run("Labels...", "color=white font=18 show bold");
	roiManager("show none");
	roiManager("show all with labels");
	
	// pause for user to define ROI
	waitForUser("Complete the following and then press OK: \n \n1. With the Polygon Selection tool, outline a Region of Interest.\n     The order regions are added into the manger determines the order the results will be output.\n     If regions are already created, adjust them by selecting the region in ROI manager and dragging the end points.\n	   To add points to an existing selection, (SHIFT+click) an existing point; (OPTION(Alt)+click) to remove a point \n2. Press Add(t) on the the ROI manager. \n3. Rename the region to its anatomical name.\n4. Repeat until all regions are selected and named, then press OK.");
	num_ROIs = roiManager("Count");
	
	// save ROIs to file
	if (num_ROIs > 0) {
   		roiManager("Save", roi_file_path);
		}
	
	// color ROIs
	for (i = 0; i < num_ROIs; i++) {
    	roiManager("Select", i);
    	Roi.setStrokeColor(colors[i % colors.length]);
    	Roi.setStrokeWidth(3);
    	roiManager("Update");
	}
	
	
	// Create maxima visualization image
	run("Select None");
	selectImage(og_imageID);
	run("Duplicate...", "title=CellDetectionVisualization");
	selectImage("CellDetectionVisualization");
	maxima_composite_ID = getImageID();
	
	// Prepare visualization image
	selectImage(maxima_composite_ID);
	run("RGB Color"); 
	run("Remove Overlay");
	
	// Split color channels, ID the windows
	selectImage(og_imageID);
	run("Split Channels");
	all_image_IDs = getImageIDs();
	green_ID = all_image_IDs[2];
	
	// Close extra images
	for (i = 0; i < all_image_IDs.length; i++) {
    	if (all_image_IDs[i] != green_ID && all_image_IDs[i] != maxima_composite_ID) { 
        	selectImage(all_image_IDs[i]);
        	close();
    	}
	}
	
	// Select green channel
	selectImage(green_ID);
	
	// Display ROI again 
	roiManager("Show All without labels");
	
	// Subtract Background
	run("Subtract Background...", "rolling=55 light sliding");
	
	// Apply Gaussian Blur
	run("Gaussian Blur...", "sigma=1.5");
	
//	// Enhance Contrast
//	run("Enhance Contrast...", "saturated=0.03 normalize");
	
	// Find maxima count and area for each ROI and output results
	for (i = 0; i < num_ROIs ; i++) {
		selectImage(green_ID);
	    roiManager("Select", i);
	    
	    // Find maxima for counting
	    run("Find Maxima...", "prominence=25 light output=Count");
	    row_index = nResults - 1;
    	
		// Find area and label of current ROI
		ROI_area = getValue("Area");
		ROI_label = Roi.getName();

	    // Add results to output
	    setResult("Area of ROI (pixels^2)", row_index, ROI_area);
	    setResult("ROI", row_index, ROI_label);
	    setResult("File name", row_index, file_name);
	    
	    updateResults();
	    
	    // Add ROI outlines to the overlay
    	selectImage(maxima_composite_ID);
    	roiManager("Select", i);
    	
    	 // Add ROI outline to overlay
    	Overlay.addSelection;
	 
	    // Find maxima for point selection overlay
	    selectImage(green_ID);
	    roiManager("Select", i);
	    run("Find Maxima...", "prominence=25 light output=[Point Selection]");
	    
	    // If points found (selection type 10), add them to overlay
	    if (selectionType() == 10) {
	    	getSelectionCoordinates(xpoints, ypoints);
	    	
	    	// Switch to visualization image and add overlay points
	    	selectImage(maxima_composite_ID);
	    	
	    	setForegroundColor(colors[i % colors.length]);
	    	for (j = 0; j < xpoints.length; j++) {
    			makeOval(xpoints[j]-1, ypoints[j]-1, 10, 10); // Small 3x3 circle
    			run("Fill", "slice");
			}
	    	
	    	run("Select None");
	    }
	}

	// Flatten image to burn overlays in and save to session_dir
	selectImage(maxima_composite_ID);
	roiManager("Show All with labels");
	run("Flatten");
	saveAs("PNG", session_dir + File.getNameWithoutExtension(file_name)+ "_cells_detected.png");
	close();
		
    // Ask user if they want to continue
    Dialog.create("Continue Processing?");
    Dialog.addMessage("Quantified image saved. Processing complete for this image.");
    Dialog.addCheckbox("Process another image?", true);
    Dialog.show();
    
    continueProcessing = Dialog.getCheckbox();
    
    // Close current images when done processing to prep for next image
    if (nImages > 0) {
    	close("*");
	} 
    
    // Kill script
    if (!continueProcessing) {
        break; // Exit the loop
    }
}

// After processing all images in the session, append results to project CSV
appendSessionToProjectCSV(project_csv_path, session_name, session_dir);

showMessage("Processing Complete", "Session '" + session_name + "' complete.\nResults have been appended to: " + project_csv_path);


