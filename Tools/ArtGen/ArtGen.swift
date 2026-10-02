// Copper Kit — procedural illustration generator.
//
// A small CPU signed-distance-field ray-marcher (rounded boxes, round cones, tapered tubes,
// tori, extruded 2D profiles; soft shadows, ambient occlusion, glossy soft-box reflections,
// velvet sheen) that renders every raster illustration of the app — onboarding backgrounds,
// transparent sprites and the app icon — and writes it into the asset catalog.
//
// The engine is adapted from PlotLantern/Tools/ArtGen (itself from TileLoom/Tools/ArtGen).
// See Tools/ArtGen/README.md for how to run it.

import Foundation
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

typealias V3 = SIMD3<Float>
typealias V4 = SIMD4<Float>
typealias M3 = simd_float3x3

// MARK: - Math helpers

@inline(__always) func sat(_ x: Float) -> Float { min(max(x, 0), 1) }
@inline(__always) func clampf(_ x: Float, _ a: Float, _ b: Float) -> Float { min(max(x, a), b) }
@inline(__always) func mixf(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inline(__always) func mix3(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }
@inline(__always) func sstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = sat((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}
@inline(__always) func reflectv(_ i: V3, _ n: V3) -> V3 { i - 2 * dot(n, i) * n }
@inline(__always) func vabs(_ p: V3) -> V3 { V3(abs(p.x), abs(p.y), abs(p.z)) }
@inline(__always) func vmax0(_ p: V3) -> V3 { V3(max(p.x, 0), max(p.y, 0), max(p.z, 0)) }
@inline(__always) func rad(_ d: Float) -> Float { d * .pi / 180 }
@inline(__always) func fract(_ x: Float) -> Float { x - floor(x) }
@inline(__always) func len2(_ x: Float, _ y: Float) -> Float { (x * x + y * y).squareRoot() }

func rotX(_ a: Float) -> M3 { let c = cos(a), s = sin(a); return M3(rows: [V3(1, 0, 0), V3(0, c, -s), V3(0, s, c)]) }
func rotY(_ a: Float) -> M3 { let c = cos(a), s = sin(a); return M3(rows: [V3(c, 0, s), V3(0, 1, 0), V3(-s, 0, c)]) }
func rotZ(_ a: Float) -> M3 { let c = cos(a), s = sin(a); return M3(rows: [V3(c, -s, 0), V3(s, c, 0), V3(0, 0, 1)]) }

/// Integer hash -> [0,1)
@inline(__always) func ihash(_ x: Int32, _ y: Int32, _ z: Int32) -> Float {
    var h = UInt32(bitPattern: x) &* 73856093
    h ^= UInt32(bitPattern: y) &* 19349663
    h ^= UInt32(bitPattern: z) &* 83492791
    h ^= h >> 13
    h = h &* 0x5bd1_e995
    h ^= h >> 15
    return Float(h & 0xFFFFFF) / Float(0x1000000)
}
@inline(__always) func fhash(_ x: Float, _ y: Float, _ z: Float) -> Float {
    ihash(Int32(clamping: Int(floor(x))), Int32(clamping: Int(floor(y))), Int32(clamping: Int(floor(z))))
}
/// Smooth 2D value noise in [0,1).
@inline(__always) func vnoise(_ x: Float, _ y: Float, _ seed: Int32 = 0) -> Float {
    let ix = floor(x), iy = floor(y)
    let fx = x - ix, fy = y - iy
    let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
    let i = Int32(clamping: Int(ix)), j = Int32(clamping: Int(iy))
    let a = ihash(i, j, seed), b = ihash(i &+ 1, j, seed)
    let c = ihash(i, j &+ 1, seed), d = ihash(i &+ 1, j &+ 1, seed)
    return mixf(mixf(a, b, ux), mixf(c, d, ux), uy)
}

// MARK: - Colour

@inline(__always) func srgbToLinear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
@inline(__always) func linearToSrgb(_ c: Float) -> Float {
    let x = max(c, 0)
    return x <= 0.0031308 ? x * 12.92 : 1.055 * powf(x, 1 / 2.4) - 0.055
}
func hexc(_ h: UInt32) -> V3 {
    V3(srgbToLinear(Float((h >> 16) & 0xFF) / 255),
       srgbToLinear(Float((h >> 8) & 0xFF) / 255),
       srgbToLinear(Float(h & 0xFF) / 255))
}
/// Soft highlight shoulder (identity below the knee).
@inline(__always) func tonemap(_ x: Float) -> Float {
    let k: Float = 0.8
    return x <= k ? x : k + (1 - k) * (1 - expf(-(x - k) / (1 - k)))
}
@inline(__always) func tonemap3(_ c: V3) -> V3 { V3(tonemap(c.x), tonemap(c.y), tonemap(c.z)) }


/// Brand palette (linear light). Brand colours first, derived shades below.
enum Pal {
    // brand
    static let gold = hexc(0xFFD24C)        // Bright Gold: polished brass, small highlights
    static let copper = hexc(0xB46A32)      // Copper: latches, rims, metal parts
    static let amber = hexc(0xFF9B2F)       // Amber: enamel accents, service tag
    static let deepBlue = hexc(0x111E3D)    // Deep Blue: lacquered case, hero world
    static let velvet = hexc(0x263C68)      // Velvet: linings, foam, dark panels
    static let cream = hexc(0xFFF4D8)       // Cream: enamel handles, paper, canvas, tags
    static let appBg = hexc(0xF8F3E9)       // app background (sprites are reviewed on it)
    static let ink = hexc(0x242D43)         // text colour, used for contact shadows
    static let muted = hexc(0x657087)       // secondary text: blank "writing" lines
    static let service = hexc(0x965D28)     // service brown: string, leather straps (sparingly)
    // derived: metals
    static let brass = hexc(0xE3AD3F)
    static let brassDeep = hexc(0x8F6A22)
    static let copperHi = hexc(0xDC905A)
    static let copperDeep = hexc(0x6E3A17)
    // derived: blues
    static let lacquer = hexc(0x15254B)
    static let blueNight = hexc(0x0C1630)
    static let blueMid = hexc(0x162548)
    static let velvetDeep = hexc(0x1B2D55)
    static let velvetHi = hexc(0x3A5588)
    static let velvetSheen = hexc(0x7E98CC)
    // derived: cream / amber
    static let creamDeep = hexc(0xEFDDB4)
    static let canvas = hexc(0xF4E6C4)
    static let paper = hexc(0xFFF9EC)
    static let amberDeep = hexc(0xD8761F)
    static let glowWarm = V3(1.0, 0.72, 0.38)
}

// MARK: - SDF primitives

@inline(__always) func sdRoundBox(_ p: V3, _ b: V3, _ r: Float) -> Float {
    let q = vabs(p) - b + V3(repeating: r)
    return length(vmax0(q)) + min(max(q.x, max(q.y, q.z)), 0) - r
}
@inline(__always) func sdBox(_ p: V3, _ b: V3) -> Float {
    let q = vabs(p) - b
    return length(vmax0(q)) + min(max(q.x, max(q.y, q.z)), 0)
}
@inline(__always) func sdSphere(_ p: V3, _ r: Float) -> Float { length(p) - r }
/// Vertical capped cylinder (radius r, half height h), used for tight bounds.
@inline(__always) func sdCylY(_ p: V3, _ r: Float, _ h: Float) -> Float {
    let dx = len2(p.x, p.z) - r, dy = abs(p.y) - h
    let ox = max(dx, 0), oy = max(dy, 0)
    return min(max(dx, dy), 0) + (ox * ox + oy * oy).squareRoot()
}
@inline(__always) func sdEllipsoid(_ p: V3, _ r: V3) -> Float {
    let k0 = length(p / r)
    let k1 = length(p / (r * r))
    return k0 * (k0 - 1) / k1
}
@inline(__always) func sdCapsule(_ p: V3, _ a: V3, _ b: V3, _ r: Float) -> Float {
    let pa = p - a, ba = b - a
    let h = sat(dot(pa, ba) / dot(ba, ba))
    return length(pa - ba * h) - r
}
/// Ring in the local xy plane (axis z): major radius R, tube radius r.
@inline(__always) func sdTorusZ(_ p: V3, _ R: Float, _ r: Float) -> Float { len2(len2(p.x, p.y) - R, p.z) - r }
/// Ring in the local yz plane (axis x).
@inline(__always) func sdTorusX(_ p: V3, _ R: Float, _ r: Float) -> Float { len2(len2(p.y, p.z) - R, p.x) - r }
/// Ring in the local xz plane (axis y).
@inline(__always) func sdTorusY(_ p: V3, _ R: Float, _ r: Float) -> Float { len2(len2(p.x, p.z) - R, p.y) - r }
/// 2D rounded rectangle distance.
@inline(__always) func sdRoundRect(_ x: Float, _ y: Float, _ bx: Float, _ by: Float, _ r: Float) -> Float {
    let qx = abs(x) - bx + r, qy = abs(y) - by + r
    let ox = max(qx, 0), oy = max(qy, 0)
    return sqrt(ox * ox + oy * oy) + min(max(qx, qy), 0) - r
}
/// 2D distance to a segment.
@inline(__always) func sdSeg2(_ px: Float, _ py: Float, _ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
    let pax = px - ax, pay = py - ay, bax = bx - ax, bay = by - ay
    let h = sat((pax * bax + pay * bay) / (bax * bax + bay * bay))
    return len2(pax - bax * h, pay - bay * h)
}
/// 2D regular hexagon with apothem r: flat sides facing ±y, corners on the ±x axis.
@inline(__always) func sdHex2(_ x: Float, _ y: Float, _ r: Float) -> Float {
    let kx: Float = -0.866025404, ky: Float = 0.5, kz: Float = 0.577350269
    var px = abs(x), py = abs(y)
    let d = 2 * min(kx * px + ky * py, 0)
    px -= d * kx
    py -= d * ky
    px -= clampf(px, -kz * r, kz * r)
    py -= r
    return len2(px, py) * (py < 0 ? -1 : 1)
}
/// 2D isosceles trapezoid: half width r1 at y = -he, r2 at y = +he.
@inline(__always) func sdTrapezoid2(_ px0: Float, _ py: Float, _ r1: Float, _ r2: Float, _ he: Float) -> Float {
    let px = abs(px0)
    let k1x = r2, k1y = he
    let k2x = r2 - r1, k2y = 2 * he
    let cax = px - min(px, py < 0 ? r1 : r2), cay = abs(py) - he
    let tt = sat(((k1x - px) * k2x + (k1y - py) * k2y) / (k2x * k2x + k2y * k2y))
    let cbx = px - k1x + k2x * tt, cby = py - k1y + k2y * tt
    let s: Float = (cbx < 0 && cay < 0) ? -1 : 1
    return s * min(cax * cax + cay * cay, cbx * cbx + cby * cby).squareRoot()
}
/// Round cone (y axis): sphere r1 at the origin, sphere r2 at (0, h, 0).
@inline(__always) func sdRoundCone(_ p: V3, _ r1: Float, _ r2: Float, _ h: Float) -> Float {
    let b = (r1 - r2) / h
    let a = (1 - b * b).squareRoot()
    let qx = len2(p.x, p.z), qy = p.y
    let k = -qx * b + qy * a
    if k < 0 { return len2(qx, qy) - r1 }
    if k > a * h { return len2(qx, qy - h) - r2 }
    return qx * a + qy * b - r1
}
/// Sample a Catmull-Rom spline through `pts` (per segment `k` samples) into a polyline.
func catmullRom(_ pts: [V3], _ k: Int) -> [V3] {
    var out: [V3] = []
    let n = pts.count
    for i in 0..<(n - 1) {
        let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, n - 1)]
        for j in 0..<k {
            let t = Float(j) / Float(k)
            let t2 = t * t, t3 = t2 * t
            var a = p1 * 2
            a += (p2 - p0) * t
            a += (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2
            a += (p1 * 3 - p0 - p2 * 3 + p3) * t3
            out.append(a * 0.5)
        }
    }
    out.append(pts[n - 1])
    return out
}
/// Distance to a tube of radius r along a polyline.
@inline(__always) func sdTube(_ q: V3, _ pts: [V3], _ r: Float) -> Float {
    var d = Float.greatestFiniteMagnitude
    for i in 0..<(pts.count - 1) { d = min(d, sdCapsule(q, pts[i], pts[i + 1], r)) }
    return d
}

/// Extrude a 2D distance along y (half height h) with rounded caps of radius r.
@inline(__always) func opExtrude(_ d2: Float, _ y: Float, _ h: Float, _ r: Float) -> Float {
    let wx = d2 + r, wy = abs(y) - h + r
    let ox = max(wx, 0), oy = max(wy, 0)
    return min(max(wx, wy), 0) + sqrt(ox * ox + oy * oy) - r
}
@inline(__always) func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
    let h = max(k - abs(a - b), 0) / k
    return min(a, b) - h * h * k * 0.25
}
@inline(__always) func smax(_ a: Float, _ b: Float, _ k: Float) -> Float { -smin(-a, -b, k) }


@inline(__always) func sgnf(_ x: Float) -> Float { x >= 0 ? 1 : -1 }

/// Round cone between two arbitrary points: radius r1 at a, r2 at b (exact, after iq).
@inline(__always) func sdCone(_ p: V3, _ a: V3, _ b: V3, _ r1: Float, _ r2: Float) -> Float {
    let ba = b - a
    let l2 = dot(ba, ba)
    let rr = r1 - r2
    let a2 = l2 - rr * rr
    let il2 = 1 / l2
    let pa = p - a
    let y = dot(pa, ba)
    let z = y - l2
    let xv = pa * l2 - ba * y
    let x2 = dot(xv, xv)
    let y2 = y * y * l2
    let z2 = z * z * l2
    let k = sgnf(rr) * rr * rr * x2
    if sgnf(z) * a2 * z2 > k { return (x2 + z2).squareRoot() * il2 - r2 }
    if sgnf(y) * a2 * y2 < k { return (x2 + y2).squareRoot() * il2 - r1 }
    return ((x2 * a2 * il2).squareRoot() + y * rr) * il2 - r1
}
/// Capped cylinders along x / z (radius r, half length h, edge rounding e).
@inline(__always) func sdCylX(_ p: V3, _ r: Float, _ h: Float, _ e: Float = 0) -> Float { opExtrude(len2(p.y, p.z) - r, p.x, h, e) }
@inline(__always) func sdCylZ(_ p: V3, _ r: Float, _ h: Float, _ e: Float = 0) -> Float { opExtrude(len2(p.x, p.y) - r, p.z, h, e) }
/// Ring (torus) around an arbitrary unit axis `ax` through `c`.
@inline(__always) func sdRing(_ p: V3, _ c: V3, _ ax: V3, _ R: Float, _ r: Float) -> Float {
    let v = p - c
    let a = dot(v, ax)
    return len2(length(v - ax * a) - R, a) - r
}

struct Hit { var d: Float; var m: Int32 }
@inline(__always) func U(_ a: Hit, _ d: Float, _ m: Int32) -> Hit { d < a.d ? Hit(d: d, m: m) : a }
@inline(__always) func U(_ a: Hit, _ b: Hit) -> Hit { b.d < a.d ? b : a }

protocol SDF { func map(_ p: V3) -> Hit }

/// Rigid transform (rotation + translation). `rot` maps local -> world.
struct Xf {
    var t: V3
    var rot: M3
    var inv: M3
    init(_ t: V3, _ r: M3 = matrix_identity_float3x3) { self.t = t; rot = r; inv = r.transpose }
    @inline(__always) func loc(_ p: V3) -> V3 { inv * (p - t) }
    @inline(__always) func locDir(_ d: V3) -> V3 { inv * d }
    @inline(__always) func world(_ p: V3) -> V3 { rot * p + t }
    @inline(__always) func worldDir(_ d: V3) -> V3 { rot * d }
    /// Compose: child expressed in this frame.
    func child(_ c: Xf) -> Xf { Xf(world(c.t), rot * c.rot) }
}

// MARK: - Ray marching

struct MR { var t: Float; var m: Int32 }

@inline(__always) func march<S: SDF>(_ s: S, _ ro: V3, _ rd: V3, _ tmin: Float, _ tmax: Float,
                                      _ eps0: Float, _ epsK: Float, _ steps: Int, _ relax: Float = 1) -> MR {
    var t = tmin
    var last = Hit(d: 1e9, m: -1)
    for _ in 0..<steps {
        let h = s.map(ro + rd * t)
        last = h
        if h.d < eps0 + epsK * t { return MR(t: t, m: h.m) }
        t += h.d * relax
        if t > tmax { return MR(t: -1, m: -1) }
    }
    if last.d < 0.01 { return MR(t: t, m: last.m) }
    return MR(t: -1, m: -1)
}

