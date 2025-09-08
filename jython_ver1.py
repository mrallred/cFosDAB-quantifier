import os
import csv
import traceback
import time

from ij import IJ, WindowManager
from ij.gui import ImageCanvas, ImageWindow, OvalRoi, Overlay
from ij.plugin.frame import RoiManager
from ij.measure import ResultsTable, Measurements
from ij.plugin.filter import ParticleAnalyzer


from java.io import File, IOException
from java.nio.file import Files, StandardCopyOption, Paths
from java.beans import PropertyChangeListener
from java.lang import Runnable, System

from javax.swing import (JFrame, JDialog, JMenuBar, JMenu, JMenuItem, JSplitPane,
                         JPanel, JComboBox, JScrollPane, JOptionPane, JTree, JTable,
                         JButton, JLabel, JFileChooser, ListSelectionModel, BorderFactory,
                         JTextField, JList, JCheckBox, DefaultListModel,
                         SwingWorker, JProgressBar, ProgressMonitor, SwingUtilities)
from javax.swing.table import AbstractTableModel, DefaultTableModel
from javax.swing.tree import DefaultMutableTreeNode, DefaultTreeModel
from javax.swing.event import ListSelectionListener, ListDataListener
from javax.swing.border import EmptyBorder
from javax.swing.filechooser import FileNameExtensionFilter

from java.awt import BorderLayout, FlowLayout, Font, GridLayout, Cursor
from java.awt.event import WindowAdapter, MouseAdapter, KeyListener

#==============================================
# Project structure and file managment
#==============================================

class ProjectImage(object):
    """ Simple class to hold info about a single image file """
    def __init__(self, filename, project_path):
        self.filename = filename
        self.full_path = os.path.join(project_path, "Images", filename)

        base_name, _ = os.path.splitext(self.filename)
        self.roi_path = os.path.join(project_path, "ROI_Files", base_name + "_ROIs.zip")
        self.rois = [] # list of dictionaries
        self.status = "New" 

    def has_roi(self):
        """ Checks if corrosponding ROI file exists """
        return os.path.exists(self.roi_path)
    
    def add_roi(self, roi_data):
        """ Adds an ROI's data to the image"""
        self.rois.append(roi_data)

    def populate_rois_from_zip(self):
        """ Populate roi names from a zip file for images where the roi list in the DB is empty """
        if self.has_roi() and not self.rois:
            # Hidden, non-interactive ROIManager to read files
            rm = RoiManager(True)
            try:
                rm.open(self.roi_path)
                rois_array = rm.getRoisAsArray()

                # clear empty entries before populating
                self.rois = []

                for roi in rois_array:
                    self.rois.append({
                        'roi_name': roi.getName(),
                        'bregma': 'N/A',
                        'status': 'From File'
                    })
            finally:
                # ensure manager is closed
                rm.close()

class Project(object):
    """ Class representing a project, holding its structure and data once opened from folder """
    def __init__(self, root_dir):
        self.root_dir = root_dir
        self.name = os.path.basename(os.path.normpath(root_dir))
        self.paths = self._discover_paths()
        self._verify_and_create_dirs()
        self.images = [] # list of ProjectImage objects
        self._load_project_db()
        self._scan_for_new_images()
        self.images.sort(key=self._get_natural_sort_key)

    def _get_natural_sort_key(self, image_object):
        """ correctly sorts filenames by extracting leading number """
        try:
            return int(image_object.filename.split('_')[0])
        except (ValueError, IndexError):
            return float('inf')
        
    def _verify_and_create_dirs(self):
        """ Check for essential project files and creates them if missing"""
        for key, path in self.paths.items():
            if not os.path.exists(path):
                try:
                    # For csv databases
                    if path.endswith(".csv"):
                        headers = []
                        if key == 'roi_db':
                            headers = ['filename', 'roi_name', 'bregma', 'status']
                        elif key == 'image_status_db': 
                            headers = ['filename', 'status']
                        elif key == 'results_db':
                            headers = ['filename', 'roi_name', 'roi_area', 'brema_value', 'cell_count', 'total_cell_area' ]

                        if headers:
                            with open(path, 'w') as csvfile:
                                writer = csv.writer(csvfile)
                                writer.writerow(headers)
                                IJ.log("Created missing project database: {}".format(path))
                    else:
                        os.makedirs(path)
                        IJ.log("Created missing project directory: {}".format(path))
                except OSError as e:
                    IJ.log("Error creating directory {}: {}".format(path, e))

    def _discover_paths(self):
        """ Creates dict of essential project components """
        return {
            'images': os.path.join(self.root_dir, 'Images'),
            'rois': os.path.join(self.root_dir, 'ROI_Files'),
            'processed': os.path.join(self.root_dir, 'Processed_Images'),
            'probabilities': os.path.join(self.root_dir, 'Ilastik_Probabilites'),
            'temp': os.path.join(self.root_dir, 'temp'),
            'roi_db': os.path.join(self.root_dir, 'Roi_DB.csv'),
            'image_status_db': os.path.join(self.root_dir, 'Image_Status_DB.csv'),
            'results_db': os.path.join(self.root_dir, 'Results_DB.csv')
        }

    def _load_project_db(self):
        """
        Loads and parses both databases and immediately tries to populate
        ROI details from zip files if they are missing from the DB.
        """
        images_map = {}

        # Load Image Status DB
        status_db_path = self.paths['image_status_db']
        if os.path.exists(status_db_path):
            with open(status_db_path, 'r') as csvfile:
                reader = csv.DictReader(csvfile)
                for row in reader:
                    filename = row['filename']
                    if filename not in images_map:
                        images_map[filename] = ProjectImage(filename, self.root_dir)
                    images_map[filename].status = row.get('status', 'New')

        # Load ROI DB
        roi_db_path = self.paths['roi_db']
        if os.path.exists(roi_db_path):
            with open(roi_db_path, 'r') as csvfile:
                reader = csv.DictReader(csvfile)
                for row in reader:
                    filename = row['filename']
                    if filename not in images_map:
                        images_map[filename] = ProjectImage(filename, self.root_dir)
                    images_map[filename].add_roi(row)

        # Loop through all loaded images and populate from zip if needed 
        for image in images_map.values():
            image.populate_rois_from_zip()

        self.images = sorted(images_map.values(), key=lambda img: img.filename)

    def _scan_for_new_images(self):
        """ Scans images folder for any files not already loaded from the DBs. """
        if not os.path.isdir(self.paths['images']):
            return
        
        existing_filenames = {img.filename for img in self.images}
        for f in sorted(os.listdir(self.paths['images'])):
            if f.lower().endswith(('.tif', '.tiff', 'jpg', 'jpeg')) and f not in existing_filenames:
                new_image = ProjectImage(f, self.root_dir)
                new_image.status = "Untracked"
                new_image.populate_rois_from_zip() # new images
                self.images.append(new_image)

    def sync_project_db(self):
        """ Master save function that syncs both databases. """
        roi_success = self._sync_roi_db()
        status_success = self._sync_image_status_db()
        return roi_success and status_success

    def _sync_roi_db(self):
        """ Rewrites the Roi_DB.csv (ROI data) from memory. """
        db_path = self.paths['roi_db']
        headers = ['filename', 'roi_name', 'bregma', 'status']
        try:
            with open(db_path, 'wb') as csvfile:
                writer = csv.DictWriter(csvfile, fieldnames=headers)
                writer.writeheader()
                for image in self.images:
                    if not image.rois:
                        continue # Skip images with no ROIs
                    for roi_data in image.rois:
                        row = {
                            'filename': image.filename,
                            'roi_name': roi_data.get('roi_name', 'N/A'),
                            'bregma': roi_data.get('bregma', 'N/A'),
                            'status': roi_data.get('status', 'Pending')
                        }
                        writer.writerow(row)
            return True
        except IOError as e:
            IJ.log("Error syncing ROI DB: {}".format(e))
            return False

    def _sync_image_status_db(self):
        """ Rewrites the Image_Status_DB.csv from memory. """
        db_path = self.paths['image_status_db']
        headers = ['filename', 'status']
        try:
            with open(db_path, 'wb') as csvfile:
                writer = csv.DictWriter(csvfile, fieldnames=headers)
                writer.writeheader()
                for image in self.images:
                    writer.writerow({'filename': image.filename, 'status': image.status})
            return True
        except IOError as e:
            IJ.log("Error syncing Image Status DB: {}".format(e))
            return False

