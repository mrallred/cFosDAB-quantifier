// =============================================================================
// =============================================================================
// Module to setup project. Two main pathes:
// 1. If main_suite passed "new": sets up a new project's files and launches them immediately into the roi workflow
// 2. If main_suite passed "existing": brings up a dialog to choose between 4 workflows:
//      * Roi workflow --- Allows user to create or edit ROIs for any file, either already in the project or new to be added.
//      * Image processor --- Faciliates all quantification processing tools (currently ilastik and findmaxima based processors).
//      * Convert and import images --- Opens a whole folder of .jpgs and import them into project directry input_image_dir.
//      * Find missing ROI files  --- compares roi_dir to input_image_dir to find any missing ROI files for input image.

// Called by main_suite.ijm, calls quantification.ijm if quantification module is chosen.
// =============================================================================
// =============================================================================

// Colors for ROI overlays
colors = newArray("#FF0000", "#0000FF", "#00FF00", "#FFFF00", "#FF00FF", "#00FFFF", "#B300FF", "#48FF00");

// ============================================================
//                          UTIL FUNCTIONS
// ============================================================

function cleanUp() {
    close("*");
	run("Clear Results");
	roiManager("reset");
	close("Results");
	close("ROI Manager");
    close("Log");
    close("Summary");
}

function getImageIDs() {
    ids = newArray(nImages);
    for (i = 0; i < nImages; i++) {
        selectImage(i + 1);  // Select by position (1-indexed)
        ids[i] = getImageID();
    }
    return ids;
}

function checkStructure(expected) {
    // ARG: expected -- array of paths for expected component files or directory
    // RETURN: string of any missing components, or "" if all exist

    missing = "";

    for (i=0; i <expected.length; i++) {
        if (!File.exists(expected[i])) missing += "- Missing: " + expected[i] + "\n";
    }
    return missing;
}