@inline(__always) func calcNormal<S: SDF>(_ s: S, _ p: V3, _ e: Float) -> V3 {
    let k1 = V3(1, -1, -1), k2 = V3(-1, -1, 1), k3 = V3(-1, 1, -1), k4 = V3(1, 1, 1)
    let a = k1 * s.map(p + k1 * e).d
    let b = k2 * s.map(p + k2 * e).d
    let c = k3 * s.map(p + k3 * e).d
    let d = k4 * s.map(p + k4 * e).d
    return normalize(a + b + c + d)
}

/// Soft shadow toward `rd`. `jitter` in [0,1) offsets the first step per sample so that
/// penumbra step-banding turns into fine noise that the supersampling averages out.
@inline(__always) func softShadow<S: SDF>(_ s: S, _ ro: V3, _ rd: V3, _ mint: Float, _ maxt: Float, _ k: Float,
                                           _ jitter: Float = 0) -> Float {
    var res: Float = 1
    var t = mint * (1 + 2 * jitter)
    for _ in 0..<200 {
        let h = s.map(ro + rd * t).d
        if h < 0.00008 { return 0 }
        res = min(res, k * h / t)
        t += clampf(h, 0.0025, 0.1) * (0.8 + 0.4 * jitter)
        if t > maxt || res < 0.001 { break }
    }
    res = sat(res)
    return res * res * (3 - 2 * res)
}

@inline(__always) func calcAO<S: SDF>(_ s: S, _ p: V3, _ n: V3, _ scale: Float) -> Float {
    var occ: Float = 0
    var w: Float = 1
    for i in 1...5 {
        let h = scale * Float(i) / 5
        let d = s.map(p + n * h).d
        occ += max(h - d, 0) * w
        w *= 0.72
    }
    return sat(1 - 0.95 * occ / scale)
}

// MARK: - Lighting

struct Softbox {
    var c = V3.zero
    var n = V3(0, -1, 0)
    var ax = V3(1, 0, 0)
    var ay = V3(0, 0, 1)
    var hx: Float = 1
    var hy: Float = 1
    var soft: Float = 0.2
    var I: Float = 0
    var col = V3(1, 1, 1)

    @inline(__always) func radiance(_ p: V3, _ r: V3) -> V3 {
        if I <= 0 { return .zero }
        let dn = dot(r, n)
        if dn > -1e-4 { return .zero }
        let t = dot(c - p, n) / dn
        if t <= 0 { return .zero }
        let q = p + r * t - c
        let x = abs(dot(q, ax)), y = abs(dot(q, ay))
        let m = (1 - sstep(hx - soft, hx + soft, x)) * (1 - sstep(hy - soft, hy + soft, y))
        return col * (I * m)
    }
}

/// A long soft-box strip positioned so that its reflection crosses a flat face
/// (normal `faceN`) through the point `through`, tilted by `angle` degrees.
func bandBox(through: V3, faceN: V3, viewDir: V3, dist: Float, angle: Float, width: Float,
             soft: Float, intensity: Float, col: V3 = V3(1, 1, 1)) -> Softbox {
    let r0 = normalize(reflectv(normalize(viewDir), normalize(faceN)))
    var b = Softbox()
    b.c = through + r0 * dist
    b.n = -r0
    var ref = V3(0, 1, 0)
    if abs(dot(ref, b.n)) > 0.95 { ref = V3(1, 0, 0) }
    let u0 = normalize(cross(ref, b.n))
    let v0 = cross(b.n, u0)
    let a = rad(angle)
    b.ax = u0 * cos(a) + v0 * sin(a)
    b.ay = v0 * cos(a) - u0 * sin(a)
    b.hx = 100
    b.hy = width * 0.5
    b.soft = soft
    b.I = intensity
    b.col = col
    return b
}

struct Studio {
    var L = normalize(V3(-0.4, 1, 0.5))
    var keyCol = V3(1.0, 0.955, 0.89)
    var keyI: Float = 0.95
    var skyCol = V3(0.95, 0.93, 0.95)
    var skyI: Float = 0.42
    var bounceCol = V3(1.0, 0.88, 0.72)
    var bounceI: Float = 0.16
    var wrap: Float = 0.3
    var envLo = V3(0.08, 0.07, 0.09)
    var envHi = V3(0.5, 0.47, 0.44)
    var b1 = Softbox()
    var b2 = Softbox()
    var b3 = Softbox()
    /// warm rim light (direction toward the light), fades in at grazing angles only
    var rimDir = V3(0.7, 0.5, -0.5)
    var rimCol = V3(1.0, 0.84, 0.58)
    var rimI: Float = 0
    /// warm glow: unshadowed point light (e.g. a cream-lit case interior)
    var ptPos = V3.zero
    var ptCol = Pal.glowWarm
    var ptI: Float = 0
    var ptR: Float = 1

    @inline(__always) func env(_ p: V3, _ r: V3) -> V3 {
        let e = mix3(envLo, envHi, sstep(-0.4, 0.9, r.y))
        return e + b1.radiance(p, r) + b2.radiance(p, r) + b3.radiance(p, r)
    }
}

struct Surf {
    var albedo: V3
    var n: V3
    var spec: Float = 0.25
    var pw: Float = 24
    var refl: Float = 0.15
    var f0: Float = 0.04
    var metal: Float = 0
    var dif: Float = 1
    var emit = V3.zero
    var rim: Float = 1
    /// thin fabric / paper: the warm point light shining through from behind
    var trans: Float = 0
    /// velvet pile: extra sheen toward grazing angles, tinted by `sheenCol`
    var velvet: Float = 0
    var sheenCol = V3.zero
}

@inline(__always) func shade(_ s: Surf, _ p: V3, _ rd: V3, _ sh: Float, _ ao: Float, _ st: Studio) -> V3 {
    let n = s.n
    let v = -rd
    let ndl = dot(n, st.L)
    let key = sat((ndl + st.wrap) / (1 + st.wrap)) * sh
    let aoL = 0.22 + 0.78 * ao
    let sky = (0.62 + 0.38 * n.y) * aoL
    let bnc = sat(0.55 - 0.45 * n.y) * aoL
    var light = st.keyCol * (key * st.keyI) + st.skyCol * (sky * st.skyI) + st.bounceCol * (bnc * st.bounceI)
    var ptSpec = V3.zero
    if st.ptI > 0 {
        let dv = st.ptPos - p
        let d2 = dot(dv, dv)
        let l = dv / d2.squareRoot()
        let fall = st.ptI / (1 + d2 / (st.ptR * st.ptR))
        let ndp = sat(dot(n, l))
        light += st.ptCol * (ndp * fall * (0.35 + 0.65 * ao))
        if s.trans > 0 { light += st.ptCol * (sat(-dot(n, l)) * fall * s.trans) }
        let hp = normalize(l + v)
        let sp = powf(sat(dot(n, hp)), s.pw) * s.spec * fall * ndp
        ptSpec = st.ptCol * sp
    }
    var col = s.albedo * light * s.dif
    let h = normalize(st.L + v)
    let spe = powf(sat(dot(n, h)), s.pw) * s.spec * sh * sat(ndl * 3)
    let ndv = sat(dot(n, v))
    let fr = s.f0 + (1 - s.f0) * powf(1 - ndv, 5)
    let r = reflectv(rd, n)
    let e = st.env(p, r)
    let tint = mix3(V3(1, 1, 1), s.albedo, s.metal)
    let reflAmt = s.refl * mixf(fr, 1, s.metal) * (0.3 + 0.7 * ao)
    col += tint * (st.keyCol * spe + e * reflAmt + ptSpec)
    if s.velvet > 0 {
        let g = powf(1 - ndv, 2.2)
        col += s.sheenCol * (g * s.velvet * (0.2 + 0.8 * key * st.keyI + 0.5 * sky * st.skyI))
    }
    if st.rimI > 0 && s.rim > 0 {
        let g = powf(1 - ndv, 3) * sat(dot(n, st.rimDir) * 0.8 + 0.2)
        let rimTint = mix3(V3(1, 1, 1), s.albedo, 0.3 + 0.5 * s.metal)
        col += st.rimCol * rimTint * (g * st.rimI * s.rim * (0.4 + 0.6 * ao))
    }
    col += s.emit
    return col
}

// MARK: - Material ids (shared by every part and scene)

enum Mat {
    static let ground: Int32 = 1
    static let mat: Int32 = 2
    static let wall: Int32 = 3
    static let brass: Int32 = 10
    static let gold: Int32 = 11
    static let copper: Int32 = 12
    static let cream: Int32 = 13
    static let lacquer: Int32 = 14
    static let foam: Int32 = 15
    static let amber: Int32 = 16
    static let canvas: Int32 = 17
    static let leather: Int32 = 18
    static let paper: Int32 = 19
    static let cord: Int32 = 20
    static let glove: Int32 = 21
    static let cuff: Int32 = 22
    static let tagFace: Int32 = 23
    static let serviceTag: Int32 = 24
    static let blueCord: Int32 = 25
    static let pocket: Int32 = 26
    static let sheet: Int32 = 27
}

// MARK: - Materials

/// Polished brass: the golden metal (Bright Gold highlights). Metals are the only glinting surfaces.
@inline(__always) func brassSurf(_ n: V3, _ polish: Float = 0) -> Surf {
    Surf(albedo: mix3(Pal.brass, Pal.gold, 0.3 * polish), n: n, spec: 1.4 + 0.5 * polish, pw: 60 + 50 * polish,
         refl: 0.95, f0: 0.55, metal: 1, dif: 0.4)
}
/// Polished copper (latches, rims, hammer head, clamp frame).
@inline(__always) func copperSurf(_ n: V3, _ polish: Float = 0) -> Surf {
    Surf(albedo: mix3(Pal.copper, Pal.copperHi, 0.35 * polish), n: n, spec: 1.2 + 0.4 * polish, pw: 50 + 40 * polish,
         refl: 0.9, f0: 0.5, metal: 1, dif: 0.5)
}
/// Satin enamel (cream handles, amber accents): a soft broad sheen, no metallic glint.
@inline(__always) func enamelSurf(_ alb: V3, _ n: V3, sheen: Float = 0.2) -> Surf {
    Surf(albedo: alb, n: n, spec: sheen, pw: 14, refl: 0.2, f0: 0.04)
}
/// Deep-blue lacquer: glossy soft-box reflections and a broad key sheen (no pin-point glints).
@inline(__always) func lacquerSurf(_ alb: V3, _ n: V3) -> Surf {
    Surf(albedo: alb, n: n, spec: 0.3, pw: 22, refl: 0.8, f0: 0.05)
}
/// Velvet / flocked foam: matte, darker face-on, a soft bright sheen toward grazing angles.
@inline(__always) func velvetSurf(_ alb: V3, _ n: V3, _ p: V3, sheen: Float = 1) -> Surf {
    let fib = vnoise(p.x * 95 + p.y * 17, p.z * 95 + p.y * 43, 7)
    var s = Surf(albedo: alb * (0.92 + 0.14 * fib), n: n, spec: 0.03, pw: 6, refl: 0, f0: 0.02)
    s.velvet = 0.85 * sheen
    s.sheenCol = Pal.velvetSheen
    s.rim = 0.5
    return s
}
/// Matte fabric / paper with a faint fibre texture.
@inline(__always) func fabricSurf(_ alb: V3, _ n: V3, _ q: V3, sheen: Float = 0.1, grain: Float = 70) -> Surf {
    let fib = vnoise(q.x * grain + q.z * 11, q.y * grain + q.z * 57, 21)
    return Surf(albedo: alb * (0.97 + 0.05 * fib), n: n, spec: sheen, pw: 12, refl: 0.04, f0: 0.04)
}

/// Default look of every shared material id (scenes override the few that need local texture).
func stdSurf(_ m: Int32, _ p: V3, _ n: V3) -> Surf {
    switch m {
    case Mat.brass: return brassSurf(n, 0.3)
    case Mat.gold: return brassSurf(n, 1)
    case Mat.copper: return copperSurf(n, 0.5)
    case Mat.cream: return enamelSurf(Pal.cream, n, sheen: 0.22)
    case Mat.lacquer: return lacquerSurf(Pal.lacquer, n)
    case Mat.foam: return velvetSurf(Pal.velvet, n, p)
    case Mat.amber, Mat.serviceTag: return enamelSurf(Pal.amber, n, sheen: 0.24)
    case Mat.canvas, Mat.pocket: return fabricSurf(Pal.canvas, n, p, sheen: 0.06, grain: 160)
    case Mat.leather: return Surf(albedo: Pal.service, n: n, spec: 0.22, pw: 16, refl: 0.08, f0: 0.04)
    case Mat.paper, Mat.sheet: return fabricSurf(Pal.paper, n, p, sheen: 0.1)
    case Mat.cord: return fabricSurf(Pal.service, n, p, sheen: 0.12, grain: 220)
    case Mat.blueCord: return fabricSurf(Pal.velvetHi, n, p, sheen: 0.12, grain: 220)
    case Mat.glove: return fabricSurf(Pal.cream, n, p, sheen: 0.14, grain: 130)
    case Mat.cuff: return fabricSurf(Pal.amber, n, p, sheen: 0.16, grain: 130)
    case Mat.tagFace: return fabricSurf(Pal.cream, n, p, sheen: 0.14)
    default: return enamelSurf(Pal.cream, n)
    }
}

// MARK: - Scene protocol (opaque surfaces + thin glass)

struct GlassLook {
    var tint = V3(0.8, 0.72, 1.0)
    var back = Pal.blueNight
    var glowC = V3.zero
    var glowR: Float = 0.4
    var glowCol = V3.zero
    var f0: Float = 0.06
    var reflI: Float = 1.4
    var paneT: Float = 0.02
    var maxT: Float = 3
    var reflTint = V3(0.62, 0.56, 0.9)
}

protocol Scene: SDF {
    var studio: Studio { get }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf
    func aoScale(_ m: Int32) -> Float
    func keyMask(_ p: V3) -> Float
    func isGlass(_ m: Int32) -> Bool
    func glassLook(_ p: V3) -> GlassLook
}
extension Scene {
    func keyMask(_ p: V3) -> Float { 1 }
    func isGlass(_ m: Int32) -> Bool { false }
    func glassLook(_ p: V3) -> GlassLook { GlassLook() }
}

/// Debug: 1 = disable shadows, 2 = disable AO (tuning only).
var debugMode = 0

func shadeHit<S: Scene, A: SDF>(_ s: S, _ aoS: A, _ ro: V3, _ rd: V3, _ t: Float, _ m: Int32, _ jit: Float,
                                _ nEps: Float, _ shadowK: Float, _ maxShadowT: Float, _ depth: Int = 0) -> V3 {
    let p = ro + rd * t
    let n = calcNormal(s, p, nEps)
    if depth == 0 && s.isGlass(m) {
        return shadeGlass(s, aoS, p, n, rd, jit, nEps, shadowK, maxShadowT)
    }
    let st = s.studio
    let sf = s.surface(p, n, m)
    var sh: Float = 1
    if debugMode != 1 { sh = softShadow(s, p + n * 0.003, st.L, 0.004, maxShadowT, shadowK, jit) * s.keyMask(p) }
    let ao: Float = debugMode == 2 ? 1 : calcAO(aoS, p + n * 0.001, n, s.aoScale(m))
    return shade(sf, p, rd, sh, ao, st)
}

/// Thin tinted glass (unused by the current scenes): glossy reflection on top, transmitted view
/// of whatever sits behind it, plus a warm glow scattered around an inner light source.
func shadeGlass<S: Scene, A: SDF>(_ s: S, _ aoS: A, _ p: V3, _ n0: V3, _ rd: V3, _ jit: Float,
                                  _ nEps: Float, _ shadowK: Float, _ maxShadowT: Float) -> V3 {
    let st = s.studio
    let g = s.glassLook(p)
    let n = dot(n0, rd) > 0 ? -n0 : n0
    let v = -rd
    let ndv = sat(dot(n, v))
    let fr = g.f0 + (1 - g.f0) * powf(1 - ndv, 5)
    let e = st.env(p, reflectv(rd, n))
    let hv = normalize(st.L + v)
    let spe = powf(sat(dot(n, hv)), 150) * 1.4
    let start = p + rd * (g.paneT / max(ndv, 0.2))
    let r2 = march(s, start, rd, 0, g.maxT, 0.0003, 0, 220)
    var tcol = g.back
    var seg = g.maxT
    if r2.t > 0 {
        seg = r2.t
        if !s.isGlass(r2.m) {
            tcol = shadeHit(s, aoS, start, rd, r2.t, r2.m, jit, nEps, shadowK, maxShadowT, 1)
        }
    }
    let tt = clampf(dot(g.glowC - start, rd), 0, seg)
    let dq = start + rd * tt - g.glowC
    let glow = g.glowCol * expf(-dot(dq, dq) / (g.glowR * g.glowR))
    let trans = tcol * g.tint + glow
    return trans * (1 - fr) + (e * g.reflTint * fr + st.keyCol * spe) * g.reflI
}

