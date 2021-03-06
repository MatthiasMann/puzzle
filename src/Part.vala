namespace puzzle {
    public struct Edge {
        public float pin;
        public bool left;

        public Edge(float pin, bool left) {
            this.pin = pin;
            this.left = left;
        }
    }

    public class MergePoint {
        public uint own { get; private set; }
        public uint other { get; private set; }

        public MergePoint(uint own, uint other) {
            this.own = own;
            this.other = other;
        }

        public MergePoint swap() { return new MergePoint(other, own); }
    }

    enum MergeResult {
        FAILED,
        REMOVED_SELF,
        REMOVED_OTHER
    }

    public class Part {
        public Vec2 pos;
        private Grid grid;
        private uint[] corners;
        private Cairo.ImageSurface mask;
        private Cairo.ImageSurface cache;
        private Vec2 img_pos;
        private Vec2 translate;
        private Vec2[] vl;

        private const double spx[] = {  1, 2.5, 5, 7, 7, 5, 5, 6, 8,13 };
        private const double spy[] = { 13,12.5,11, 8, 5, 2, 0,-2,-3,-3 };
        private const int shadow_width = 1;

        public int width { get { return mask.get_width(); } }
        public int height { get { return mask.get_height(); } }

        public Part(Grid _grid, owned uint[] _corners) {
            this.grid = _grid;
            this.corners = _corners;
            
            img_pos = grid.getPos(corners[0]);
            for(uint idx=1 ; idx<corners.length ; idx++)
                img_pos = img_pos.min(grid.getPos(corners[idx]));
            
            vl = {};
            var s = corners[corners.length - 1];
            var spos = grid.getPos(s).sub(img_pos);
            foreach(var c in corners) {
                vl += spos;
                
                var epos = grid.getPos(c).sub(img_pos);
                var edge = grid.getEdge(s, c);
                if(edge.pin > 0) {
                    var d = epos.sub(spos);

                    var m1 = spos.add(d.mul(edge.pin));
                    var bw = spos.sub(m1).div(24.0);
                    var fw = epos.sub(m1).div(24.0);

                    var n = d.div(54.0);
                    var o = edge.left ? n.turnLeft() : n.turnRight();

                    for(var j = 1; j <= spx.length; j++)
                       vl += m1.spline(bw, spx[spx.length - j], o, spy[spx.length - j]);
                    for(var j = 0; j < spx.length; j++)
                       vl += m1.spline(fw, spx[j], o, spy[j]);
                }
                
                s = c;
                spos = epos;
            }
            
            /*
            stdout.printf("vl={");
            foreach(var v in vl)
                stdout.printf("{%f,%f},", v.x, v.y);
            stdout.printf("/ *length=%u* /}\n", vl.length);
            */

            // start with zero so that e.min <= Vec2(0,0)
            var e = Extend.zero();
            foreach(var v in vl)
                e.update(v);
            var size = e.size();
            
            mask = new Cairo.ImageSurface(Cairo.Format.A8, (int)Math.lrint(size.x) + 2*shadow_width, (int)Math.lrint(size.y) + 2*shadow_width);

            translate = e.min.round().sub(Vec2(shadow_width, shadow_width));
            pos = img_pos = img_pos.add(translate);
            
            //stdout.printf("extend=%f,%f,%f,%f mask=%d,%d img_pos=%f,%f translate=%f,%f\n", e.min.x,e.min.y,e.max.x,e.max.y, width, height, img_pos.x, img_pos.y, translate.x, translate.y);
            {
                var ctx = new Cairo.Context(mask);
                ctx.translate(-translate.x, -translate.y);
                path_outline(ctx);
                ctx.set_source_rgba(1, 1, 1, 1);
                ctx.fill();
            }
            
            mask.flush();
        }

        public Part recreate(double pos_scale) {
            var p = new Part(grid, corners);
            p.pos = pos.mul(pos_scale);
            return p;
        }

        public void update_cache(Cairo.Surface image) {
            cache = new Cairo.ImageSurface(Cairo.Format.ARGB32, width, height);
            var cctx = new Cairo.Context(cache);
            render_core(cctx, image);
        }

        public void render(Cairo.Context ctx, Cairo.Surface image, bool do_cache) {
            if(do_cache && cache == null)
                update_cache(image);
            ctx.save();
            ctx.translate(Math.round(pos.x), Math.round(pos.y));
            if(cache != null) {
                ctx.set_source_surface(cache, 0, 0);
                ctx.paint();
            } else {
                render_core(ctx, image);
            }
            ctx.restore();
            //render_corner_ids(ctx);
        }

        public void render_outline(Cairo.Context ctx) {
            ctx.save();
            ctx.translate(Math.round(pos.x)-translate.x, Math.round(pos.y)-translate.y);
            path_outline(ctx);
            ctx.stroke();
            ctx.restore();
        }

        private void path_outline(Cairo.Context ctx) {
            ctx.move_to(vl[0].x, vl[0].y);
            for(uint idx=1 ; idx<vl.length ; idx++)
                ctx.line_to(vl[idx].x, vl[idx].y);
            ctx.close_path();
        }

        private void render_core(Cairo.Context ctx, Cairo.Surface image) {
            ctx.set_source_rgb(0, 0, 0);
            for(int i=1 ; i<=shadow_width ; i++)
                ctx.mask_surface(mask, i, i);
            ctx.set_source_rgb(1, 1, 1);
            for(int i=-shadow_width ; i<0 ; i++)
                ctx.mask_surface(mask, i, i);
            ctx.set_source_surface(image, -img_pos.x, -img_pos.y);
            ctx.mask_surface(mask, 0, 0);
        }
/*
        private void render_corner_ids(Cairo.Context ctx) {
            var layout = Pango.cairo_create_layout(ctx);
            ctx.set_source_rgb(0, 0, 0);
            foreach(var e in corners) {
                layout.set_text(e.id.to_string(), -1);
                ctx.save();
                ctx.translate(e.pos.x - img_pos.x + pos.x - Random.next_double() * 10, e.pos.y - img_pos.y + pos.y - Random.next_double() * 10);
                Pango.cairo_show_layout(ctx, layout);
                ctx.restore();
            }
        }
*/
        public bool isInside(Vec2 mouse) {
            mouse = mouse.sub(pos);
            var x = Math.lrint(mouse.x);
            var y = Math.lrint(mouse.y);
            if(x < 0 || y < 0 || x >= width || y >= height)
                return false;
            var stride = mask.get_stride();
            var val = mask.get_data()[y*stride + x];
            //stdout.printf("x=%ld y=%ld stride=%u width=%u -> %d\n", x, y, stride, width, val);
            return val > 0;
        }

        public bool isInsideExtend(Extend e) {
            return get_extend().isInside(e);
        }

        public Extend get_extend() {
            return Extend.point_and_size(pos, Vec2(width, height));
        }

        public bool is_edge() {
            var s = corners[corners.length - 1];
            foreach(var c in corners) {
                var edge = grid.getEdge(s, c);
                if(edge.pin <= 0)
                    return true;
                s = c;
            }
            return false;
        }

        public bool canMerge(Part other) {
            return canMergeAxis(this.pos.x, this.width,  other.pos.x, other.width) &&
                   canMergeAxis(this.pos.y, this.height, other.pos.y, other.height);
        }

        private bool canMergeAxis(double v00, double d0, double v10, double d1)
            requires(d0 > 0)
            requires(d1 > 0)
        {
            double v01 = v00 + d0;
            double v11 = v10 + d1;
            return (v00 < v11) ? (v10 - v01) < 10.0 : (v00 - v11) < 10.0;
        }


        public MergePoint? findMergeStart(Part other)
            requires(this != other)
        {
            var own_off = pos.sub(img_pos);
            var other_off = other.pos.sub(other.img_pos);
            for(uint idx0=0 ; idx0<this.corners.length ; idx0++) {
                var e0 = this.corners[idx0];
                for(uint idx1=0 ; idx1<other.corners.length ; idx1++) {
                    if(other.corners[idx1] == e0 &&
                        other.corners[other.inc_corner_idx(idx1)] == this.corners[this.dec_corner_idx(idx0)] &&
                        other_off.distSqr(own_off) < 100.0)
                        return new MergePoint(idx0, idx1);
                }
            }
            return null;
        }

        public Part? merge(Part other) {
            var start = findMergeStart(other);
            return (start != null) ? merge_impl(other, start, false) : null;
        }

        private Part? merge_impl(Part other, MergePoint start, bool swapped)
            requires(start.own < this.corners.length)
            requires(start.other < other.corners.length)
        {
            uint count = 1;
            uint own_start_idx = start.own;
            uint own_end_idx = start.own;
            uint other_start_idx = start.other;
            uint other_end_idx = start.other;
            uint other_len = other.corners.length;

            for(uint off=1 ; off<other_len ; off++) {
                uint other_idx = other.inc_corner_idx(other_end_idx);
                uint own_idx = this.dec_corner_idx(own_start_idx);
                if(this.corners[own_idx] != other.corners[other_idx])
                    break;
                count++;
                other_end_idx = other_idx;
                own_start_idx = own_idx;
            }

            for(uint off=1 ; off<other_len ; off++) {
                uint other_idx = other.dec_corner_idx(other_start_idx);
                uint own_idx = this.inc_corner_idx(own_end_idx);
                if(this.corners[own_idx] != other.corners[other_idx])
                    break;
                count++;
                other_start_idx = other_idx;
                own_end_idx = own_idx;
            }

            stdout.printf("own mp=%u start=%u end=%u ", start.own, own_start_idx, own_end_idx); dump_corner_ids(corners);
            stdout.printf("other mp=%u start=%u end=%u ", start.other, other_start_idx, other_end_idx); dump_corner_ids(other.corners);
            stdout.printf("count=%u\n", count);

            if(count <= 1)
                return null;

            if(count >= this.corners.length) {
                stdout.printf("Swapping (was %s swapped)\n", swapped ? "" : "not ");
                assert(!swapped);
                if(swapped) return null;
                return other.merge_impl(this, start.swap(), true);
            }

            uint[] new_corners = {};
            do{
                new_corners += this.corners[own_end_idx];
                own_end_idx = this.inc_corner_idx(own_end_idx);
            }while(own_end_idx != own_start_idx);

            if(count < other_len) {
                new_corners += this.corners[own_end_idx];
                other_start_idx = other.dec_corner_idx(other_start_idx);
                do {
                    other_end_idx = other.inc_corner_idx(other_end_idx);
                    new_corners += other.corners[other_end_idx];
                } while(other_start_idx != other_end_idx);
            } else {
                if(this.corners[own_end_idx] != new_corners[0])
                    new_corners += this.corners[own_end_idx];

                new_corners = cleanup_corners(new_corners);
            }
            dump_corner_ids(new_corners);

            var pos_diff = pos.sub(img_pos);
            var new_part = new Part(grid, new_corners);
            new_part.pos.x = (pos.x < other.pos.x) ? pos.x : other.img_pos.x + pos_diff.x;
            new_part.pos.y = (pos.y < other.pos.y) ? pos.y : other.img_pos.y + pos_diff.y;
            return new_part;
        }

        private uint inc_corner_idx(uint idx)
            requires(idx < corners.length)
        {
            ++idx;
            return (idx == corners.length) ? 0 : idx;
        }

        private uint dec_corner_idx(uint idx)
            requires(idx < corners.length)
        {
            if(idx == 0) idx = corners.length;
            return idx - 1;
        }

        private static uint[] cleanup_corners(owned uint[] corners) {
            int len = corners.length;
            for(int idx=1 ; idx<len ; idx++) {
                if(corners[idx] != corners[len-idx]) {
                    if(idx == 1)
                        break;
                    --idx;
                    stdout.printf("Removing %d warp around indices: ", idx);
                    dump_corner_ids(corners);
                    return cleanup_corners(corners[idx:len-idx]);
                }
            }
            for(int idx=0 ; idx<len ; idx++) {
                while(corners[idx] == corners[(idx+2)%len]) {
                    var idx2 = (idx+2)%len;
                    stdout.printf("Removing from %d to %d: ", idx, idx2);
                    dump_corner_ids(corners);
                    if(idx2 < idx)
                        return cleanup_corners(corners[idx2:idx]);
                    len -= 2;
                    corners.move(idx2, idx, len-idx);
                    corners.resize(len);
                    if(idx > 0) idx--;
                }
            }
            return corners;
        }

        private static void dump_corner_ids(uint[] corners) {
            stdout.printf("id={");
            foreach(var e in corners)
                stdout.printf("%u,", e);
            stdout.printf("}\n");
        }
    }
}
