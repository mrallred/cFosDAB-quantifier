// ImageJ Macro to set up project and faciltate ROIs selection and managment
// Complete workflow for project-based ROI analysis

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

function initializeBregmaDB(bregma_path) {
    if (!File.exists(bregma_path)) {
        headers = "Filename,Bregma\n";
        File.saveString(headers, bregma_path);
        print("Bregma database initialized: " + bregma_path);
    }
}

function initializeProjectResults(results_path) {
    if (!File.exists(results_path)) {
        headers = "ID,Filename,ROI,ROI Area(px^2),L-R,Bregma,Count";
        File.saveString(headers, results_path);
        print("Project Result database initialized: " + results_path);
    }
}

function saveBregmaValue(bregma_path, filename, bregma_value) {
    if (File.exists(bregma_path)) {
        existing_content = File.openAsString(bregma_path);
        lines = split(existing_content, "\n");
        
        new_content = "";
        filename_found = false;
        
        // Process each line
        for (i = 0; i < lines.length; i++) {
            if (lines[i].length > 0) {
                parts = split(lines[i], ",");
                if (parts.length >= 2 && parts[0] == filename && i > 0) {
                    // Update existing filename
                    new_content += filename + "," + bregma_value + "\n";
                    filename_found = true;
                } else {
                    // Keep existing line
                    new_content += lines[i] + "\n";
                }
            }
        }
        
        // Add new filename if not found
        if (!filename_found) {
            new_content += filename + "," + bregma_value + "\n";
        }
        
        File.saveString(new_content, bregma_path);
    } else {
        // Create new database
        initializeBregmaDB(bregma_path);
        content = "Filename,Bregma\n" + filename + "," + bregma_value + "\n";
        File.saveString(content, bregma_path);
    }
    print("Saved bregma value: " + filename + " = " + bregma_value);
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

function collectROIsByRegion() {
    setTool("polygon");
    RoiManager.useNamesAsLabels(true);
    run("Labels...", "color=white font=18 show bold");
    roiManager("show none");
    roiManager("show all with labels");

    while (true) {
        // Ask for anatomical region name
        Dialog.create("Define Region");
        Dialog.addMessage("Enter subregion label below.");
        Dialog.addMessage("All selections added under each label will be treated as one merged region.");
        Dialog.addMessage("For example: Use 'IL_L' and 'IL_R' for hemisphere-specific labels");
        Dialog.addString("Region Name:", "");
        Dialog.show();
        
        region = Dialog.getString();
        
        if (region == "") {
            showMessage("No region name provided. Exiting ROI collection.");
            return;
        }

        // Begin ROI drawing
        startIndex = roiManager("Count");
        roiCount = 0;

        while (true) {
            waitForUser("Draw polygon ROI #" + (roiCount + 1) + " for '" + region + "' and press OK.");
            
            if (selectionType() == -1) {
                showMessage("No selection made. Please draw a polygon selection.");
                continue;
            }
            
            roiManager("Add");
            index = roiManager("Count") - 1;
            roiManager("Select", index);
            roiManager("Rename", region + "_" + roiCount);
            roiCount++;

            Dialog.create("Add Another ROI?");
            Dialog.addCheckbox("Add another ROI for '" + region + "'?", false);
            Dialog.show();
            if (!Dialog.getCheckbox()) break;
        }

        // Collapse into one ROI if multiple were drawn
        if (roiCount > 1) {
            // Create array of indices to select multiple ROIs
            roiIndices = newArray(roiCount);
            for (i = 0; i < roiCount; i++) {
                roiIndices[i] = startIndex + i;
            }
            
            // Select all ROIs for this region using array
            roiManager("select", roiIndices);
            roiManager("Combine");
            roiManager("Add");
            
            // Rename the combined ROI
            combinedIndex = roiManager("Count") - 1;
            roiManager("Select", combinedIndex);
            roiManager("Rename", region);

            // Remove individual ROIs (in reverse order to maintain indices)
            for (j = roiCount - 1; j >= 0; j--) {
                roiManager("Select", startIndex + j);
                roiManager("Delete");
            }
        } else if (roiCount == 1) {
            roiManager("Select", startIndex);
            roiManager("Rename", region);
        }

        Dialog.create("Define Another Region?");
        Dialog.addCheckbox("Define ROIs for another anatomical region?", true);
        Dialog.show();
        if (!Dialog.getCheckbox()) {
            break;
        }
    }
}

function copyImageToInputDir(source_path, input_image_dir) {
    filename = File.getName(source_path);
    // Convert filename to .tif extension
    base_name = File.getNameWithoutExtension(filename);
    destination_path = input_image_dir + base_name + ".tif";
    
    // Always open and save as TIFF for consistency
    print("Converting image to TIFF format...");
    open(source_path);
    saveAs("TIFF", destination_path);
    close();
    print("Image converted and saved as TIFF: " + destination_path);
    return destination_path;
}

function isFileInDirectory(directory_path, file_name_to_check) {
	// Function to search if a file is in a directory.
	// Returns true if so and false if not
	
	// Ensure directory path ends with separator
	if (!endsWith(directory_path, File.separator)) {
		directory_path += File.separator;
	}
	
	// Get a list of files in directory
	file_list = getFileList(directory_path);
	
	// Check directory actually exists and has some images
	if (lengthOf(file_list) == 0) {
        return false;
	}
	
	// Iterate through list looking for file
	for (i=0; i < lengthOf(file_list); i++) {
		if (file_list[i] == file_name_to_check) {
			return true;
		}
	}
	// If not found in list, not in directory
	return false; 

}

// =============================================================================
// MAIN PROGRAM
// =============================================================================

macro "ROI Analysis Project Manager" {
    // Colors for ROI overlays
    colors = newArray("#FF0000", "#0000FF", "#00FF00", "#FFFF00", "#FF00FF", "#00FFFF", "#B300FF", "#48FF00");

    // PROGRAM INITIALIZATION
    close("*");
    run("Clear Results");
    roiManager("reset");

    // Prompt users to select working project directory
    waitForUser("Select Your Project Directory", 
                "Press OK and select an existing project or create a new project folder.\n" +
                "If this is a new project, the folder should be completely empty.");

    project_dir = getDirectory("Select Project Directory");
    if (project_dir == "") {
        exit("No project directory selected.");
    }
    
    project_file_list = getFileList(project_dir);

    // Define paths for project
    bregma_path = project_dir + "bregma_values.csv";
    results_dir = project_dir + "Results" + File.separator;
    results_path = results_dir + "results.csv";
    roi_dir = project_dir + "ROI_files" + File.separator;
    input_image_dir = project_dir + "Input_images" + File.separator;
    output_image_dir = project_dir + "Output_images" + File.separator;
    temp_dir = project_dir + "temp" + File.separator;
    ilastik_models_dir = project_dir + "Ilastik_models" + File.separator;


    // Set up project structure if new project (empty folder)
    if (project_file_list.length == 0) {
        print("Setting up new project structure...");
        initializeBregmaDB(bregma_path);
        File.makeDirectory(results_dir);
        initializeProjectResults(results_path);
        File.makeDirectory(roi_dir);
        File.makeDirectory(input_image_dir);
        File.makeDirectory(output_image_dir);
        File.makeDirectory(temp_dir);
        File.makeDirectory(ilastik_models_dir);
        
    } else {
        print("Using existing project structure...");
    }

    // MAIN PROCESSING LOOP
    while (true) {
        roiManager("Reset");
        
        // Prompt user to select image
        waitForUser("Select Image", "Press OK and select the next image to process for ROI analysis.");
        
        // Open image dialog
        image_path = File.openDialog("Select Image File");
        if (image_path == "") {
            showMessage("No image selected. Exiting.");
            break;
        }
        
        // Copy image to input directory if its not there
        image_name = File.getName(image_path);
        base_name = File.getNameWithoutExtension(image_name);
        tiff_name = base_name + ".tif";
        if (isFileInDirectory(input_image_dir, tiff_name)) {
        	copied_path = input_image_dir + tiff_name;
        	print("Image of same name already in project. Opening existing TIFF image.");
        } else {
        	copied_path = copyImageToInputDir(image_path, input_image_dir);
        }
        
        // Open the copied image
        open(copied_path);
        
        // Get image info
        roi_file_path = roi_dir + File.getNameWithoutExtension(image_name) + "_ROIs.zip";
        output_image_path = output_image_dir + File.getNameWithoutExtension(image_name) + "_labeled.png";
        
        print("Processing image: " + image_name);

        // Check if bregma value already exists for this image
        existing_bregma = getBregmaValue(bregma_path, image_name);
        
        // Prompt for bregma value
        if (existing_bregma != "") {
            // Show existing value and allow update
            Dialog.create("Bregma Value");
            Dialog.addMessage("The current bregma value for " + image_name + ": " + existing_bregma);
            Dialog.addNumber("Enter new bregma value (or keep current):", parseFloat(existing_bregma));
            Dialog.show();
            
            current_bregma = toString(Dialog.getNumber());
            saveBregmaValue(bregma_path, image_name, current_bregma);
        } else {
            // No existing value, prompt for new one
            current_bregma = getString("Enter bregma value for " + image_name + ":", "0.000");
            saveBregmaValue(bregma_path, image_name, current_bregma);
        }

        // Store original image ID and convert to RGB for visualization
        og_imageID = getImageID();
        selectImage(og_imageID);
        run("RGB Color");

        // Check if ROI file exists and handle accordingly
        if (File.exists(roi_file_path)) {
        	roiManager("reset");
            roiManager("Open", roi_file_path);
            run("ROI Manager...");
            roiManager("Show All");
            roiManager("show all with labels");

            Dialog.create("Existing ROIs Found");
            Dialog.addMessage("ROI file exists for this image: " + File.getName(roi_file_path));
            Dialog.addChoice("Action:", newArray("Modify existing ROIs", "Reset ROIs and create new", "Skip this image and select another"));
            Dialog.show();
          
            action = Dialog.getChoice();
            
            if (action == "Skip this image and select another") {
                close();
                continue;
            } 
            else if (action == "Modify existing ROIs") {
                // Display existing ROIs on the image and wait for user to adjust
                roiManager("Show All");
                roiManager("show all with labels");
                waitForUser("Adjust ROIs", "Adjust ROIs using manager and press okay when done. You can only adjust single polygon selections currently. Please create new ROIs if you have multiple selections per regions");
 				           
            }
            else if (action == "Reset ROIs and create new") {
            	roiManager("reset");
            	collectROIsByRegion();
            }
              
        } else {
            // Create new ROIs
            roiManager("reset");
            collectROIsByRegion();
        }

        // Save ROIs to file
        num_ROIs = roiManager("Count");
        if (num_ROIs > 0) {
            // Color ROIs for visualization
            for (i = 0; i < num_ROIs; i++) {
                roiManager("Select", i);
                Roi.setStrokeColor(colors[i % colors.length]);
                Roi.setStrokeWidth(3);
                roiManager("Update");
            }
            
            roiManager("Save", roi_file_path);
            print("ROIs saved: " + roi_file_path);
            
            // Show all ROIs with labels
            roiManager("Show All");
            roiManager("show all with labels");
        }

        // Ask user if they want to continue processing
        Dialog.create("Continue Processing?");
        Dialog.addMessage("Processing complete for " + image_name);
        Dialog.addMessage("- Bregma value saved: " + current_bregma);
        Dialog.addMessage("- ROIs saved: " + num_ROIs + " regions");
        Dialog.addMessage("- Output image saved");
        Dialog.addCheckbox("Process another image?", true);
        Dialog.show();
        
        continueProcessing = Dialog.getCheckbox();
        
        // Close current images to prepare for next image
        if (nImages > 0) {
            close("*");
        }
        
        // Exit if user chooses not to continue
        if (!continueProcessing) {
            break;
        }
    }

    // Final summary
    print("=== PROJECT PROCESSING COMPLETE ===");
    print("Project directory: " + project_dir);
    print("Check the following directories for results:");
    print("- Input images: " + input_image_dir);
    print("- ROI files: " + roi_dir);
    print("- Labeled output images: " + output_image_dir);
    print("- Bregma database: " + bregma_path);
    
    showMessage("Project Processing Complete", 
                "All processing finished successfully!\n\n" +
                "Check your project directory for:\n" +
                "- Input images\n" +
                "- ROI files (.zip)\n" +
                "- Labeled output images\n" +
                "- Bregma value database");

    // Clean up windows
	close("*");
	run("Clear Results");
	roiManager("reset");
	close("*");
	close("Results");
	close("ROI Manager");
}