// MARK: - Cameras

struct OrthoCam {
    var pos = V3.zero, fwd = V3(0, 0, -1), right = V3(1, 0, 0), up = V3(0, 1, 0)
    var cx: Float = 0, cy: Float = 0, halfH: Float = 1
    var W: Float, H: Float
    init(target: V3, az: Float, el: Float, W: Int, H: Int) {
        let a = rad(az), e = rad(el)
        let dir = V3(sin(a) * cos(e), sin(e), cos(a) * cos(e))
        pos = target + dir * 30
        fwd = -dir
        right = normalize(cross(fwd, V3(0, 1, 0)))
        up = cross(right, fwd)
        self.W = Float(W)
        self.H = Float(H)
    }
    @inline(__always) func ray(_ x: Float, _ y: Float) -> (V3, V3) {
        let u = ((x / W) * 2 - 1) * halfH * (W / H) + cx
        let v = (1 - (y / H) * 2) * halfH + cy
        return (pos + right * u + up * v, fwd)
    }
    /// Light direction relative to the camera (upper-left studio key).
    func light(left: Float, up upA: Float, front: Float) -> V3 {
        let toCam = normalize(V3(-fwd.x, 0, -fwd.z))
        let rh = normalize(V3(right.x, 0, right.z))
        return normalize(-rh * left + V3(0, 1, 0) * upA + toCam * front)
    }
}

struct PerspCam {
    var pos: V3, fwd: V3, right: V3, up: V3
    var tanY: Float, shiftY: Float
    var W: Float, H: Float
    init(pos: V3, target: V3, fovY: Float, W: Int, H: Int, shiftY: Float = 0) {
        self.pos = pos
        fwd = normalize(target - pos)
        right = normalize(cross(fwd, V3(0, 1, 0)))
        up = cross(right, fwd)
        tanY = tan(rad(fovY) / 2)
        self.shiftY = shiftY
        self.W = Float(W)
        self.H = Float(H)
    }
    @inline(__always) func ray(_ x: Float, _ y: Float) -> (V3, V3) {
        let u = ((x / W) * 2 - 1) * tanY * (W / H)
        let v = (1 - (y / H) * 2) * tanY + shiftY * tanY
        return (pos, normalize(fwd + right * u + up * v))
    }
    func light(left: Float, up upA: Float, front: Float) -> V3 {
        let toCam = normalize(V3(-fwd.x, 0, -fwd.z))
        let rh = normalize(V3(right.x, 0, right.z))
        return normalize(-rh * left + V3(0, 1, 0) * upA + toCam * front)
    }
}

func orbitCam(target: V3, az: Float, el: Float, dist: Float, fovY: Float, W: Int, H: Int, shiftY: Float) -> PerspCam {
    let a = rad(az), e = rad(el)
    let pos = target + V3(sin(a) * cos(e), sin(e), cos(a) * cos(e)) * dist
    return PerspCam(pos: pos, target: target, fovY: fovY, W: W, H: H, shiftY: shiftY)
}

/// Fit an orthographic camera to the object's silhouette with the given padding.
func fitOrtho<S: SDF>(_ s: S, _ cam: inout OrthoCam, pad: Float, span: Float = 4) {
    let n = 420
    var umin = Float.greatestFiniteMagnitude, umax = -Float.greatestFiniteMagnitude
    var vmin = umin, vmax = umax
    for j in 0..<n {
        for i in 0..<n {
            let u = -span + 2 * span * (Float(i) + 0.5) / Float(n)
            let v = -span + 2 * span * (Float(j) + 0.5) / Float(n)
            let ro = cam.pos + cam.right * u + cam.up * v
            let r = march(s, ro, cam.fwd, 0, 100, 0.001, 0, 220)
            if r.t > 0 {
                umin = min(umin, u); umax = max(umax, u)
                vmin = min(vmin, v); vmax = max(vmax, v)
            }
        }
    }
    let cell = 2 * span / Float(n)
    umin -= cell; umax += cell; vmin -= cell; vmax += cell
    cam.cx = (umin + umax) / 2
    cam.cy = (vmin + vmax) / 2
    let avail = 1 - 2 * pad
    let aspect = cam.W / cam.H
    cam.halfH = max((vmax - vmin) / (2 * avail), (umax - umin) / (2 * avail * aspect))
}

/// Studio for transparent sprites: key from the upper left, warm rim from the back right.
func spriteStudio(_ cam: OrthoCam, left: Float = 0.6, up: Float = 1.0, front: Float = 0.4) -> Studio {
    var st = Studio()
    st.L = cam.light(left: left, up: up, front: front)
    let back = normalize(V3(cam.fwd.x, 0, cam.fwd.z))
    let rh = normalize(V3(cam.right.x, 0, cam.right.z))
    st.rimDir = normalize(rh * 0.75 + V3(0, 0.55, 0) + back * 0.45)
    st.rimI = 0.32
    return st
}

// MARK: - Rendering

protocol PixelShader { func pixel(_ x: Float, _ y: Float) -> V4 }

/// Renders premultiplied linear RGBA (already tone-mapped) with ss x ss supersampling.
func render<S: PixelShader>(_ s: S, _ w: Int, _ h: Int, ss: Int) -> [Float] {
    var out = [Float](repeating: 0, count: w * h * 4)
    let inv = 1 / Float(ss * ss)
    out.withUnsafeMutableBufferPointer { buf in
        let base = buf.baseAddress!
        DispatchQueue.concurrentPerform(iterations: h) { y in
            for x in 0..<w {
                var acc = V4.zero
                for j in 0..<ss {
                    for i in 0..<ss {
                        let ox = (Float(i) + 0.5) / Float(ss)
                        let oy = (Float(j) + 0.5) / Float(ss)
                        acc += s.pixel(Float(x) + ox, Float(y) + oy)
                    }
                }
                acc *= inv
                let o = (y * w + x) * 4
                base[o] = acc.x; base[o + 1] = acc.y; base[o + 2] = acc.z; base[o + 3] = acc.w
            }
        }
    }
    return out
}

enum OutFormat { case pngAlpha, pngOpaque, jpeg(Float) }

/// When set, transparent sprites are flattened onto this colour (for review only).
var previewBG: V3? = nil

func saveImage(_ buf: [Float], _ w: Int, _ h: Int, path: String, format: OutFormat) throws {
    var alpha: Bool
    switch format { case .pngAlpha: alpha = true; default: alpha = false }
    if previewBG != nil { alpha = false }
    let comps = alpha ? 4 : 3
    var bytes = [UInt8](repeating: 0, count: w * h * comps)
    let dither: Bool
    if case .jpeg = format { dither = true } else { dither = !alpha }
    let bg = previewBG ?? Pal.appBg
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let a = buf[i + 3]
            var c = V3(buf[i], buf[i + 1], buf[i + 2])
            if alpha {
                c = a > 1e-6 ? c / a : .zero
            } else if a < 0.999 {
                c = c + bg * (1 - a)
            }
            var s = V3(linearToSrgb(c.x), linearToSrgb(c.y), linearToSrgb(c.z)) * 255
            if dither {
                let n = ihash(Int32(x), Int32(y), 991) + ihash(Int32(x), Int32(y), 17) - 1
                s += V3(repeating: n * 0.9)
            }
            let o = (y * w + x) * comps
            bytes[o] = UInt8(clampf(s.x.rounded(), 0, 255))
            bytes[o + 1] = UInt8(clampf(s.y.rounded(), 0, 255))
            bytes[o + 2] = UInt8(clampf(s.z.rounded(), 0, 255))
            if alpha { bytes[o + 3] = UInt8(clampf((a * 255).rounded(), 0, 255)) }
        }
    }
    let data = Data(bytes) as CFData
    guard let provider = CGDataProvider(data: data) else { throw NSError(domain: "ArtGen", code: 1) }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = CGBitmapInfo(rawValue: alpha ? CGImageAlphaInfo.last.rawValue : CGImageAlphaInfo.none.rawValue)
    guard let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8 * comps,
                            bytesPerRow: w * comps, space: space, bitmapInfo: info, provider: provider,
                            decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
        throw NSError(domain: "ArtGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "CGImage creation failed"])
    }
    let url = URL(fileURLWithPath: path)
    let type: CFString
    var props: [CFString: Any] = [:]
    switch format {
    case .jpeg(let q):
        type = UTType.jpeg.identifier as CFString
        props[kCGImageDestinationLossyCompressionQuality] = q
    default:
        type = UTType.png.identifier as CFString
    }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
        throw NSError(domain: "ArtGen", code: 3, userInfo: [NSLocalizedDescriptionKey: "cannot write \(path)"])
    }
    CGImageDestinationAddImage(dest, img, props as CFDictionary)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "ArtGen", code: 4, userInfo: [NSLocalizedDescriptionKey: "finalize failed \(path)"])
    }
}

// MARK: - Sprite (transparent) rendering

struct WithGround<M: SDF>: SDF {
    let m: M
    @inline(__always) func map(_ p: V3) -> Hit {
        let h = m.map(p)
        return p.y < h.d ? Hit(d: p.y, m: 0) : h
    }
}

struct SpriteShader<M: Scene>: PixelShader {
    let model: M
    let cam: OrthoCam
    var shadowK: Float = 8
    var shadowStr: Float = 0.34
    var aoStr: Float = 0.58
    var groundAO: Float = 0.3
    var shadowCol: V3 = Pal.ink
    var maxShadowT: Float = 7
    var edgeFade: Float = 0.05

    func pixel(_ x: Float, _ y: Float) -> V4 {
        let (ro, rd) = cam.ray(x, y)
        let st = model.studio
        let jit = fhash(x * 8, y * 8, 5)
        let r = march(model, ro, rd, 0, 100, 0.00022, 0, 320)
        if r.t > 0 {
            let c = tonemap3(shadeHit(model, WithGround(m: model), ro, rd, r.t, r.m, jit, 0.0005, shadowK, maxShadowT))
            return V4(c.x, c.y, c.z, 1)
        }
        if rd.y < -1e-4 && ro.y > 0 {
            let tg = -ro.y / rd.y
            let pg = ro + rd * tg
            let sh = softShadow(model, pg + V3(0, 0.002, 0), st.L, 0.004, maxShadowT, shadowK, jit)
            let ao = calcAO(model, pg, V3(0, 1, 0), groundAO)
            let a1 = (1 - sh) * shadowStr
            let a2 = (1 - ao) * aoStr
            var a = 1 - (1 - a1) * (1 - a2)
            let ex = min(x, cam.W - x) / cam.W
            let ey = min(y, cam.H - y) / cam.H
            a *= sstep(0.0, edgeFade, min(ex, ey))
            if a < 0.002 { return .zero }
            return V4(shadowCol.x * a, shadowCol.y * a, shadowCol.z * a, a)
        }
        return .zero
    }
}

// MARK: - Background (opaque, perspective) rendering

struct BGShader<M: Scene>: PixelShader {
    let model: M
    let cam: PerspCam
    var quietStart: Float = 0.6
    var quietEnd: Float = 0.8
    var quietTop: V3 = Pal.blueMid
    var quietBottom: V3 = Pal.blueNight
    var quietAmount: Float = 0.85
    var vignette: Float = 0.12
    var shadowK: Float = 7
    var maxShadowT: Float = 8
    var tmax: Float = 60

    func pixel(_ x: Float, _ y: Float) -> V4 {
        let (ro, rd) = cam.ray(x, y)
        let r = march(model, ro, rd, 0.01, tmax, 0.00015, 0.00022, 420, 0.95)
        var c = quietTop
        if r.t > 0 {
            let e = 0.0004 + 0.0002 * r.t
            c = shadeHit(model, model, ro, rd, r.t, r.m, fhash(x * 8, y * 8, 5), e, shadowK, maxShadowT)
        }
        let v = y / cam.H
        let u = x / cam.W
        // soft vignette (mostly upper corners)
        let dx = (u - 0.5) * 1.6, dy = (v - 0.35) * 1.1
        let vig = 1 - vignette * sstep(0.35, 1.25, sqrt(dx * dx + dy * dy))
        c *= vig
        // quiet bottom area for UI text
        let q = sstep(quietStart, quietEnd, v) * quietAmount
        let quiet = mix3(quietTop, quietBottom, sstep(quietStart, 1, v))
        c = mix3(c, quiet, q)
        let t = tonemap3(c)
        return V4(t.x, t.y, t.z, 1)
    }
}

func bgStudio(_ cam: PerspCam, left: Float = 0.75, up: Float = 1.1, front: Float = 0.35) -> Studio {
    var st = Studio()
    st.L = cam.light(left: left, up: up, front: front)
    let back = normalize(V3(cam.fwd.x, 0, cam.fwd.z))
    let rh = normalize(V3(cam.right.x, 0, cam.right.z))
    st.rimDir = normalize(rh * 0.75 + V3(0, 0.55, 0) + back * 0.45)
    st.rimI = 0.2
    return st
}


// MARK: - Tools
//
// Every tool lies flat: its profile is in the local xz plane, thickness along local y, mid-plane
// at y = 0. `xf` places it in the parent frame (a case, a roll, the world), `s` scales it.

protocol Tool {
    var xf: Xf { get }
    var s: Float { get }
    /// half thickness (local units)
    var halfT: Float { get }
    var show: Bool { get }
    func dist(_ q: V3) -> Hit
}
extension Tool {
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = dist(xf.loc(p) / s)
        h.d *= s
        return h
    }
    /// Distance to the tool's outline in its own mid-plane (parent units), for fitted cut-outs.
    @inline(__always) func outline(_ p: V3) -> Float {
        var q = xf.loc(p) / s
        q.y = 0
        return dist(q).d * s
    }
    var bottomY: Float { xf.t.y - halfT * s - 0.006 }
    var topY: Float { xf.t.y + halfT * s + 0.006 }
}

/// Parts return their bounding-box distance only beyond this range. It must exceed the AO and
/// penumbra sampling scale, otherwise the (under-estimated) box distance darkens nearby ground.
let boundSkip: Float = 0.3

/// Screwdriver: fluted cream handle with an amber ring, copper ferrule, brass shaft and flat tip.
/// Axis along +x (tip); the handle runs from x = -hl to 0.
struct Screwdriver: Tool {
    var xf: Xf
    var s: Float = 1
    var hl: Float = 0.44
    var hr: Float = 0.085
    var sl: Float = 0.52
    var sr: Float = 0.021
    var ring = true
    var show = true
    var halfT: Float { hr }

    @inline(__always) func dist(_ q: V3) -> Hit {
        let bd = sdBox(q - V3((sl - hl) * 0.5, 0, 0), V3((sl + hl) * 0.5 + 0.02, hr + 0.02, hr + 0.02))
        if bd > boundSkip { return Hit(d: bd, m: Mat.cream) }
        let a = V3(-hl + hr, 0, 0), m = V3(-0.14, 0, 0), b = V3(-0.035, 0, 0)
        var hd = sdCone(q, a, m, hr * 0.94, hr)
        hd = smin(hd, sdCone(q, m, b, hr, hr * 0.6), 0.04)
        let phi = atan2(q.z, q.y)
        let along = sstep(-hl + 0.1, -hl + 0.16, q.x) * (1 - sstep(-0.2, -0.13, q.x))
        let g = sstep(0.5, 0.95, cos(phi * 6)) * along
        hd = (hd + 0.012 * g) * 0.85
        var h = Hit(d: hd, m: Mat.cream)
        if ring { h = U(h, sdCylX(q - V3(-hl + 0.075, 0, 0), hr * 0.95 + 0.004, 0.02, 0.008), Mat.amber) }
        h = U(h, sdCone(q, V3(-0.06, 0, 0), V3(0.05, 0, 0), 0.05, 0.034), Mat.copper)
        var sh = sdCapsule(q, V3(0.03, 0, 0), V3(sl - 0.08, 0, 0), sr)
        let bq = q - V3(sl - 0.045, 0, 0)
        let tp = sat((bq.x + 0.045) / 0.09)
        let blade = sdRoundBox(bq, V3(0.045, sr * mixf(0.85, 0.3, tp), sr * 1.2), 0.004) * 0.9
        sh = smin(sh, blade, 0.02)
        h = U(h, sh, Mat.brass)
        return h
    }
}