#==============================================
# Main GUI Classes
#==============================================

class ProjectManagerGUI(WindowAdapter):
    """ Builds and manages the main GUI, facilitating dialogs and and controling the script """
    def __init__(self):
        self.project = None
        self.unsaved_changes = False
        self.save_proj_item = None
        
        self.frame = JFrame("Project Manager")
        self.frame.setSize(900, 700)
        self.frame.setLayout(BorderLayout())
        self.frame.setDefaultCloseOperation(JFrame.DO_NOTHING_ON_CLOSE)

        self.build_menu()
        self.build_main_panel()
        self.build_status_bar()

        self.frame.addWindowListener(self)

    def show(self):
        self.frame.setLocationRelativeTo(None)
        self.frame.setVisible(True)

    def build_menu(self):
        menu_bar = JMenuBar()
        file_menu = JMenu("File")
        open_proj_item = JMenuItem("Open Project", actionPerformed=self.open_project_action)
        self.save_proj_item = JMenuItem("Save Project", actionPerformed=self.save_project_action, enabled=False)
        exit_item = JMenuItem("Exit", actionPerformed=lambda event: self.frame.dispose())
        file_menu.add(open_proj_item)
        file_menu.add(self.save_proj_item)
        file_menu.addSeparator()
        file_menu.add(exit_item)
        menu_bar.add(file_menu)
        self.frame.setJMenuBar(menu_bar)

    def build_main_panel(self):
        # Project header
        self.project_name_label = JLabel("No Project Loaded")
        self.project_name_label.setFont(Font("SansSerif", Font.BOLD, 16))
        self.project_name_label.setBorder(EmptyBorder(10,10,10,10))
        self.frame.add(self.project_name_label, BorderLayout.NORTH)

        # File Tree
        root_node = DefaultMutableTreeNode("Project")
        self.tree_model = DefaultTreeModel(root_node)
        self.file_tree = JTree(self.tree_model)
        tree_scroll_pane = JScrollPane(self.file_tree)

        right_panel = JPanel(BorderLayout())

        # Image table 
        image_cols = ["Filename", "ROI File", "# ROIs", "Status"]
        self.image_table_model = DefaultTableModel(None, image_cols)
        self.image_table = JTable(self.image_table_model)
        self.image_table.setSelectionMode(ListSelectionModel.MULTIPLE_INTERVAL_SELECTION)
        self.image_table.getSelectionModel().addListSelectionListener(self.on_image_selection)
        image_table_pane = JScrollPane(self.image_table)
        image_table_pane.setBorder(BorderFactory.createTitledBorder("Project Images"))
        
        # ROI detail table
        self.roi_table = JTable()
        roi_table_pane = JScrollPane(self.roi_table)
        roi_table_pane.setBorder(BorderFactory.createTitledBorder("ROI Details (Editable)"))
        
        # Split pane for two tables
        right_split_pane = JSplitPane(JSplitPane.VERTICAL_SPLIT, image_table_pane, roi_table_pane)
        right_split_pane.setDividerLocation(300)
        right_panel.add(right_split_pane, BorderLayout.CENTER)

        # Main split pane for tree and tables
        main_split_pane = JSplitPane(JSplitPane.HORIZONTAL_SPLIT, tree_scroll_pane, right_panel)
        main_split_pane.setDividerLocation(220)
        self.frame.add(main_split_pane, BorderLayout.CENTER)

    def build_status_bar(self):
        control_panel = JPanel(BorderLayout())
        control_panel.setBorder(EmptyBorder(5,5,5,5))

        self.status_label = JLabel("Open a project folder to begin")
        control_panel.add(self.status_label, BorderLayout.CENTER)
        
        button_panel = JPanel(FlowLayout(FlowLayout.RIGHT))

        self.import_button = JButton("Import Images", enabled=False)
        self.select_all_button = JButton("Select All / None")
        self.roi_button = JButton("Define/Edit ROIs", enabled=False)
        self.quant_button = JButton("Run Quantification", enabled=False)

        button_panel.add(self.import_button)
        button_panel.add(self.select_all_button)
        button_panel.add(self.roi_button)
        button_panel.add(self.quant_button)

        control_panel.add(button_panel, BorderLayout.EAST)
        self.frame.add(control_panel, BorderLayout.SOUTH)

        self.import_button.addActionListener(self.import_images_action)
        self.select_all_button.addActionListener(self.toggle_select_all_action)
        self.roi_button.addActionListener(self.open_roi_editor_action)
        self.quant_button.addActionListener(self.open_quantification_dialog_action)

    def set_unsaved_changes(self, state):
        """ Updates UI to show if there are unsaved changes """
        self.unsaved_changes = state
        self.save_proj_item.setEnabled(state)
        title = "Project Manager"
        if state:
            title += " *"
        self.frame.setTitle(title)

    # Event Handlers and actions

    def open_project_action(self, event):
        chooser = JFileChooser()
        chooser.setFileSelectionMode(JFileChooser.DIRECTORIES_ONLY)
        chooser.setDialogTitle("Select Project Directory")
        if chooser.showOpenDialog(self.frame) == JFileChooser.APPROVE_OPTION:
            project_dir = chooser.getSelectedFile().getAbsolutePath()
            self.load_project(project_dir)

    def save_project_action(self, event):
        """ Saves current state of project to csv file"""
        if not (self.project and self.unsaved_changes):
            return True

        # Sync database
        if self.project.sync_project_db():
            self.status_label.setText("Project saved successfully.")
            self.set_unsaved_changes(False)
            return True
        else:
            self.status_label.setText("Error saving project. See Log.")
            return False

    def on_image_selection(self, event):
        """ called when user selects image(s) in the top table"""
        if not event.getValueIsAdjusting():
            # get count of selected images
            selection_count = self.image_table.getSelectedRowCount()

            # enable define/edit ROIs only if exactly one image selected
            self.roi_button.setEnabled(selection_count == 1)

            # enable run quantification if one or more images selected
            self.quant_button.setEnabled(selection_count > 0)

            if selection_count == 1:
                selected_row = self.image_table.getSelectedRow()
                selected_image = self.project.images[selected_row]
                self.status_label.setText("Selected: {}".format(selected_image.filename))

                # Populate the ROI details table
                editable_model = EditableROIsTableModel(selected_image)
                editable_model.addTableModelListener(lambda e: self.set_unsaved_changes(True))
                self.roi_table.setModel(editable_model)

            elif selection_count > 1:
                self.status_label.setText("Selected: {} images".format(selection_count))
                self.roi_table.setModel(EditableROIsTableModel(None)) # clear bottom table

            else:
                self.status_label.setText("No Image(s) Selected")
                self.roi_table.setModel(EditableROIsTableModel(None)) # clear table

    def toggle_select_all_action(self, event):
        """ Selects all rows in the image table if not all are selected or clears selection if all are already selected"""
        row_count = self.image_table.getRowCount()
        if row_count == 0:
            return
        
        selected_count = self.image_table.getSelectedRowCount()

        if selected_count == row_count:
            self.image_table.clearSelection()
        else:
            self.image_table.selectAll()

    def open_roi_editor_action(self, event):
        """ Opens ROI editor window for selected image """
        selected_row = self.image_table.getSelectedRow()
        if selected_row != -1:
            selected_image = self.project.images[selected_row]

            editor = ROIEditor(self, self.project, selected_image)
            editor.show()

    def open_quantification_dialog_action(self, event):
        """ Gathers selected images and opens the quantification settings dialog. """
        selected_rows = self.image_table.getSelectedRows()
        if not selected_rows: return

        selected_images = [self.project.images[row] for row in selected_rows]

        quant_dialog = QuantificationDialog(self.frame, selected_images)
        settings = quant_dialog.show_dialog()

        if settings:
            progress_dialog = ProgressDialog(self.frame, "Processing images...", 100)
            worker = QuantificationWorker(self.project, settings, progress_dialog)
            progress_dialog.setVisible(True)
            worker.execute()

    def import_images_action(self, event):
        """ Opens file chooser to select and copy images into project structure """
        if not self.project:
            return
        
        chooser = JFileChooser()
        chooser.setDialogTitle("Select Images to Import")
        chooser.setMultiSelectionEnabled(True)
        chooser.setFileFilter(FileNameExtensionFilter("Image Files (tif, tiff, jpg, jpeg)", ["tif","tiff","jpg","jpeg"]))

        if chooser.showOpenDialog(self.frame) == JFileChooser.APPROVE_OPTION:
            selected_files = chooser.getSelectedFiles()
            images_dir = self.project.paths['images']
            newly_added_count = 0

            for source_file in selected_files:
                source_path = source_file.toPath()
                dest_file = File(images_dir, source_file.getName())
                dest_path = dest_file.toPath()

                # Check if file with name already exists
                if dest_file.exists():
                    IJ.error("Skipped Import", "{} already exists in the project").format(source_file.getName())
                    continue

                try:
                    Files.copy(source_path, dest_path, StandardCopyOption.REPLACE_EXISTING)

                    # Create projectImage object and add it to memory
                    new_image = ProjectImage(dest_file.getName(), self.project.root_dir)
                    new_image.status = "Untracked"
                    self.project.images.append(new_image)
                    newly_added_count += 1

                except Exception as e:
                    error_msg ="Failed to import '{}': {}".format(source_file.getName(), e) 
                    IJ.log(error_msg)
                    JOptionPane.showMessageDialog(self.frame, error_msg, "Import Error", JOptionPane.ERROR_MESSAGE)

            if newly_added_count > 0:
                self.status_label.setText("Successfully imported {} new images.".format(newly_added_count))
                self.update_ui_for_project()
                self.set_unsaved_changes(True)     


    def windowClosing(self, event):
        """ Called when user attempts to close window, intercepts and prompts to save changes """
        if self.unsaved_changes:
            title = "Unsaved Changes"
            message = "You have unsaved changes. Would you like to save before closing?"

            # show dialog
            result = JOptionPane.showConfirmDialog(self.frame, message, title, JOptionPane.YES_NO_CANCEL_OPTION)

            if result == JOptionPane.YES_OPTION:
                if self.save_project_action(None):
                    self.frame.dispose()
                # If save fails, do nothing

            elif result == JOptionPane.NO_OPTION:
                self.frame.dispose()

            # if cancel, do nothing

        else: # no unsaved changes
            self.frame.dispose()

    # UI update logic
    def load_project(self, project_dir):
        """ Loads a project's data and update entire UI"""
        self.status_label.setText("Loading Project {}".format(project_dir))
        try:
            self.project = Project(project_dir)
            self.update_ui_for_project()

            self.import_button.setEnabled(True)

            self.status_label.setText("Sucessfully loaded project: {}".format(self.project.name))
            self.set_unsaved_changes(False)
        except Exception as e:
            self.status_label.setText("Error Loading Project. See Log for details")
            IJ.log("--- ERROR while loading project ---")
            IJ.log(traceback.format_exc())
            IJ.log("-----------------------------------")

    def update_ui_for_project(self):
        """ Populates the UI componenets with the current project's data """
        if not self.project:
            return
        
        # Update name
        self.project_name_label.setText("Project: " + self.project.name)
        
        # Image table
        while self.image_table_model.getRowCount() > 0:
            self.image_table_model.removeRow(0)
        
        for img in self.project.images:
            roi_file_status = "Yes" if img.has_roi() else "No"
            self.image_table_model.addRow([
                img.filename,
                roi_file_status,
                len(img.rois),
                img.status
            ])

        # update file tree 
        root_node = DefaultMutableTreeNode(self.project.name)
        for name, path in self.project.paths.items():
            # show directorys and key files
            if os.path.isdir(path) or name.endswith('_db'):
                node = DefaultMutableTreeNode(os.path.basename(path))
                root_node.add(node)

        self.tree_model.setRoot(root_node)

    def refresh_project_and_ui(self):
        """
        Reloads the project from disk and updates the UI tables.
        This method will be called by the ROIEditor when it closes.
        """
        if self.project:
            self.load_project(self.project.root_dir)

