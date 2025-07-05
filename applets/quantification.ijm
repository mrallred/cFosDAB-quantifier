// ImageJ Macro to batch process images through cell-quantifcation workflows. Optimized for cFos DAB stained tissue. 
// Project directory must be set up properly before use. Use ROIProcessor Workflow to set up project and define the 
// Regions of Interest, then run this macro to do the quantification.
SUITE_AND_PROJECT_ARG = getArgument();
print("succesfully entered quantification" +SUITE_AND_PROJECT_ARG);
// Colors for ROI overlays
colors = newArray("#FF0000", "#0000FF", "#00FF00", "#FFFF00", "#FF00FF", "#00FFFF","#B300FF","48FF00");

// Initilize headers as global variable
csv_header_findmaxima = "ID,File name,ROI,Area of ROI (px^2),Bregma,Count(FindMaxima)\n";
csv_header_ilastik = "ID,File name,ROI,Area of ROI (px^2),Bregma,Count(Ilastik)\n";

// GitHub repo configration for model updates
GITHUB_REPO_URL = "https://raw.githubusercontent.com/your-username/your-repo/main/";
DEFAULT_MODEL_NAME = "cFos_classification.ilp";

// =============================================================================
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
	
function cleanupTempDirectory(temp_dir) {
    if (File.exists(temp_dir)) {
        temp_files = getFileList(temp_dir);
        for (i = 0; i < temp_files.length; i++) {
            File.delete(temp_dir + temp_files[i]);
        }
    }
}

// =============================================================================
// ILASTIK MODEL MANAGMENT FUNCTIONS
// =============================================================================
function checkAndDownloadModel(project_dir, model_name) {
    models_path = models_dir + model_name;
    
    if (!File.exists(models_path)) {
        showMessage("Model Download", "First-time setup: downloading " + model_name + "\nThis may take a few minutes...");
        
        // Download model from GitHub
        model_url = GITHUB_REPO_URL + "models/" + model_name;
        
        // Use ImageJ's built-in download capability
        // Check if URL downloading is available
        if (isOpen("URL...")) {
            run("URL...", "url=" + model_url + " name=" + model_name);
            if (nImages > 0) {
                saveAs("Ilastik Project", model_path);
                close();
                showMessage("Download Complete", "Model successfully downloaded to:\n" + model_path);
            } else {
                exit("Failed to download model from:\n" + model_url + "\n\nPlease download the model manually and place it in:\n" + model_path);
            }
        } else {
            exit("Cannot download model automatically.\nPlease download " + model_name + " manually from:\n" + model_url + "\n\nAnd place it in:\n" + model_path);
        }
    }
    return model_path;
}

function validateModel(model_path) {
    if (!File.exists(model_path)) {
        return false;
    }
    
    // Basic validation - check file size and extension
    if (endsWith(model_path, ".ilp") && File.length(model_path) > 1000) {
        return true;
    }
    
    return false;
}

// =============================================================================
// ILASTIK PROCESSING FUNCTIONS
// =============================================================================
function extractROIRegions(original_ID, temp_dir, roi_file_path) {
    selectImage(original_ID);
    
    // Load ROI file
    roiManager("reset");
    roiManager("Open", roi_file_path);
    num_ROIs = roiManager("Count");
    
    roi_info = newArray();
    
    for (i = 0; i < num_ROIs; i++) {
        roiManager("Select", i);
        
        // Get ROI bounds with buffer
        Roi.getBounds(x, y, width, height);
        buffer = 10; // pixel buffer around ROI
        
        // Expand bounds with buffer
        x_start = maxOf(0, x - buffer);
        y_start = maxOf(0, y - buffer);
        x_end = minOf(getWidth(), x + width + buffer);
        y_end = minOf(getHeight(), y + height + buffer);
        
        // Extract ROI region
        makeRectangle(x_start, y_start, x_end - x_start, y_end - y_start);
        run("Duplicate...", "title=ROI_" + i);
        roi_region_ID = getImageID();
        
        // Save ROI region to temp file
        temp_roi_path = temp_dir + "ROI_region_" + i + ".tif";
        saveAs("Tiff", temp_roi_path);
        
        // Store ROI information
        roi_info_string = i + "," + Roi.getName() + "," + x + "," + y + "," + width + "," + height + "," + temp_roi_path;
        roi_info = Array.concat(roi_info, roi_info_string);
        
        close();
        selectImage(original_ID);
    }
    
    return roi_info;
}