/// Claw hammer: polished copper head (round striking face toward +z, curved claw toward -z)
/// on a cream enamel handle along -x with a copper collar and a gold butt cap.
struct Hammer: Tool {
    var xf: Xf
    var s: Float = 1
    var show = true
    var halfT: Float { 0.075 }
    // (no arrays in parts: a stored array makes every copy of a scene do atomic ARC traffic)

    @inline(__always) func dist(_ q: V3) -> Hit {
        let bd = sdBox(q - V3(-0.46, 0, -0.04), V3(0.64, 0.1, 0.4))
        if bd > boundSkip { return Hit(d: bd, m: Mat.copper) }
        var hd = sdRoundBox(q, V3(0.098, 0.07, 0.115), 0.062)
        hd = smin(hd, sdCone(q, V3(0, 0, 0.05), V3(0, 0, 0.21), 0.08, 0.07), 0.06)
        let face = opExtrude(len2(q.x, q.y) - 0.09, q.z - 0.25, 0.04, 0.022)
        hd = smin(hd, face, 0.045)
        // claw: tapered, curving back toward the handle
        let c0 = V3(0.0, 0, -0.05), c1 = V3(-0.005, 0, -0.17), c2 = V3(-0.045, 0, -0.27)
        let c3 = V3(-0.115, 0, -0.34), c4 = V3(-0.2, 0, -0.37)
        var claw = sdCone(q, c0, c1, 0.072, 0.059)
        claw = smin(claw, sdCone(q, c1, c2, 0.059, 0.046), 0.03)
        claw = smin(claw, sdCone(q, c2, c3, 0.046, 0.033), 0.025)
        claw = smin(claw, sdCone(q, c3, c4, 0.033, 0.02), 0.02)
        hd = smin(hd, claw, 0.06)
        var h = Hit(d: hd, m: Mat.copper)
        let hq = V3(q.x, q.y * 1.25, q.z)
        var hn = sdCone(hq, V3(-0.06, 0, 0), V3(-0.72, 0, 0), 0.052, 0.057)
        hn = smin(hn, sdCone(hq, V3(-0.72, 0, 0), V3(-0.97, 0, 0), 0.057, 0.068), 0.06)
        hn *= 0.8
        h = U(h, hn, Mat.cream)
        let collar = smax(hn - 0.009, abs(q.x + 0.17) - 0.035, 0.01)
        h = U(h, collar, Mat.copper)
        let cap = smax(hn - 0.007, q.x + 0.985, 0.01)
        h = U(h, cap, Mat.gold)
        return h
    }
}

/// Open-end / ring spanner: flat forged profile, open jaw at +x (15° offset), hex ring at -x.
struct Wrench: Tool {
    var xf: Xf
    var s: Float = 1
    var L: Float = 0.46
    var t: Float = 0.028
    var metal: Int32 = Mat.copper
    var show = true
    var halfT: Float { t }

    @inline(__always) func prof(_ x: Float, _ z: Float) -> Float {
        var d = sdSeg2(x, z, -L + 0.08, 0, L - 0.08, 0) - 0.047
        d = smin(d, len2(x - L, z) - 0.13, 0.09)
        d = smin(d, len2(x + L, z) - 0.108, 0.09)
        let c: Float = 0.9659, sn: Float = 0.2588
        let hx = x - L
        let jx = c * hx + sn * z, jz = -sn * hx + c * z
        let slot = min(max(abs(jz) - 0.046, -jx), len2(jx, jz) - 0.046)
        d = max(d, -slot)
        d = max(d, -sdHex2(x + L, z, 0.052))
        return d
    }
    @inline(__always) func dist(_ q: V3) -> Hit {
        let bd = sdBox(q, V3(L + 0.15, t + 0.02, 0.15))
        if bd > boundSkip { return Hit(d: bd, m: metal) }
        return Hit(d: opExtrude(prof(q.x, q.z), q.y, t, 0.013), m: metal)
    }
}

/// Try-square: thick copper stock along +z with gold rivets, polished gold blade along +x.
struct TrySquare: Tool {
    var xf: Xf
    var s: Float = 1
    var show = true
    var halfT: Float { 0.045 }

    @inline(__always) func dist(_ q: V3) -> Hit {
        let bd = sdBox(q - V3(0.44, 0, 0.24), V3(0.56, 0.07, 0.36))
        if bd > boundSkip { return Hit(d: bd, m: Mat.copper) }
        var h = Hit(d: sdRoundBox(q - V3(0, 0, 0.25), V3(0.068, 0.045, 0.32), 0.028), m: Mat.copper)
        h = U(h, sdRoundBox(q - V3(0.46, 0, 0), V3(0.5, 0.011, 0.058), 0.008), Mat.gold)
        let rq = V3(q.x, abs(q.y), q.z)
        var rv = sdSphere(rq - V3(0, 0.03, 0.14), 0.026)
        rv = min(rv, sdSphere(rq - V3(0, 0.03, 0.3), 0.026))
        rv = min(rv, sdSphere(rq - V3(0, 0.03, 0.46), 0.026))
        h = U(h, rv, Mat.gold)
        return h
    }
}

/// C-clamp: copper C-frame (spine at -x), brass threaded screw along +z with a swivel pad,
/// gold T-bar with ball ends.
struct CClamp: Tool {
    var xf: Xf
    var s: Float = 1
    var show = true
    var halfT: Float { 0.05 }

    @inline(__always) func frame2(_ x: Float, _ z: Float) -> Float {
        var f = sdSeg2(x, z, -0.24, -0.19, -0.24, 0.19) - 0.06
        f = smin(f, sdSeg2(x, z, -0.24, 0.19, 0.12, 0.19) - 0.05, 0.04)
        f = smin(f, sdSeg2(x, z, -0.24, -0.19, 0.12, -0.19) - 0.05, 0.04)
        f = smin(f, len2(x - 0.13, z - 0.2) - 0.066, 0.04)
        f = smin(f, len2(x - 0.13, z + 0.2) - 0.074, 0.04)
        return f
    }
    @inline(__always) func dist(_ q: V3) -> Hit {
        let bd = sdBox(q - V3(-0.02, 0, -0.1), V3(0.34, 0.08, 0.42))
        if bd > boundSkip { return Hit(d: bd, m: Mat.copper) }
        var h = Hit(d: opExtrude(frame2(q.x, q.z), q.y, 0.042, 0.016), m: Mat.copper)
        let sq = q - V3(0.13, 0, 0)
        let thread = 0.0035 * sin(sq.z * 120)
        let screw = (sdCapsule(sq, V3(0, 0, -0.43), V3(0, 0, 0.06), 0.023) + thread) * 0.85
        let pad = opExtrude(len2(sq.x, sq.y) - 0.052, sq.z - 0.085, 0.022, 0.01)
        h = U(h, min(screw, pad), Mat.brass)
        var tb = sdCapsule(sq, V3(-0.14, 0, -0.45), V3(0.14, 0, -0.45), 0.02)
        tb = min(tb, sdSphere(V3(abs(sq.x) - 0.15, sq.y, sq.z + 0.45), 0.034))
        h = U(h, tb, Mat.gold)
        return h
    }
}

/// Sliding caliper (no graduations): gold beam and jaws, copper slider, brass thumb wheel.
struct Caliper: Tool {
    var xf: Xf
    var s: Float = 1
    var show = true
    var halfT: Float { 0.03 }

    /// Jaw pair profile: body on u < 0, long jaw toward -z, short jaw toward +z.
    @inline(__always) func jaw(_ u: Float, _ z: Float) -> Float {
        let k: Float = 0.3, nk: Float = 1.044
        let main = max(max(u, (-u - 0.115 - k * z) / nk), max(-z - 0.33, z - 0.02))
        let k2: Float = 0.35, nk2: Float = 1.06
        let small = max(max(u, (-u - 0.07 + k2 * z) / nk2), max(z - 0.14, -z - 0.02))
        return min(main, small)
    }
    @inline(__always) func dist(_ q: V3) -> Hit {
        let bd = sdBox(q - V3(0.02, 0, -0.08), V3(0.6, 0.06, 0.28))
        if bd > boundSkip { return Hit(d: bd, m: Mat.gold) }
        var h = Hit(d: sdRoundBox(q - V3(0.04, 0, 0), V3(0.54, 0.012, 0.044), 0.008), m: Mat.gold)
        let fj = opExtrude(jaw(q.x + 0.44, q.z), q.y, 0.012, 0.005)
        let sj = opExtrude(jaw(-0.415 - q.x, q.z), q.y, 0.012, 0.005)
        h = U(h, min(fj, sj), Mat.gold)
        h = U(h, sdRoundBox(q - V3(-0.27, 0, 0), V3(0.15, 0.026, 0.072), 0.022), Mat.copper)
        let wq = q - V3(-0.2, 0, -0.105)
        let knurl = 0.003 * sin(atan2(wq.z, wq.x) * 28)
        h = U(h, opExtrude(len2(wq.x, wq.z) - 0.042 + knurl, wq.y, 0.014, 0.006), Mat.brass)
        h = U(h, opExtrude(len2(q.x + 0.3, q.z - 0.1) - 0.022, q.y, 0.03, 0.01), Mat.gold)
        return h
    }
}

/// Compact cordless drill lying on its side: deep-blue lacquer housing with an amber belt stripe,
/// copper chuck, brass bit, cream grip leaning back, deep-blue battery with a copper band, amber
/// trigger. Forward = +x, the grip points toward +z.
struct Drill: Tool {
    var xf: Xf
    var s: Float = 1
    var show = true
    var halfT: Float { 0.12 }

    @inline(__always) func dist(_ q: V3) -> Hit {
        let bd = sdBox(q - V3(0.09, 0, 0.03), V3(0.64, 0.15, 0.46))
        if bd > boundSkip { return Hit(d: bd, m: Mat.lacquer) }
        var body = sdRoundBox(q - V3(-0.1, 0, -0.22), V3(0.31, 0.112, 0.135), 0.11)
        body = smin(body, sdCylX(q - V3(0.235, 0, -0.22), 0.098, 0.05, 0.03), 0.05)
        let gx = q.x + 0.12, gz = q.z - 0.1
        let dx: Float = -0.196, dz: Float = 0.9806
        let gq = V3(gx * dz - gz * dx, q.y, gx * dx + gz * dz)
        let grip = sdRoundBox(gq, V3(0.074, 0.084, 0.2), 0.07)
        let batt = sdRoundBox(q - V3(-0.16, 0, 0.36), V3(0.21, 0.118, 0.075), 0.045)
        var h = Hit(d: smin(body, grip, 0.05), m: grip < body ? Mat.cream : Mat.lacquer)
        h = U(h, smin(batt, grip, 0.03), batt < grip ? Mat.lacquer : Mat.cream)
        let stripe = smax(smax(body - 0.006, abs(q.z + 0.22) - 0.03, 0.006), abs(q.x + 0.1) - 0.25, 0.01)
        h = U(h, stripe, Mat.amber)
        let band = smax(batt - 0.008, abs(q.z - 0.305) - 0.016, 0.006)
        h = U(h, band, Mat.copper)
        let cq = q - V3(0, 0, -0.22)
        let groove = 0.006 * sstep(0.2, 0.9, cos(atan2(cq.z, cq.y) * 8)) * sstep(0.3, 0.33, cq.x)
        let chuck = (sdCone(cq, V3(0.28, 0, 0), V3(0.45, 0, 0), 0.078, 0.052) + groove) * 0.9
        h = U(h, chuck, Mat.copper)
        h = U(h, sdCapsule(cq, V3(0.44, 0, 0), V3(0.7, 0, 0), 0.018), Mat.brass)
        h = U(h, sdRoundBox(q - V3(0.0, 0, -0.045), V3(0.034, 0.04, 0.045), 0.026), Mat.amber)
        return h
    }
}

// MARK: - Brand mark

/// The Copper Kit mark: abstract geometry of a tool handle — a rounded grip bar, fuller in the
/// middle, with three raised ridges at its centre, a ring ferrule toward each end, short necks and
/// domed end caps — as a low relief rising from a face. Face plane n = 0 (normal +n), bar along
/// `a`; symmetric in `a` and `b`. Unit length ~1.04, width ~0.2.
@inline(__always) func handleMark(_ a: Float, _ b: Float, _ n: Float) -> Float {
    let k: Float = 1.7   // relief flattening
    let q = V3(abs(a), b, n * k)
    var d = sdCone(q, V3(0, 0, 0), V3(0.27, 0, 0), 0.088, 0.074)
    d = min(d, sdTorusX(q, 0.086, 0.021))
    d = min(d, sdTorusX(q - V3(0.09, 0, 0), 0.085, 0.021))
    d = min(d, sdCylX(q - V3(0.325, 0, 0), 0.1, 0.035, 0.018))
    d = smin(d, sdCone(q, V3(0.36, 0, 0), V3(0.45, 0, 0), 0.07, 0.056), 0.02)
    d = smin(d, sdSphere(q - V3(0.46, 0, 0), 0.062), 0.02)
    return d / k
}

// MARK: - The case

/// The Copper Kit case: deep-blue lacquered shell split into a base and a lid hinged along the back
/// edge (-z), copper rim bands at the seam, two copper latches (a plate + lever on the base and a
/// wrap-around cap on the lid), a brass carry handle with a gold three-ridge grip on the front (+z)
/// and the embossed handle-mark on the lid. Open, it shows a velvet foam insert with fitted
/// cut-outs (base) and a velvet lining with shallow cut-outs (lid).
/// Local frame: base on y = 0. Base tools use case-local coordinates; lid tools use closed-lid
/// coordinates (they swing up with the lid).
struct CasePart {
    var xf: Xf
    var s: Float = 1
    var hx: Float = 1.25, hz: Float = 0.8, hb: Float = 0.36, hl: Float = 0.22
    var rc: Float = 0.11, wt: Float = 0.05
    let lidAng: Float
    let lidRot: M3
    let handleAng: Float
    let hCos: Float, hSin: Float
    var handleW: Float = 0.3, handleReach: Float = 0.2, handleCR: Float = 0.07
    var latchX: Float = 0.8
    var markScale: Float = 1
    let floorY: Float = 0.07
    // contents
    var drill: Drill? = nil
    var driver: Screwdriver? = nil
    var clamp: CClamp? = nil
    var wrench: Wrench? = nil
    var square: TrySquare? = nil      // lid
    var caliper: Caliper? = nil       // lid
    var hammer: Hammer? = nil         // lid

    init(xf: Xf, s: Float = 1, lidAng: Float = 0, handleAng: Float = 0) {
        self.xf = xf
        self.s = s
        self.lidAng = lidAng
        lidRot = rotX(lidAng)
        self.handleAng = handleAng
        hCos = cos(handleAng)
        hSin = sin(handleAng)
    }

    var open: Bool { lidAng > 0.01 }
    var foamTop: Float { hb - 0.04 }
    var liningY: Float { hb + 0.075 }
    var hinge: V3 { V3(0, hb, -hz) }
    /// Mid-plane height for a tool (half thickness `ht`, parent units) seated in the base foam.
    func baseSeat(_ ht: Float) -> Float { foamTop - 0.4 * ht }
    /// Mid-plane height (closed-lid coordinates) for a tool seated in the lid lining.
    func lidSeat(_ ht: Float) -> Float { liningY + 0.4 * ht }
    /// Case-local point -> closed-lid coordinates.
    @inline(__always) func lidLocal(_ q: V3) -> V3 { hinge + lidRot * (q - hinge) }
    /// Case-local point of the handle grip centre (offset `u` along the grip).
    func gripPoint(_ u: Float = 0) -> V3 {
        V3(u, hb - 0.1 - hCos * handleReach, hz + 0.035 + hSin * handleReach)
    }

