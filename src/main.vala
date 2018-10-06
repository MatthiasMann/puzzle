int main (string[] args) {
    var app = new Gtk.Application ("de.matthiasmann.Puzzle", ApplicationFlags.FLAGS_NONE);
    app.activate.connect (() => {
        var win = app.active_window;
        if (win == null) {
            win = new puzzle.Window (app);
        }
        win.show_all ();
    });

    return app.run (args);
}
