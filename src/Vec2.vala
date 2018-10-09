namespace puzzle {
    public struct Vec2 {
        public double x;
        public double y;

        public Vec2.zero() { x = 0; y = 0; }
        public Vec2(double x, double y) {
            this.x = x;
            this.y = y;
        }
        public Vec2.vec2(Vec2 other) {
            this.x = other.x;
            this.y = other.y;
        }

        public Vec2 turnLeft()  { return Vec2(-y, x); }
        public Vec2 turnRight() { return Vec2(y, -x); }

        public Vec2 add(Vec2 other) { return Vec2(x + other.x, y + other.y); }
        public Vec2 sub(Vec2 other) { return Vec2(x - other.x, y - other.y); }
        public Vec2 mul(double factor) { return Vec2(x * factor, y * factor); }
        public Vec2 mul2(double fx, double fy) { return Vec2(x * fx, y * fy); }
        public Vec2 div(double factor) { return Vec2(x / factor, y / factor); }
        
        public Vec2 round() { return Vec2(Math.round(x), Math.round(y)); }

        public Vec2 min(Vec2 other) {
            return Vec2(double.min(x, other.x), double.min(y, other.y));
        }
        public Vec2 max(Vec2 other) {
            return Vec2(double.max(x, other.x), double.max(y, other.y));
        }

        public Vec2 spline(Vec2 p0, double f0, Vec2 p1, double f1) {
            return Vec2(
                x + p0.x * f0 + p1.x * f1,
                y + p0.y * f0 + p1.y * f1
            );
        }

        public double distSqr(Vec2 other) {
            double dx = x - other.x;
            double dy = y - other.y;
            return dx*dx + dy*dy;
        }
    }

    public struct UVec2 {
        public uint x;
        public uint y;
        
        public UVec2.zero() { x = 0; y = 0; }
        public UVec2(uint x, uint y) {
            this.x = x;
            this.y = y;
        }
        public UVec2.uvec2(UVec2 other) {
            this.x = other.x;
            this.y = other.y;
        }
    }

    public struct Extend {
        public Vec2 min;
        public Vec2 max;
        
        public Extend.zero() {
            this.min = Vec2.zero();
            this.max = Vec2.zero();
        }
        public Extend.point(Vec2 p) {
            this.min = p;
            this.max = p;
        }
        public Extend.points(Vec2 a, Vec2 b) {
            this.min.x = double.min(a.x, b.x);
            this.min.y = double.min(a.y, b.y);
            this.max.x = double.max(a.x, b.x);
            this.max.y = double.max(a.y, b.y);
        }
        public Extend.point_and_size(Vec2 p, Vec2 size)
            requires(size.x >= 0)
            requires(size.y >= 0)
        {
            this.min = p;
            this.max = p.add(size);
        }
        public void update(Vec2 p) {
            min = min.min(p);
            max = max.max(p);
        }
        public void update_extend(Extend e) {
            min = min.min(e.min);
            max = max.max(e.max);
        }
        
        public Vec2 size() { return max.sub(min); }

        public bool empty { get { return max.x <= min.x && max.y <= min.y; }}

        public bool isInside(Extend other) {
            return min.x >= other.min.x && max.x <= other.max.x &&
                   min.y >= other.min.y && max.y <= other.max.y;
        }
    }
}