    @inline(__always) func shellD(_ q: V3) -> Float {
        sdRoundBox(q - V3(0, (hb + hl) * 0.5, 0), V3(hx, (hb + hl) * 0.5, hz), rc)
    }
    @inline(__always) func cavity(_ q: V3, _ y0: Float, _ y1: Float) -> Float {
        sdRoundBox(q - V3(0, (y0 + y1) * 0.5, 0), V3(hx - wt, (y1 - y0) * 0.5, hz - wt), max(rc - wt, 0.02))
    }
    /// Carry handle: (brass loop, gold grip with three ridges).
    @inline(__always) func handleD(_ q: V3) -> (Float, Float) {
        let d = q - V3(0, hb - 0.1, hz + 0.035)
        let W = handleW, R = handleReach, cr = handleCR
        let u = d.x
        let v = -d.y * hCos + d.z * hSin
        let w = d.y * hSin + d.z * hCos
        let bd = sdBox(V3(u, v - R * 0.5, w), V3(W + 0.07, R * 0.5 + 0.07, 0.07))
        if bd > boundSkip { return (bd, bd) }
        var d2: Float
        if v > R * 0.5 {
            d2 = abs(sdRoundRect(u, v - R * 0.5, W, R * 0.5, cr))
        } else {
            d2 = sdSeg2(abs(u), v, W, 0, W, R * 0.5)
        }
        let loop = len2(d2, w) - 0.021
        let gq = V3(u, v - R, w)
        let gl = max(W - cr - 0.03, 0.13)
        var grip = sdCapsule(gq, V3(-gl, 0, 0), V3(gl, 0, 0), 0.046)
        grip = min(grip, sdTorusX(gq, 0.046, 0.012))
        grip = min(grip, sdTorusX(V3(abs(u) - 0.075, v - R, w), 0.046, 0.012))
        return (loop, grip)
    }
    @inline(__always) func pocket<T: Tool>(_ t: T, _ q: V3) -> Float { max(t.outline(q) - 0.022, t.bottomY - q.y) }
    @inline(__always) func lidPocket<T: Tool>(_ t: T, _ q: V3) -> Float { max(t.outline(q) - 0.022, q.y - t.topY) }

    @inline(__always) func baseMap(_ q: V3) -> Hit {
        let sh = shellD(q)
        var body = max(sh, q.y - hb)
        var rim = smax(sh - 0.012, abs(q.y - (hb - 0.034)) - 0.034, 0.008)
        if open {
            let cav = cavity(q, floorY, hb + 1)
            body = max(body, -cav)
            rim = max(rim, -cav)
        } else {
            rim = max(rim, q.y - hb)
        }
        var h = Hit(d: body, m: Mat.lacquer)
        let lx = V3(abs(q.x) - latchX, q.y, q.z)
        var cu = sdRoundBox(lx - V3(0, hb - 0.1, hz + 0.006), V3(0.088, 0.075, 0.02), 0.018)
        cu = min(cu, sdRoundBox(lx - V3(0, hb - 0.04, hz + 0.03), V3(0.062, 0.062, 0.013), 0.012))
        cu = min(cu, sdRoundBox(V3(abs(q.x) - handleW, q.y - (hb - 0.1), q.z - hz), V3(0.05, 0.06, 0.035), 0.022))
        h = U(h, min(rim, cu), Mat.copper)
        if open {
            var foam = sdRoundBox(q - V3(0, (floorY + foamTop) * 0.5, 0),
                                  V3(hx - wt - 0.002, (foamTop - floorY) * 0.5, hz - wt - 0.002), max(rc - wt, 0.02))
            if foam < 0.3 {
                var pk: Float = 1e9
                if let t = drill { pk = min(pk, pocket(t, q)) }
                if let t = driver { pk = min(pk, pocket(t, q)) }
                if let t = clamp { pk = min(pk, pocket(t, q)) }
                if let t = wrench { pk = min(pk, pocket(t, q)) }
                foam = smax(foam, -pk, 0.022)
            }
            h = U(h, foam, Mat.foam)
            if let t = drill, t.show { h = U(h, t.map(q)) }
            if let t = driver, t.show { h = U(h, t.map(q)) }
            if let t = clamp, t.show { h = U(h, t.map(q)) }
            if let t = wrench, t.show { h = U(h, t.map(q)) }
        }
        return h
    }

    @inline(__always) func lidMap(_ lq: V3) -> Hit {
        let sh = shellD(lq)
        var body = max(sh, hb - lq.y)
        var rim = smax(sh - 0.012, abs(lq.y - (hb + 0.034)) - 0.034, 0.008)
        let lx = V3(abs(lq.x) - latchX, lq.y, lq.z)
        var cap = max(sh - 0.016, sdRoundBox(lx - V3(0, hb + hl * 0.5, hz), V3(0.075, hl * 0.5 + 0.03, 0.13), 0.025))
        cap = max(cap, hb + 0.004 - lq.y)
        if open {
            let cav = cavity(lq, hb - 1, hb + hl - wt)
            body = max(body, -cav)
            rim = max(rim, -cav)
            cap = max(cap, -cav)
        } else {
            rim = max(rim, hb - lq.y)
        }
        var h = Hit(d: body, m: Mat.lacquer)
        h = U(h, min(rim, cap), Mat.copper)
        if open {
            let top = hb + hl - wt
            var lining = sdRoundBox(lq - V3(0, (liningY + top) * 0.5, 0),
                                    V3(hx - wt - 0.002, (top - liningY) * 0.5 + 0.004, hz - wt - 0.002), max(rc - wt, 0.02))
            if lining < 0.3 {
                var pk: Float = 1e9
                if let t = square { pk = min(pk, lidPocket(t, lq)) }
                if let t = caliper { pk = min(pk, lidPocket(t, lq)) }
                if let t = hammer { pk = min(pk, lidPocket(t, lq)) }
                lining = smax(lining, -pk, 0.02)
            }
            h = U(h, lining, Mat.foam)
            if let t = square, t.show { h = U(h, t.map(lq)) }
            if let t = caliper, t.show { h = U(h, t.map(lq)) }
            if let t = hammer, t.show { h = U(h, t.map(lq)) }
        } else if markScale > 0 {
            let n = lq.y - (hb + hl)
            if n < 0.1 {
                h = U(h, handleMark(lq.x / markScale, lq.z / markScale, n / markScale) * markScale, Mat.gold)
            }
        }
        return h
    }

    @inline(__always) func mapLocal(_ q: V3) -> Hit {
        var h = Hit(d: 1e9, m: Mat.lacquer)
        let bb = sdBox(q - V3(0, (hb + 0.14) * 0.5, 0), V3(hx + 0.03, (hb + 0.14) * 0.5 + 0.01, hz + 0.07))
        if bb > boundSkip { h.d = bb } else { h = baseMap(q) }
        let (loop, grip) = handleD(q)
        h = U(h, loop, Mat.brass)
        h = U(h, grip, Mat.gold)
        let lq = lidLocal(q)
        let lb = sdBox(lq - V3(0, hb + hl * 0.5, 0), V3(hx + 0.03, hl * 0.5 + 0.1, hz + 0.03))
        if lb > boundSkip { h = U(h, lb, Mat.lacquer) } else { h = U(h, lidMap(lq)) }
        return h
    }
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = mapLocal(xf.loc(p) / s)
        h.d *= s
        return h
    }
    /// Local (unscaled) case point -> world.
    func world(_ q: V3) -> V3 { xf.world(q * s) }
}

/// Fill a case with the standard kit: drill, screwdriver, C-clamp and spanner in the base foam;
/// try-square, caliper and (optionally) a hammer in the lid lining.
func standardKit(_ c0: CasePart, hammer: Bool = true) -> CasePart {
    var c = c0
    let ds: Float = 1.0
    c.drill = Drill(xf: Xf(V3(-0.52, c.baseSeat(0.12 * ds), -0.12)), s: ds)
    let ss: Float = 1.05
    c.driver = Screwdriver(xf: Xf(V3(-0.62, c.baseSeat(0.085 * ss), 0.575)), s: ss)
    let cs: Float = 1.1
    c.clamp = CClamp(xf: Xf(V3(0.74, c.baseSeat(0.05 * cs), 0.3)), s: cs)
    let ws: Float = 0.95
    c.wrench = Wrench(xf: Xf(V3(0.6, c.baseSeat(0.028 * ws), -0.54), rotY(rad(-2))), s: ws)
    let ts: Float = 1.15
    c.square = TrySquare(xf: Xf(V3(-1.02, c.lidSeat(0.045 * ts), -0.52)), s: ts)
    let ks: Float = 1.2
    c.caliper = Caliper(xf: Xf(V3(0.42, c.lidSeat(0.03 * ks), 0.48)), s: ks)
    if hammer {
        let hs: Float = 0.85
        c.hammer = Hammer(xf: Xf(V3(1.03, c.lidSeat(0.075 * hs), -0.36)), s: hs)
    }
    return c
}

// MARK: - Small props

/// Luggage-style tag: rounded plate with chamfered top corners, optional brass rim, copper
/// eyelet around the hole. Local frame: face in the xy plane (normal +z), hole toward +y.
struct Tag {
    var xf: Xf
    var s: Float = 1
    var hw: Float = 0.3, hh: Float = 0.44, th: Float = 0.016
    var face: Int32 = Mat.tagFace
    var rim = true
    var holeY: Float { hh - 0.15 }

    @inline(__always) func prof(_ x: Float, _ y: Float) -> Float {
        let d = sdRoundRect(x, y, hw, hh, 0.05)
        let ch = (abs(x) + y - (hw + hh - 0.13)) * 0.7071
        return smax(d, ch, 0.03)
    }
    @inline(__always) func dist(_ q: V3) -> Hit {
        let bd = sdBox(q, V3(hw + 0.03, hh + 0.03, 0.06))
        if bd > boundSkip { return Hit(d: bd, m: face) }
        let p2 = prof(q.x, q.y)
        let hole = len2(q.x, q.y - holeY) - 0.045
        var h = Hit(d: opExtrude(max(p2, -hole), q.z, th, th * 0.8), m: face)
        if rim {
            let band = abs(p2 + 0.03) - 0.03
            h = U(h, opExtrude(band, q.z, th + 0.006, 0.008), Mat.brass)
        }
        h = U(h, sdTorusZ(q - V3(0, holeY, 0), 0.066, 0.024), Mat.copper)
        return h
    }
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = dist(xf.loc(p) / s)
        h.d *= s
        return h
    }
    /// World position of the eyelet centre.
    var eyelet: V3 { xf.world(V3(0, holeY, 0) * s) }
    /// A tag lying flat on a surface at height `base`, its top pointing along -z rotated by `yaw`.
    static func flat(x: Float, z: Float, base: Float, yaw: Float, s: Float) -> Tag {
        Tag(xf: Xf(V3(x, base + 0.016 * s, z), rotY(rad(yaw)) * rotX(rad(-90))), s: s)
    }
}

/// Cord: a round tube along a Catmull-Rom curve, with a bounding box for speed. The samples live in
/// a raw buffer that is never freed (it lasts for the run), so copying a scene costs no ARC traffic.
struct Cord {
    let pts: UnsafeMutablePointer<V3>
    let n: Int
    let r: Float
    let bc: V3, bh: V3
    init(_ ctrl: [V3], r: Float, k: Int = 5) {
        let smp = catmullRom(ctrl, k)
        n = smp.count
        pts = UnsafeMutablePointer<V3>.allocate(capacity: n)
        pts.initialize(from: smp, count: n)
        self.r = r
        var lo = V3(repeating: 1e9), hi = V3(repeating: -1e9)
        for p in smp { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        bc = (lo + hi) * 0.5
        bh = (hi - lo) * 0.5 + V3(repeating: r + 0.01)
    }
    @inline(__always) func d(_ p: V3) -> Float {
        let bd = sdBox(p - bc, bh)
        if bd > boundSkip { return bd }
        var d = Float.greatestFiniteMagnitude
        for i in 0..<(n - 1) { d = min(d, sdCapsule(p, pts[i], pts[i + 1], r)) }
        return d
    }
}

/// Chunky stylised work glove. Local frame: fingers toward +x, back of the hand +y, thumb +z
/// (`mirror` flips the thumb side), flared amber gauntlet cuff toward -x with a copper snap.
struct Glove {
    var xf: Xf
    var s: Float = 1
    var mirror = false
    var spread: Float = 1
    var mitten: Float = 0.035
    let f1: V3, f2: V3, f3: V3
    let t0: V3, t1: V3, t2: V3
    init(xf: Xf, s: Float = 1, mirror: Bool = false, curl: Float = 0.08, thumbFist: Float = 0,
         mitten: Float = 0.035, spread: Float = 1) {
        self.xf = xf; self.s = s; self.mirror = mirror; self.mitten = mitten; self.spread = spread
        f1 = V3(cos(curl), -sin(curl), 0)
        f2 = V3(cos(2 * curl), -sin(2 * curl), 0)
        f3 = V3(cos(3 * curl), -sin(3 * curl), 0)
        t0 = V3(0.03, -0.01, 0.14)
        t1 = mix3(V3(0.16, -0.025, 0.28), V3(0.18, -0.07, 0.23), thumbFist)
        t2 = mix3(V3(0.27, -0.04, 0.33), V3(0.28, -0.14, 0.15), thumbFist)
    }
    @inline(__always) func finger(_ q: V3, _ z: Float, _ len: Float) -> Float {
        let a = V3(0.16, 0.005, z)
        let b = a + f1 * (len * 0.42)
        let c = b + f2 * (len * 0.33)
        let d = c + f3 * (len * 0.25)
        var f = sdCapsule(q, a, b, 0.062)
        f = min(f, sdCapsule(q, b, c, 0.06))
        return min(f, sdCapsule(q, c, d, 0.057))
    }
    @inline(__always) func dist(_ q0: V3) -> Hit {
        var q = q0
        if mirror { q.z = -q.z }
        let bd = sdBox(q - V3(0.0, -0.05, 0.04), V3(0.62, 0.3, 0.45))
        if bd > boundSkip { return Hit(d: bd, m: Mat.glove) }
        var hand = sdRoundBox(q - V3(0, 0, -0.005), V3(0.19, 0.072, 0.18), 0.07)
        let sp = 0.094 * spread
        var fg = finger(q, 1.5 * sp, 0.25)
        fg = smin(fg, finger(q, 0.5 * sp, 0.28), mitten)
        fg = smin(fg, finger(q, -0.5 * sp, 0.26), mitten)
        fg = smin(fg, finger(q, -1.5 * sp, 0.21), mitten)
        hand = smin(hand, fg, 0.04)
        let thumb = min(sdCapsule(q, t0, t1, 0.066), sdCapsule(q, t1, t2, 0.06))
        hand = smin(hand, thumb, 0.05)
        var h = Hit(d: hand, m: Mat.glove)
        let cq = V3(q.x, (q.y - 0.01) * 1.5, q.z)
        var cuff = sdCone(cq, V3(-0.13, 0, 0), V3(-0.37, 0, 0), 0.165, 0.2)
        cuff = max(cuff, -sdCone(cq, V3(-0.31, 0, 0), V3(-0.5, 0, 0), 0.15, 0.18))
        h = U(h, cuff / 1.5, Mat.cuff)
        h = U(h, sdTorusX(cq - V3(-0.37, 0, 0), 0.19, 0.026) / 1.5, Mat.glove)
        let snap = opExtrude(len2(q.x + 0.24, q.z) - 0.034, q.y - 0.132, 0.012, 0.008)
        h = U(h, snap, Mat.copper)
        return h
    }
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = dist(xf.loc(p) / s)
        h.d *= s
        return h
    }
}

/// Clipboard lying flat: deep-blue lacquer board, cream sheet (blank lines are texture),
/// brass clip plate with a gold wire lever. Top edge toward -z.
struct Clipboard {
    var xf: Xf
    var s: Float = 1
    let hx: Float = 0.6, hz: Float = 0.8
    @inline(__always) func dist(_ q: V3) -> Hit {
        let bd = sdBox(q - V3(0, 0.08, 0), V3(hx + 0.03, 0.12, hz + 0.03))
        if bd > boundSkip { return Hit(d: bd, m: Mat.lacquer) }
        var h = Hit(d: sdRoundBox(q - V3(0, 0.025, 0), V3(hx, 0.025, hz), 0.022), m: Mat.lacquer)
        h = U(h, sdRoundBox(q - V3(0, 0.054, 0.05), V3(hx - 0.07, 0.006, hz - 0.12), 0.004), Mat.sheet)
        h = U(h, sdRoundBox(q - V3(0, 0.07, -hz + 0.13), V3(0.25, 0.018, 0.1), 0.018), Mat.brass)
        let loop = abs(sdRoundRect(q.x, q.z + hz - 0.1, 0.17, 0.075, 0.06))
        h = U(h, len2(loop, q.y - 0.105) - 0.015, Mat.gold)
        h = U(h, sdSphere(V3(abs(q.x) - 0.19, q.y - 0.088, q.z + hz - 0.13), 0.022), Mat.gold)
        return h
    }
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = dist(xf.loc(p) / s)
        h.d *= s
        return h
    }
    /// Sheet look: cream paper with three blank rounded "writing" lines (no text).
    func sheetSurf(_ p: V3, _ n: V3) -> Surf {
        let q = xf.loc(p) / s
        var line: Float = 1e9
        line = min(line, sdRoundRect(q.x + 0.06, q.z + 0.3, 0.36, 0.024, 0.024))
        line = min(line, sdRoundRect(q.x + 0.12, q.z + 0.08, 0.3, 0.024, 0.024))
        line = min(line, sdRoundRect(q.x + 0.09, q.z - 0.14, 0.33, 0.024, 0.024))
        let ink = 1 - sstep(-0.003, 0.003, line)
        let alb = mix3(Pal.paper, mix3(Pal.muted, Pal.velvet, 0.35), 0.75 * ink)
        return fabricSurf(alb, n, q, sheen: 0.1)
    }
}

