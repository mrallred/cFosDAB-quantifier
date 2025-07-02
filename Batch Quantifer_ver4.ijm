// ImageJ Macro to batch process images through cell-quantifcation workflows. Optimized for cFos DAB stained tissue. 
// Project directory must be set up properly before use. Use ROIProcessor Workflow to set up project and define the Regions of Interest, then run this macro to do the quantification.

// Colors for ROI overlays
colors = newArray("#FF0000", "#0000FF", "#00FF00", "#FFFF00", "#FF00FF", "#00FFFF","#B300FF","48FF00");

// =============================================================================
// FUNCTIONS
// =============================================================================
function getImageIDs() {
    ids = newArray(nImages);
    for (i = 0; i < nImages; i++) {
        selectImage(i + 1);  // Select by position (1-indexed)
        ids[i] = getImageID();
    }
    return ids;
}

function getBregmaValue(bregma_path, file_name) {
    if (!File.exists(bregma_path)) {
        return "";
    }
    
    content = File.openAsString(bregma_path);
    lines = split(content, "\n");
    
    for (i = 1; i < lines.length; i++) { // Skip header
        if (lines[i].length > 0) {
            parts = split(lines[i], ",");
            if (parts.length >= 2 && parts[0] == file_name) {
                return parts[1];
            }
        }
    }
    
    return ""; // Filename not found
}

function selectProjectDirectory() {
	waitForUser("Select Your Project Directory", 
                "Press OK and select an existing project.\n" +
                "This project should have been set up by the ROI_processor macro.");

	project_dir = getDirectory("Select Project Directory");

	if (project_dir == "") {
        return false;
    } else {
		return project_dir;
	}
}

function checkProjectSetup(project_dir, results_path, bregma_path, roi_dir, input_image_dir, output_image_dir) {
	missing = "";

	if (!File.exists(bregma_path)) missing += "- Missing: bregma_values.csv\n";
	if (!File.exists(results_path)) missing += "- Missing: results.csv\n";
	if (!File.exists(roi_dir)) missing += "- Missing folder: ROI_files\n";
	if (!File.exists(input_image_dir)) missing += "- Missing folder: Input_images\n";
	if (!File.exists(output_image_dir)) missing += "- Missing folder: Output_images\n";

	return missing;
}

function processorFindMaxima(original_ID, original_name) {
	selectImage(original_ID);
	output_name = getTitle() + "_FM_Output";
	
	// Prepare output image
	run("Duplicate...", "title="+output_name);
	selectImage(output_name);
	output_ID = getImageID();
	
	// Process original image
	
	// Split Channels
	selectImage(original_ID);
	run("Split Channels");
	all_image_IDs = getImageIDs();
	green_ID = all_image_IDs[2];
	
	// Close extra images
	for (i = 0; i < all_image_IDs.length; i++) {
    	if (all_image_IDs[i] != green_ID && all_image_IDs[i] != output_ID) { 
        	selectImage(all_image_IDs[i]);
        	close();
    	}
	 }
	selectImage(green_ID);
	
	// Open ROI file, handle error if it doesn't exist
	roi_file_path = roi_dir + File.getNameWithoutExtension(original_name) + "_ROIs.zip";
	if (File.exists(roi_file_path)) {
		roiManager("reset");
		roiManager("Open", roi_file_path);
		run("ROI Manager...");
		roiManager("Show All");
        roiManager("show all with labels");
      
        waitForUser("Proceed to process?");
        
        // Save ROIs in case they were changed
        num_ROIs = roiManager("Count");
        if (num_ROIs > 0) {
   			roiManager("Save", roi_file_path);
		}	
	} else {
		exit("ROI file does not exist for this image. Ensure it is named properly and in the correct folder."
	}
	
	//Subtract background
	run("Subtract Background...", "rolling=55 light sliding");

	// Apply Gaussian Blur
	run("Gaussian Blur...", "sigma=1.5");
	
	// Find maxima count and area for each ROI and output results
	for (i = 0; i < num_ROIs ; i++) {
		selectImage(green_ID);
	    roiManager("Select", i);
	    
	    // Find maxima for counting
	    run("Find Maxima...", "prominence=25 light output=Count");
	    row_index = nResults - 1;
    	
		// Find area and label of current ROI and bregma value
		ROI_area = getValue("Area");
		ROI_label = Roi.getName();
		bregma = getBregmaValue(bregma_path, original_name);
		file_name_parts = split(original_name, "_");
		animal_ID = file_name_parts[0];
		
	    // Add results to output
	    setResult("ID", row_index, animal_ID);
	    setResult("File name", row_index, original_name);
	    setResult("ROI", row_index, ROI_label);
	    setResult("Area of ROI (px^2)", row_index, ROI_area);
	    setResult("Bregma", row_index, bregma);
	    
	    updateResults();
	    
	    // Add ROI outlines to the overlay
    	selectImage(output_ID);
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
	    	selectImage(output_ID);
	    	
	    	setForegroundColor(colors[i % colors.length]);
	    	for (j = 0; j < xpoints.length; j++) {
    			makeOval(xpoints[j]-1, ypoints[j]-1, 10, 10); // Small 3x3 circle
    			run("Fill", "slice");
			}
	    	
	    	
	    }
	}	
}

