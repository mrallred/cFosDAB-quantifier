# cFosDAB-quantifer
ImageJ macro workflow kit for counting cells in brightfield IHC images. Developed for cFos DAB stained neural tissue.

Made up of three macro scripts:
1. launch_macro.ijm: Macro run by user to start. Ensures the suite's integrity and runs the main loop to enter into the setup_and_roi macro.
2. setup_and_roi.ijm: Facilitates project structure setup, workflow selection, and the tools to add and edit project images and ROIs.
3. quantification.ijm: Runs all quantification tools/processors, allowing for single image and batch processing. Functionality includes: 
    - Manual counting
    - FindMaxima automatic
    - Ilastik automatic

Ilastik workflow requires Ilastik (https://www.ilastik.org/download) to be installed on your machine, and the Fiji/ilastik plugin (https://www.ilastik.org/documentation/fiji_export/plugin) to be enabled and installed. It uses the pixel classification workflow, and models can be trained in Ilastik and imported into this macro by adding them the the models folder, or the default can be used.
