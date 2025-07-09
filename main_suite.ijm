// =============================================================================
// =============================================================================
// Entry point macro for macro suite. Orients program, defines paths, defines universal functions, runs UI loop, calling setup_and_roi
// =============================================================================
// =============================================================================

// ================================
//         UTILITY FUNCTIONS
// ================================

function checkStructure(expected) {
    // ARG: expected -- array of paths for expected component files or directory
    // RETURN: string of any missing components, or "" if all exist

    missing = "";

    for (i=0; i <expected.length; i++) {
        if (!File.exists(expected[i])) missing += "- Missing: " + expected[i] + "\n";
    }
    return missing;
}

function cleanUp() {
    close("*");
	run("Clear Results");
	roiManager("reset");
	close("Results");
	close("ROI Manager");
    close("Log");
}

function concatArrayIntoStr(array){
    str = "";
    for (i=0; i < array.length; i++){
        str += array[i] +",";
    }  
    return str;
}

// ================================
//         DEFINE SUITE PATHS
// ================================

// HARD WIRED TO REPO FOR NOW ----- CHANGE ONCE IMPLEMENTED?
MAIN_DIR = File.directory;

// Define suite component paths
APPLET_DIR = MAIN_DIR + "applets" + File.separator;
MODEL_DIR = MAIN_DIR + "models" + File.separator;
QUANTIFICATION_PATH = APPLET_DIR + "quantification.ijm";
SETUP_PATH = APPLET_DIR + "setup_and_roi.ijm";
MAIN_SUITE_PATH = MAIN_DIR + "main_suite.ijm";

SUITE_EXPECTED = newArray(MAIN_DIR, APPLET_DIR, MODEL_DIR, QUANTIFICATION_PATH,SETUP_PATH,MAIN_SUITE_PATH);
SUITE_ARG = concatArrayIntoStr(SUITE_EXPECTED);

// ================================
//              MAIN
// ================================



// Check integrity of suite directory
missing = checkStructure(SUITE_EXPECTED);
if (missing != "") {
    exit("Macro suite not properly setup. Try updating it.\nMissing:\n"+missing);
} else{
    print("Suite is intact.");
}

// Main loop
continue_loop = true;
options = newArray("Create New Project",
                   "Work on Existing Project",
                   "Quit Macro");

while (continue_loop){
    // Create main menu dialog
    Dialog.create("IHC_processing_suite");
    Dialog.addChoice("Action:", options);
    Dialog.show();

    action = Dialog.getChoice();

    if (action == "Create New Project"){
        args = "new,"+ SUITE_ARG;
        runMacro(SETUP_PATH, args);
    } else if (action == "Work on Existing Project"){
        args = "existing,"+ SUITE_ARG;
        runMacro(SETUP_PATH, args);
    } else {
        cleanUp();
        exit("Macro quit.");
    }
}



