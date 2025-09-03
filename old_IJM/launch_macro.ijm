// =============================================================================
// =============================================================================
// Entry point macro for cFos-DAB suite. Orients program in file system, defines paths, defines universal functions,
// runs UI loop and enters user into workflow, calling setup_and_roi macro to do so.
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

// sets file directory location of launch macro to set other paths
plugin_dir = getDirectory("plugins");
plugin_dir = replace(plugin_dir, "\\", "/");
fiji_root = replace(plugin_dir, "plugins/", ""); 

MAIN_DIR = plugin_dir + "cell-quantifier-workflows" + File.separator;

// Define suite component paths
MACRO_DIR = MAIN_DIR + "macros" + File.separator;
MODEL_DIR = fiji_root + "lib" + File.separator + "cell-quantifier-workflow-ilastik-models" + File.separator;
QUANTIFICATION_PATH = MACRO_DIR + "quantification.ijm";
SETUP_PATH = MACRO_DIR + "setup_and_roi.ijm";
LAUNCH_MACRO_PATH = MAIN_DIR + "launch_macro.ijm";

SUITE_EXPECTED = newArray(MAIN_DIR, MACRO_DIR, MODEL_DIR, QUANTIFICATION_PATH,SETUP_PATH,LAUNCH_MACRO_PATH);
SUITE_ARG = concatArrayIntoStr(SUITE_EXPECTED);

// ================================
//              MAIN
// ================================



// Check integrity of suite directory
missing = checkStructure(SUITE_EXPECTED);
if (missing != "") {
    ("Macro suite not properly setup. Try updating it.\nMissing:\n"+missing);
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
        break;
    }
}