/// Unrolled canvas tool roll: base sheet with a velvet-blue binding, a front pocket panel that
/// drapes over the tools tucked into it (handles and heads stick out above its hem), a loose curl
/// at the right end and two leather straps with copper buckles. Pockets open toward -z.
struct ToolRoll {
    var xf: Xf
    var hx: Float = 1.1, hz: Float = 0.62, t: Float = 0.012
    var hem: Float = -0.06
    var dividers: (Float, Float, Float) = (-0.46, -0.02, 0.44)
    var d1: Screwdriver? = nil
    var d2: Screwdriver? = nil
    var wrench: Wrench? = nil
    var hammer: Hammer? = nil
    var top: Float { 2 * t }

    @inline(__always) func tools(_ q: V3) -> Hit {
        var h = Hit(d: 1e9, m: Mat.cream)
        if let x = d1, x.show { h = U(h, x.map(q)) }
        if let x = d2, x.show { h = U(h, x.map(q)) }
        if let x = wrench, x.show { h = U(h, x.map(q)) }
        if let x = hammer, x.show { h = U(h, x.map(q)) }
        return h
    }
    @inline(__always) func map(_ p: V3) -> Hit {
        let q = xf.loc(p)
        let bd = sdBox(q - V3(0.25, 0.1, -0.2), V3(hx + 0.65, 0.2, hz + 0.6))
        if bd > boundSkip { return Hit(d: bd, m: Mat.canvas) }
        var h = Hit(d: sdRoundBox(q - V3(0, t, 0), V3(hx, t, hz), t * 0.9), m: Mat.canvas)
        h = U(h, sdCapsule(q, V3(hx + 0.02, 0.085, -hz + 0.09), V3(hx + 0.02, 0.085, hz - 0.09), 0.085), Mat.canvas)
        let tl = tools(q)
        h = U(h, tl)
        let z0 = hem, z1 = hz - 0.03
        let slab = sdRoundBox(q - V3(0, top + 0.007, (z0 + z1) * 0.5), V3(hx - 0.03, 0.007, (z1 - z0) * 0.5), 0.006)
        var panel = smin(slab, tl.d - 0.008, 0.045)
        let region = max(max(z0 - q.z, q.z - z1), abs(q.x) - (hx - 0.03))
        panel = smax(panel, region, 0.004)
        h = U(h, panel, Mat.pocket)
        // straps + buckles
        let sq = V3(q.x, q.y, abs(q.z) - 0.3)
        let strap = sdRoundBox(sq - V3(hx + 0.36, 0.012, 0), V3(0.34, 0.011, 0.045), 0.009)
        h = U(h, strap, Mat.leather)
        let bx = hx + 0.3
        let frame = opExtrude(abs(sdRoundRect(sq.x - bx, sq.z, 0.045, 0.07, 0.022)) - 0.012, sq.y - 0.03, 0.012, 0.006)
        let prong = sdCapsule(sq, V3(bx - 0.04, 0.036, 0), V3(bx + 0.035, 0.03, 0), 0.008)
        h = U(h, min(frame, prong), Mat.copper)
        return h
    }
    func surf(_ p: V3, _ n: V3, _ m: Int32) -> Surf {
        let q = xf.loc(p)
        if m == Mat.canvas {
            let e = -sdRoundRect(q.x, q.z, hx, hz, 0.04)
            let bind = 1 - sstep(0.045, 0.055, e)
            let wv = 0.5 + 0.5 * sin(q.x * 420) * sin(q.z * 420)
            let alb = mix3(Pal.canvas, Pal.velvet, bind) * (0.965 + 0.05 * wv)
            return fabricSurf(alb, n, q, sheen: 0.06, grain: 160)
        }
        // pocket panel: velvet-blue canvas, cream binding along the hem, dashed cream stitches
        let hemBand = 1 - sstep(0.036, 0.046, q.z - hem)
        let dash = sstep(0.35, 0.45, fract(q.z * 14)) * (1 - sstep(0.75, 0.85, fract(q.z * 14)))
        var dv = min(abs(q.x - dividers.0), abs(q.x - dividers.1))
        dv = min(dv, abs(q.x - dividers.2))
        var stitch = (1 - sstep(0.004, 0.009, dv)) * dash * sstep(hem + 0.06, hem + 0.07, q.z)
        let dashX = sstep(0.35, 0.45, fract(q.x * 14)) * (1 - sstep(0.75, 0.85, fract(q.x * 14)))
        stitch = max(stitch, (1 - sstep(0.004, 0.009, abs(q.z - (hem + 0.08)))) * dashX)
        let wv = 0.5 + 0.5 * sin(q.x * 420) * sin(q.z * 420)
        var alb = mix3(Pal.velvet, Pal.canvas, hemBand) * (0.94 + 0.08 * wv)
        alb = mix3(alb, Pal.cream, 0.85 * stitch * (1 - hemBand))
        return fabricSurf(alb, n, q, sheen: 0.08, grain: 160)
    }
}

/// Pull-out drawer: deep-blue lacquer box with a taller front panel carrying a copper frame and a
/// brass D-pull on copper roses, copper side runners, velvet floor. Front toward +z.
struct Drawer {
    var xf: Xf
    var hx: Float = 0.82, hz: Float = 0.56, h: Float = 0.3, wt: Float = 0.05
    let floorTop: Float = 0.1
    var tool: Screwdriver? = nil
    @inline(__always) func map(_ p: V3) -> Hit {
        let q = xf.loc(p)
        let bd = sdBox(q - V3(0, h * 0.5 + 0.05, 0.1), V3(hx + 0.12, h * 0.5 + 0.15, hz + 0.3))
        if bd > boundSkip { return Hit(d: bd, m: Mat.lacquer) }
        var body = sdRoundBox(q - V3(0, h * 0.5, 0), V3(hx, h * 0.5, hz), 0.045)
        body = max(body, -sdRoundBox(q - V3(0, h * 0.5 + 0.55, 0), V3(hx - wt, h * 0.5 + 0.5, hz - wt), 0.03))
        let fy = (h + 0.06) * 0.5
        let front = sdRoundBox(q - V3(0, fy, hz + 0.03), V3(hx + 0.05, fy, 0.045), 0.04)
        var r = Hit(d: min(body, front), m: Mat.lacquer)
        let fz = q.z - (hz + 0.075)
        let frame = max(abs(sdRoundRect(q.x, q.y - fy, hx - 0.01, fy - 0.055, 0.04)) - 0.014, abs(fz) - 0.012)
        let runner = sdRoundBox(V3(abs(q.x) - hx - 0.012, q.y - h * 0.55, q.z), V3(0.014, 0.028, hz - 0.06), 0.012)
        let pw: Float = 0.28, pr: Float = 0.11
        let rose = sdCylZ(V3(abs(q.x) - pw, q.y - fy, q.z - (hz + 0.085)), 0.046, 0.014, 0.008)
        r = U(r, min(min(frame, runner), rose), Mat.copper)
        var d2: Float
        if fz > pr * 0.5 {
            d2 = abs(sdRoundRect(q.x, fz - pr * 0.5, pw, pr * 0.5, 0.06))
        } else {
            d2 = sdSeg2(abs(q.x), fz, pw, 0, pw, pr * 0.5)
        }
        r = U(r, len2(d2, q.y - fy) - 0.026, Mat.gold)
        let fl = sdRoundBox(q - V3(0, (0.04 + floorTop) * 0.5, 0), V3(hx - wt - 0.002, (floorTop - 0.04) * 0.5, hz - wt - 0.002), 0.012)
        r = U(r, fl, Mat.foam)
        if let t = tool, t.show { r = U(r, t.map(q)) }
        return r
    }
}

/// Shallow service tray: deep-blue lacquer shell, copper bead along the rim, velvet floor.
struct Tray {
    var xf: Xf
    var hx: Float = 0.9, hz: Float = 0.6, h: Float = 0.15
    let floorTop: Float = 0.07
    @inline(__always) func map(_ p: V3) -> Hit {
        let q = xf.loc(p)
        let bd = sdBox(q - V3(0, h * 0.5, 0), V3(hx + 0.05, h * 0.5 + 0.05, hz + 0.05))
        if bd > boundSkip { return Hit(d: bd, m: Mat.lacquer) }
        let outer = sdRoundBox(q - V3(0, h * 0.5, 0), V3(hx, h * 0.5, hz), 0.07)
        let inner = sdRoundBox(q - V3(0, h * 0.5 + 0.54, 0), V3(hx - 0.06, h * 0.5 + 0.5, hz - 0.06), 0.05)
        var r = Hit(d: max(outer, -inner), m: Mat.lacquer)
        r = U(r, len2(sdRoundRect(q.x, q.z, hx - 0.03, hz - 0.03, 0.05), q.y - h) - 0.032, Mat.copper)
        let fl = sdRoundBox(q - V3(0, (0.04 + floorTop) * 0.5, 0), V3(hx - 0.062, (floorTop - 0.04) * 0.5, hz - 0.062), 0.012)
        r = U(r, fl, Mat.foam)
        return r
    }
}

// MARK: - Scene helpers

/// Deep-blue velvet floor of the hero world, with a slow pile mottling.
@inline(__always) func velvetFloor(_ p: V3, _ n: V3, _ alb: V3 = Pal.velvetDeep, sheen: Float = 0.5) -> Surf {
    var s = velvetSurf(alb, n, p, sheen: sheen)
    let m = vnoise(p.x * 0.8 + 3.1, p.z * 0.8 - 1.7, 12)
    s.albedo = s.albedo * (0.9 + 0.2 * m)
    return s
}
/// Velvet albedo that is richer (lighter Velvet) in a soft pool around `c` and deeper far away.
@inline(__always) func poolAlbedo(_ p: V3, _ c: V3, _ r: Float) -> V3 {
    let d = len2(p.x - c.x, p.z - c.z)
    return mix3(Pal.velvet, Pal.velvetDeep * 0.75, sstep(r * 0.25, r, d))
}
/// Spotlight key: full strength inside a soft pool around `c`, `lo` outside.
@inline(__always) func spotMask(_ p: V3, _ c: V3, _ L: V3, _ r2: Float, _ lo: Float) -> Float {
    let d = p - c
    let perp = d - L * dot(d, L)
    return mixf(lo, 1, expf(-dot(perp, perp) / r2))
}
/// Teardrop cord loop hanging from a bar along x through `B` down to the eyelet `E` (same x).
@inline(__always) func hangLoop(_ q: V3, _ B: V3, _ E: V3, _ rho: Float, _ r: Float) -> Float {
    let dx = q.x - B.x
    let dy = q.y - B.y, dz = q.z - B.z
    var d2: Float
    if dy > 0 {
        d2 = abs(len2(dy, dz) - rho)
    } else {
        d2 = min(sdSeg2(q.z, q.y, B.z + rho, B.y, E.z, E.y), sdSeg2(q.z, q.y, B.z - rho, B.y, E.z, E.y))
    }
    return len2(d2, dx) - r
}
/// Warm studio over the deep-blue velvet world: cream key from the upper left, cool blue sky fill,
/// velvet bounce, a dark-blue-to-warm environment for the metals, a gold rim from the back right.
func blueStudio(_ cam: PerspCam, left: Float = 0.75, up: Float = 1.25, front: Float = 0.45) -> Studio {
    var st = bgStudio(cam, left: left, up: up, front: front)
    st.keyCol = V3(1.0, 0.9, 0.76)
    st.keyI = 1.3
    st.skyCol = V3(0.42, 0.52, 0.85)
    st.skyI = 0.3
    st.bounceCol = V3(0.3, 0.38, 0.62)
    st.bounceI = 0.12
    st.envLo = V3(0.012, 0.018, 0.045)
    st.envHi = V3(0.6, 0.48, 0.32)
    st.rimCol = V3(1.0, 0.74, 0.42)
    st.rimI = 0.5
    return st
}
/// The same warm studio for transparent sprites on the light app background.
func warmSpriteStudio(_ cam: OrthoCam, left: Float = 0.6, up: Float = 1.1, front: Float = 0.5) -> Studio {
    var st = spriteStudio(cam, left: left, up: up, front: front)
    st.keyCol = V3(1.0, 0.95, 0.88)
    st.envLo = V3(0.06, 0.07, 0.11)
    st.envHi = V3(0.62, 0.55, 0.46)
    st.rimCol = V3(1.0, 0.8, 0.52)
    st.rimI = 0.4
    return st
}
/// Onboarding background shader: calm deep-blue gradient over the bottom 40 % for UI text.
func onboardingShader<M: Scene>(_ model: M, _ cam: PerspCam) -> BGShader<M> {
    var sh = BGShader(model: model, cam: cam)
    sh.quietStart = 0.56
    sh.quietEnd = 0.66
    sh.quietTop = Pal.blueMid
    sh.quietBottom = Pal.blueNight
    sh.quietAmount = 1
    sh.vignette = 0.42
    sh.shadowK = 6
    return sh
}

// MARK: - Onboarding backgrounds

/// CK01 — the open case at 3/4 from above: every tool in its fitted velvet cut-out, a cream ID tag
/// tied to the handle, spot-lit on the deep-blue velvet.
struct CatalogueScene: Scene {
    var studio = Studio()
    var cs: CasePart
    var tag: Tag
    var ring = V3.zero
    var cord: Cord
    var spotC = V3.zero
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = Hit(d: p.y, m: Mat.ground)
        h = U(h, cs.map(p))
        h = U(h, tag.map(p))
        let q = cs.xf.loc(p) / cs.s
        h = U(h, min(sdTorusX(q - ring, 0.062, 0.012) * cs.s, cord.d(p)), Mat.blueCord)
        return h
    }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf {
        m == Mat.ground ? velvetFloor(p, n, poolAlbedo(p, spotC, 3.6)) : stdSurf(m, p, n)
    }
    func aoScale(_ m: Int32) -> Float { m == Mat.ground ? 0.35 : 0.12 }
    @inline(__always) func keyMask(_ p: V3) -> Float { spotMask(p, spotC, studio.L, 6, 0.16) }
}

func renderCatalogue(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    let c = standardKit(CasePart(xf: Xf(V3(0, 0, 0), rotY(rad(-6))), lidAng: rad(100), handleAng: 0.4))
    let ring = c.gripPoint(0.14)
    let tag = Tag.flat(x: 0.78, z: 1.2, base: 0, yaw: -26, s: 0.4)
    let a = c.world(ring + V3(0, -0.035, 0.05))
    let e = tag.eyelet + V3(0, 0.03, 0)
    let cord = Cord([a, V3(a.x + 0.08, 0.02, a.z + 0.1), V3((a.x + e.x) * 0.5 + 0.04, 0.013, (a.z + e.z) * 0.5 - 0.02),
                     e + V3(-0.05, -0.01, -0.05), e], r: 0.012)
    var model = CatalogueScene(cs: c, tag: tag, ring: ring, cord: cord)
    model.spotC = V3(0, 0.4, 0.1)
    let cam = orbitCam(target: V3(0, 0.55, -0.1), az: -4, el: 50, dist: 13.5, fovY: 30, W: w, H: h, shiftY: -0.4)
    var st = blueStudio(cam, left: 0.75, up: 1.25, front: 0.3)
    let tp = c.world(c.lidLocal(V3(0, c.liningY, 0)))
    st.b1 = bandBox(through: tp, faceN: V3(0, 1, 0), viewDir: tp - cam.pos, dist: 4, angle: -35, width: 0.5,
                    soft: 0.35, intensity: 1.4)
    let fp = c.world(V3(-0.4, 0.2, c.hz))
    st.b2 = bandBox(through: fp, faceN: c.xf.worldDir(V3(0, 0, 1)), viewDir: fp - cam.pos, dist: 4, angle: 70,
                    width: 0.35, soft: 0.25, intensity: 0.9)
    model.studio = st
    return render(onboardingShader(model, cam), w, h, ss: ss)
}