class ROIEditor(WindowAdapter):
    """ Creates Jframe with all tools for creating, modifing and managing ROIs for a single image """
    def __init__(self, parent_gui, project, project_image):
        self.parent_gui = parent_gui
        self.project = project
        self.image_obj = project_image
        self.win = None

        # Open Image and create canvas and imagewindow to hold it
        self.imp = IJ.openImage(self.image_obj.full_path)
        if not self.imp:
            IJ.error("Failed to open image:", self.image_obj.full_path)
            return
        self.imp.show()
        self.win = self.imp.getWindow()

        # Open rm
        self.rm = RoiManager(True) 
        self.rm.reset()

        if self.image_obj.has_roi():
            self.rm.runCommand("Open", self.image_obj.roi_path)

        # Build GUI
        self.frame = JDialog(self.win, "ROI Editor Controls: " + self.image_obj.filename, False)
        self.frame.setSize(350,700)
        self.frame.addWindowListener(self)
        self.frame.setLayout(BorderLayout(5,5))

        # ROI list
        self.roi_list_model = DefaultListModel()
        self.update_roi_list_from_manager()
        self.roi_list = JList(self.roi_list_model)
        self.roi_list.setSelectionMode(ListSelectionModel.SINGLE_SELECTION)
        # listener to update text fields when roi is selected
        self.roi_list.addListSelectionListener(self._on_roi_select)

        list_pane = JScrollPane(self.roi_list)
        list_pane.setBorder(BorderFactory.createTitledBorder("ROIs"))

        # Edit Panel
        edit_panel = JPanel(GridLayout(0,2,5,5))
        edit_panel.setBorder(BorderFactory.createTitledBorder("Edit Selected ROI"))
        self.roi_name_field = JTextField()
        self.bregma_field = JTextField()
        edit_panel.add(JLabel("ROI Name: "))
        edit_panel.add(self.roi_name_field)
        edit_panel.add(JLabel("Bregma Value:"))
        edit_panel.add(self.bregma_field)

        self.show_all_checkbox = JCheckBox("Show All ROIs")
        self.show_all_checkbox.addActionListener(self._toggle_show_all)
        edit_panel.add(self.show_all_checkbox)
        edit_panel.add(JLabel(""))

        # Button panel
        button_panel = JPanel(GridLayout(0, 1, 10, 10))
        button_panel.setBorder(BorderFactory.createEmptyBorder(10,10,10,10))

        create_button = JButton("Create New From Selection", actionPerformed=self._create_new_roi)
        update_button = JButton("Update Selected ROI", actionPerformed=self._update_selected_roi)
        delete_button = JButton("Delete Selected ROI", actionPerformed=self._delete_selected_roi)
        finalize_button = JButton("Mark Image Ready For Processing", actionPerformed=self._finalize_image)
        save_button = JButton("Save & Close", actionPerformed=self._save_and_close)


        button_panel.add(create_button)
        button_panel.add(update_button)
        button_panel.add(delete_button)
        button_panel.add(finalize_button)
        button_panel.add(save_button)

        # Controls
        south_contols = JPanel(BorderLayout())
        south_contols.add(edit_panel, BorderLayout.NORTH)
        south_contols.add(button_panel, BorderLayout.CENTER)

        self.frame.add(list_pane, BorderLayout.CENTER)
        self.frame.add(south_contols, BorderLayout.SOUTH)

    def show(self):
        if not self.frame or not self.win:
            return # dont show if init failed
        
        img_win_x = self.win.getX()
        img_win_width = self.win.getWidth()
        img_win_y = self.win.getY()
        
        # Position control frame to right of image window
        self.frame.setLocation(img_win_x + img_win_width, img_win_y)
        self.frame.setVisible(True)

    def update_roi_list_from_manager(self):
        """ Syncs JList with IJ roi manager"""
        self.roi_list_model.clear()
        rois = self.rm.getRoisAsArray()
        for roi in rois:
            self.roi_list_model.addElement(roi.getName())

    def _toggle_show_all(self, event):
        """ toggles visibility of all ROIs in image """
        checkbox = event.getSource()

        if checkbox.isSelected():
            self.rm.runCommand("Show All")
        else:
            self.rm.runCommand("Show None")

    def _on_roi_select(self, event):
        """ when roi is selected in list, update text fields"""
        if not event.getValueIsAdjusting():
            selected_index = self.roi_list.getSelectedIndex()
            if selected_index != -1:
                self.rm.select(self.imp, selected_index)
                selected_name = self.roi_list.getSelectedValue()
                self.roi_name_field.setText(selected_name)

                # Find Roi data in project data
                bregma_val = 'N/A'
                for roi_data in self.image_obj.rois:
                    if roi_data.get('roi_name') == selected_name:
                        bregma_val = roi_data.get('bregma', 'N/A')
                        break
                self.bregma_field.setText(bregma_val)

    def _create_new_roi(self, event):
        """ Creates new ROI from current selection and applies the name and bregma vales from the text field"""
        current_roi = self.imp.getRoi()
        if not current_roi:
            IJ.error("No Selection found", "Please create a selection on the image first.")
            return
        
        new_name = self.roi_name_field.getText()
        new_bregma = self.bregma_field.getText()

        if not new_name:
            IJ.error("Name Required", "Pleaser enter a name for new the ROI in the 'ROI Name' field")
            return
        
        if not self._is_name_unique(new_name):
            IJ.error("Duplicate Name", "An ROI with the name {} already exists. Use a unique name.".format(new_name))
            return
        
        current_roi.setName(new_name)
        self.rm.addRoi(current_roi)

        self.image_obj.add_roi({
            'roi_name': new_name,
            'bregma': new_bregma,
            'status': 'Defined'
        })

        self.roi_list_model.addElement(new_name)
        self.roi_list.setSelectedValue(new_name, True)

    def _is_name_unique(self, name_to_check, ignore_index=-1):
        """ Checks a given game is not in the ROI manager already """
        rois = self.rm.getRoisAsArray()
        for i, roi in enumerate(rois):
            if i == ignore_index:
                continue
            if roi.getName() == name_to_check:
                return False
        return True    

    def _update_selected_roi(self,event):
        selected_index = self.roi_list.getSelectedIndex()
        if selected_index == -1:
            IJ.error("No ROI selected.")
            return

        new_name = self.roi_name_field.getText()
        new_bregma = self.bregma_field.getText()

        original_index = self.roi_list.getSelectedIndex()

        # Update ROI name in the ROI Manager
        self.rm.runCommand("Rename", new_name)
        
        # Update data in our project structure
        # Find the original name to locate the data entry
        original_name = self.roi_list.getSelectedValue()
        found = False
        for roi_data in self.image_obj.rois:
            if roi_data.get('roi_name') == original_name:
                roi_data['roi_name'] = new_name
                roi_data['bregma'] = new_bregma
                roi_data['status'] = 'Modified'
                found = True
                break
        
        # If it was a newly created ROI, it won't be in the list yet
        if not found:
            self.image_obj.add_roi({
                'roi_name': new_name,
                'bregma': new_bregma,
                'status': 'Defined'
            })
            
        if original_index != -1:
            self.roi_list_model.setElementAt(new_name, original_index)

    def _delete_selected_roi(self, event):
        selected_index = self.roi_list.getSelectedIndex()
        if selected_index == -1:
            IJ.error("No ROI selected")
            return

        # Get roi name to rmeove from internal data list
        roi_name_to_delete = self.roi_list.getSelectedValue()

        # Tell hidden RoiManager to delete selected ROI
        self.rm.select(selected_index)
        self.rm.runCommand("Delete")

        # delete dictionary from data list
        self.image_obj.rois = [roi for roi in self.image_obj.rois if roi.get('roi_name') != roi_name_to_delete]

        if selected_index != -1:
            self.roi_list_model.removeElementAt(selected_index)

        # refresh visible list from update manager & clear text field
        self.roi_name_field.setText("")
        self.bregma_field.setText("")

    def _finalize_image(self, event):
        self.image_obj.status = "Finalized"

        # Now we call the specific method to save only the image statuses
        if self.project._sync_image_status_db():
            IJ.log("Image '{}' status updated and saved.".format(self.image_obj.filename))
        else:
            IJ.error("Save Failed", "Could not save the image status database. See Log.")
            return

        self.parent_gui.refresh_project_and_ui()
        self.cleanup()


    def _save_and_close(self, event=None):
        """
        Synchronizes the ROI Manager with the project's internal data,
        then saves both the ROI zip file and the project CSV database.
        """
        # Get the final list of ROIs from the manager, which is the source of truth for shapes and names.
        rois_from_manager = self.rm.getRoisAsArray()

        # Create a lookup map of existing ROI data (name -> full data dict) from internal project data to preserve metadata like bregma.
        existing_roi_data_map = {
            roi_info['roi_name']: roi_info for roi_info in self.image_obj.rois
        }

        # This will be the new, synchronized list of ROI data for the image object.
        new_rois_list = []

        # Loop through what's currently in the manager.
        for roi in rois_from_manager:
            roi_name = roi.getName()
            
            # Check if we have existing metadata for this ROI.
            if roi_name in existing_roi_data_map:
                # Yes, so we carry over its existing data dictionary, preserving its bregma and status.
                new_rois_list.append(existing_roi_data_map[roi_name])
            else:
                # No, this is a brand new ROI created in this session. We add it to our list with default values.
                new_rois_list.append({
                    'roi_name': roi_name,
                    'bregma': '0.00',  # Default Bregma for new ROIs
                    'status': 'Defined'
                })

        # Replace the image object's old ROI list with the newly synchronized one.
        self.image_obj.rois = new_rois_list

        # Now, perform the final save operations with the fully consistent data.
        self.rm.runCommand("Save", self.image_obj.roi_path)
        self.project._sync_roi_db()

        self.parent_gui.refresh_project_and_ui()
        self.cleanup()

    def cleanup(self):
        """ Closes image and disposes frame """
        if self.imp:
            self.imp.close()
        self.frame.dispose()

    def windowClosing(self, event):
        """ called when x on window is clicked """
        self.cleanup()