function concatArrayIntoStr(array){
    str = "";
    for (i=0; i < array.length; i++){
        str += array[i] +",";
    }  
    return str;
}
// ============================================================
//                          SETUP FUNCTIONS
// ============================================================
function initializeBregmaDB(bregma_path) {
    if (!File.exists(bregma_path)) {
        headers = "Filename,Bregma\n";
        File.saveString(headers, bregma_path);
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

function copyImageToInputDir(source_path, input_image_dir) {
    filename = File.getName(source_path);
    // Convert filename to .tif extension
    base_name = File.getNameWithoutExtension(filename);
    destination_path = input_image_dir + base_name + ".tif";
    
    // Always open and save as TIFF for consistency
    open(source_path);
    saveAs("TIFF", destination_path);
    close();
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

function setupNew(project_expected){
    // Initilize Project structure and files
    project_file_list = getFileList(project_dir);
    if (project_file_list.length == 0) {
        File.makeDirectory(results_dir);
        File.makeDirectory(roi_dir);
        File.makeDirectory(input_image_dir);
        File.makeDirectory(output_image_dir);
        File.makeDirectory(ilastik_output_dir);
        File.makeDirectory(ilastik_models_dir);
        initializeBregmaDB(bregma_path);    
    } else {
        exit("This folder is not empty. Please Select an empty folder or use Open Existing Proejct to avoid losing project data");
    }

    // verify project setup
    missing = checkStructure(project_expected);
    if (missing != "") {
        exit("Project structure is not correct. Something must have gone wrong. Try emptying folder and creating project again.\nMissing:\n"+missing);
    }
}

function openExisting(project_expected) {
    // verify project setup
    missing = checkStructure(project_expected);
    if (missing != "") {
        exit("Project structure is not correct. Ensure valid project folder.\nMissing:\n"+missing);
    }
}
function convertImportDirectory(input_image_dir) {
    dir = getDirectory("Choose folder containing jpg images to import into project: ");

    list = getFileList(dir);
    for (i=0; i<list.length; i++){
        if (endsWith(list[i], ".jpg") || endsWith(list[i], ".jpeg")) {
            open(dir + list[i]);
            saveAs("Tiff", input_image_dir + replace(list[i], ".jpg", ".tif"));
            close();
        }
    }
}
// ============================================================
//                       ROI FUNCTIONS
// ============================================================
function findMissingROIs(roi_dir,input_image_dir) {
    roi_list = getFileList(roi_dir);
    input_image_list = getFileList(input_image_dir);

    print("=== Missing ROI Files Report ===");
    print("ROI files found: " + lengthOf(roi_list));
    print("Input images found: " + lengthOf(input_image_list));
    print("");
    
    missing_count = 0;
    
    for (i=0; i < lengthOf(input_image_list); i++) {
        if (endsWith(input_image_list[i], ".tif")){
            base_name = File.getNameWithoutExtension(input_image_list[i]);
            expected_roi_file = base_name + "_ROIs.zip";

            roi_exists = false;
            for (j = 0; j < lengthOf(roi_list); j++) {
                if (roi_list[j] == expected_roi_file) {
                    roi_exists = true;
                    break;
                }
            }
            
            if (!roi_exists) {
                print("- MISSING: " + expected_roi_file + " (for image: " + input_image_list[i] + ")");
                missing_count++;
            }
        }
    }
    if (missing_count == 0) {
        print("All input images have corresponding ROI files!");
    } else {
        print("Found " + missing_count + " missing ROI files.");
    }
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
function roiWorkflow() {
    // MAIN PROCESSING LOOP
    continue_loop = true;
    while (continue_loop) {
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
        } else {
        	copied_path = copyImageToInputDir(image_path, input_image_dir);
        }
        
        // Open the copied image
        open(copied_path);
        
        // Get roi path
        roi_file_path = roi_dir + base_name + "_ROIs.zip";

        // Check if bregma value already exists for this image
        existing_bregma = getBregmaValue(bregma_path, tiff_name);
        
        // Prompt for bregma value
        if (existing_bregma != "") {
            // Show existing value and allow update
            Dialog.create("Bregma Value");
            Dialog.addMessage("The current bregma value for " + tiff_name + ": " + existing_bregma);
            Dialog.addNumber("Enter new bregma value (or keep current):", parseFloat(existing_bregma));
            Dialog.show();
            
            current_bregma = toString(Dialog.getNumber());
            saveBregmaValue(bregma_path, tiff_name, current_bregma);
        } else {
            // No existing value, prompt for new one
            current_bregma = getString("Enter bregma value for " + tiff_name + ":", "0.000");
            saveBregmaValue(bregma_path, tiff_name, current_bregma);
        }

        // Store original image ID and ensure RGB
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
                waitForUser("Adjust ROIs", "Adjust ROIs using manager and press okay when done. You can only adjust single polygon selections currently. Please create new ROIs if you have multiple selections per regions. (tell me if this is annoying and worth fixing)");
 				           
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
            
            // Show all ROIs with labels
            roiManager("Show All");
            roiManager("show all with labels");
        }

        // Ask user if they want to continue processing
        Dialog.create("Continue ROI workflow?");
        Dialog.addMessage("Processing complete for " + image_name);
        Dialog.addMessage("- Bregma value saved: " + current_bregma);
        Dialog.addMessage("- ROIs saved: " + num_ROIs + " regions");
        Dialog.addCheckbox("Define ROIs for another image?", true);
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
}

// ============================================================
//                  RECOVER PASSED SUITE VARIABLES
// ============================================================

PASSED_ARG = getArgument();

if (PASSED_ARG == "") {
    exit("Error: No argument string received by this macro.");
}

// Assign arg back to individual variables
parts= split(PASSED_ARG, ",");

type = parts[0];
MAIN_DIR = parts[1];
APPLET_DIR = parts[2];
MODEL_DIR = parts[3];
QUANTIFICATION_PATH = parts[4];
SETUP_PATH = parts[5];
MAIN_SUITE_PATH = parts[6];

// ============================================================
//                  PROJECT ENTRY 
// ============================================================

// note for new projects
if (type == "new"){
    note = "The folder should be completely empty.";
    waitForUser("Select Your Project Directory", 
            "Press OK and select or create the folder where the project's files are saved.\n" +
            note);  
}

// Prompt users to select project directory   
project_dir=getDirectory("Select Project Directory");
project_name = File.getName(project_dir);
if (project_dir == "") {
    exit("No project directory selected.");
}

// Define Project Paths 
bregma_path = project_dir + "bregma_values.csv";
results_dir = project_dir + "Results" + File.separator;
roi_dir = project_dir + "ROI_files" + File.separator;
input_image_dir = project_dir + "Input_images" + File.separator;
output_image_dir = project_dir + "Output_images" + File.separator;
ilastik_output_dir = project_dir + "ilastik_processed" + File.separator;
ilastik_models_dir = project_dir + "Ilastik_models" + File.separator;

// Package project details
project_expected = newArray(project_dir, bregma_path,results_dir,roi_dir,input_image_dir,output_image_dir,ilastik_output_dir,ilastik_models_dir);
PROJECT_ARG = project_name+","+concatArrayIntoStr(project_expected);

// ============================================================
//                          MAIN
// ============================================================


// Project initilization
if (type == "new") {
    setupNew(project_expected);
} 

continue_loop = true;
while (continue_loop){
    openExisting(project_expected);
    
    // Create a dialog to choose whether to workflow
    options = newArray("ROI Workflow", "Image Processor Workflow", "Convert and import images", "Find missing ROI", "Exit Project");
    Dialog.create("Choose workflow");
    Dialog.addMessage(project_name + " is loaded.\nROI Workflow: Add new images and/or modify ROIs\nImage Processor Workflow: Access quantification tools and process images with defined ROIs\nConvert and import images: Open a folder of jpg images and import them into the project folder\nFind missing ROI: Check if all images in input_image_dir have ROIs defined\nExit Project: Exit and return to launch menu");
    Dialog.addChoice("Workflow:", options);
    Dialog.show();

    action = Dialog.getChoice();

    // Enter workflow
    if (action == "ROI Workflow"){
        roiWorkflow();
    } else if (action == "Image Processor Workflow") {
        SUITE_AND_PROJECT_ARG = PASSED_ARG + PROJECT_ARG;
        runMacro(QUANTIFICATION_PATH, SUITE_AND_PROJECT_ARG);
    } else if (action == "Convert and import images") {
        convertImportDirectory(input_image_dir);
    } else if (action == "Find missing ROI") {
        findMissingROIs(roi_dir,input_image_dir);
    } else if (action == "Exit Project"){
        continue_loop = false;
        break;
    }
}



