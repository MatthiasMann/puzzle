namespace puzzle {
    public struct PreviewResult {
        Gdk.Pixbuf thumbnail;
        int        fullsize_width;
        int        fullsize_height;
        bool       is_animation;

        public PreviewResult() {
            thumbnail = null;
            fullsize_width = 0;
            fullsize_height = 0;
            is_animation = false;
        }
    }

    public class Window : Gtk.ApplicationWindow {
        private PuzzleArea pa;
        private Settings settings;
        private Puzzle.Parameters parameters;
        private Gtk.MenuItem item_open_random;
      
        public Window(Gtk.Application app) {
            Object(application: app);

            set_default_size(1024, 768);

            settings = new Settings("de.matthiasmann.Puzzle");
            parameters = Puzzle.Parameters();
            parameters.randomize = (Puzzle.Randomize)settings.get_enum("randomize");
            parameters.min_tile_size = settings.get_uint("min-tile-size");
            parameters.max_num_tiles = settings.get_uint("max-num-tiles");

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            add(box);

            var accel_group = new Gtk.AccelGroup();
            add_accel_group(accel_group);

            var bar = new Gtk.MenuBar();
            box.pack_start(bar, false, false, 0);

            var item_file = new Gtk.MenuItem.with_label("File");
            bar.add(item_file);
            var filemenu = new Gtk.Menu();
            item_file.set_submenu(filemenu);

            var item_open = new Gtk.MenuItem.with_mnemonic("_Open");
            item_open.set_use_underline(true);
            item_open.add_accelerator("activate", accel_group, Gdk.Key.o, Gdk.CONTROL_MASK, Gtk.AccelFlags.VISIBLE);
            item_open.activate.connect(do_file_open);
            filemenu.add(item_open);

            item_open_random = new Gtk.MenuItem.with_mnemonic("Open _Random");
            item_open_random.set_sensitive(false);
            item_open_random.set_use_underline(true);
            item_open_random.add_accelerator("activate", accel_group, Gdk.Key.r, Gdk.CONTROL_MASK, Gtk.AccelFlags.VISIBLE);
            item_open_random.activate.connect(() => {
                if(last_opened_folder != null)
                    createRandomPuzzle(last_opened_folder, parameters);
            });
            filemenu.add(item_open_random);

            var recent_menu = new Gtk.RecentChooserMenu();
            var filter = new Gtk.RecentFilter();
            filter.set_filter_name("Images");
            filter.add_pixbuf_formats();
            //recent_menu.add_filter(filter);
            recent_menu.item_activated.connect(() => {
                var info = recent_menu.get_current_item ();
                createPuzzle(info.get_uri(), parameters);
            });
            var item_open_recent = new Gtk.MenuItem.with_label("Open Recent");
            filemenu.add(item_open_recent);
            item_open_recent.set_submenu(recent_menu);

            filemenu.add(new Gtk.SeparatorMenuItem());
            Gtk.MenuItem item_exit = new Gtk.MenuItem.with_label("Exit");
            item_exit.activate.connect(dispose);
            filemenu.add(item_exit);

            pa = new PuzzleArea();
            pa.preparePreview = show_preview;
            var scroll = new Gtk.ScrolledWindow(null, null);
            scroll.add(pa);
            box.pack_start(scroll, true, true, 0);
        }

        private Gtk.Window preview_dialog;
        private Gtk.Image preview_image;

        private void show_preview(Gdk.Pixbuf pixbuf) {
            var size = Size.compute_thumbnail(pixbuf.width, pixbuf.height, 128);
            var thumbnail = pixbuf.scale_simple(size.width, size.height, Gdk.InterpType.HYPER);
            if(thumbnail != null) {
                if(preview_dialog == null) {
                    preview_image = new Gtk.Image();
                    preview_dialog = new Gtk.Window();
                    preview_dialog.accept_focus = false;
                    preview_dialog.deletable = false;
                    preview_dialog.resizable = false;
                    preview_dialog.destroy_with_parent = true;
                    preview_dialog.type_hint=Gdk.WindowTypeHint.MENU;
                    preview_dialog.set_title("Preview");
                    preview_dialog.set_transient_for(this);
                    preview_dialog.add(preview_image);

                    int x, y;
                    get_position(out x, out y);
                    preview_dialog.move(x, y);
                }

                preview_image.pixbuf = thumbnail;
                preview_dialog.show_all();
            }
        }

        public struct Size {
            int width;
            int height;

            public Size(int width, int height) {
                this.width = width;
                this.height = height;
            }

            public Size.compute_thumbnail(int width, int height, int image_size)
                requires(width >= 0)
                requires(height >= 0)
                requires(image_size >= 0)
            {
                if(height > width) {
                    if(height > image_size) {
                        width = (int)Math.lrint((double)width * image_size / (double)height);
                        height = image_size;
                    }
                } else if(width > image_size) {
                    height = (int)Math.lrint((double)height * image_size / (double)width);
                    width = image_size;
                }
                this.width = width;
                this.height = height;
            }
        }

        public static bool pixbuf_loader_loop(Gdk.PixbufLoader loader, File file) throws GLib.Error {
            var type = file.query_file_type(FileQueryInfoFlags.NONE);
            if(type == FileType.DIRECTORY || type == FileType.SPECIAL)
                return false;
            var fis = file.read();
            var buffer = new uint8[64 << 10];
            for(;;) {
                var read = fis.read(buffer);
                if(read < 0)
                    return false;
                if(read == 0)
                    break;
                if(!loader.write(buffer[0:read]))
                    return false;
            }
            return loader.close();
        }

        private static extern uint64 compare_rows(Gdk.Pixbuf pixbuf, uint row0, uint row1);
        private static extern uint64 compare_columns(Gdk.Pixbuf pixbuf, uint col0, uint col1, uint y0, uint y1);

        private Gdk.Pixbuf auto_crop(Gdk.Pixbuf pixbuf) {
            int width = pixbuf.width;
            int height = pixbuf.height;
            if(width < 4 || height < 4)
                return pixbuf;
            int midy = height/2;
            int starty, endy;
            uint64 threshold = ((uint64)(10 * 10)) * width;
            for(starty=0 ; starty<midy ; starty++) {
                uint64 res = compare_rows(pixbuf, 0, starty+1);
                stdout.printf("starty=%u res=%llu\n", starty, res);
                if(res > threshold)
                    break;
            }
            for(endy=height ; endy>midy ; endy--) {
                uint64 res = compare_rows(pixbuf, height-1, endy-2);
                stdout.printf("endy=%u res=%llu\n", endy, res);
                if(res > threshold)
                    break;
            }
            threshold = ((uint64)(10 * 10)) * (endy - starty);
            int midx = width/2;
            int startx, endx;
            for(startx=0 ; startx<midx ; startx++) {
                uint64 res = compare_columns(pixbuf, 0, startx+1, starty, endy);
                stdout.printf("startx=%u res=%llu\n", startx, res);
                if(res > threshold)
                    break;
            }
            for(endx=width ; endx>midx ; endx--) {
                uint64 res = compare_columns(pixbuf, width-1, endx-2, starty, endy);
                stdout.printf("endx=%u res=%llu\n", endx, res);
                if(res > threshold)
                    break;
            }
            return new Gdk.Pixbuf.subpixbuf(pixbuf, startx, starty, endx- startx, endy - starty);
        }

        private void createPuzzle(string uri, Puzzle.Parameters parameters) {
            try {
                var file = File.new_for_uri(uri);
                var loader = new Gdk.PixbufLoader();
                loader.size_prepared.connect((width,height) => {
                    stdout.printf("width=%d height=%d\n", width, height);
                });
                if(!pixbuf_loader_loop(loader, file))
                    return;
                var anim = loader.get_animation();
                if(anim.is_static_image())
                    pa.createPuzzleFromPixbuf(auto_crop(loader.get_pixbuf()), parameters);
                else
                    pa.createPuzzleFromAnim(anim, parameters);

                var ret = Gtk.RecentManager.get_default().add_item(uri);
                if(!ret)
                    stderr.printf("Failed to add item to recent manager");

                var filename_start_idx = uri.last_index_of_char('/') + 1;
                set_title("puzzle " + uri.substring(filename_start_idx));

                this.parameters = parameters;
                settings.set_enum("randomize", parameters.randomize);
                settings.set_uint("min-tile-size", parameters.min_tile_size);
                settings.set_uint("max-num-tiles", parameters.max_num_tiles);
            } catch(GLib.Error e) {
                message("Error loading image file: %s", e.message);
            }
        }

        private void createRandomPuzzle(string folder, Puzzle.Parameters parameters) {
            string[] paths = {};
            try {
                var dir = Dir.open(folder, 0);
                string? name;
                while((name = dir.read_name()) != null) {
                    if(name.has_suffix(".png") || name.has_suffix(".jpg") || name.has_suffix(".jpeg") || name.has_suffix(".bmp")) {
                        string path = Path.build_filename(folder, name);
                        if(FileUtils.test(path, FileTest.IS_REGULAR))
                            paths += path;
                    }
                }
            } catch(GLib.FileError e) {
                message("Could not list files: %s", e.message);
                return;
            }
            if(paths.length < 3)
                return;
            var buffer = new uint8[64 << 10];
            for(int tries=3 ; tries-->0 ;) {
                var idx = Random.int_range(0, paths.length);
                var path = paths[idx];

                try {
                    var file = File.new_for_path(path);
                    var loader = new Gdk.PixbufLoader();
                    var stop = false;
                    loader.size_prepared.connect((width,height) => {
                        stdout.printf("width=%d height=%d\n", width, height);
                        if(width < 300 || height < 300 || width > 4096 || height > 4096)
                            stop = true;
                    });
                    var fis = file.read();
                    var done = false;
                    while(!stop) {
                        var read = fis.read(buffer);
                        if(read <= 0) {
                            done = read == 0;
                            break;
                        }
                        if(!loader.write(buffer[0:read]))
                            break;
                    }
                    if(loader.close() && done && !stop) {
                        pa.createPuzzleFromPixbuf(auto_crop(loader.get_pixbuf()), parameters);

                        var filename_start_idx = path.last_index_of_char('/') + 1;
                        set_title("puzzle " + path.substring(filename_start_idx));

                        this.parameters = parameters;
                        settings.set_enum("randomize", parameters.randomize);
                        settings.set_uint("min-tile-size", parameters.min_tile_size);
                        settings.set_uint("max-num-tiles", parameters.max_num_tiles);
                        return;
                    }
                } catch(GLib.Error e) {
                    message("Error loading image file: %s", e.message);
                }
            }
        }

        public static PreviewResult loadPreview(string? uri, int thumbnail_size) {
            var result = PreviewResult();
            if(uri == null)
                return result;
            try {
                var file = File.new_for_uri(uri);
                var loader = new Gdk.PixbufLoader();
                loader.size_prepared.connect((width,height) => {
                    result.fullsize_width = width;
                    result.fullsize_height = height;
                    var size = Size.compute_thumbnail(width, height, thumbnail_size);
                    loader.set_size(size.width, size.height);
                });
                if(pixbuf_loader_loop(loader, file)) {
                    var anim = loader.get_animation();
                    result.is_animation = !anim.is_static_image();
                    result.thumbnail = loader.get_pixbuf();
                }
                return result;
            } catch(GLib.Error e) {
                message("Error loading image preview: %s", e.message);
                return result;
            }
        }

        class AsyncPreviewJob {
            private static int next_id = 0;
            private int _id;
            public int id {
                get { return _id; }
            }
            private string? _uri;
            public string uri {
                get { assert(_uri != null); return _uri; }
            }
            public bool is_terminate {
                get { return _uri == null; }
            }

            public AsyncPreviewJob(string uri, out int id) {
                this._id = next_id++;
                this._uri = uri;
                id = _id;
            }
            public AsyncPreviewJob.terminate() {
                this._uri = null;
            }
        }

        class ParametersBox : Gtk.Box {
            private Puzzle.Parameters _parameters;
            private Gtk.ComboBoxText randomize_cb;
            private Gtk.SpinButton min_tile_size_spinbtn;
            private Gtk.SpinButton max_num_tiles_spinbtn;

            public Puzzle.Parameters parameters {
                get { return _parameters; }
            }

            private struct RandomizeCBEntries {
                Puzzle.Randomize val;
                string           str;

                RandomizeCBEntries(Puzzle.Randomize _val, string _str) {
                    this.val = _val;
                    this.str = _str;
                }
            }
            private RandomizeCBEntries[] randomize_entries;

            public ParametersBox(Puzzle.Parameters __parameters) {
                orientation = Gtk.Orientation.HORIZONTAL;
                spacing = 5;
                this._parameters = __parameters;

                randomize_entries = {
                    RandomizeCBEntries(Puzzle.Randomize.NONE, "None"),
                    RandomizeCBEntries(Puzzle.Randomize.MESSY, "Messy"),
                    RandomizeCBEntries(Puzzle.Randomize.GRID, "Grid"),
                    RandomizeCBEntries(Puzzle.Randomize.GRID_EDGES_FIRST, "Grid, edges first")
                };

                var eboxv = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
                randomize_cb = new Gtk.ComboBoxText();
                for(int idx=0 ; idx<randomize_entries.length ; idx++) {
                    randomize_cb.append_text(randomize_entries[idx].str);
                    if(parameters.randomize == randomize_entries[idx].val)
                        randomize_cb.active = idx;
                }
                randomize_cb.changed.connect(randomize_cb_changed);
                eboxv.add(new Gtk.Label("Randomization"));
                eboxv.add(randomize_cb);
                add(eboxv);

                eboxv = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
                min_tile_size_spinbtn = new Gtk.SpinButton.with_range(10.0, 1000.0, 10.0);
                min_tile_size_spinbtn.value = parameters.min_tile_size;
                min_tile_size_spinbtn.digits = 0;
                min_tile_size_spinbtn.width_chars = 4;
                min_tile_size_spinbtn.max_width_chars = 4;
                min_tile_size_spinbtn.value_changed.connect(min_tile_size_spinbtn_value_changed);
                eboxv.add(new Gtk.Label("Min tile size"));
                eboxv.add(min_tile_size_spinbtn);
                add(eboxv);

                eboxv = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
                max_num_tiles_spinbtn = new Gtk.SpinButton.with_range(10.0, 2000.0, 10.0);
                max_num_tiles_spinbtn.value = parameters.max_num_tiles;
                max_num_tiles_spinbtn.digits = 0;
                max_num_tiles_spinbtn.width_chars = 4;
                max_num_tiles_spinbtn.max_width_chars = 4;
                max_num_tiles_spinbtn.value_changed.connect(max_num_tiles_spinbtn_value_changed);
                eboxv.add(new Gtk.Label("Maximum number of tiles"));
                eboxv.add(max_num_tiles_spinbtn);
                add(eboxv);
            }

            private void randomize_cb_changed() {
                var idx = randomize_cb.active;
                if(idx >= 0 && idx < randomize_entries.length)
                    _parameters.randomize = randomize_entries[idx].val;
            }

            private void min_tile_size_spinbtn_value_changed() {
                _parameters.min_tile_size = min_tile_size_spinbtn.get_value_as_int();
            }

            private void max_num_tiles_spinbtn_value_changed() {
                _parameters.max_num_tiles = max_num_tiles_spinbtn.get_value_as_int();
            }
        }

        class FileOpenDialog : Gtk.FileChooserDialog {
            private Gtk.Label img_size;
            private Gtk.Image preview;
            private Gtk.Spinner spinner;
            private Gtk.Stack stack;
            private AsyncQueue<AsyncPreviewJob> queue;
            private Thread<bool> thread;
            private int job_id;
            private ParametersBox pbox;
            public Puzzle.Parameters parameters {
                get { return pbox.parameters; }
            }

            private const int thumbnail_size = 128;

            public FileOpenDialog(Gtk.Window? parent, Puzzle.Parameters _parameters) {
                this.title = "Select an image or animation to saw up";
                this.action = Gtk.FileChooserAction.OPEN;

                add_button("_Cancel", Gtk.ResponseType.CANCEL);
                add_button("_Open", Gtk.ResponseType.ACCEPT);
                add_button("_Random", 1);
                set_default_response(Gtk.ResponseType.ACCEPT);

                if(parent != null)
                    set_transient_for(parent);

                img_size = new Gtk.Label(null);
                preview = new Gtk.Image();
                preview.set_size_request(thumbnail_size, thumbnail_size);

                spinner = new Gtk.Spinner();
                spinner.active = true;
                stack = new Gtk.Stack();
                stack.add(preview);
                stack.add(spinner);

                var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
                box.pack_start(stack, false, false, 0);
                box.pack_start(img_size, false, false, 0);
                box.valign = Gtk.Align.CENTER;
                // FileChooserDialog only calls box.show()
                img_size.show_all();
                stack.show_all();

                set_select_multiple(false);
                set_create_folders(false);
                set_use_preview_label(false);
                set_preview_widget(box);

                pbox = new ParametersBox(_parameters);
                pbox.show_all();
                set_extra_widget(pbox);

                queue = new AsyncQueue<AsyncPreviewJob>();
                try {
                    thread = new Thread<bool>.try("FCPreview", preview_thread_run);
                } catch(GLib.Error e) {
                }

                update_preview.connect((fc) => {
                    preview.pixbuf = null;
                    var uri = get_preview_uri();
                    if(uri == null) {
                        set_preview_widget_active(false);
                    } else if(thread != null) {
                        queue.push(new AsyncPreviewJob(uri, out job_id));
                        stack.visible_child = spinner;
                        img_size.set_text("");
                        set_preview_widget_active(true);
                    } else
                        set_preview(loadPreview(uri, thumbnail_size));
                });

                var filter = new Gtk.FileFilter();
                filter.set_filter_name("All images");
                filter.add_pixbuf_formats();
                add_filter(filter);
                filter = new Gtk.FileFilter();
                filter.set_filter_name("Static images");
                filter.add_pattern("*.png");
                filter.add_pattern("*.jpg");
                filter.add_pattern("*.jpeg");
                filter.add_pattern("*.bmp");
                add_filter(filter);
                filter = new Gtk.FileFilter();
                filter.set_filter_name("Animations");
                filter.add_pattern("*.gif");
                add_filter(filter);
            }

            public override void close() {
                queue.push(new AsyncPreviewJob.terminate());
                if(thread != null)
                    thread.join();
                base.close();
            }

            private bool preview_thread_run() {
                for(;;) {
                    var job = queue.pop();
                    if(job.is_terminate)
                        return true;
                    var result = loadPreview(job.uri, thumbnail_size);
                    var source = new IdleSource();
                    source.set_callback(() => {
                        if(job.id == job_id)
                            set_preview(result);
                        return Source.REMOVE;
                    });
                    source.attach();
                }
            }

            private void set_preview(PreviewResult result) {
                if(result.thumbnail == null) {
                    preview.icon_name = "gtk-missing-image";
                    img_size.set_text("");
                } else {
                    preview.set_from_pixbuf(result.thumbnail);
                    img_size.set_text("%d x %d%s".printf(result.fullsize_width, result.fullsize_height, result.is_animation ? "\nanimation" : ""));
                }
                stack.visible_child = preview;
                set_preview_widget_active(true);
            }
        }

        private string? last_loaded_uri = null;
        private string? last_opened_folder = null;
        private void do_file_open() {
            var chooser = new FileOpenDialog(this, parameters);
            if(last_loaded_uri != null)
                chooser.set_uri(last_loaded_uri);
            else if(last_opened_folder != null)
                chooser.set_current_folder(last_opened_folder);
            switch(chooser.run()) {
                case Gtk.ResponseType.ACCEPT:
                    createPuzzle(chooser.get_uri(), chooser.parameters);
                    last_loaded_uri = chooser.get_uri();
                    last_opened_folder = chooser.get_current_folder();
                    break;
                case 1:
                    last_opened_folder = chooser.get_current_folder();
                    last_loaded_uri = null;
                    createRandomPuzzle(last_opened_folder, chooser.parameters);
                    break;
                default:
                    break;
            }
            chooser.close();
            if(last_opened_folder != null)
                item_open_random.set_sensitive(true);
        }
    }
}