class EditableROIsTableModel(AbstractTableModel):
    """ Helper class to creat custom table model that allows editing of ROI details table"""
    def __init__(self, project_image):
        self.image = project_image
        self.headers = ["ROI Name", "Bregma", "Status"]
        self.data = self.image.rois if self.image else []
        self.header_map = {'roi_name': 0, 'bregma': 1, 'status': 2}

    def getRowCount(self):
        return len(self.data)
    
    def getColumnCount(self):
        return len(self.headers)
    
    def getValueAt(self, rowIndex, columnIndex):
        key = self.headers[columnIndex].lower().replace(" ", "_")
        return self.data[rowIndex].get(key, "")
    
    def getColumnName(self, columnIndex):
        return self.headers[columnIndex]
    
    def isCellEditable(self, rowIndex, columnIndex):
        return True

    def setValueAt(self, aValue, rowIndex, columnIndex):
        key = self.headers[columnIndex].lower().replace(" ", "_")
        self.data[rowIndex][key] = aValue
        # Updates data in projectImage directly
        self.fireTableCellUpdated(rowIndex, columnIndex)


#==============================================
# Quantification dialog class
#==============================================

class QuantificationDialog(JDialog):
    """
    modal dialog to configure setting for a batch quantification process.
    Returns selected settings to be passed to the worker class.
    """
    def __init__(self, parent_frame, selected_images):
        super(QuantificationDialog, self).__init__(parent_frame, "Quantification Setting", True)

        self.selected_images = selected_images
        self.settings = None
        self.available_models = self._get_models()

        # Main panel
        main_panel = JPanel(BorderLayout(10,10))
        main_panel.setBorder(EmptyBorder(15,15,15,15))
        self.add(main_panel)

        # Info label
        info_text = "Ready to process {} selected images.".format(len(self.selected_images))
        info_label = JLabel(info_text)
        main_panel.add(info_label, BorderLayout.NORTH)

        # Settings panel
        settings_panel = JPanel(GridLayout(0,2,10,10))
        settings_panel.setBorder(BorderFactory.createTitledBorder("Processing Options"))

        # workflow selection
        workflows = ["cFosDAB+ Detection (Generic Model)", "cFosDAB+ Detection (region specific model)"]
        settings_panel.add(JLabel("Choose Your Quantification Type: "))
        self.workflow_combo = JComboBox(workflows)
        settings_panel.add(self.workflow_combo)

        # Verbose images or no
        settings_panel.add(JLabel("Display Options: "))
        self.show_images_checkbox = JCheckBox("Show images during processing", False)
        settings_panel.add(self.show_images_checkbox)

        main_panel.add(settings_panel, BorderLayout.CENTER)

        # Bottom button panel
        button_panel = JPanel(FlowLayout(FlowLayout.RIGHT))
        run_button = JButton("Run", actionPerformed=self._run_action)
        cancel_button = JButton("Cancel", actionPerformed=self._cancel_action)
        button_panel.add(run_button)
        button_panel.add(cancel_button)
        main_panel.add(button_panel, BorderLayout.SOUTH)

        self.pack()

    def _run_action(self, event):
        """ Gathers settings into dictionary and closes dialog """
        selected_workflow = self.workflow_combo.getSelectedItem()

        if selected_workflow == "cFosDAB+ Detection (Generic Model)": 
            self.settings = {
                'images': self.selected_images,
                'pixel_classifier': self.available_models['PIXEL_cFosDAB_TiffIO_Generic'],
                'object_classifier': self.available_models['OBJECT_cFosDAB_TiffIO_Generic'],  
                'show_images': self.show_images_checkbox.isSelected()
                }
        elif selected_workflow == "cFosDAB+ Detection (region specific model)":
            IJ.error("NOT IMPLEMENTED", "Havnent made this yet. use the generic model.")
        
        self.dispose()

    def _cancel_action(self,event):
        """ Leaves settings=None and closes dialog"""
        self.settings = None
        self.dispose()

    def show_dialog(self):
        """ Public method called by the GUI """
        self.setLocationRelativeTo(self.getParent())
        self.setVisible(True)
        return self.settings
    
    def _get_models(self):
        """
        Finds models in a dedicated folder inside Fiji's 'lib' directory.
        This works by locating the core ImageJ .jar file
        to determine the Fiji root directory, regardless of how
        the application was launched.
        """
        from java.net import URLDecoder
        from java.lang import System

        MODELS_FOLDER_NAME = "cell-quantifier-toolkit-models"
        models = {}
        
        try:
            class_loader = IJ.getClassLoader()
            if class_loader is None:
                raise IOError("Could not get ImageJ ClassLoader.")

            resource_url = class_loader.getResource("IJ_Props.txt")
            if resource_url is None:
                raise IOError("Could not find core resource 'IJ_Props.txt'. Is Fiji installed correctly?")

            url_str = URLDecoder.decode(resource_url.toString(), "UTF-8")
            path_part = url_str.split("!")[0].replace("jar:file:", "")

            if System.getProperty("os.name").lower().startswith("windows") and path_part.startswith("/"):
                path_part = path_part[1:]

            jar_file = File(path_part)
            fiji_root_file = jar_file.getParentFile().getParentFile()
            fiji_root = fiji_root_file.getAbsolutePath()
           
            models_dir = os.path.join(fiji_root, "lib", MODELS_FOLDER_NAME)

            if os.path.isdir(models_dir):
                for f in os.listdir(models_dir):
                    if f.lower().endswith('.ilp'):
                        display_name = os.path.splitext(f)[0]
                        full_path = os.path.join(models_dir, f)
                        models[display_name] = full_path
            else:
                IJ.log("Model directory not found. Please create it at: " + models_dir)

        except Exception as e:
            IJ.log("Error discovering models: " + str(e))
            IJ.log(traceback.format_exc())

        return models

