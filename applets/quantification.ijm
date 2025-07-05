// =============================================================================
// =============================================================================
// Quantification workflows and tools
// =============================================================================
// =============================================================================

// Colors for ROI overlays
colors = newArray("#FF0000", "#0000FF", "#00FF00", "#FFFF00", "#FF00FF", "#00FFFF", "#B300FF", "#48FF00");

// Initilize headers for result outputs as global variables
csv_header_findmaxima = "ID,File name,ROI,Area of ROI (px^2),Bregma,Count(FindMaxima)\n";
csv_header_ilastik = "ID,File name,ROI,Area of ROI (px^2),Bregma,Count(Ilastik)\n";

// GENERAL FUNCTIONS
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

function cleanUp() {
    close("*");
	run("Clear Results");
	roiManager("reset");
	close("Results");
	close("ROI Manager");
    close("Log");
}

function cleanupTempDirectory(temp_dir) {
    if (File.exists(temp_dir)) {
        temp_files = getFileList(temp_dir);
        for (i = 0; i < temp_files.length; i++) {
            File.delete(temp_dir + temp_files[i]);
        }
    }
}

// =============================================================================
// ILASTIK PROCESSING FUNCTIONS
// =============================================================================

// =============================================================================
// PROCESSOR FUNCTIONS
// =============================================================================

