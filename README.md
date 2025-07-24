# cFosDAB-quantifer
This FIJI macro suite was developed to quantify cFos-DAB-stained positive cells in brightfield images. It counts dark cell nuclei that are set against lighter background tissue. It enables analysis of many Regions of Interest (ROIs) within a single image simultaneously, outputting the results for each sub-region separately. 

Counting can be done automatically with two workflows: using Ilastik and FindMaxima. Additionally, it includes a tool for hand counting images while still collecting info about ROI size. The Ilastik processer utilizes the Ilastik Pixel classification workflow (a Random Forest classifier) to segment the image. Output from Ilastik are further processed and quantified in FIJI.

Made up of three macro scripts:
1. launch_macro.ijm: Macro run by user to start. Ensures the suite's integrity and runs the main loop to enter into the setup_and_roi macro.
2. setup_and_roi.ijm: Facilitates project structure setup, workflow selection, and the tools to add and edit project images and ROIs.
3. quantification.ijm: Runs all quantification tools/processors, allowing for single image and batch processing. Functionality includes: 
    - Manual counting
    - FindMaxima automatic
    - Ilastik automatic

Ilastik workflow requires Ilastik (https://www.ilastik.org/download) to be installed on your machine, and the Fiji/ilastik plugin (https://www.ilastik.org/documentation/fiji_export/plugin) to be enabled and installed. It uses the pixel classification workflow, and models can be trained in Ilastik and imported into this macro by adding them the the models folder, or the default can be used.
