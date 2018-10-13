namespace puzzle {
    struct PreviewResult {
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
      
        public Window(Gtk.Application app) {
            Object (application: app);

            set_default_size(1024, 768);

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            add(box);

            var bar = new Gtk.MenuBar();
            box.pack_start(bar, false, false, 0);

            var item_file = new Gtk.MenuItem.with_label("File");
            bar.add(item_file);
            var filemenu = new Gtk.Menu();
            item_file.set_submenu(filemenu);

            var item_open = new Gtk.MenuItem.with_label("Open");
            item_open.activate.connect(do_file_open);
            filemenu.add(item_open);

            var recent_menu = new Gtk.RecentChooserMenu();
            var filter = new Gtk.RecentFilter();
            filter.set_filter_name("Images");
            filter.add_pixbuf_formats();
            //recent_menu.add_filter(filter);
            recent_menu.item_activated.connect(() => {
                var info = recent_menu.get_current_item ();
                createPuzzle(info.get_uri());
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
            var size = compute_thumbnail_size(pixbuf.width, pixbuf.height, 128);
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

        struct Size {
            int width;
            int height;

            public Size(int width, int height) {
                this.width = width;
                this.height = height;
            }
        }

        private Size compute_thumbnail_size(int width, int height, int image_size)
            requires(width >= 0)
            requires(height >= 0)
            requires(image_size >= 0)
        {
            if(height > width) {
                width = (int)Math.lrint((double)width * image_size / (double)height);
                height = image_size;
            } else {
                height = (int)Math.lrint((double)height * image_size / (double)width);
                width = image_size;
            }

            return Size(width, height);
        }

        private bool pixbuf_loader_loop(Gdk.PixbufLoader loader, File file) throws GLib.Error {
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

        private void createPuzzle(string uri) {
            try {
                var file = File.new_for_uri(uri);
                var loader = new Gdk.PixbufLoader();
                loader.size_prepared.connect((width,height) => {
                    stdout.printf("width=%d height=%d\n", width, height);
                });
                if(!pixbuf_loader_loop(loader, file))
                    return;
                var anim = loader.get_animation();
                if(anim.is_static_image()) {
                    var pixbuf = loader.get_pixbuf();
                    var tile_size = uint.max(50, uint.min(pixbuf.width, pixbuf.height) / 14);
                    pa.createPuzzleFromPixbuf(pixbuf, UVec2(pixbuf.width / tile_size, pixbuf.height / tile_size));
                } else {
                    var tile_size = 50;//uint.max(1, uint.min(anim.get_width(), anim.get_height()) / 12);
                    pa.createPuzzleFromAnim(anim, UVec2(anim.get_width() / tile_size, anim.get_height() / tile_size));
                }

                var ret = Gtk.RecentManager.get_default().add_item(uri);
                if(!ret)
                    stderr.printf("Failed to add item to recent manager");
            } catch(GLib.Error e) {
                message("Error loading image file: %s", e.message);
            }
        }

        private PreviewResult loadPreview(string? uri) {
            var result = PreviewResult();
            if(uri == null)
                return result;
            try {
                var file = File.new_for_uri(uri);
                var loader = new Gdk.PixbufLoader();
                loader.size_prepared.connect((width,height) => {
                    result.fullsize_width = width;
                    result.fullsize_height = height;
                    var size = compute_thumbnail_size(width, height, 128);
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

        private void do_file_open() {
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            var img_size = new Gtk.Label(null);
            var preview = new Gtk.Image();
            box.pack_start(preview, false, false, 0);
            box.pack_start(img_size, false, false, 0);
            box.valign = Gtk.Align.CENTER;
            // FileChooserDialog only calls box.show()
            img_size.show();
            preview.show();

            var chooser = new Gtk.FileChooserDialog(
                "Select an image or animation to saw up",
                this, Gtk.FileChooserAction.OPEN,
                "_Cancel", Gtk.ResponseType.CANCEL,
                "_Open", Gtk.ResponseType.ACCEPT);
            chooser.set_select_multiple(false);
            chooser.set_create_folders(false);
            chooser.set_use_preview_label(false);
            chooser.set_preview_widget(box);
            chooser.update_preview.connect((fc) => {
                var uri = chooser.get_preview_uri();
                var result = loadPreview(uri);
                preview.set_from_pixbuf(result.thumbnail);
                img_size.set_text("%d x %d%s".printf(result.fullsize_width, result.fullsize_height, result.is_animation ? "\nanimation" : ""));
                chooser.set_preview_widget_active(result.thumbnail != null);
            });
            var filter = new Gtk.FileFilter();
            filter.set_filter_name("All images");
            filter.add_pixbuf_formats();
            chooser.add_filter(filter);
            filter = new Gtk.FileFilter();
            filter.set_filter_name("Static images");
            filter.add_pattern("*.png");
            filter.add_pattern("*.jpg");
            filter.add_pattern("*.jpeg");
            filter.add_pattern("*.bmp");
            chooser.add_filter(filter);
            filter = new Gtk.FileFilter();
            filter.set_filter_name("Animations");
            filter.add_pattern("*.gif");
            chooser.add_filter(filter);
            if(chooser.run() == Gtk.ResponseType.ACCEPT) {
                createPuzzle(chooser.get_uri());
            }
            chooser.close();
        }
    }
}