function processorFindMaxima(original_ID, original_name, workflow) {
	selectImage(original_ID);
	
	// Prepare CSV string
	csv = "";
	
	// Split Channels
	run("Split Channels");
	all_image_IDs = getImageIDs();
	green_ID = all_image_IDs[1];
	
	// Close extra images
	for (i = 0; i < all_image_IDs.length; i++) {
    	if (all_image_IDs[i] != green_ID) { 
        	selectImage(all_image_IDs[i]);
        	close();
    	}
	 }
	selectImage(green_ID);
	
	// Open ROI file, handle error if it doesn't exist
	roi_file_path = roi_dir + File.getNameWithoutExtension(original_name) + "_ROIs.zip";
	if (File.exists(roi_file_path)) {
		prepROILabels();
		num_ROIs = roiManager("Count");
		
		if (workflow == "single") {
        	waitForUser("Proceed to process?");
        	
        	// Save ROIs in case they were changed
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
    	roiManager("Select", i);
    	Overlay.addSelection;
	 
	    // Find maxima for point selection overlay
	    run("Find Maxima...", "prominence=25 light output=[Point Selection]");
	    
	    // If points found (selection type 10), add them to overlay
	    if (selectionType() == 10) {
	    	getSelectionCoordinates(xpoints, ypoints);
			
			// Add point overlays to image
			run("RGB Color");
	    	setForegroundColor(255,0,0);
	    	for (j = 0; j < xpoints.length; j++) {
    			makeOval(xpoints[j]-1, ypoints[j]-1, 5, 5); 
    			run("Fill", "slice");
			}
	    }
	    
	    // Append to csv - make sure all variables are converted to strings
		csv += toString(animal_ID) + "," + original_name + "," + ROI_label + "," + toString(ROI_area) + "," + toString(bregma) + "," + toString(count) + "\n";
	}
	// Show Overlays and burn into image
	Overlay.show()
	run("Flatten");
	
	// Return results of this processor as a csv string
	return csv;
}

function processorIlastik(original_ID, original_name, workflow) {
    
    // Prepare CSV string
	csv = "";

    // Open image
    selectImage(original_ID);

    // Split Channels
	run("Split Channels");
	all_image_IDs = getImageIDs();
	green_ID = all_image_IDs[1];

    // Close extra images
	for (i = 0; i < all_image_IDs.length; i++) {
    	if (all_image_IDs[i] != green_ID) { 
        	selectImage(all_image_IDs[i]);
        	close();
    	}
	 }
	selectImage(green_ID);
}

// =============================================================================
// WORKFLOW FUNCTIONS
// =============================================================================

function singleImageWorkflow(image_list, processor) {
	if (image_list.length == 0) {
		exit("No images found in input_images folder.");
	}
	
	// Create Dialog to select image
	Dialog.create("Select an Image");
	Dialog.addChoice("Image: ", image_list, image_list[0]);
	Dialog.show();
	
	selected_image_name = Dialog.getChoice();
	selected_image_name_no_ext = File.getNameWithoutExtension(selected_image_name);
	selected_image_path = input_image_dir + selected_image_name;
	
	open(selected_image_path);
	selected_ID = getImageID();
	
	// Run correct processor
	if (processor == "findmaxima"){
		results = processorFindMaxima(selected_ID, selected_image_name, "single");
		final_csv = csv_header_findmaxima + results;
		suffix = "_findmaxima_processed";
	} else if (processor == "ilastik") {
		results = processorIlastik(selected_ID, selected_image_name, "single");
		final_csv = csv_header_ilastik + results;
        suffix = "_ilastik_processed"; 
	}
	
	
	// Save csv and overlay image
	File.saveString(final_csv, results_dir + selected_image_name_no_ext + suffix + ".csv");
	saveAs("Tiff", output_image_dir + selected_image_name_no_ext + suffix); 
	
	// Close all
	close("*");
	run("Clear Results");
	roiManager("reset");
	close("*");
	close("Results");
	close("ROI Manager");
}

function batchWorkflow(image_list, processor) {
	// Ensure images in list
	if (image_list.length == 0) {
		exit("No images found in input_images folder.");
	}
	
	// Initialize csv and suffix
    if (processor == "findmaxima") {
        batch_csv_str = csv_header_findmaxima;
        suffix = "_findmaxima_batch_processed";
    } else if (processor == "ilastik") {
        batch_csv_str = csv_header_ilastik;
        suffix = "_ilastik_batch_processed";
    }
    
    // Progress tracking
    start_time = getTime();
	
	// go through all images in project input_image list
	for (i=0; i < image_list.length; i++) {
		progress = (i + 1) / image_list.length * 100;
        showProgress(progress / 100);
        showStatus("Processing image " + (i + 1) + " of " + image_list.length + " (" + d2s(progress, 1) + "%)");
        
		// Extract paths and names for current image
		selected_image_name = image_list[i];
		selected_image_name_no_ext = File.getNameWithoutExtension(selected_image_name);
		selected_image_path = input_image_dir + selected_image_name;
		
		open(selected_image_path);
		selected_ID = getImageID();
		
		// Run correct processor
        if (processor == "findmaxima") {
            results = processorFindMaxima(selected_ID, selected_image_name, "batch");
        } else if (processor == "ilastik") {
            results = processorIlastik(selected_ID, selected_image_name, "batch");
        }
		
		batch_csv_str += results;
		
		saveAs("Tiff", output_image_dir + selected_image_name_no_ext +"_batch_processed");
		
		// Clean up windows
		close("*");
		run("Clear Results");
		roiManager("reset");
		close("*");
		close("Results");
		close("ROI Manager");
		
		// Memory cleanup
        run("Collect Garbage");
	}
	// Save aggregated csv to results.csv
	File.saveString(batch_csv_str, results_path);
	
	// Show completion time
    end_time = getTime();
    processing_time = (end_time - start_time) / 1000; // Convert to seconds
    showMessage("Batch Processing Complete", 
                "Processed " + image_list.length + " images in " + d2s(processing_time, 1) + " seconds\n" +
                "Average: " + d2s(processing_time / image_list.length, 1) + " seconds per image");
}
// =============================================================================
// RECOVER PASSED VARIABLES
// =============================================================================

PASSED_ARG = getArgument();

if (PASSED_ARG == "") {
    exit("Error: No argument string received by this macro.");
}

// Assign arg back to individual variables
parts = split(PASSED_ARG, ",");
type = parts[0];
MAIN_DIR = parts[1];
APPLET_DIR = parts[2];
MODEL_DIR = parts[3];
QUANTIFICATION_PATH = parts[4];
SETUP_PATH = parts[5];
MAIN_SUITE_PATH = parts[6];

project_name = parts[7];
project_dir = parts [8];
bregma_path = parts[9];
results_dir = parts[10];
results_path = parts[11];
roi_dir = parts[12];
input_image_dir = parts[13];
output_image_dir = parts[14];
temp_dir = parts[15];
ilastik_models_dir = parts[16];


// =============================================================================
//                                 MAIN 
// =============================================================================
// Cleanup workspace
cleanUp();

// Generate image file list and its length
image_list = Array.sort(getFileList(input_image_dir));
num_images = image_list.length;

// Initialize main dialog/workflow selection
workflows = newArray(
    "Process Single Image (FindMaxima)", 
    "Process Single Image (Ilastik)", 
    "Process All Images (FindMaxima)", 
    "Process All Images (Ilastik)", 
    "Quit Image Processor");
continue_loop = true;

while (continue_loop){
    Dialog.create("Select Workflow");
    Dialog.addMessage("Project " + project_name + " is loaded. ");
    Dialog.addMessage("- Project directory: " + project_dir);
    Dialog.addMessage("- Number of images: " + num_images);
    Dialog.addMessage("- First Image: " + image_list[0]);
    Dialog.addMessage("- Last Image: " + image_list[image_list.length-1]); 
    Dialog.addChoice("\nSelect what you want to do: ", workflows);
    Dialog.show();

    action = Dialog.getChoice();
    
    if (action == "Process Single Image (FindMaxima)") {
        singleImageWorkflow(image_list, "findmaxima");
    } else if (action == "Process Single Image (Ilastik)") {
        singleImageWorkflow(image_list, "ilastik");
    } else if (action == "Process All Images (FindMaxima)") {
        batchWorkflow(image_list, "findmaxima");
    } else if (action == "Process All Images (Ilastik)") {
        batchWorkflow(image_list, "ilastik");
    } else if (action == "Quit Image Processor") {
        continue_loop = false;
    }
}
exit("Finished Processing. Macro will close.");


