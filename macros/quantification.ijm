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
csv_header_manual = "ID,File name,ROI,Area of ROI (px^2),Bregma,Count(Manual)\n";

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
	close("Summary");
}

function cleanUpDirectory(dir) {
    if (File.exists(dir)) {
        files = getFileList(dir);
        for (i = 0; i < files.length; i++) {
            File.delete(dir + files[i]);
        }
    }
}

// =============================================================================
// ILASTIK PROCESSING FUNCTIONS
// =============================================================================

function chooseModel() {
	model_list = getFileList(MODEL_DIR);

	Dialog.create("Select a Ilastik model");
	Dialog.addChoice("Model: ", model_list, model_list[0]);
	Dialog.show();
	
	selected_model_name = MODEL_DIR + Dialog.getChoice();
	return selected_model_name;
}

function saveIlastikOutput(output_path) {
	saveAs("Tiff", output_path);
}

function runPixelClassification(model, image_name) {
	// Process With ilastik
	run("Run Pixel Classification Prediction", "projectfilename=[" + model + "] input=[" + image_name + "] pixelclassificationtype=[" + "Probabilities"+ "]");

	// Split channels of processed probability map image
	run("Split Channels");
	channel_IDs = getImageIDs();
	c2_ID = channel_IDs[3];

	// Close extra images
	for (i = 0; i < channel_IDs.length; i++) {
    	if (channel_IDs[i] != c2_ID) { 
        	selectImage(channel_IDs[i]);
        	close();
    	}
	 }
	selectImage(c2_ID);
}
function isOpen(imageID) {
    // Check if an image with given ID is still open
    if (imageID == 0) return false;
    
    currentImages = getImageIDs();
    for (i = 0; i < currentImages.length; i++) {
        if (currentImages[i] == imageID) {
            return true;
        }
    }
    return false;
}
// =============================================================================
// PROCESSOR FUNCTIONS
// =============================================================================