function singleImageWorkflow(image_list) {
	if (image_list.length == 0) {
		exit("No images found in input_images folder.");
	}
	
	// Create Dialog to select image
	Dialog.create("Select an Image");
	Dialog.addChoice("Image: ", image_list, image_list[0]);
	Dialog.show();
	
	selected_image_name = Dialog.getChoice();
	selected_image_path = input_image_dir + selected_image_name;
	
	open(selected_image_path);
	original_ID = getImageID();
	
	// Run processor
	processorFindMaxima(original_ID, selected_image_name);
	print("Image Processed");
}


// =============================================================================
// MAIN PROGRAM
// =============================================================================

macro "Project Batch Processor" {
	// Program set-up
	close("*");
    run("Clear Results");
    roiManager("reset");

	// Prompt users to select working project directory
	project_dir = false;
    while (project_dir == false) {
		project_dir = selectProjectDirectory();
		if (project_dir == false) {
        showMessage("Invalid Selection", 
                    "Error getting project directory path.\n" +
                    "Please try again and ensure you are selecting a proper directory.");
    	}
	}
	// Valid directory found
	print("Selected project directory: " + project_dir);
	project_name = File.getName(project_dir);

	// Define Paths for project
	bregma_path = project_dir + "bregma_values.csv";
    results_path = project_dir + "results.csv";
    roi_dir = project_dir + "ROI_files" + File.separator;
    input_image_dir = project_dir + "Input_images" + File.separator;
    output_image_dir = project_dir + "Output_images" + File.separator;

	// Ensure Project is correctly setup before beginning
	missing = checkProjectSetup(project_dir, results_path, bregma_path, roi_dir, input_image_dir, output_image_dir);
	if (missing != "") {
		exit("Project directory is missing required components:\n" + missing + "\nPlease Fix project folder and rerun macro.");
	} 
	
	// Generate image file list and its length
	image_list = Array.sort(getFileList(input_image_dir));
	num_images = image_list.length;

	// Initialize main dialog/workflow selection
	workflows = newArray("Process Single Image", "Process all images in project", "Quit Macro");
	
	Dialog.create("Select Workflow");
	Dialog.addMessage("Project " + project_name + " is loaded. ");
	Dialog.addMessage("- Project path: " + project_dir);
	Dialog.addMessage("- Number of images: " + num_images);
	Dialog.addMessage("- First Image: " + image_list[0]); 
	Dialog.addMessage("- Last Image: " + image_list[image_list.length-1]); 
	Dialog.addChoice("\nSelect what you want to do: ", workflows);
	Dialog.show();

	action = Dialog.getChoice();
	
	if (action == "Process Single Image"){
		singleImageWorkflow(image_list);
	}
	else if (action == "Process all images in project"){
		continue;
	}
	else if (action == "Quit Macro"){
		continue;
	}


}






