function processWithIlastik(roi_info, model_path, temp_dir) {
    // Create batch list for Ilastik processing
    input_files = newArray();
    
    for (i = 0; i < roi_info.length; i++) {
        parts = split(roi_info[i], ",");
        temp_roi_path = parts[6];
        input_files = Array.concat(input_files, temp_roi_path);
    }
    
    // Run Ilastik in batch mode
    // Note: This assumes the Ilastik ImageJ plugin is properly installed
    // The exact command may vary depending on your Ilastik plugin version
    
    output_dir = temp_dir + "ilastik_output" + File.separator;
    if (!File.exists(output_dir)) {
        File.makeDirectory(output_dir);
    }
    
    // Process each ROI region through Ilastik
    processed_results = newArray();
    
    for (i = 0; i < input_files.length; i++) {
        input_file = input_files[i];
        output_file = output_dir + "classified_" + i + ".tif";
        
        // Run Ilastik pixel classification
        // This is the actual Ilastik plugin call - syntax may vary
        run("Run Pixel Classification Prediction", 
            "projectfilename=" + model_path + 
            " inputimage=" + input_file + 
            " pixelclassificationtype=Probabilities" +
            " outputtype=TIF" +
            " outputdirectory=" + output_dir);
        
        processed_results = Array.concat(processed_results, output_file);
    }
    
    return processed_results;
}

function quantifyIlastikResults(roi_info, processed_results, original_ID) {
    results_array = newArray();
    
    for (i = 0; i < roi_info.length; i++) {
        roi_parts = split(roi_info[i], ",");
        roi_index = parseInt(roi_parts[0]);
        roi_name = roi_parts[1];
        roi_x = parseInt(roi_parts[2]);
        roi_y = parseInt(roi_parts[3]);
        roi_width = parseInt(roi_parts[4]);
        roi_height = parseInt(roi_parts[5]);
        
        // Open classified result
        classified_path = processed_results[i];
        open(classified_path);
        classified_ID = getImageID();
        
        // Apply threshold to get binary mask
        // Assuming class 1 (second channel) represents positive cells
        run("Split Channels");
        selectWindow("C2-" + File.getNameWithoutExtension(classified_path));
        setThreshold(128, 255); // Adjust threshold as needed
        run("Convert to Mask");
        
        // Analyze particles to count and get centers
        run("Analyze Particles...", "size=10-Infinity show=Nothing display clear add");
        
        // Count objects and calculate metrics
        cell_count = nResults;
        total_area = 0;
        center_points = newArray();
        
        for (j = 0; j < nResults; j++) {
            area = getResult("Area", j);
            centroid_x = getResult("XM", j);
            centroid_y = getResult("YM", j);
            
            total_area += area;
            
            // Convert local coordinates to original image coordinates
            global_x = roi_x + centroid_x;
            global_y = roi_y + centroid_y;
            
            center_points = Array.concat(center_points, global_x + "," + global_y);
        }
        
        // Store results
        result_string = roi_index + "," + roi_name + "," + cell_count + "," + total_area + "," + String.join(center_points, ";");
        results_array = Array.concat(results_array, result_string);
        
        // Clean up
        close("*");
        run("Clear Results");
    }
    
    return results_array;
}

function createIlastikOverlay(original_ID, roi_info, quantification_results) {
    selectImage(original_ID);
    run("RGB Color");
    
    // Draw ROI boundaries and center points
    for (i = 0; i < roi_info.length; i++) {
        roi_parts = split(roi_info[i], ",");
        roi_x = parseInt(roi_parts[2]);
        roi_y = parseInt(roi_parts[3]);
        roi_width = parseInt(roi_parts[4]);
        roi_height = parseInt(roi_parts[5]);
        
        // Draw ROI boundary
        color_index = i % colors.length;
        setColor(colors[color_index]);
        drawRect(roi_x, roi_y, roi_width, roi_height);
        
        // Draw center points
        result_parts = split(quantification_results[i], ",");
        if (result_parts.length > 5) {
            center_points_str = result_parts[5];
            if (center_points_str != "") {
                center_points = split(center_points_str, ";");
                
                setColor("#FF0000"); // Red for center points
                for (j = 0; j < center_points.length; j++) {
                    point_coords = split(center_points[j], ",");
                    if (point_coords.length == 2) {
                        x = parseInt(point_coords[0]);
                        y = parseInt(point_coords[1]);
                        
                        // Draw small circle at center point
                        drawOval(x - 2, y - 2, 4, 4);
                        fillOval(x - 2, y - 2, 4, 4);
                    }
                }
            }
        }
    }
    
    run("Flatten");
    return getImageID();
}

// =============================================================================
// PROCESSOR FUNCTIONS
// =============================================================================

