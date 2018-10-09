namespace puzzle {
    public class Grid {
        public uint stride { get; private set; }
        private float[,] pin;
        private bool[,] left;

        public Grid(UVec2 img_size, UVec2 num_tiles) {
            stride = num_tiles.x + 1;
            var grid_size = stride * (num_tiles.y+1);
            left = new bool[2, grid_size];
            pin = new float[2, grid_size];

            for(uint y=0,idx=0 ; y<=num_tiles.y ; y++) {
                for(uint x=0 ; x<=num_tiles.x ; x++,idx++) {
                    left[0,idx] = Random.boolean();
                    left[1,idx] = Random.boolean();
                }
            }

            for(uint y=1 ; y<num_tiles.y ; y++) {
                for(uint x=1,idx=y*stride+x ; x<num_tiles.x ; x++,idx++) {
                    pin[0,idx] = (float)(Random.next_double() * 0.4 + 0.3);
                    pin[1,idx] = (float)(Random.next_double() * 0.4 + 0.3);
                }
            }

            for(uint x=1 ; x<num_tiles.x ; x++)
                pin[1,x] = (float)(Random.next_double() * 0.4 + 0.3);
            for(uint y=1 ; y<num_tiles.y ; y++)
                pin[0,y*stride] = (float)(Random.next_double() * 0.4 + 0.3);
        }

        public Edge getEdge(uint from, uint to) {
            if(to < from) {
                if(to+1 == from)
                    return Edge(flip_pin(pin[0,to]), !left[0,to]);
                assert(to+stride == from);
                return Edge(flip_pin(pin[1,to]), !left[1,to]);
            } else {
                if(from+1 == to)
                    return Edge(pin[0,from], left[0,from]);
                assert(from+stride == to);
                return Edge(pin[1,from], left[1,from]);
            }
        }

        private float flip_pin(float pin) {
            return pin > 0 ? 1.0f - pin : 0f;
        }
    }

    public class Puzzle {
        private UVec2 img_size;
        private Grid grid;
        private Part[] parts;

        public Puzzle(UVec2 img_size, UVec2 num_tiles, bool randomize = true) {
            this.img_size = img_size;
            this.grid = new Grid(img_size, num_tiles);
            this.parts = {};
            
            var stride = grid.stride;
            var grid_size = stride * (num_tiles.y+1);
            var positions = new Vec2[grid_size];

            var tile_size = Vec2(img_size.x / (double)num_tiles.x, img_size.y / (double)num_tiles.y);
            for(uint y=0,idx=0 ; y<=num_tiles.y ; y++) {
                for(uint x=0 ; x<=num_tiles.x ; x++,idx++)
                    positions[idx] = Vec2(tile_size.x * x, tile_size.y * y);
            }
            
            for(uint y=1 ; y<num_tiles.y ; y++) {
                for(uint x=1,idx=y*stride+x ; x<num_tiles.x ; x++,idx++)
                    positions[idx] = positions[idx].add(tile_size.mul2(random_offset(), random_offset())).round();
            }

            for(uint y=0 ; y<num_tiles.y ; y++) {
                for(uint x=0,idx=y*stride ; x<num_tiles.x ; x++,idx++) {
                    var p = new Part(grid, {
                        Corner(positions[idx         ], idx),
                        Corner(positions[idx+1       ], idx+1),
                        Corner(positions[idx+stride+1], idx+stride+1),
                        Corner(positions[idx+stride  ], idx+stride)
                    });
                    if(randomize) {
                        p.pos.x = Random.next_double() * (img_size.x - p.width);
                        p.pos.y = Random.next_double() * (img_size.y - p.height);
                    }
                    parts += p;
                }
            }

        }
        
        private double random_offset() {
            const double max_offset = 0.25;
            return Random.next_double() * (2*max_offset) - max_offset; 
        }
        
        public void update_cache(Cairo.Surface img) {
            foreach(var p in parts)
                p.update_cache(img);
        }

        public void render(Cairo.Context ctx, Cairo.Surface img, bool do_cache) {
            foreach(var p in parts)
                p.render(ctx, img, do_cache);
        }

        public void render_outlines(Cairo.Context ctx) {
            foreach(var p in parts)
                p.render_outline(ctx);
        }

        public Part? getPart(Vec2 pos) {
            for(int idx=parts.length ; idx-->0 ;) {
                if(parts[idx].isInside(pos))
                    return parts[idx];
            }
            return null;
        }

        public Part[] getParts(Extend e) {
            Part[] res = {};
            for(int idx=parts.length ; idx-->0 ;) {
                if(parts[idx].isInsideExtend(e))
                    res += parts[idx];
            }
            return res;
        }

        public void movePartsToTop(Part[] selected_parts) {
            for(int idx=0,end=parts.length ; idx<end ;) {
                var part = parts[idx];
                if(part in selected_parts) {
                    remove_at_and_add(idx, part);
                    end--; // part is now at the end of the array - so need to check it again
                    // a new part is now at idx - so check that idx again
                } else
                    idx++;
            }
        }

        public int checkMerge(Part part) {
            int count = 0;
            checkMerge_impl(part, part, ref count);
            return count;
        }

        public void checkMerge_impl(Part part, Part org_part, ref int count) {
            int part_idx = -1;
            for(int idx=parts.length ; idx-->0 ;) {
                if(parts[idx] == part)
                    part_idx = idx;
                else if(parts[idx].canMerge(org_part)) {
                    //stdout.printf("Can merge %d %d\n", idx, part_idx);
                    var new_part = parts[idx].merge(part);
                    if(new_part != null) {
                        if(part_idx < 0) {
                            remove_at(idx);
                            for(; idx-->0 ;) {
                                if(parts[idx] == part) {
                                    //stdout.printf("part_idx=%d\n", idx);
                                    part_idx = idx;
                                    break;
                                }
                            }
                            assert(part_idx >= 0);
                            remove_at_and_add(part_idx, new_part);
                        } else {
                            remove_at(part_idx);
                            remove_at_and_add(idx, new_part);
                        }
                        count++;
                        if(count < 10)
                            checkMerge_impl(new_part, org_part, ref count);
                        return;
                    }
                }
            }
        }

        private void remove_at(int idx)
            requires(idx >= 0 && idx < parts.length)
        {
            var new_len = parts.length - 1;
            parts[idx] = null; // array.move() does not unref() objects
            parts.move(idx+1, idx, new_len - idx);
            parts.length = new_len;
        }

        private void remove_at_and_add(int idx, owned Part new_part)
            requires(idx >= 0 && idx < parts.length)
        {
            var new_len = parts.length - 1;
            parts[idx] = null; // array.move() does not unref() objects
            parts.move(idx+1, idx, new_len - idx);
            parts[new_len] = new_part;
        }

        public Extend get_extend() {
            var e = Extend.zero();
            foreach(var part in parts)
                e.update_extend(part.get_extend());
            return e;
        }
    }

    public class PuzzleArea : Gtk.DrawingArea, Gtk.Scrollable {
        private Gtk.GestureDrag gesture;
        private Cairo.Surface image;
        private Puzzle p;
        private Gdk.PixbufAnimation anim;
        private Gdk.PixbufAnimationIter anim_iter;

        public PuzzleArea() {
            can_focus = true;

            gesture = new Gtk.GestureDrag(this);
            gesture.drag_begin.connect(on_drag_begin);
            gesture.drag_update.connect(on_drag_update);
            gesture.drag_end.connect(on_drag_end);

            size_allocate.connect((w,a) => { update_scrollable_area(); });

            key_press_event.connect((e) => {
                if(e.keyval == Gdk.Key.Control_L || e.keyval == Gdk.Key.Control_R)
                    render_outline = true;
                return false;
            });
            key_release_event.connect((e) => {
                render_outline = false;
                return false;
            });
        }

        public void createPuzzle(Cairo.ImageSurface image, UVec2 num_tiles) {
            this.image = image;
            this.anim = null;
            this.anim_iter = null;
            doCreatePuzzle(image.get_width(), image.get_height(), num_tiles);
        }

        public void createPuzzleFromPixbuf(Gdk.Pixbuf pixbuf, UVec2 num_tiles) {
            this.anim = null;
            this.anim_iter = null;
            update_image_from_pixbuf(pixbuf);
            doCreatePuzzle(pixbuf.width, pixbuf.height, num_tiles);
        }

        public void createPuzzleFromAnim(Gdk.PixbufAnimation anim, UVec2 num_tiles) {
            this.anim = anim;
            this.anim_iter = anim.get_iter(null);
            update_image_from_pixbuf(anim_iter.get_pixbuf());
            animate();
            doCreatePuzzle(anim.get_width(), anim.get_height(), num_tiles);
        }

        private void doCreatePuzzle(int width, int height, UVec2 num_tiles)
            requires(width > 0)
            requires(height > 0)
        {
            dragParts = null;
            selectedParts = null;
            p = new Puzzle(UVec2((uint)width, (uint)height), num_tiles);
            set_size_request(width+20, height+20);
            update_scrollable_area();
        }

        private void update_image_from_pixbuf(Gdk.Pixbuf pixbuf) {
            image = Gdk.cairo_surface_create_from_pixbuf(pixbuf, 0, get_window());
            queue_draw();
        }

        private void animate() {
            var delay = anim_iter.get_delay_time();
            if(delay == -1)
                return;

            if(delay < 20)
                delay = 20; // Minimum value for GIF images.
            GLib.Timeout.add(delay, () => {
                if(anim_iter == null)
                    return false;
                if(anim_iter.advance(null))
                    update_image_from_pixbuf(anim_iter.get_pixbuf());
                this.animate();
                return false;
            });
        }

        public override bool draw (Cairo.Context ctx) {
            var timer = new Timer ();
            ctx.set_source_rgb(0.1, 0.1, 1.0);
            ctx.paint();
            ctx.translate(-hScrollPos, -vScrollPos);

            if(p != null) {
                if(image != null)
                    p.render(ctx, image, anim == null);
                if(_render_outline) {
                    ctx.set_source_rgb(1.0, 0.0, 0.0);
                    p.render_outlines(ctx);
                }
                if(selectedParts != null && selectedParts.length > 0) {
                    ctx.set_source_rgb(0.0, 1.0, 0.0);
                    foreach(var part in selectedParts)
                        part.render_outline(ctx);
                }
            }

            if(!selection.empty) {
                var size = selection.size();
                ctx.set_source_rgb(0.0, 1.0, 1.0);
                ctx.rectangle(selection.min.x, selection.min.y, size.x, size.y);
                ctx.stroke();
            }

            timer.stop();
            //stdout.printf("%g\n", timer.elapsed());
            return true;
        }

        private bool _render_outline;
        public bool render_outline {
            set { if(_render_outline != value) { _render_outline = value; queue_draw(); }}
            get { return _render_outline; }
        }

        public double hScrollPos {
            set { if(hadjust != null) hadjust.value = value; }
            get { return (hadjust != null) ? Math.round(hadjust.value) : 0; }
        }

        public double vScrollPos {
            set { if(vadjust != null) vadjust.value = value; }
            get { return (vadjust != null) ? Math.round(vadjust.value) : 0; }
        }

        private Part[] dragParts;
        private Vec2[] dragStart;
        private Vec2 selectionStart;
        private Extend _selection;
        private Extend selection {
            set { _selection = value; queue_draw(); }
            get { return _selection; }
        }
        private Part[] selectedParts;

        private void setSelectedParts(owned Part[]? value) {
            if(selectedParts != value) {
                selectedParts = value;
                queue_draw();
            }
        }

        private void on_drag_begin(Gtk.GestureDrag g, double x, double y) {
            selectionStart = Vec2(x + hScrollPos, y + vScrollPos);
            if(p != null) {
                var part = p.getPart(selectionStart);
                if(part != null) {
                    if(selectedParts != null && part in selectedParts)
                        dragParts = selectedParts;
                    else {
                        dragParts = { part };
                        setSelectedParts(null);
                    }
                    p.movePartsToTop(dragParts);
                    dragStart = new Vec2[dragParts.length];
                    for(int idx=0 ; idx<dragParts.length ; idx++)
                        dragStart[idx] = dragParts[idx].pos;
                    return;
                }
            }
            setSelectedParts(null);
        }

        private void on_drag_update(Gtk.GestureDrag g, double x, double y) {
            if(dragParts != null) {
                assert(dragParts.length == dragStart.length);
                for(int idx=0 ; idx<dragParts.length ; idx++)
                    dragParts[idx].pos = Vec2(x, y).add(dragStart[idx]);
                queue_draw();
            } else {
                selection = Extend.points(selectionStart, selectionStart.add(Vec2(x, y)));
                if(p != null)
                    setSelectedParts(p.getParts(selection));
            }
        }

        private void on_drag_end(Gtk.GestureDrag g, double x, double y) {
            if(p != null && dragParts != null && dragParts.length == 1) {   // only merge a single piece
                if(p.checkMerge(dragParts[0]) > 0)
                    queue_draw();
                update_scrollable_area(false);
            }
            dragParts = null;
            dragStart = null;
            if(!selection.empty) {
                selection = Extend.zero();
                queue_draw();
            }
        }

        private Gtk.Adjustment hadjust;
        public Gtk.Adjustment hadjustment {
            construct set {
                hadjust = value;
                if(hadjust != null) {
                    hadjust.value_changed.connect(queue_draw);
                    update_scrollable_area();
                }
            }
            get { return hadjust; }
        }

        private Gtk.Adjustment vadjust;
        public Gtk.Adjustment vadjustment {
            construct set {
                vadjust = value;
                if(vadjust != null) {
                    vadjust.value_changed.connect(queue_draw);
                    update_scrollable_area();
                }
            }
            get { return vadjust; }
        }

        public Gtk.ScrollablePolicy hscroll_policy { set; get; default = Gtk.ScrollablePolicy.NATURAL; }
        public Gtk.ScrollablePolicy vscroll_policy { set; get; default = Gtk.ScrollablePolicy.NATURAL; }

        public bool get_border (out Gtk.Border border) { border = Gtk.Border(); return false; }

        private void update_scrollable_area(bool allow_shrinking = true) {
            var e = (p != null) ? p.get_extend() : Extend.zero();
            if(hadjust != null) {
                hadjust.lower = compute_lower(hadjust.value, e.min.x - 10.0, allow_shrinking);
                hadjust.upper = e.max.x + 10.0;
                hadjust.page_size = get_allocated_width();
                hadjust.step_increment = hadjust.page_size * 0.1;
                hadjust.page_increment = hadjust.page_size * 0.8;
            }

            if(vadjust != null) {
                vadjust.lower = compute_lower(vadjust.value, e.min.y - 10.0, allow_shrinking);
                vadjust.upper = e.max.y + 10.0;
                vadjust.page_size = get_allocated_height();
                vadjust.step_increment = hadjust.page_size * 0.1;
                vadjust.page_increment = hadjust.page_size * 0.8;
            }
        }

        private double compute_lower(double cur_val, double new_val, bool allow_shrinking) {
            if(allow_shrinking || new_val < cur_val)
                return new_val;
            return cur_val;
        }
    }
}

