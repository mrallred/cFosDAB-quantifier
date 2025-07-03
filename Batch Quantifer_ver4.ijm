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

function prepROILabels() {
		roiManager("reset");
		roiManager("Open", roi_file_path);
		run("ROI Manager...");
		RoiManager.useNamesAsLabels(true);
		run("Labels...", "color=white font=18 show bold");
        roiManager("show all with labels");
      
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

function processorFindMaxima(original_ID, original_name, workflow) {
	selectImage(original_ID);
	output_name = getTitle() + "_FM_Output";
	
	// Prepare output image
	run("Duplicate...", "title="+output_name);
	selectImage(output_name);
	output_ID = getImageID();
	
	// Prepare CSV string
	csv = "";
	
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
		prepROILabels();
		
		if (workflow == "single") {
        	waitForUser("Proceed to process?");
        	
        	// Save ROIs in case they were changed
        	num_ROIs = roiManager("Count");
        	if (num_ROIs > 0) {
   				roiManager("Save", roi_file_path);
			}
		}	
	} else {
		exit("ROI file does not exist for this image. Ensure it is named properly and in the correct folder."
	}
	
	// Preprocess Image
	run("Subtract Background...", "rolling=55 light sliding");
	run("Gaussian Blur...", "sigma=1.5");
	
	// Find maxima count and area for each ROI and output results
	for (i = 0; i < num_ROIs ; i++) {
		selectImage(green_ID);
	    roiManager("Select", i);
	    
	    // Find maxima count
	    run("Find Maxima...", "prominence=25 light output=Count");
	    count = getResult("Count", nResults - 1);
	    
		// Find various values for output
		ROI_area = getValue("Area");
		ROI_label = Roi.getName();
		bregma = getBregmaValue(bregma_path, original_name);
		file_name_parts = split(original_name, "_");
		animal_ID = file_name_parts[0];
		
	    // Add ROI overlay
    	selectImage(output_ID);
    	roiManager("Select", i);
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
    			makeOval(xpoints[j]-1, ypoints[j]-1, 5, 5); 
    			run("Fill", "slice");
			}
	    }
	    
	    // Append to csv - make sure all variables are converted to strings
		csv += toString(animal_ID) + "," + original_name + "," + ROI_label + "," + toString(ROI_area) + "," + toString(bregma) + "," + toString(count) + "\n";
	}
	
	// Return results of this processor as a csv string
	print(csv);
	return csv;
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
	results = processorFindMaxima(original_ID, selected_image_name, "single");
	final_csv = csv_header + results;
	File.saveString(final_csv, project_dir+selected_image_name+"_processed.csv");
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
	
	// Define csv headers for output
	csv_header = "ID,File name,ROI,Area of ROI (px^2),Bregma,Count\n";

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