/// CK02 — gathering a few chosen tools on the velvet: an open canvas tool roll with a screwdriver
/// and a spanner tucked in and two pockets still free, a hammer waiting beside it, a clipboard
/// with blank lines.
struct PrepareScene: Scene {
    var studio = Studio()
    var roll: ToolRoll
    var hammer: Hammer
    var board: Clipboard
    var spotC = V3.zero
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = Hit(d: p.y, m: Mat.ground)
        h = U(h, roll.map(p))
        h = U(h, hammer.map(p))
        h = U(h, board.map(p))
        return h
    }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf {
        switch m {
        case Mat.ground: return velvetFloor(p, n, poolAlbedo(p, spotC, 3.6))
        case Mat.canvas, Mat.pocket: return roll.surf(p, n, m)
        case Mat.sheet: return board.sheetSurf(p, n)
        default: return stdSurf(m, p, n)
        }
    }
    func aoScale(_ m: Int32) -> Float { m == Mat.ground ? 0.3 : 0.12 }
    @inline(__always) func keyMask(_ p: V3) -> Float { spotMask(p, spotC, studio.L, 7, 0.22) }
}

func renderPrepare(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    var roll = ToolRoll(xf: Xf(V3(-0.3, 0, 0.3), rotY(rad(2))))
    roll.hem = -0.02
    let s1: Float = 1.1
    roll.d1 = Screwdriver(xf: Xf(V3(-0.76, roll.top + 0.085 * s1, 0.03), rotY(rad(-90))), s: s1)
    let ws: Float = 0.9
    roll.wrench = Wrench(xf: Xf(V3(0.21, roll.top + 0.028 * ws, 0.1), rotY(rad(90))), s: ws)
    let hs: Float = 0.95
    let hammer = Hammer(xf: Xf(V3(1.22, 0.075 * hs, -1.5), rotY(rad(70)) * rotX(rad(1.2))), s: hs)
    let board = Clipboard(xf: Xf(V3(-0.78, 0, -1.3), rotY(rad(-10))), s: 0.8)
    var model = PrepareScene(roll: roll, hammer: hammer, board: board)
    model.spotC = V3(0, 0.2, -0.4)
    let cam = orbitCam(target: V3(0.12, 0.1, -0.5), az: 0, el: 57, dist: 14, fovY: 30, W: w, H: h, shiftY: -0.4)
    var st = blueStudio(cam, left: 0.75, up: 1.25, front: 0.3)
    let tp = V3(-0.2, 0.1, -0.2)
    st.b1 = bandBox(through: tp, faceN: V3(0, 1, 0), viewDir: tp - cam.pos, dist: 4, angle: -35, width: 0.5,
                    soft: 0.35, intensity: 1.2)
    model.studio = st
    return render(onboardingShader(model, cam), w, h, ss: ss)
}

/// CK03 — the open case with two empty cut-outs (the drill and a screwdriver are out); the drill
/// rests beside the case wearing an amber service tag on a brown string.
struct ReturnScene: Scene {
    var studio = Studio()
    var cs: CasePart
    var drill: Drill
    var tag: Tag
    var ringC = V3.zero, ringAx = V3(1, 0, 0), ringR: Float = 0.1
    var cord: Cord
    var spotC = V3.zero
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = Hit(d: p.y, m: Mat.ground)
        h = U(h, cs.map(p))
        h = U(h, drill.map(p))
        h = U(h, tag.map(p))
        h = U(h, min(sdRing(p, ringC, ringAx, ringR, 0.011), cord.d(p)), Mat.cord)
        return h
    }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf {
        if m == Mat.ground { return velvetFloor(p, n, poolAlbedo(p, spotC, 3.8)) }
        if m == Mat.tagFace { return enamelSurf(Pal.amber, n, sheen: 0.24) }
        return stdSurf(m, p, n)
    }
    func aoScale(_ m: Int32) -> Float { m == Mat.ground ? 0.35 : 0.12 }
    @inline(__always) func keyMask(_ p: V3) -> Float { spotMask(p, spotC, studio.L, 8, 0.22) }
}

func renderReturn(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    var c = standardKit(CasePart(xf: Xf(V3(-0.2, 0, -0.45), rotY(rad(9))), lidAng: rad(100), handleAng: 0.1))
    c.drill?.show = false
    c.driver?.show = false
    let ds: Float = 0.9
    let drill = Drill(xf: Xf(V3(1.02, 0.12 * ds, 0.92), rotY(rad(-26))), s: ds)
    let gl = V3(-0.12 - 0.196 * 0.1, 0, 0.1 + 0.98 * 0.1)
    let ringC = drill.xf.world(gl * ds)
    let ringAx = drill.xf.worldDir(V3(-0.196, 0, 0.9806))
    var tag = Tag.flat(x: 1.52, z: 1.42, base: 0, yaw: 30, s: 0.36)
    tag.rim = false
    let side = normalize(cross(ringAx, V3(0, 1, 0)))
    let a = ringC + side * (0.1 * ds) + V3(0, -0.02, 0)
    let e = tag.eyelet + V3(0, 0.025, 0)
    let cord = Cord([a, a + side * 0.08 + V3(0, -0.05, 0), V3((a.x + e.x) * 0.5, 0.011, (a.z + e.z) * 0.5 + 0.05), e],
                    r: 0.011)
    var model = ReturnScene(cs: c, drill: drill, tag: tag, ringC: ringC, ringAx: ringAx, ringR: 0.1 * ds, cord: cord)
    model.spotC = V3(0.2, 0.4, 0.1)
    let cam = orbitCam(target: V3(0.2, 0.5, -0.1), az: 9, el: 48, dist: 14, fovY: 31, W: w, H: h, shiftY: -0.36)
    var st = blueStudio(cam, left: 0.75, up: 1.25, front: 0.3)
    let tp = c.world(c.lidLocal(V3(0, c.liningY, 0)))
    st.b1 = bandBox(through: tp, faceN: V3(0, 1, 0), viewDir: tp - cam.pos, dist: 4, angle: -35, width: 0.5,
                    soft: 0.35, intensity: 1.4)
    let dp = drill.xf.world(V3(-0.1, 0.1, -0.22) * ds)
    st.b2 = bandBox(through: dp, faceN: V3(0, 1, 0), viewDir: dp - cam.pos, dist: 4, angle: 40, width: 0.25,
                    soft: 0.18, intensity: 1.0)
    model.studio = st
    return render(onboardingShader(model, cam), w, h, ss: ss)
}

// MARK: - Sprites

/// CK04 — home hero: the open case with the standard kit, lit to read on the deep-blue panel.
struct HeroCaseModel: Scene {
    var studio = Studio()
    var cs: CasePart
    @inline(__always) func map(_ p: V3) -> Hit { cs.map(p) }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf { stdSurf(m, p, n) }
    func aoScale(_ m: Int32) -> Float { 0.12 }
}

func renderHomeCase(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    let az: Float = -26
    var cam = OrthoCam(target: V3(0, 0.6, 0), az: az, el: 30, W: w, H: h)
    let cs = standardKit(CasePart(xf: Xf(V3(0, 0, 0), rotY(rad(4))), lidAng: rad(98)), hammer: false)
    var model = HeroCaseModel(cs: cs)
    fitOrtho(model, &cam, pad: 0.06)
    var st = warmSpriteStudio(cam, left: 0.65, up: 1.2, front: 0.5)
    st.rimI = 1.2
    st.rimCol = V3(1.0, 0.72, 0.38)
    st.envLo = V3(0.03, 0.04, 0.08)
    st.skyCol = V3(0.7, 0.75, 0.95)
    st.ptPos = cs.world(V3(0.1, 0.9, 0.3))
    st.ptCol = V3(1.0, 0.9, 0.7)
    st.ptI = 0.35
    st.ptR = 1.4
    let lf = cs.world(cs.lidLocal(V3(0, cs.hb + cs.hl, 0)))
    st.b1 = bandBox(through: lf, faceN: normalize(cs.xf.worldDir(V3(0, -0.2, -1))), viewDir: cam.fwd, dist: 3,
                    angle: 60, width: 0.4, soft: 0.25, intensity: 1.6)
    model.studio = st
    var sh = SpriteShader(model: model, cam: cam)
    sh.shadowCol = Pal.blueNight
    sh.shadowStr = 0.5
    return render(sh, w, h, ss: ss)
}

/// CK05 — a copper claw hammer with a cream enamel handle.
struct HammerModel: Scene {
    var studio = Studio()
    let hammer: Hammer
    @inline(__always) func map(_ p: V3) -> Hit { hammer.map(p) }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf { stdSurf(m, p, n) }
    func aoScale(_ m: Int32) -> Float { 0.1 }
}

func renderHammer(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    var cam = OrthoCam(target: V3(0, 0.1, 0), az: -10, el: 48, W: w, H: h)
    var model = HammerModel(hammer: Hammer(xf: Xf(V3(0, 0.075, 0), rotY(rad(40)) * rotX(rad(1.2))), s: 1))
    fitOrtho(model, &cam, pad: 0.08)
    var st = warmSpriteStudio(cam)
    let hp = model.hammer.xf.world(V3(0, 0.07, 0))
    st.b1 = bandBox(through: hp, faceN: V3(0, 1, 0), viewDir: cam.fwd, dist: 3, angle: 55, width: 0.18, soft: 0.1,
                    intensity: 2.2)
    st.b2 = bandBox(through: model.hammer.xf.world(V3(-0.5, 0.05, 0)), faceN: V3(0, 1, 0), viewDir: cam.fwd, dist: 3,
                    angle: 55, width: 0.3, soft: 0.2, intensity: 0.6)
    model.studio = st
    return render(SpriteShader(model: model, cam: cam), w, h, ss: ss)
}

/// CK06 — a blank cream luggage-style tool tag with a brass rim, copper eyelet and a short cord.
struct TagModel: Scene {
    var studio = Studio()
    let tag: Tag
    let cord: Cord
    let knot: V3
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = tag.map(p)
        h = U(h, min(cord.d(p), sdSphere(p - knot, 0.032)), Mat.blueCord)
        return h
    }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf { stdSurf(m, p, n) }
    func aoScale(_ m: Int32) -> Float { 0.1 }
}

func renderToolTag(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    var cam = OrthoCam(target: V3(0, 0, 0), az: -8, el: 58, W: w, H: h)
    var tag = Tag(xf: Xf(V3(0, 0.022, 0.1), rotY(rad(-9)) * rotX(rad(-90))), s: 1)
    tag.th = 0.022
    func tp(_ x: Float, _ y: Float, _ hgt: Float) -> V3 { tag.xf.world(V3(x, y, 0)) + V3(0, hgt, 0) }
    let r: Float = 0.018
    let face: Float = 0.044 + r
    let knot = tp(0.13, 0.66, r + 0.012)
    let cord = Cord([tp(0, 0.29, face - 0.02), tp(0.0, 0.36, face), tp(0.03, 0.47, r + 0.012), tp(0.1, 0.6, r),
                     knot, tp(0.02, 0.78, r), tp(-0.14, 0.86, r), tp(-0.26, 0.76, r), tp(-0.22, 0.6, r),
                     tp(-0.08, 0.54, r), knot, tp(0.26, 0.7, r), tp(0.34, 0.66, r)], r: r)
    var model = TagModel(tag: tag, cord: cord, knot: knot)
    fitOrtho(model, &cam, pad: 0.075)
    var st = warmSpriteStudio(cam)
    st.b1 = bandBox(through: tag.xf.world(V3(-0.1, 0.1, 0.02)), faceN: V3(0, 1, 0), viewDir: cam.fwd, dist: 3,
                    angle: 50, width: 0.25, soft: 0.2, intensity: 1.2)
    model.studio = st
    return render(SpriteShader(model: model, cam: cam), w, h, ss: ss)
}

/// CK07 — a deep-blue pull-out drawer with a brass pull, velvet floor and one screwdriver inside.
struct DrawerModel: Scene {
    var studio = Studio()
    let drawer: Drawer
    @inline(__always) func map(_ p: V3) -> Hit { drawer.map(p) }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf { stdSurf(m, p, n) }
    func aoScale(_ m: Int32) -> Float { 0.14 }
}

func renderBlueTray(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    var cam = OrthoCam(target: V3(0, 0.2, 0), az: -28, el: 36, W: w, H: h)
    var dr = Drawer(xf: Xf(V3(0, 0, 0), rotY(rad(2))))
    let s: Float = 1.05
    dr.tool = Screwdriver(xf: Xf(V3(0.04, dr.floorTop + 0.085 * s, -0.04), rotY(rad(-18))), s: s)
    var model = DrawerModel(drawer: dr)
    fitOrtho(model, &cam, pad: 0.07)
    var st = warmSpriteStudio(cam)
    let fp = dr.xf.world(V3(0, 0.18, dr.hz + 0.08))
    st.b1 = bandBox(through: fp, faceN: dr.xf.worldDir(V3(0, 0, 1)), viewDir: cam.fwd, dist: 3, angle: 62, width: 0.3,
                    soft: 0.2, intensity: 1.4)
    model.studio = st
    return render(SpriteShader(model: model, cam: cam), w, h, ss: ss)
}

/// CK08 — an unrolled canvas tool roll with four tools tucked into its pockets.
struct RollModel: Scene {
    var studio = Studio()
    let roll: ToolRoll
    @inline(__always) func map(_ p: V3) -> Hit { roll.map(p) }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf {
        m == Mat.canvas || m == Mat.pocket ? roll.surf(p, n, m) : stdSurf(m, p, n)
    }
    func aoScale(_ m: Int32) -> Float { 0.12 }
}

func fullRoll(_ xf: Xf) -> ToolRoll {
    var roll = ToolRoll(xf: xf)
    roll.hem = -0.02
    let s1: Float = 1.1, s2: Float = 0.85
    roll.d1 = Screwdriver(xf: Xf(V3(-0.76, roll.top + 0.085 * s1, 0.03), rotY(rad(-90))), s: s1)
    roll.d2 = Screwdriver(xf: Xf(V3(-0.24, roll.top + 0.085 * s2, 0.05), rotY(rad(-90))), s: s2)
    let ws: Float = 0.9
    roll.wrench = Wrench(xf: Xf(V3(0.21, roll.top + 0.028 * ws, 0.1), rotY(rad(90))), s: ws)
    let hs: Float = 0.85
    roll.hammer = Hammer(xf: Xf(V3(0.74, roll.top + 0.075 * hs, -0.3), rotY(rad(90))), s: hs)
    return roll
}

func renderToolRoll(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    var cam = OrthoCam(target: V3(0, 0, 0), az: -6, el: 58, W: w, H: h)
    var model = RollModel(roll: fullRoll(Xf(V3(-0.2, 0, 0), rotY(rad(-3)))))
    fitOrtho(model, &cam, pad: 0.065)
    var st = warmSpriteStudio(cam)
    st.b1 = bandBox(through: V3(0, 0.1, -0.4), faceN: V3(0, 1, 0), viewDir: cam.fwd, dist: 3, angle: 55, width: 0.3,
                    soft: 0.2, intensity: 1.2)
    model.studio = st
    return render(SpriteShader(model: model, cam: cam), w, h, ss: ss)
}

/// CK09 — a chunky cream work glove with an amber cuff resting on a clipboard with blank lines.
struct GloveBoardModel: Scene {
    var studio = Studio()
    let board: Clipboard
    let glove: Glove
    @inline(__always) func map(_ p: V3) -> Hit { U(board.map(p), glove.map(p)) }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf { m == Mat.sheet ? board.sheetSurf(p, n) : stdSurf(m, p, n) }
    func aoScale(_ m: Int32) -> Float { 0.14 }
}

func renderGloveClipboard(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    var cam = OrthoCam(target: V3(0, 0.1, 0), az: -10, el: 50, W: w, H: h)
    let board = Clipboard(xf: Xf(V3(-0.12, 0, -0.1), rotY(rad(6))), s: 1)
    let gs: Float = 1.3
    let glove = Glove(xf: Xf(V3(0.3, 0.062 + 0.125 * gs, 0.5), rotY(rad(126)) * rotZ(rad(-2))), s: gs, curl: 0.06,
                      spread: 1.08)
    var model = GloveBoardModel(board: board, glove: glove)
    fitOrtho(model, &cam, pad: 0.07)
    var st = warmSpriteStudio(cam)
    st.b1 = bandBox(through: V3(-0.1, 0.1, -0.7), faceN: V3(0, 1, 0), viewDir: cam.fwd, dist: 3, angle: 55, width: 0.25,
                    soft: 0.15, intensity: 1.4)
    model.studio = st
    return render(SpriteShader(model: model, cam: cam), w, h, ss: ss)
}