class ProgressDialog(JDialog):
    """ A simple, non-modal dialog to display a progress bar. """
    def __init__(self, parent_frame, title, max_value):
        super(ProgressDialog, self).__init__(parent_frame, title, False)
        self.progress_bar = JProgressBar(0, max_value)
        self.progress_bar.setStringPainted(True)
        self.add(self.progress_bar)
        self.pack()
        self.setSize(400, 80)
        self.setLocationRelativeTo(parent_frame)

#==============================================
# Processor Classes
#==============================================

class QuantificationWorker(SwingWorker):
    """ Processor Classs facilitating image quantification on a background thread given settings from the dialog """
    def __init__(self, project, settings, progress_dialog):
        super(QuantificationWorker, self).__init__()
        self.project = project
        self.settings = settings
        self.progress_dialog = progress_dialog
        self.all_results = []

    def doInBackground(self):
        """ This method uses a filesystem bridge to run the pixelclassifications on a background thread """

        class UpdateProgressBarTask(Runnable):
            def __init__(self, dialog, value):
                self.dialog = dialog
                self.value = value
            def run(self):
                self.dialog.progress_bar.setValue(self.value)

        images_to_process = self.settings['images']
        total_rois = sum(len(img.rois) for img in images_to_process)
        if total_rois == 0: 
            return "No ROIs to process."
        roi_counter = 0

        for image_obj in images_to_process:
            if self.isCancelled(): 
                break
            
            imp_original = IJ.openImage(image_obj.full_path)
            imp_original_name = image_obj.filename
            if not imp_original:
                raise Exception("ERROR: Failed to open original image: " + image_obj.full_path)
            
            if self.settings.get('show_images', True):
                imp_original.show()
            else:
                imp_original.close()


            # This inner loop defines 'roi_data' for each ROI in the current image
            for roi_data in image_obj.rois:
                if self.isCancelled(): 
                    break
                
                roi_name = roi_data['roi_name']
                temp_cropped_path = None # Define here for the finally block
                
                try:
                    rm = RoiManager(True)
                    rm.open(image_obj.roi_path)
                    roi = rm.getRoi(rm.getIndex(roi_name))
                    rm.close()
                    if not roi:
                        raise Exception("Could not find ROI '" + roi_name + "' in the ROI file.")

                    # Get bounding box coordinates
                    roi_x = roi.getBounds().x
                    roi_y = roi.getBounds().y

                    roi_for_analysis = roi.clone()

                    imp_cropped = imp_original.duplicate()
                    imp_cropped.setRoi(roi_for_analysis)
                    IJ.run(imp_cropped, "Crop", "")
                    
                    # set up the file paths we need and save a temp version of the cropped image
                    base_name = "{}_{}".format(os.path.splitext(image_obj.filename)[0], roi_data['roi_name'])
                    temp_cropped_path = os.path.join(self.project.paths['temp'], base_name + "_cropped.tif")
                    prob_map_path = os.path.join(self.project.paths['probabilities'], base_name)
                    IJ.saveAs(imp_cropped, "Tiff", temp_cropped_path)

                    if self.settings.get('show_images', True):
                        imp_cropped.show()
                    else:
                        imp_cropped.close()

                    # Run ilastik classification 
                    result_imp = self._run_ilastik_classification(roi_for_analysis, temp_cropped_path, imp_original_name, prob_map_path)

                    # Process and analyze in fiji
                    analysis = self._analyze_results(result_imp, roi_for_analysis, roi_x, roi_y)

                    single_roi_result = {
                        'filename': image_obj.filename,
                        'roi_name': roi_data['roi_name'],
                        'roi_area': roi.getStatistics().area, # Get area of the main analysis ROI
                        'brema_value': roi_data.get('bregma', 'N/A'),
                        'cell_count': analysis['count'],
                        'total_cell_area': analysis['total area']
                    }
                    # Add this result to the master list that will be saved later
                    self.all_results.append(single_roi_result)

                    particle_outlines = analysis.get('outlines', [])

                    if particle_outlines:
                        outlines_to_add = particle_outlines + [roi]

                        overlay = imp_original.getOverlay()
                        if overlay is None:
                            overlay = Overlay()
                            imp_original.setOverlay(overlay)

                        for outline_roi in outlines_to_add:
                            overlay.add(outline_roi)
                        imp_original.updateAndDraw()   

                        if self.settings.get('show_images', True):
                            imp_original.show()
                        else:
                            imp_original.close()

                    else:
                        print("fail")

                except Exception as e:
                    IJ.log("ERROR processing ROI '{}' in '{}': {}".format(roi_name, image_obj.filename, e))
                    continue 

                finally:
                    if temp_cropped_path and os.path.exists(temp_cropped_path):
                        try:
                            os.remove(temp_cropped_path)
                        except Exception as ex:
                            IJ.log("Warning: Could not delete temporary file " + temp_cropped_path)
                    
                    roi_counter += 1
                    progress = int(100.0 * roi_counter / total_rois)
                    update_task = UpdateProgressBarTask(self.progress_dialog, progress)
                    SwingUtilities.invokeLater(update_task)
            
            if imp_original:
                export_path = os.path.join(self.project.paths['processed'], os.path.splitext(imp_original_name)[0] + "_processed.tiff")
                
                image_to_save = None
                
                # Check if an overlay exists to be flattened
                if imp_original.getOverlay():
                    IJ.log("Flattening overlay for " + imp_original_name)
                    # flatten() creates a NEW image with the overlay burned in.
                    image_to_save = imp_original.flatten()
                else:
                    # No overlay, so we will just save the original.
                    image_to_save = imp_original

                # Save the designated image (either the new flattened one or the original).
                IJ.saveAs(image_to_save, "Tiff", export_path)

                # Manage windows based on user settings.
                if self.settings.get('show_images', True):
                    image_to_save.show() # Show the final result.
                    # If we created a new flattened image, close the old one with the interactive overlay.
                    if image_to_save is not imp_original:
                        imp_original.close()
                else:
                    # If not showing images, clean up everything.
                    image_to_save.close()
                    if image_to_save is not imp_original:
                        imp_original.close()
                    
        return "Batch processing complete. {} ROIs processed.".format(roi_counter)
    
    def _run_ilastik_classification(self, roi, temp_cropped_path, img_name, prob_map_path):
        """ Segment input image using two step ilastik workflow. Generate proability maps with pixel classification workflow,
            save those results, and then generate object maps with object classifcation workflow."""
        try:
            pixel_classifier = self.settings['pixel_classifier']
            object_classifer = self.settings['object_classifier']

            pixel_prob_path = prob_map_path + "_probabilities.tif"
            object_prob_path = prob_map_path + "_objects.tif"
            
            # Run pixel classification
            if os.path.exists(object_prob_path):
                result_imp = IJ.openImage(object_prob_path)
                if self.settings.get('show_images', True):
                    result_imp.show()

            
            elif os.path.exists(pixel_prob_path):
                result_imp = IJ.openImage(pixel_prob_path)
                if self.settings.get('show_images', True):
                    result_imp.show()

                # Run Object classification with generated probability map
                object_macro_cmd = 'run("Run Object Classification Prediction", "projectfilename=[{}] rawinputimage=[{}] inputproborsegimage=[{}] secondinputtype=Probabilities ");'.format(object_classifer,temp_cropped_path, pixel_prob_path)
                IJ.runMacro(object_macro_cmd)

                result_imp = IJ.getImage()
                if result_imp:
                    IJ.saveAs(result_imp, "Tiff", object_prob_path)
                    if self.settings.get('show_images', True):
                        result_imp.show()
                else:
                    raise Exception("No probability map output from ilastik object classifier.")

            else:
                pixel_macro_cmd = 'run("Run Pixel Classification Prediction", "projectfilename=[{}] inputimage=[{}] pixelclassificationtype=Probabilities");'.format(pixel_classifier, temp_cropped_path)
                IJ.runMacro(pixel_macro_cmd)

                result_imp = IJ.getImage()
                if result_imp:
                    IJ.saveAs(result_imp, "Tiff", pixel_prob_path)
                    if self.settings.get('show_images', True):
                        result_imp.show()
                else:
                    raise Exception("No probability map output from ilastik pixel classifier.")
            
                # Run Object classification with generated probability map
                object_macro_cmd = 'run("Run Object Classification Prediction", "projectfilename=[{}] rawinputimage=[{}] inputproborsegimage=[{}] secondinputtype=Probabilities ");'.format(object_classifer,temp_cropped_path, pixel_prob_path)
                IJ.runMacro(object_macro_cmd)

                result_imp = IJ.getImage()
                if result_imp:
                    IJ.saveAs(result_imp, "Tiff", object_prob_path)
                    if self.settings.get('show_images', True):
                        result_imp.show()
                else:
                    raise Exception("No probability map output from ilastik object classifier.")

            return result_imp
            
        except Exception as e:
            IJ.log("ilastik processing failed: " + str(e))
            raise e

    def _analyze_results(self, result_imp, roi, offset_x, offset_y):
        """ final processing and analysis of ilastik output in fiji. creates selection of points in roi manager. """
        IJ.run("Clear Results")

        # Threshold to select dark and light cells
        IJ.setThreshold(result_imp, 1, 3)
        IJ.run(result_imp, "Convert to Mask", "")

        # watershed to split any cells that were merged
        IJ.run(result_imp, "Watershed", "")
        
        #select only roi
        rm = RoiManager(True)

        # Set up and run the ParticleAnalyzer programmatically
        rt = ResultsTable()
        options = ParticleAnalyzer.SHOW_OUTLINES | ParticleAnalyzer.EXCLUDE_EDGE_PARTICLES
        measurements = Measurements.AREA | Measurements.CENTER_OF_MASS 

        # Instantiate the analyzer
        pa = ParticleAnalyzer(options, measurements, rt, 0, float('inf'), 0.0, 1.0)
        pa.setRoiManager(rm)

        roi_clone_for_analysis = roi.clone()
        roi_clone_for_analysis.setLocation(0, 0) # Move the clone to the top-left.
        result_imp.setRoi(roi_clone_for_analysis)

        # Run analyze particles
        args = "size=0-Infinity circularity=0.00-1.00 show=Nothing clear add"
        IJ.run(result_imp, "Analyze Particles...", args)

        # get stats
        rt = ResultsTable.getResultsTable()
        count = rt.getCounter()
        total_area = 0
        area_col = rt.getColumn(rt.getColumnIndex("Area"))
        if area_col:
            total_area = sum(area_col)

        # Get particle oulines
        particle_outlines_relative = rm.getRoisAsArray()
        rm.reset()

        if particle_outlines_relative is None:
            particle_outlines_relative = []

        # translate outlines to correct position
        particle_outlines_absolute = []
        for outline in particle_outlines_relative:
            # Get current location and set the new, offset location
            current_bounds = outline.getBounds()
            outline.setLocation(current_bounds.x + offset_x, current_bounds.y + offset_y)
            particle_outlines_absolute.append(outline)

        analysis = {
            'count': count,
            'total area': total_area,
            'outlines': particle_outlines_absolute
        }
        return analysis
    
    def done(self):
        """ Runs on GUI thread after background work is finished. """
        try:
            # Save all collected results to the database
            if self.all_results:
                results_db_path = self.project.paths['results_db']
                headers = ['filename', 'roi_name', 'roi_area', 'brema_value', 'cell_count', 'total_cell_area' ]
                file_exists = os.path.isfile(results_db_path)
                with open(results_db_path, 'ab') as csvfile:
                    writer = csv.DictWriter(csvfile, fieldnames=headers)
                    if not file_exists or os.path.getsize(results_db_path) == 0: 
                        writer.writeheader()
                    writer.writerows(self.all_results)
            
            # Show final status message
            final_message = self.get()
            JOptionPane.showMessageDialog(self.progress_dialog, final_message, "Status", JOptionPane.INFORMATION_MESSAGE)
        except Exception as e:
            IJ.log(traceback.format_exc())
            JOptionPane.showMessageDialog(self.progress_dialog, "An error occurred during processing:\n" + str(e), "Error", JOptionPane.ERROR_MESSAGE)
        finally:
            self.progress_dialog.dispose()



#==============================================
# Program entry point
#==============================================
if __name__ == '__main__':
    def create_and_show_gui():
        gui = ProjectManagerGUI()
        gui.show()

    SwingUtilities.invokeLater(create_and_show_gui)