//// Prompt users to select working project directory and sets up files
//waitForUser("Select Your Project directory", "Press OK and select the directory where you're project was setup");
//
//project_dir = getDirectory("Save");
//roi_dir = project_dir + File.separator + "ROI_files" + File.separator;
//
//
//                
//
//
//
//// MAIN PROCESSING LOOP
//
//while (true) {
//    // Prompt user to select the first image, stores file, path, directory and filename, and a list of files in dir. 
//	open();
//	path = getInfo("image.directory") + getInfo("image.filename");
//	dir = getInfo("image.directory");
//	file_name = getInfo("image.filename");
//	roi_file_path = roi_dir + File.getNameWithoutExtension(file_name) + "_ROIs.zip";
//	
//    
//	// Stores ID for first window and selects this image
//	og_imageID = getImageID();
//	selectImage(og_imageID);
//	run("RGB Color");
//	
//	
//	// Checks if an ROI exists and open the ROI manager
//	if (File.exists(roi_file_path)) {
//		roiManager("reset")
//    	roiManager("Open", roi_file_path);
//	} 
//	run("ROI Manager...");
//	
//	
//	// Prep ROI attributes
//	setTool("polygon");
//	RoiManager.useNamesAsLabels(true);
//	run("Labels...", "color=white font=18 show bold");
//	roiManager("show none");
//	roiManager("show all with labels");
//	
//	// pause for user to define ROI
//	waitForUser("Complete the following and then press OK: \n \n1. With the Polygon Selection tool, outline a Region of Interest.\n     The order regions are added into the manger determines the order the results will be output.\n     If regions are already created, adjust them by selecting the region in ROI manager and dragging the end points.\n	   To add points to an existing selection, (SHIFT+click) an existing point; (OPTION(Alt)+click) to remove a point \n2. Press Add(t) on the the ROI manager. \n3. Rename the region to its anatomical name.\n4. Repeat until all regions are selected and named, then press OK.");
//	num_ROIs = roiManager("Count");
//	
//	// save ROIs to file
//	if (num_ROIs > 0) {
//   		roiManager("Save", roi_file_path);
//		}
//	
//	// color ROIs
//	for (i = 0; i < num_ROIs; i++) {
//    	roiManager("Select", i);
//    	Roi.setStrokeColor(colors[i % colors.length]);
//    	Roi.setStrokeWidth(3);
//    	roiManager("Update");
//	}
//	
//	
//	// Create maxima visualization image
//	run("Select None");
//	selectImage(og_imageID);
//	run("Duplicate...", "title=CellDetectionVisualization");
//	selectImage("CellDetectionVisualization");
//	maxima_composite_ID = getImageID();
//	
//	// Prepare visualization image
//	selectImage(maxima_composite_ID);
//	run("RGB Color"); 
//	run("Remove Overlay");
//	
//	// Split color channels, ID the windows
//	selectImage(og_imageID);
//	run("Split Channels");
//	all_image_IDs = getImageIDs();
//	green_ID = all_image_IDs[2];
//	
//	// Close extra images
//	for (i = 0; i < all_image_IDs.length; i++) {
//    	if (all_image_IDs[i] != green_ID && all_image_IDs[i] != maxima_composite_ID) { 
//        	selectImage(all_image_IDs[i]);
//        	close();
//    	}
//	}
//	
//	// Select green channel
//	selectImage(green_ID);
//	
//	// Display ROI again 
//	roiManager("Show All without labels");
//	
//	// Subtract Background
//	run("Subtract Background...", "rolling=55 light sliding");
//	
//	// Apply Gaussian Blur
//	run("Gaussian Blur...", "sigma=1.5");
//	
////	// Enhance Contrast
////	run("Enhance Contrast...", "saturated=0.03 normalize");
//	
//	// Find maxima count and area for each ROI and output results
//	for (i = 0; i < num_ROIs ; i++) {
//		selectImage(green_ID);
//	    roiManager("Select", i);
//	    
//	    // Find maxima for counting
//	    run("Find Maxima...", "prominence=25 light output=Count");
//	    row_index = nResults - 1;
//    	
//		// Find area and label of current ROI
//		ROI_area = getValue("Area");
//		ROI_label = Roi.getName();
//
//	    // Add results to output
//	    setResult("Area of ROI (pixels^2)", row_index, ROI_area);
//	    setResult("ROI", row_index, ROI_label);
//	    setResult("File name", row_index, file_name);
//	    
//	    updateResults();
//	    
//	    // Add ROI outlines to the overlay
//    	selectImage(maxima_composite_ID);
//    	roiManager("Select", i);
//    	
//    	 // Add ROI outline to overlay
//    	Overlay.addSelection;
//	 
//	    // Find maxima for point selection overlay
//	    selectImage(green_ID);
//	    roiManager("Select", i);
//	    run("Find Maxima...", "prominence=25 light output=[Point Selection]");
//	    
//	    // If points found (selection type 10), add them to overlay
//	    if (selectionType() == 10) {
//	    	getSelectionCoordinates(xpoints, ypoints);
//	    	
//	    	// Switch to visualization image and add overlay points
//	    	selectImage(maxima_composite_ID);
//	    	
//	    	setForegroundColor(colors[i % colors.length]);
//	    	for (j = 0; j < xpoints.length; j++) {
//    			makeOval(xpoints[j]-1, ypoints[j]-1, 10, 10); // Small 3x3 circle
//    			run("Fill", "slice");
//			}
//	    	
//	    	run("Select None");
//	    }
//	}
//
//	// Flatten image to burn overlays in and save to session_dir
//	selectImage(maxima_composite_ID);
//	roiManager("Show All with labels");
//	run("Flatten");
//	saveAs("PNG", session_dir + File.getNameWithoutExtension(file_name)+ "_cells_detected.png");
//	close();
//		
//    // Ask user if they want to continue
//    Dialog.create("Continue Processing?");
//    Dialog.addMessage("Quantified image saved. Processing complete for this image.");
//    Dialog.addCheckbox("Process another image?", true);
//    Dialog.show();
//    
//    continueProcessing = Dialog.getCheckbox();
//    
//    // Close current images when done processing to prep for next image
//    if (nImages > 0) {
//    	close("*");
//	} 
//    
//    // Kill script
//    if (!continueProcessing) {
//        break; // Exit the loop
//    }
//}
//
//// After processing all images in the session, append results to project CSV
//appendSessionToProjectCSV(project_csv_path, session_name, session_dir);
//
//showMessage("Processing Complete", "Session '" + session_name + "' complete.\nResults have been appended to: " + project_csv_path);