function processorFindMaxima(original_ID, original_name, workflow) {
	selectImage(original_ID);
	
	// Prepare CSV string
	csv = "";
	
	// csv headers for output
	csv_header = "ID,File name,ROI,Area of ROI (px^2),Bregma,Count(FindMaxima)\n";

	
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
    selectImage(original_ID);
    
    // Initialize CSV string
    csv = "";
    
    model_path = models_dir + DEFAULT_MODEL_NAME;
        
    if (!validateModel(model_path)) {
    	cleanupTempDirectory(temp_dir);
        exit("Invalid or corrupted Ilastik model file: " + model_path);
    }
        
    // Extract ROI regions
    roi_file_path = roi_dir + File.getNameWithoutExtension(original_name) + "_ROIs.zip";
    if (!File.exists(roi_file_path)) {
    	cleanupTempDirectory(temp_dir);
        exit("ROI file does not exist for this image: " + original_name);
    }
        
    roi_info = extractROIRegions(original_ID, temp_dir, roi_file_path);
        
    if (workflow == "single") {
        waitForUser("Proceed with Ilastik processing?", "ROI regions extracted. Click OK to continue with classification.");
    }
        
    // Process through Ilastik
    processed_results = processWithIlastik(roi_info, model_path, temp_dir);
        
    // Quantify results
    quantification_results = quantifyIlastikResults(roi_info, processed_results, original_ID);
        
    // Create overlay visualization
    overlay_ID = createIlastikOverlay(original_ID, roi_info, quantification_results);
        
    // Generate CSV output
    for (i = 0; i < quantification_results.length; i++) {
        result_parts = split(quantification_results[i], ",");
        roi_index = result_parts[0];
        roi_name = result_parts[1];
        cell_count = result_parts[2];
        classified_area = result_parts[3];
        density = result_parts[4];
            
        // Get additional info
        roi_parts = split(roi_info[i], ",");
        roi_area = parseInt(roi_parts[4]) * parseInt(roi_parts[5]); // width * height
            
        bregma = getBregmaValue(bregma_path, original_name);
        file_name_parts = split(original_name, "_");
        animal_ID = file_name_parts[0];
            
        csv += animal_ID + "," + original_name + "," + roi_name + "," + roi_area + "," + bregma + "\n";
    }
    // Clean up temporary files
    cleanupTempDirectory(temp_dir);
   
    return csv;
}

// =============================================================================
// PROJECT MANGEMENT WORKFLOW FUNCTIONS
// =============================================================================

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

function checkProjectSetup(project_dir, results_dir, results_path, bregma_path, roi_dir, input_image_dir, output_image_dir,temp_dir,models_dir) {
	missing = "";

	if (!File.exists(bregma_path)) missing += "- Missing: bregma_values.csv\n";
	if (!File.exists(results_dir)) missing += "- Missing folder: Results\n";
	if (!File.exists(results_path)) missing += "- Missing: results.csv\n";
	if (!File.exists(roi_dir)) missing += "- Missing folder: ROI_files\n";
	if (!File.exists(input_image_dir)) missing += "- Missing folder: Input_images\n";
	if (!File.exists(output_image_dir)) missing += "- Missing folder: Output_images\n";
	if (!File.exists(temp_dir)) missing += "- Missing folder: temp\n";
	if (!File.exists(models_dir)) missing += "- Missing folder: Ilasik_models\n";

	return missing;
}
// =============================================================================
// WORKFLOWS
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
	project_name = File.getName(project_dir);

	// Define Paths for project
	bregma_path = project_dir + "bregma_values.csv";
	results_dir = project_dir + "Results" + File.separator;
    results_path = results_dir + "results.csv";
    roi_dir = project_dir + "ROI_files" + File.separator;
    input_image_dir = project_dir + "Input_images" + File.separator;
    output_image_dir = project_dir + "Output_images" + File.separator;
    temp_dir = project_dir + "temp" + File.separator;
    models_dir = project_dir + "Ilastik_models" + File.separator;

	// Ensure Project is correctly setup before beginning
	missing = checkProjectSetup(project_dir, results_dir, results_path, bregma_path, roi_dir, input_image_dir, output_image_dir, temp_dir, models_dir);
	if (missing != "") {
		exit("Project directory is missing required components:\n" + missing + "\nPlease Fix project folder and rerun macro.");
	} 
	
	// Generate image file list and its length
	image_list = Array.sort(getFileList(input_image_dir));
	num_images = image_list.length;

	// Initialize main dialog/workflow selection
	workflows = newArray(
        "Process Single Image (FindMaxima)", 
        "Process Single Image (Ilastik)", 
        "Process All Images (FindMaxima)", 
        "Process All Images (Ilastik)", 
        "Quit Macro");
	continue_loop = true;
	
	while (continue_loop){
		Dialog.create("Select Workflow");
		Dialog.addMessage("Project " + project_name + " is loaded. ");
		Dialog.addMessage("- Project path: " + project_dir);
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
        } else if (action == "Quit Macro") {
            continue_loop = false;
        }
	}
	exit("Finished Processing. Macro will close.");
}