/// CK10 — hand-over: two chunky gloved hands grip the carry handle of a small deep-blue case from
/// above, side by side (overhand grip, cuffs rising up and out), the case hanging below with its
/// lid mark toward us.
struct HandoverModel: Scene {
    var studio = Studio()
    let cs: CasePart
    let left: Glove
    let right: Glove
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = cs.map(p)
        h = U(h, left.map(p))
        h = U(h, right.map(p))
        return h
    }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf { stdSurf(m, p, n) }
    func aoScale(_ m: Int32) -> Float { 0.12 }
}

/// Upright pose for a case: lid face toward +z (camera), front edge (handle, latches) up.
/// Case-local (x, y, z) maps to world (-x, z, y).
let uprightRot: M3 = rotZ(.pi) * rotX(.pi / 2)

func renderHandover(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    let s: Float = 0.62
    var c = CasePart(xf: Xf(V3(0, 0.7 * s + 0.08, 0), uprightRot), s: s, handleAng: .pi / 2)
    c.hz = 0.7
    c.latchX = 1.0
    c.handleW = 0.72
    c.handleReach = 0.3
    c.markScale = 1.0
    let barY = c.world(c.gripPoint(0)).y
    let barZ = c.world(c.gripPoint(0)).z
    let gs: Float = 0.78
    // palm down on the bar, fingers curling over it toward us, forearm rising up and back
    let beta = rad(38)
    let fx = V3(0, -sin(beta), cos(beta)), fy = V3(0, cos(beta), sin(beta))
    let base = M3(columns: (fx, fy, cross(fx, fy)))
    let lRot = rotY(rad(24)) * base
    let rRot = rotY(rad(-24)) * base
    let grip = V3(0.2, -0.07, 0) * gs
    let xg: Float = 0.23
    let left = Glove(xf: Xf(V3(-xg, barY, barZ) - lRot * grip, lRot), s: gs, mirror: true, curl: 1.05, thumbFist: 1,
                     mitten: 0.04)
    let right = Glove(xf: Xf(V3(xg, barY, barZ) - rRot * grip, rRot), s: gs, mirror: false, curl: 1.05, thumbFist: 1,
                      mitten: 0.04)
    var model = HandoverModel(cs: c, left: left, right: right)
    var cam = OrthoCam(target: V3(0, 0.8, 0), az: 0, el: 10, W: w, H: h)
    fitOrtho(model, &cam, pad: 0.065)
    var st = warmSpriteStudio(cam, left: 0.6, up: 1.2, front: 0.7)
    let lf = c.world(V3(0, c.hb + c.hl, 0))
    st.b1 = bandBox(through: lf, faceN: V3(0, 0, 1), viewDir: cam.fwd, dist: 3, angle: 60, width: 0.35, soft: 0.25,
                    intensity: 1.4)
    model.studio = st
    var sh = SpriteShader(model: model, cam: cam)
    sh.shadowStr = 0.28
    return render(sh, w, h, ss: ss)
}

/// CK11 — a small closed case: copper latches, gold handle, embossed handle-mark on the lid, a cream
/// tag hanging from the handle.
struct ClosedCaseModel: Scene {
    var studio = Studio()
    let cs: CasePart
    let tag: Tag
    let B: V3, E: V3
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = cs.map(p)
        h = U(h, tag.map(p))
        h = U(h, hangLoop(p, B, E, 0.064, 0.012), Mat.blueCord)
        return h
    }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf { stdSurf(m, p, n) }
    func aoScale(_ m: Int32) -> Float { 0.14 }
}

func renderClosedCase(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    var c = CasePart(xf: Xf(V3(0, 0, 0)), handleAng: 2.2)
    c.markScale = 1.2
    let B = c.gripPoint(0.14)
    let ts: Float = 0.34
    let E = B + V3(0, -0.046 - 0.07, 0)
    let tag = Tag(xf: Xf(E - V3(0, 0.29 * ts, 0), rotY(rad(10))), s: ts)
    var model = ClosedCaseModel(cs: c, tag: tag, B: B, E: E)
    var cam = OrthoCam(target: V3(0, 0.3, 0), az: -24, el: 30, W: w, H: h)
    fitOrtho(model, &cam, pad: 0.07)
    var st = warmSpriteStudio(cam)
    st.b1 = bandBox(through: V3(-0.2, c.hb + c.hl, -0.1), faceN: V3(0, 1, 0), viewDir: cam.fwd, dist: 3, angle: 58,
                    width: 0.45, soft: 0.3, intensity: 1.3)
    st.b2 = bandBox(through: V3(-0.3, 0.25, c.hz), faceN: V3(0, 0, 1), viewDir: cam.fwd, dist: 3, angle: 70,
                    width: 0.2, soft: 0.15, intensity: 1.0)
    model.studio = st
    return render(SpriteShader(model: model, cam: cam), w, h, ss: ss)
}

/// CK12 — a velvet-lined service tray with a copper spanner (amber service tag tied to its ring end)
/// and a cream-handled screwdriver.
struct ServiceTrayModel: Scene {
    var studio = Studio()
    let tray: Tray
    let wrench: Wrench
    let driver: Screwdriver
    let tag: Tag
    let ringC: V3, ringAx: V3
    let cord: Cord
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = tray.map(p)
        h = U(h, wrench.map(p))
        h = U(h, driver.map(p))
        h = U(h, tag.map(p))
        h = U(h, min(sdRing(p, ringC, ringAx, 0.058, 0.011), cord.d(p)), Mat.cord)
        return h
    }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf {
        m == Mat.tagFace ? enamelSurf(Pal.amber, n, sheen: 0.24) : stdSurf(m, p, n)
    }
    func aoScale(_ m: Int32) -> Float { 0.12 }
}

func renderServiceTray(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    let tray = Tray(xf: Xf(V3(0, 0, 0)))
    let ws: Float = 1.02
    let wrench = Wrench(xf: Xf(V3(0.2, tray.floorTop + 0.028 * ws, 0.12), rotY(rad(14))), s: ws)
    let ds: Float = 0.9
    let driver = Screwdriver(xf: Xf(V3(0.1, tray.floorTop + 0.085 * ds, -0.3), rotY(rad(-6))), s: ds)
    var tag = Tag.flat(x: -0.6, z: 0.36, base: tray.floorTop, yaw: 58, s: 0.42)
    tag.rim = false
    let ringC = wrench.xf.world(V3(-0.46 - 0.055, 0, 0) * ws)
    let ringAx = wrench.xf.worldDir(V3(0, 0, 1))
    let a = wrench.xf.world(V3(-0.46 - 0.113, -0.01, 0) * ws)
    let e = tag.eyelet + V3(0, 0.02, 0)
    let cord = Cord([a, V3(a.x - 0.05, tray.floorTop + 0.011, a.z + 0.02), V3((a.x + e.x) * 0.5, tray.floorTop + 0.011, (a.z + e.z) * 0.5 - 0.03), e], r: 0.011)
    var model = ServiceTrayModel(tray: tray, wrench: wrench, driver: driver, tag: tag, ringC: ringC, ringAx: ringAx, cord: cord)
    var cam = OrthoCam(target: V3(0, 0.1, 0), az: -18, el: 46, W: w, H: h)
    fitOrtho(model, &cam, pad: 0.07)
    var st = warmSpriteStudio(cam)
    st.b1 = bandBox(through: V3(0, 0.12, 0), faceN: V3(0, 1, 0), viewDir: cam.fwd, dist: 3, angle: 55, width: 0.25,
                    soft: 0.15, intensity: 1.6)
    model.studio = st
    return render(SpriteShader(model: model, cam: cam), w, h, ss: ss)
}

// MARK: - App icon

/// The case front close-up: upright deep-blue case, raised golden handle-mark in the centre, two
/// copper latches and the gold handle on the top edge, gold rim light, deep-blue velvet ground.
struct IconModel: Scene {
    var studio = Studio()
    let cs: CasePart
    let backZ: Float = -1.6
    var haloC = V3.zero
    @inline(__always) func map(_ p: V3) -> Hit {
        var h = Hit(d: smin(p.y, p.z - backZ, 1.2), m: Mat.wall)
        h = U(h, cs.map(p))
        return h
    }
    func surface(_ p: V3, _ n: V3, _ m: Int32) -> Surf {
        if m == Mat.wall {
            var s = velvetFloor(p, n, Pal.velvetDeep * 0.8, sheen: 0.35)
            let d = p - haloC
            s.emit = V3(1.0, 0.8, 0.45) * (0.012 * expf(-dot(d, d) / 1.2))
            s.rim = 0
            return s
        }
        return stdSurf(m, p, n)
    }
    func aoScale(_ m: Int32) -> Float { m == Mat.wall ? 0.4 : 0.14 }
    @inline(__always) func keyMask(_ p: V3) -> Float { spotMask(p, V3(0, 0.9, 0.3), studio.L, 2.6, 0.3) }
}

func renderIcon(_ w: Int, _ h: Int, _ ss: Int) -> [Float] {
    var c = CasePart(xf: Xf(V3(0, 0.9, 0), uprightRot), s: 1, handleAng: 0)
    c.hx = 1.0
    c.hz = 0.9
    c.latchX = 0.62
    c.handleW = 0.26
    c.markScale = 1.2
    var model = IconModel(cs: c)
    model.haloC = V3(0, 1.3, model.backZ + 0.2)
    let cam = orbitCam(target: V3(0.02, 0.92, 0.3), az: -13, el: 17, dist: 11, fovY: 15, W: w, H: h, shiftY: 0.02)
    var st = blueStudio(cam, left: 0.7, up: 1.1, front: 0.6)
    st.rimI = 1.2
    st.rimCol = V3(1.0, 0.76, 0.4)
    st.skyI = 0.22
    st.envHi = V3(0.55, 0.45, 0.32)
    let face = V3(0, 0.9, c.hb + c.hl)
    st.b1 = bandBox(through: face + V3(-0.95, 0.85, 0), faceN: V3(0, 0, 1), viewDir: face - cam.pos, dist: 3, angle: 58,
                    width: 0.3, soft: 0.28, intensity: 0.8)
    st.b2 = bandBox(through: face + V3(-0.84, 0.3, 0.05), faceN: V3(0, 0, 1), viewDir: face - cam.pos, dist: 3,
                    angle: 84, width: 0.06, soft: 0.045, intensity: 1.2, col: V3(1, 0.9, 0.66))
    model.studio = st
    var sh = BGShader(model: model, cam: cam)
    sh.quietAmount = 0
    sh.vignette = 0.35
    sh.tmax = 40
    return render(sh, w, h, ss: ss)
}

// MARK: - Registry / main

struct Asset {
    let name: String
    let w: Int
    let h: Int
    let format: OutFormat
    let ss: Int
    let render: (Int, Int, Int) -> [Float]
    var ext: String { if case .jpeg = format { return "jpg" } else { return "png" } }
}

let assets: [Asset] = [
    Asset(name: "ck01_onboarding_catalogue", w: 1290, h: 2796, format: .jpeg(0.9), ss: 3, render: renderCatalogue),
    Asset(name: "ck02_onboarding_prepare", w: 1290, h: 2796, format: .jpeg(0.9), ss: 3, render: renderPrepare),
    Asset(name: "ck03_onboarding_return", w: 1290, h: 2796, format: .jpeg(0.9), ss: 3, render: renderReturn),
    Asset(name: "ck04_home_case", w: 1232, h: 1136, format: .pngAlpha, ss: 4, render: renderHomeCase),
    Asset(name: "ck05_copper_hammer", w: 1024, h: 1024, format: .pngAlpha, ss: 4, render: renderHammer),
    Asset(name: "ck06_tool_tag", w: 800, h: 1000, format: .pngAlpha, ss: 4, render: renderToolTag),
    Asset(name: "ck07_blue_tray", w: 1040, h: 880, format: .pngAlpha, ss: 4, render: renderBlueTray),
    Asset(name: "ck08_tool_roll", w: 1120, h: 800, format: .pngAlpha, ss: 4, render: renderToolRoll),
    Asset(name: "ck09_glove_clipboard", w: 800, h: 880, format: .pngAlpha, ss: 4, render: renderGloveClipboard),
    Asset(name: "ck10_handover_case", w: 960, h: 800, format: .pngAlpha, ss: 4, render: renderHandover),
    Asset(name: "ck11_closed_case", w: 1000, h: 900, format: .pngAlpha, ss: 4, render: renderClosedCase),
    Asset(name: "ck12_service_tray", w: 1000, h: 900, format: .pngAlpha, ss: 4, render: renderServiceTray),
    Asset(name: "AppIcon", w: 1024, h: 1024, format: .pngOpaque, ss: 4, render: renderIcon),
]

let catalogPath = "CopperKit/Assets.xcassets"
let appIconFile = "AppIcon-1024.png"

/// iOS-only app icon set: the universal 1024 entry carries the file, dark and tinted stay empty.
func writeAppIconContents(dir: String) throws {
    let images: [[String: Any]] = [
        ["filename": appIconFile, "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ["appearances": [["appearance": "luminosity", "value": "dark"]], "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ["appearances": [["appearance": "luminosity", "value": "tinted"]], "idiom": "universal", "platform": "ios", "size": "1024x1024"],
    ]
    let obj: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: dir + "/Contents.json"))
}

func writeImagesetContents(dir: String, filename: String) throws {
    let json = """
    {
      "images" : [
        {
          "filename" : "\(filename)",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
    try json.write(toFile: dir + "/Contents.json", atomically: true, encoding: .utf8)
}

func parseColor(_ s: String) -> V3 {
    switch s.lowercased() {
    case "light", "appbg", "background": return Pal.appBg
    case "blue", "deepblue", "panel": return Pal.deepBlue
    case "cream": return Pal.cream
    default:
        let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        return hexc(UInt32(hex, radix: 16) ?? 0xF8F3E9)
    }
}

func main() throws {
    var args = Array(CommandLine.arguments.dropFirst())
    var only: Set<String>? = nil
    var outDir: String? = nil
    var scale: Float = 1
    var ssOverride: Int? = nil
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().path
    while !args.isEmpty {
        let a = args.removeFirst()
        switch a {
        case "--only": only = Set(args.removeFirst().split(separator: ",").map(String.init))
        case "--out": outDir = args.removeFirst()
        case "--scale": scale = Float(args.removeFirst()) ?? 1
        case "--ss": ssOverride = Int(args.removeFirst())
        case "--root": root = args.removeFirst()
        case "--preview": previewBG = Pal.appBg
        case "--preview-bg": previewBG = parseColor(args.removeFirst())
        case "--debug": debugMode = Int(args.removeFirst()) ?? 0
        case "--list":
            for a in assets { print("\(a.name)  \(a.w)x\(a.h)  \(a.ext)") }
            return
        case "-h", "--help":
            print("usage: artgen [--only a,b] [--out dir] [--scale 0.5] [--ss n] [--preview] [--preview-bg light|blue|RRGGBB] [--root projectRoot] [--list]")
            return
        default:
            print("unknown argument \(a)"); exit(2)
        }
    }
    let fm = FileManager.default
    let catalog = root + "/" + catalogPath
    if outDir == nil && !fm.fileExists(atPath: catalog) {
        print("error: asset catalog not found under \(root) (pass --root <projectRoot> or --out <dir>)")
        exit(1)
    }
    if let only = only {
        let known = Set(assets.map { $0.name })
        for n in only where !known.contains(n) { print("warning: unknown asset \(n)") }
    }
    let tAll = Date()
    for asset in assets {
        if let only = only, !only.contains(asset.name) { continue }
        let w = max(8, Int((Float(asset.w) * scale).rounded()))
        let h = max(8, Int((Float(asset.h) * scale).rounded()))
        let ss = ssOverride ?? asset.ss
        let t0 = Date()
        let buf = asset.render(w, h, ss)
        let isIcon = asset.name == "AppIcon"
        let file = isIcon ? appIconFile : "\(asset.name).\(asset.ext)"
        let path: String
        if let outDir = outDir {
            try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
            path = outDir + "/" + file
        } else if isIcon {
            let dir = catalog + "/AppIcon.appiconset"
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try writeAppIconContents(dir: dir)
            path = dir + "/" + file
        } else {
            let dir = catalog + "/\(asset.name).imageset"
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            for f in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where f != "Contents.json" && f != file {
                try? fm.removeItem(atPath: dir + "/" + f)
            }
            try writeImagesetContents(dir: dir, filename: file)
            path = dir + "/" + file
        }
        try saveImage(buf, w, h, path: path, format: asset.format)
        print(String(format: "%@  %dx%d  ss%d  %.1fs  -> %@", asset.name, w, h, ss, Date().timeIntervalSince(t0), path))
    }
    print(String(format: "total %.1fs", Date().timeIntervalSince(tAll)))
}

do { try main() } catch { print("error: \(error)"); exit(1) }
