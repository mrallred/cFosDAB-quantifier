import os
import csv
import traceback
from ij import IJ, WindowManager
from ij.gui import ImageCanvas, ImageWindow
from ij.plugin.frame import RoiManager

from javax.swing import (JFrame, JDialog, JMenuBar, JMenu, JMenuItem, JSplitPane,
                         JPanel, JComboBox, JScrollPane, JOptionPane, JTree, JTable,
                         JButton, JLabel, JFileChooser, ListSelectionModel, BorderFactory,
                         JTextField, JList, JCheckBox, DefaultListModel)

from javax.swing.table import AbstractTableModel, DefaultTableModel
from javax.swing.tree import DefaultMutableTreeNode, DefaultTreeModel
from java.awt import BorderLayout, FlowLayout, Font, GridLayout, Cursor
from java.awt.event import WindowAdapter, MouseAdapter, KeyListener
from javax.swing.event import ListSelectionListener, ListDataListener
from javax.swing.border import EmptyBorder

#==============================================
# Project structure and file managment
#==============================================

class ProjectImage(object):
    """ Simple class to hold info about a single image file """
    def __init__(self, filename, project_path):
        self.filename = filename
        self.full_path = os.path.join(project_path, "Images", filename)
        self.roi_path = os.path.join(project_path, "ROI_Files", self.filename.replace(".tif", "_ROIs.zip"))
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
            'project_db': os.path.join(self.root_dir, 'Project_DB.csv'),
            'results_db': os.path.join(self.root_dir, 'Results_DB.csv')
        }

    def _load_project_db(self):
        """ Loads and parses project_db.csv """
        db_path = self.paths['project_db']
        if not os.path.exists(db_path):
            # create dummy file for now
            with open(db_path, 'w') as f:
                f.write("filename,roi_name,bregma,status\n")
            return
        
        images_map = {} # map to group ROIs by filename
        with open(db_path, 'r') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                filename = row['filename']
                if filename not in images_map:
                    images_map[filename] = ProjectImage(filename, self.root_dir)

                # add ROI info to correct ProjectImage object
                images_map[filename].add_roi(row)

        self.images = sorted(images_map.values(), key=lambda img: img.filename)

    def _scan_for_new_images(self):
        """ scans images folder for any files not added to the DB """
        if not os.path.isdir(self.paths['images']):
            return
        
        existing_filenames = {img.filename for img in self.images}
        for f in sorted(os.listdir(self.paths['images'])):
            if f.lower().endswith(('.tif', '.tiff')) and f not in existing_filenames:
                new_image = ProjectImage(f, self.root_dir)
                new_image.status = "Untracked"
                new_image.populate_rois_from_zip() # try to load existing zip
                self.images.append(new_image)

    def sync_project_db(self):
        """ Rewrites project_DB.csv file from in memory project state. """
        db_path = self.paths['project_db']
        headers = ['filename', 'roi_name', 'bregma', 'status']
        try:
            with open(db_path, 'wb') as csvfile:
                writer = csv.DictWriter(csvfile, fieldnames=headers)
                writer.writeheader()
                for image in self.images:
                    if not image.rois:
                        continue
                    for roi_data in image.rois:
                        row = {
                            'filename': image.filename,
                            'roi_name': roi_data.get('roi_name', 'N/A'),
                            'bregma': roi_data.get('bregma', 'N/A'),
                            'status': roi_data.get('status', 'Pending')
                        }
                        writer.writerow(row)
            IJ.log("Sucessfully synced Project_DB.csv")
            return True
        except IOError as e:
            IJ.log("Error syncing Project_DB.csv: {}".format(e))
            return False

#==============================================
# GUI Classes
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
        self.select_all_button = JButton("Select All / None")
        self.select_all_button.addActionListener(self.toggle_select_all_action)
        self.roi_button = JButton("Define/Edit ROIs", enabled=False)
        self.quant_button = JButton("Run Quantification", enabled=False)
        button_panel.add(self.select_all_button)
        button_panel.add(self.roi_button)
        button_panel.add(self.quant_button)

        control_panel.add(button_panel, BorderLayout.EAST)
        self.frame.add(control_panel, BorderLayout.SOUTH)

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
        """ Gathers selectd images and opens the quantification settings dialog """
        selected_rows = self.image_table.getSelectedRows()
        if not selected_rows:
            return
        
        # Create list of ProjectImage objects that were selected
        selected_images = [self.project.images[row] for row in selected_rows]

        quant_dialog = QuantificationDialog(self.frame, selected_images)
        selections = quant_dialog.show_dialog()

        # if selections:
        #   # Run QuantificationWorker here
        
        IJ.showMessage("Quantification ready.", "Ready to process {}".format(len(selected_images)))

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
        save_button = JButton("Save & Close", actionPerformed=self._save_and_close)

        button_panel.add(create_button)
        button_panel.add(update_button)
        button_panel.add(save_button)
        button_panel.add(delete_button)

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

        self.update_roi_list_from_manager()
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
            
        self.update_roi_list_from_manager()
        IJ.log("Updated ROI: " + new_name)

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

        # refresh visible list from update manager & clear text field
        self.update_roi_list_from_manager()
        self.roi_name_field.setText("")
        self.bregma_field.setText("")


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
        self.project.sync_project_db()

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

class QuantificationDialog(JDialog):
    """ modal dialog to configure setting for a batch quantification process. Returns select settings to be passed to the worker """
    def __init__(self, parent_frame, selected_images):
        super(QuantificationDialog, self).__init__(parent_frame, "Quantification Setting", True)

        self.selected_images = selected_images
        self.setting = None

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

        # Drop down menu for processing method
        settings_panel.add(JLabel("Processing Method:"))
        processing_methods = ["Ilastik Pixel Classifcation", "Option 2"]
        self.method_combo = JComboBox(processing_methods)
        settings_panel.add(self.method_combo)

        # MORE SETTINGS HERE

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
        self.settings = {
            'images': self.selected_images,
            'method': self.method_combo.getSelectedItem()
            # OTHER SETTINGS HERE
            }
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
    
#==============================================
# Processor Classes
#==============================================



#==============================================
# Program entry point
#==============================================
if __name__ == '__main__':
    from javax.swing import SwingUtilities

    def create_and_show_gui():
        gui = ProjectManagerGUI()
        gui.show()

    SwingUtilities.invokeLater(create_and_show_gui)