function processorFindMaxima(original_ID, original_name, roi_file_path, workflow) {
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
	if (File.exists(roi_file_path)) {
		prepROILabels();
		num_ROIs = roiManager("Count");
		
		if (workflow == "single") {
        	waitForUser("You can adjust ROIs here if needed. Proceed to process?");
        	
        	// Save ROIs in case they were changed
        	if (num_ROIs > 0) {
   				roiManager("Save", roi_file_path);
			}
		}	
	} else {
		exit("ROI file does not exist for this image. Ensure it is named properly and in the correct folder.");
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

function processorIlastik(original_ID, original_name, roi_file_path, workflow, model_path) {
    // Initialize CSV string and get file_name wo extension
	csv = "";
	name = File.getNameWithoutExtension(original_name);

	// prepare duplicate for visualization
    selectImage(original_ID);
	run("Duplicate...", "title="+name+"_OGDup");
	dup_ID = getImageID();

	selectImage(original_ID);

    // Split Channels
	run("Split Channels");
	rgb_IDs = getImageIDs();
	green_ID = rgb_IDs[2];

    // Close extra images and rename green channel back to og name
	for (i = 0; i < rgb_IDs.length; i++) {
    	if (rgb_IDs[i] != green_ID && rgb_IDs[i] != dup_ID) { 
        	selectImage(rgb_IDs[i]);
        	close();
    	}
	 }

	selectImage(green_ID);
	rename(original_name);
	

	// Check if a ilastik output exist, load it if so, otherwise run the classification
	output_path = ilastik_output_dir + name + "_probability_map.tif";
	if (!File.exists(output_path)) {
		runPixelClassification(model_path, original_name);
		saveIlastikOutput(output_path);
	} else {
		open(output_path);
		close(original_name);
	}
	ilastik_output_ID = getImageID();

	// post processing
	run("Median...", "radius=4");
	run("Gaussian Blur...", "sigma=2");

	// Thresholding
	setAutoThreshold("IsoData dark no-reset");
	setThreshold(0.2745, 1000000000000000000000000000000.0000); 
	setOption("BlackBackground", true);
	run("Convert to Mask");
	run("Watershed");


	// Open ROI file, handle error if it doesn't exist
	if (File.exists(roi_file_path)) {
		prepROILabels();
		num_ROIs = roiManager("Count");
		
		if (workflow == "single") {
        	waitForUser("You can adjust ROIs here if needed. Proceed to process?");
        	
        	// Save ROIs in case they were changed
        	if (num_ROIs > 0) {
   				roiManager("Save", roi_file_path);
			}
		}	
	} else {
		exit("ROI file does not exist for this image. Ensure it is named properly and in the correct folder.");
	}

	// ensure duplicate image still exists
	if (!isOpen(dup_ID)) {
        open(input_image_dir+original_name);
        run("Duplicate...", "title="+name+"_OGDup_Recreated");
        dup_ID = getImageID();
        run("RGB Color");
	}

	// For each ROI, run analyze particles and append results
	for (i = 0; i < num_ROIs ; i++) {
		selectImage(ilastik_output_ID);
	    roiManager("Select", i);
		Overlay.addSelection("", colors[i % colors.length]);

		// Collect various values for output
		ROI_area = getValue("Area");
		ROI_label = Roi.getName();
		bregma = getBregmaValue(bregma_path, original_name);
		file_name_parts = split(original_name, "_");
		animal_ID = file_name_parts[0];

		// Clear results table before analyzing this ROI
		run("Clear Results");

		// Run analyze particles WITHOUT adding to ROI manager
		run("Analyze Particles...", "size=30-Infinity circularity=0.10-1.00 clear summarize record");
		
		// Count particles from results table
		particle_count = nResults;

		// For visualization: run analyze particles WITH add to get particle ROIs
		run("Analyze Particles...", "size=30-Infinity circularity=0.10-1.00 add");
		
		total_rois = roiManager("Count");
		particle_rois_start = num_ROIs;

		// Add particle overlays to image for visualization
		selectImage(dup_ID);
		for (j = particle_rois_start; j < total_rois; j++) {
			roiManager("Select", j);
			Overlay.addSelection("", colors[i % colors.length]);
		}
		
		// Build csv output
		csv += toString(animal_ID) + "," + original_name + "," + ROI_label + "," + toString(ROI_area) + "," + toString(bregma) + "," + toString(particle_count) + "\n";
		
		// Reset ROI manager to original ROIs for next iteration
		roiManager("Reset");
		roiManager("Open", roi_file_path);
	}

	// Show Overlays and burn into image
	Overlay.show()
	run("Flatten");

	// Return CSV results
	return csv;
}

function processorCountManually(original_ID, original_name, roi_file_path) {
	csv = "";
	name = File.getNameWithoutExtension(original_name);

	// Open ROI file, handle error if it doesn't exist
	if (File.exists(roi_file_path)) {
		prepROILabels();
		num_ROIs = roiManager("Count");
		
		waitForUser("You can adjust ROIs here if needed. Proceed to process?");
        	
        // Save ROIs in case they were changed
        if (num_ROIs > 0) {
   			roiManager("Save", roi_file_path);
		}
	} else {
		exit("ROI file does not exist for this image. Ensure it is named properly and in the correct folder.");
	}


	// For each ROI, guide user to count cells
	for (i=0; i < num_ROIs; i++) {
		selectImage(original_ID);
		roiManager("Select", i);

		// get roi info
		ROI_area = getValue("Area");
        ROI_label = Roi.getName();
        bregma = getBregmaValue(bregma_path, original_name);
        file_name_parts = split(original_name, "_");
        animal_ID = file_name_parts[0];

		// Add ROI overlay with distinct color
        Overlay.addSelection("", colors[i % colors.length]);
        
		// Zoom to ROI for better visibility
		run("To Selection");

		// Set multipoint tool and clear any existing selection
        setTool("multipoint");
        run("Select None");
        roiManager("Select", i); 
		roiManager("show all without labels");

		selectImage(original_ID);

		waitForUser("Manual Counting - ROI " + (i+1) + " of " + num_ROIs, 
                   "ROI: " + ROI_label + "\n" +
                   "Area: " + d2s(ROI_area, 0) + " px²\n\n" +
                   "Instructions:\n" +
                   "1. Use the multipoint tool (already selected) to mark objects\n" +
				   "2. Hold Shift and click to start\n" +
                   "3. Click on objects within the highlighted ROI boundaries\n" +
                   "4. Press Alt+click to remove a point if needed\n" +
                   "5. Click OK when finished counting this ROI");

		// Get count from multipoint selection
        roi_count = 0;
        if (selectionType() == 10) { // Multi-point selection
            getSelectionCoordinates(xpoints, ypoints);
            roi_count = xpoints.length;
            
            // Add point overlays to image
			run("RGB Color");
	    	setForegroundColor(255,0,0);
	    	for (j = 0; j < xpoints.length; j++) {
    			makeOval(xpoints[j]-1, ypoints[j]-1, 5, 5); 
    			run("Fill", "slice");
        	}
		}
		run("Select None");

		// write to output string
		csv += toString(animal_ID) + "," + original_name + "," + ROI_label + "," + toString(ROI_area) + "," + toString(bregma) + "," + toString(roi_count) + "\n";
	}

	Overlay.show();
    run("Flatten");
    
    return csv;
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
	roi_file_path = roi_dir + File.getNameWithoutExtension(selected_image_name) + "_ROIs.zip";
	
	open(selected_image_path);
	selected_ID = getImageID();
	
	// Run correct processor
	if (processor == "findmaxima"){
		results = processorFindMaxima(selected_ID, selected_image_name, roi_file_path, "single");
		final_csv = csv_header_findmaxima + results;
		suffix = "_findmaxima_processed";
	} else if (processor == "ilastik") {
		model = chooseModel();
		results = processorIlastik(selected_ID, selected_image_name, roi_file_path, "single", model);
		final_csv = csv_header_ilastik + results;
        suffix = "_ilastik_processed"; 
	} 
	
	// Save csv and overlay image
	File.saveString(final_csv, results_dir + selected_image_name_no_ext + suffix + ".csv");
	saveAs("Tiff", output_image_dir + selected_image_name_no_ext + suffix); 
	
	cleanUp();
	run("Collect Garbage");
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
		model = chooseModel();
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
		roi_file_path = roi_dir + File.getNameWithoutExtension(selected_image_name) + "_ROIs.zip";
		
		open(selected_image_path);
		selected_ID = getImageID();
		
		// Run correct processor
        if (processor == "findmaxima") {
        	results = processorFindMaxima(selected_ID, selected_image_name, roi_file_path, "batch");
        } else if (processor == "ilastik") {
            results = processorIlastik(selected_ID, selected_image_name, roi_file_path, "batch", model);
        } 
		
		batch_csv_str += results;
		
		saveAs("Tiff", output_image_dir + selected_image_name_no_ext + suffix);
		
		cleanUp();
        run("Collect Garbage");
	}
	

	// Save aggregated csv to results.csv
	File.saveString(batch_csv_str, results_dir + "results" + suffix + ".csv");
	
	// Show completion time
    end_time = getTime();
    processing_time = (end_time - start_time) / 1000; // Convert to seconds
    showMessage("Batch Processing Complete", 
                "Processed " + image_list.length + " images in " + d2s(processing_time, 1) + " seconds\n" +
                "Average: " + d2s(processing_time / image_list.length, 1) + " seconds per image");
}

function manualWorkflow(image_list) {
	if (image_list.length == 0) {
		exit("No images found in input_images folder.");
	}
	suffix = "_manually_processed";

	continue_manual = true;
	while (continue_manual) {
		// Create Dialog to select image
		Dialog.create("Select an Image");
		Dialog.addChoice("Image: ", image_list, image_list[0]);
		Dialog.addCheckbox("Process another image?", true);
		Dialog.show();
		
		continue_manual = Dialog.getCheckbox();
		if (!continue_manual) {
			break;
		}
		selected_image_name = Dialog.getChoice();
		selected_image_name_no_ext = File.getNameWithoutExtension(selected_image_name);
		selected_image_path = input_image_dir + selected_image_name;
		roi_file_path = roi_dir + File.getNameWithoutExtension(selected_image_name) + "_ROIs.zip";

		if (File.exists(results_dir + "results" + suffix + ".csv")) {
			batch_csv_str = File.openAsString(results_dir + "results" + suffix + ".csv");
		} else {
			batch_csv_str = csv_header_manual;
		}

		open(selected_image_path);
		selected_ID = getImageID();

		results = processorCountManually(selected_ID, selected_image_name, roi_file_path);
		batch_csv_str += results;

		// append aggregated csv to results.csv
		File.saveString(batch_csv_str, results_dir + "results" + suffix + ".csv");

		saveAs("Tiff", output_image_dir + selected_image_name_no_ext + suffix);
		cleanUp();
	}
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
roi_dir = parts[11];
input_image_dir = parts[12];
output_image_dir = parts[13];
ilastik_output_dir = parts[14];
ilastik_models_dir = parts[15];


// =============================================================================
//                                 MAIN 
// =============================================================================
// Cleanup workspace
cleanUp();

// Generate image file list and its length
image_list = getFileList(input_image_dir);
num_images = image_list.length;

// Initialize main dialog/workflow selection
workflows = newArray(
    "Process Single Image (FindMaxima)", 
    "Process Single Image (Ilastik)", 
    "Process All Images (FindMaxima)", 
    "Process All Images (Ilastik)", 
	"Process Images Manually",
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
	} else if (action == "Process Images Manually"){
		manualWorkflow(image_list);
    } else if (action == "Quit Image Processor") {
        continue_loop = false;
    }
}


