// OtterBar — メニューバーに住むカワウソの全アニメーションを連番PNGとして描画する。
// 使い方: swift tools/render_otter.swift [出力ディレクトリ] [--assets <xcassetsのRunnersディレクトリ>]
// 出力: <out>/<animation>/{mono,color}/frame-NN.png, <out>/preview/<animation>.gif, <out>/preview/sheet.png
//       --assets 指定時は <dir>/Otter/otter-<animation>-frame-N.imageset も書き出す（mono版）
//       play アニメーションだけは RunCatNeo の命名規則に合わせて otter-frame-N になる。
//       --icon <png> でアプリアイコン用の大きなシルエットだけを書き出す。

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - キャンバス・体型

let canvasW = 64
let canvasH = 36
let displayScale: CGFloat = 1.2                 // 床（下端）を基準にした拡大率
let displayOrigin = CGPoint(x: 32, y: 35.5)
let pivot = CGPoint(x: 32, y: 9)   // ロープの支点（くわえる位置）。y は下向き
let bodyLength: CGFloat = 21.0      // 口先〜尻尾の先

// 胴体の太さ（半径）を背骨上の距離 s で返す
func radius(at s: CGFloat) -> CGFloat {
    let keys: [(CGFloat, CGFloat)] = [
        (0.0, 1.2),   // 鼻先
        (1.4, 2.1),
        (3.0, 3.0),   // 頭
        (4.6, 2.5),
        (5.4, 2.1),   // 首（くびれ）
        (7.4, 2.9),   // 胸
        (9.4, 3.2),   // 胴
        (11.0, 2.8),  // 腰
        (12.4, 2.0),  // 尻尾の付け根（太め）
        (14.8, 1.55),
        (17.8, 1.0),
        (21.0, 0.45), // 尻尾の先
    ]
    for i in 0 ..< keys.count - 1 {
        let (s0, r0) = keys[i], (s1, r1) = keys[i + 1]
        if s <= s1 {
            let t = max(0, (s - s0) / (s1 - s0))
            let e = t * t * (3 - 2 * t)
            return r0 + (r1 - r0) * e
        }
    }
    return keys.last!.1
}

// MARK: - ポーズ

enum Eye { case open, closed, wide, dizzy, half }

enum Rope {
    case held                       // 口でくわえている（上端〜支点）
    case free(sway: CGFloat)        // くわえていない。先端が左右に揺れる
}

enum Extra {
    case z(CGPoint, CGFloat)        // 寝息の Z
    case spark(CGPoint, CGFloat)    // キラキラ
    case exclaim(CGPoint)           // ！
    case sweat(CGPoint)             // 汗
    case pebble(CGPoint)            // 小石
    case motion(CGFloat)            // 回転の残像（体の向き θ）
    case dots(Int)                  // 「…」の点の数
}

struct Paw {
    var tilt: CGFloat   // 0 = お腹側へ真っ直ぐ。正でロープ（口）側へ曲がる
    var reach: CGFloat
}

struct Pose {
    var snout: CGPoint = pivot
    var angle: (CGFloat) -> CGFloat = { _ in 0 }  // 背骨上の距離 s における体の向き（0 = 真下）
    var scale: CGFloat = 1                        // 太さの倍率（寝息など）
    var frontNear = Paw(tilt: 1.05, reach: 3.8)
    var frontFar = Paw(tilt: 0.75, reach: 3.4)
    var hindNear = Paw(tilt: -0.15, reach: 3.8)
    var hindFar = Paw(tilt: -0.35, reach: 3.6)
    var eye: Eye = .open
    var eyeShift: CGFloat = 0                     // 目の位置を頭の前後にずらす（キョロキョロ）
    var rope: Rope = .held
    var extras: [Extra] = []
    var rig: YawRig? = nil                        // 3D の回転姿勢（指定時は angle/snout/足の設定より優先）
}

// MARK: - 3D（ロープを軸にした yaw 回転）

struct V3 {
    var x: CGFloat, y: CGFloat, z: CGFloat  // x 右, y 下, z 手前
    static func + (a: V3, b: V3) -> V3 { V3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func * (a: V3, k: CGFloat) -> V3 { V3(x: a.x * k, y: a.y * k, z: a.z * k) }
}

let cameraElevation: CGFloat = 0.38  // 少し上から見下ろす（回転の円が楕円に見える）

func project(_ v: V3) -> CGPoint {
    CGPoint(x: pivot.x + v.x, y: pivot.y + v.y * cos(cameraElevation) + v.z * sin(cameraElevation))
}

func projectVector(_ v: V3) -> CGVector {
    CGVector(dx: v.x, dy: v.y * cos(cameraElevation) + v.z * sin(cameraElevation))
}

func depth(_ v: V3) -> CGFloat { v.z * cos(cameraElevation) - v.y * sin(cameraElevation) }

struct Limb { var base: CGPoint; var tip: CGPoint; var r: CGFloat }

struct YawRig {
    var spine: [SpinePoint]
    var farLimbs: [Limb]
    var nearLimbs: [Limb]
    var ear: CGPoint
    var eye: CGPoint
    var nose: CGPoint
    var mouth: CGPoint
    var ropeBend: CGPoint  // ロープ中央の位置（遠心力で外へふくらむ）
}

// ロープの上端（固定）から支点までの 3D 上の長さ。投影後に上端が画面の外（y = -1）に来る長さにする
let ropeLength: CGFloat = (pivot.y + 1) / cos(cameraElevation)

/// 口でロープをくわえ、ロープを軸に体を斜め下へ伸ばして水平に回る姿勢。
/// phi: 体の向き（方位角）。cone: 鉛直からの開き。lag: 尻尾の遅れ。
func yawRig(phi: CGFloat, cone: CGFloat = 0.6, lag: CGFloat = 1, stretch: CGFloat = 1.18, ropeSwing: CGFloat = 0.3) -> YawRig {
    let steps = 120
    let ds = bodyLength * stretch / CGFloat(steps)
    // 遠心力でロープが外へ振れ、口の位置が回転の円を描く（体よりわずかに遅れる）
    let ropeAzimuth = phi - 0.2
    let mouth = V3(
        x: ropeLength * sin(ropeSwing) * cos(ropeAzimuth),
        y: ropeLength * (1 - cos(ropeSwing)),
        z: ropeLength * sin(ropeSwing) * sin(ropeAzimuth)
    )
    let bendSwing = ropeSwing * 0.62
    let ropeMid = V3(
        x: ropeLength * 0.5 * sin(bendSwing) * cos(ropeAzimuth - 0.15),
        y: -ropeLength * 0.5,
        z: ropeLength * 0.5 * sin(bendSwing) * sin(ropeAzimuth - 0.15)
    )
    var p = mouth
    var positions: [V3] = [], dirs: [V3] = [], bellies: [V3] = [], laterals: [V3] = []
    for i in 0 ... steps {
        let u = CGFloat(i) / CGFloat(steps)
        let polar = cone * (0.82 + 0.18 * min(u * 3, 1)) - 0.4 * pow(max(0, u - 0.6), 2) * 4
        let azimuth = phi - lag * 0.75 * pow(u, 1.5)
        let d = V3(x: sin(polar) * cos(azimuth), y: cos(polar), z: sin(polar) * sin(azimuth))
        positions.append(p)
        dirs.append(d)
        bellies.append(V3(x: -cos(polar) * cos(azimuth), y: sin(polar), z: -cos(polar) * sin(azimuth)))
        laterals.append(V3(x: -sin(azimuth), y: 0, z: cos(azimuth)))
        p = p + d * ds
    }
    func at(_ s: CGFloat) -> Int { min(steps, max(0, Int((s / bodyLength * CGFloat(steps)).rounded()))) }  // s は体型上の位置
    let spine = (0 ... steps).map { i in
        let d2 = projectVector(dirs[i])
        let len = max(0.0001, hypot(d2.dx, d2.dy))
        return SpinePoint(p: project(positions[i]), dir: CGVector(dx: d2.dx / len, dy: d2.dy / len), normal: projectVector(bellies[i]))
    }
    var far: [Limb] = [], near: [Limb] = []
    func limb(base: V3, tip: V3, r: CGFloat, bodyIndex: Int) {
        let l = Limb(base: project(base), tip: project(tip), r: r)
        if depth(base) < depth(positions[bodyIndex]) { far.append(l) } else { near.append(l) }
    }
    for side: CGFloat in [-1, 1] {
        let f = at(6.4), h = at(11.0)
        // 前足はロープをつかむ、後ろ足は重力で垂れる
        limb(
            base: positions[f] + bellies[f] * 1.4 + laterals[f] * (1.3 * side),
            tip: mouth + V3(x: 0, y: 3.4, z: 0) + laterals[f] * (0.9 * side),
            r: 0.9, bodyIndex: f
        )
        let hipBase = positions[h] + bellies[h] * 1.8 + laterals[h] * (1.5 * side)
        limb(base: hipBase, tip: hipBase + V3(x: 0, y: 3.6, z: 0) + dirs[h] * 0.8, r: 1.0, bodyIndex: h)
    }
    let head = at(3.0)
    let eyes = [CGFloat(-1), 1].map { side in
        positions[head] + laterals[head] * (1.9 * side) + bellies[head] * (-0.4) + dirs[head] * (-0.4)
    }
    let eye = depth(eyes[0]) > depth(eyes[1]) ? eyes[0] : eyes[1]
    return YawRig(
        spine: spine,
        farLimbs: far,
        nearLimbs: near,
        ear: project(positions[head] + bellies[head] * (-2.6) + dirs[head] * 0.9),
        eye: project(eye),
        nose: project(positions[at(0.5)] + bellies[at(0.5)] * 0.6),
        mouth: project(mouth),
        ropeBend: project(ropeMid)
    )
}

/// 回転しながら体と尻尾が遅れて追随する、ぶら下がりの基本形
func hangingAngle(theta: CGFloat, lag: CGFloat = 1) -> (CGFloat) -> CGFloat {
    { s in
        let u = s / bodyLength
        let bend = lag * (0.55 * pow(u, 1.6) + 0.9 * pow(max(0, u - 0.7), 2) * 4)
        let wiggle = 0.22 * pow(u, 3) * sin(2 * theta + 3.0 * u)
        return theta - bend + wiggle
    }
}

/// 静止してぶら下がる（θ はわずかな揺れ）。尻尾は揺れに遅れて振れる
func swayAngle(theta: CGFloat, tail: CGFloat) -> (CGFloat) -> CGFloat {
    { s in
        let u = s / bodyLength
        return theta * (1 - 0.4 * u) + tail * pow(u, 2.2)
    }
}

/// 丸まった姿勢（寝る）。体の向きが一定の割合で回り、ボール状になる
func curledAngle(start: CGFloat, turns: CGFloat) -> (CGFloat) -> CGFloat {
    { s in start - 2 * .pi * turns * s / bodyLength }
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t)) }
func ease(_ t: CGFloat) -> CGFloat { let c = min(max(t, 0), 1); return c * c * (3 - 2 * c) }

func blend(_ a: @escaping (CGFloat) -> CGFloat, _ b: @escaping (CGFloat) -> CGFloat, _ t: CGFloat) -> (CGFloat) -> CGFloat {
    { s in lerp(a(s), b(s), t) }
}

// MARK: - 背骨

struct SpinePoint {
    var p: CGPoint
    var dir: CGVector
    var normal: CGVector  // お腹側
}

func spine(_ pose: Pose) -> [SpinePoint] {
    if let rig = pose.rig { return rig.spine }
    var pts: [SpinePoint] = []
    var p = pose.snout
    let steps = 120
    let ds = bodyLength / CGFloat(steps)
    for i in 0 ... steps {
        let a = pose.angle(CGFloat(i) * ds)
        let dir = CGVector(dx: sin(a), dy: cos(a))
        let normal = CGVector(dx: cos(a), dy: -sin(a))
        pts.append(SpinePoint(p: p, dir: dir, normal: normal))
        p.x += dir.dx * ds
        p.y += dir.dy * ds
    }
    return pts
}

/// 背骨の外接矩形の中心が target に来るよう、鼻先の位置を求める
func snoutCentering(_ angle: @escaping (CGFloat) -> CGFloat, at target: CGPoint) -> CGPoint {
    let pts = spine(Pose(snout: .zero, angle: angle))
    let xs = pts.map(\.p.x), ys = pts.map(\.p.y)
    let cx = (xs.min()! + xs.max()!) / 2, cy = (ys.min()! + ys.max()!) / 2
    return CGPoint(x: target.x - cx, y: target.y - cy)
}

/// 背骨の最も低い点（y最大）+ 体の太さが floorY に接するよう、鼻先の位置を求める
func snoutResting(_ angle: @escaping (CGFloat) -> CGFloat, centerX: CGFloat, floorY: CGFloat) -> CGPoint {
    let pts = spine(Pose(snout: .zero, angle: angle))
    var bottom = -CGFloat.infinity
    for (i, sp) in pts.enumerated() {
        let s = CGFloat(i) / CGFloat(pts.count - 1) * bodyLength
        bottom = max(bottom, sp.p.y + radius(at: s))
    }
    let xs = pts.map(\.p.x)
    let cx = (xs.min()! + xs.max()!) / 2
    return CGPoint(x: centerX - cx, y: floorY - bottom)
}

func point(_ pts: [SpinePoint], at s: CGFloat) -> SpinePoint {
    let i = Int((s / bodyLength * CGFloat(pts.count - 1)).rounded())
    return pts[min(max(i, 0), pts.count - 1)]
}

func offset(_ p: CGPoint, _ v: CGVector, _ k: CGFloat) -> CGPoint {
    CGPoint(x: p.x + v.dx * k, y: p.y + v.dy * k)
}

// MARK: - 色

struct Palette {
    var isMono: Bool
    var rope: CGColor
    var ropeShade: CGColor?
    var body: CGColor
    var belly: CGColor?
    var paw: CGColor
    var outline: CGColor?
    var eye: CGColor?
    var z: CGColor
    var spark: CGColor
    var alert: CGColor
    var sweat: CGColor
    var pebble: CGColor
}

let black = CGColor(gray: 0, alpha: 1)
let mono = Palette(
    isMono: true, rope: black, ropeShade: nil, body: black, belly: nil, paw: black, outline: nil, eye: nil,
    z: black, spark: black, alert: black, sweat: black, pebble: black
)
let color = Palette(
    isMono: false,
    rope: CGColor(srgbRed: 0.82, green: 0.66, blue: 0.40, alpha: 1),
    ropeShade: CGColor(srgbRed: 0.55, green: 0.40, blue: 0.20, alpha: 1),
    body: CGColor(srgbRed: 0.47, green: 0.31, blue: 0.20, alpha: 1),
    belly: CGColor(srgbRed: 0.90, green: 0.79, blue: 0.62, alpha: 1),
    paw: CGColor(srgbRed: 0.33, green: 0.21, blue: 0.13, alpha: 1),
    outline: CGColor(srgbRed: 0.22, green: 0.13, blue: 0.08, alpha: 1),
    eye: CGColor(srgbRed: 0.08, green: 0.05, blue: 0.03, alpha: 1),
    z: CGColor(srgbRed: 0.55, green: 0.75, blue: 1.00, alpha: 1),
    spark: CGColor(srgbRed: 1.00, green: 0.83, blue: 0.25, alpha: 1),
    alert: CGColor(srgbRed: 1.00, green: 0.35, blue: 0.30, alpha: 1),
    sweat: CGColor(srgbRed: 0.55, green: 0.80, blue: 1.00, alpha: 1),
    pebble: CGColor(srgbRed: 0.70, green: 0.70, blue: 0.72, alpha: 1)
)

// MARK: - 描画

func circle(_ ctx: CGContext, _ c: CGPoint, _ r: CGFloat) {
    ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

func bodyPath(_ pts: [SpinePoint], scale: CGFloat, grow: CGFloat) -> CGPath {
    let path = CGMutablePath()
    for (i, sp) in pts.enumerated() where i % 2 == 0 {
        let s = CGFloat(i) / CGFloat(pts.count - 1) * bodyLength
        let r = radius(at: s) * scale + grow
        path.addEllipse(in: CGRect(x: sp.p.x - r, y: sp.p.y - r, width: r * 2, height: r * 2))
    }
    return path
}

func drawExtra(_ ctx: CGContext, _ extra: Extra, _ pal: Palette) {
    ctx.saveGState()
    defer { ctx.restoreGState() }
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    switch extra {
    case let .z(p, w):
        ctx.setStrokeColor(pal.z)
        ctx.setLineWidth(max(0.8, w * 0.28))
        ctx.move(to: p)
        ctx.addLine(to: CGPoint(x: p.x + w, y: p.y))
        ctx.addLine(to: CGPoint(x: p.x, y: p.y + w))
        ctx.addLine(to: CGPoint(x: p.x + w, y: p.y + w))
        ctx.strokePath()
    case let .spark(p, r):
        ctx.setFillColor(pal.spark)
        let path = CGMutablePath()
        let k = r * 0.28
        path.move(to: CGPoint(x: p.x, y: p.y - r))
        path.addLine(to: CGPoint(x: p.x + k, y: p.y - k))
        path.addLine(to: CGPoint(x: p.x + r, y: p.y))
        path.addLine(to: CGPoint(x: p.x + k, y: p.y + k))
        path.addLine(to: CGPoint(x: p.x, y: p.y + r))
        path.addLine(to: CGPoint(x: p.x - k, y: p.y + k))
        path.addLine(to: CGPoint(x: p.x - r, y: p.y))
        path.addLine(to: CGPoint(x: p.x - k, y: p.y - k))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    case let .exclaim(p):
        ctx.setStrokeColor(pal.alert)
        ctx.setFillColor(pal.alert)
        ctx.setLineWidth(1.6)
        ctx.move(to: p)
        ctx.addLine(to: CGPoint(x: p.x, y: p.y + 4.2))
        ctx.strokePath()
        circle(ctx, CGPoint(x: p.x, y: p.y + 6.6), 0.9)
        ctx.fillPath()
    case let .sweat(p):
        ctx.setFillColor(pal.sweat)
        circle(ctx, CGPoint(x: p.x, y: p.y + 1.0), 1.0)
        ctx.fillPath()
        ctx.move(to: CGPoint(x: p.x - 0.95, y: p.y + 0.8))
        ctx.addLine(to: CGPoint(x: p.x, y: p.y - 1.4))
        ctx.addLine(to: CGPoint(x: p.x + 0.95, y: p.y + 0.8))
        ctx.closePath()
        ctx.fillPath()
    case let .pebble(p):
        ctx.setFillColor(pal.pebble)
        circle(ctx, p, 1.25)
        ctx.fillPath()
    case let .motion(phi):
        ctx.setStrokeColor(pal.isMono ? CGColor(gray: 0, alpha: 0.55) : CGColor(gray: 1, alpha: 0.55))
        ctx.setLineWidth(0.9)
        for (r, h, span) in [(CGFloat(12.5), CGFloat(8.0), CGFloat(1.1)), (16.0, 11.0, 0.8)] {
            // 体の後ろ（回転の逆方向）に、回転面の楕円の弧を描く
            let arc = stride(from: phi - 0.35 - span, through: phi - 0.35, by: 0.05).map {
                project(V3(x: r * cos($0), y: h, z: r * sin($0)))
            }
            ctx.addLines(between: arc)
            ctx.strokePath()
        }
    case let .dots(n):
        ctx.setFillColor(pal.z)
        for i in 0 ..< n {
            circle(ctx, CGPoint(x: 40 + CGFloat(i) * 3, y: 12), 0.9)
            ctx.fillPath()
        }
    }
}

func render(_ pose: Pose, _ pal: Palette, scale: CGFloat = 1) -> CGImage {
    let ctx = CGContext(
        data: nil, width: Int(CGFloat(canvasW) * scale), height: Int(CGFloat(canvasH) * scale),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.translateBy(x: 0, y: CGFloat(canvasH) * scale)
    ctx.scaleBy(x: scale, y: -scale)
    ctx.setShouldAntialias(true)
    ctx.translateBy(x: displayOrigin.x, y: displayOrigin.y)
    ctx.scaleBy(x: displayScale, y: displayScale)
    ctx.translateBy(x: -displayOrigin.x, y: -displayOrigin.y)

    let pts = spine(pose)
    let head = point(pts, at: 3.0)

    // ロープ
    let mouth = pose.rig?.mouth ?? pivot
    let ropeEnd: CGPoint
    switch pose.rope {
    case .held: ropeEnd = CGPoint(x: mouth.x, y: mouth.y + 0.5)
    case let .free(sway): ropeEnd = CGPoint(x: pivot.x + sway, y: pivot.y + 5)
    }
    // 2次ベジェが ropeBend を t=0.5 で通るよう制御点を逆算する
    let ropeCtrl = pose.rig.map { rig in
        CGPoint(x: 2 * rig.ropeBend.x - 0.5 * (pivot.x + ropeEnd.x), y: 2 * rig.ropeBend.y - 0.5 * (-1 + ropeEnd.y))
    } ?? CGPoint(x: pivot.x, y: pivot.y * 0.5)
    ctx.setLineCap(.round)
    for (c, w) in [(pal.ropeShade, CGFloat(1.5)), (pal.rope, pal.ropeShade == nil ? 1.0 : 0.85)] {
        guard let c else { continue }
        ctx.setStrokeColor(c)
        ctx.setLineWidth(w / displayScale)
        ctx.move(to: CGPoint(x: pivot.x, y: -1))
        ctx.addQuadCurve(to: ropeEnd, control: ropeCtrl)
        ctx.strokePath()
    }
    ctx.setFillColor(pal.ropeShade ?? pal.rope)
    let knotT: CGFloat = 0.82
    let knot = CGPoint(
        x: pow(1 - knotT, 2) * pivot.x + 2 * (1 - knotT) * knotT * ropeCtrl.x + knotT * knotT * ropeEnd.x,
        y: pow(1 - knotT, 2) * -1 + 2 * (1 - knotT) * knotT * ropeCtrl.y + knotT * knotT * ropeEnd.y
    )
    circle(ctx, knot, 0.85)
    ctx.fillPath()

    func stroke(_ base: CGPoint, _ tip: CGPoint, r: CGFloat) {
        if let outline = pal.outline {
            ctx.setStrokeColor(outline)
            ctx.setLineWidth(r * 2 + 1.0)
            ctx.move(to: base); ctx.addLine(to: tip); ctx.strokePath()
        }
        ctx.setStrokeColor(pal.paw)
        ctx.setLineWidth(r * 2)
        ctx.move(to: base); ctx.addLine(to: tip); ctx.strokePath()
    }
    func paw(at s: CGFloat, _ p: Paw, r: CGFloat) {
        let sp = point(pts, at: s)
        let base = offset(sp.p, sp.normal, radius(at: s) * pose.scale * 0.6)
        let v = CGVector(
            dx: sp.normal.dx * cos(p.tilt) - sp.dir.dx * sin(p.tilt),
            dy: sp.normal.dy * cos(p.tilt) - sp.dir.dy * sin(p.tilt)
        )
        stroke(base, offset(base, v, p.reach), r: r)
    }
    if let rig = pose.rig {
        rig.farLimbs.forEach { stroke($0.base, $0.tip, r: $0.r) }
    } else {
        paw(at: 11.0, pose.hindFar, r: 0.95)
        paw(at: 7.0, pose.frontFar, r: 0.85)
    }

    let earCenter = pose.rig?.ear ?? offset(offset(head.p, head.normal, -2.6 * pose.scale), head.dir, 0.9)
    if let outline = pal.outline {
        ctx.setFillColor(outline)
        ctx.addPath(bodyPath(pts, scale: pose.scale, grow: 0.55))
        ctx.fillPath()
        circle(ctx, earCenter, 1.55)
        ctx.fillPath()
    }
    ctx.setFillColor(pal.body)
    ctx.addPath(bodyPath(pts, scale: pose.scale, grow: 0))
    ctx.fillPath()
    circle(ctx, earCenter, 1.1)
    ctx.fillPath()

    if let belly = pal.belly {
        ctx.saveGState()
        ctx.addPath(bodyPath(pts, scale: pose.scale, grow: 0))
        ctx.clip()
        ctx.setFillColor(belly)
        for (i, sp) in pts.enumerated() where i % 2 == 0 {
            let s = CGFloat(i) / CGFloat(pts.count - 1) * bodyLength
            guard s < 11.5 else { break }
            let r = radius(at: s) * pose.scale
            circle(ctx, offset(sp.p, sp.normal, r * 0.95), r * (s < 5 ? 0.75 : 0.55) * (pose.rig == nil ? 1 : 0.75))
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    if let rig = pose.rig {
        rig.nearLimbs.forEach { stroke($0.base, $0.tip, r: $0.r) }
    } else {
        paw(at: 10.5, pose.hindNear, r: 1.0)
        paw(at: 6.6, pose.frontNear, r: 0.95)
    }

    // 目・鼻
    let eyePos = pose.rig?.eye ?? offset(offset(head.p, head.normal, 0.1), head.dir, -0.6 + pose.eyeShift)
    let nosePos = pose.rig?.nose ?? offset(point(pts, at: 0.5).p, point(pts, at: 0.5).normal, 0.7)
    ctx.saveGState()
    if pal.isMono {
        ctx.setBlendMode(.clear)
    }
    let eyeColor = pal.eye ?? black
    ctx.setFillColor(eyeColor)
    ctx.setStrokeColor(eyeColor)
    ctx.setLineCap(.round)
    switch pose.eye {
    case .open:
        circle(ctx, eyePos, pal.isMono ? 0.9 : 0.95); ctx.fillPath()
    case .wide:
        circle(ctx, eyePos, 1.25); ctx.fillPath()
    case .half:
        ctx.setLineWidth(1.1)
        ctx.move(to: offset(eyePos, head.normal, -0.9))
        ctx.addLine(to: offset(eyePos, head.normal, 0.9))
        ctx.strokePath()
    case .closed:
        ctx.setLineWidth(0.7)
        ctx.move(to: offset(eyePos, head.normal, -1.0))
        ctx.addLine(to: offset(eyePos, head.normal, 1.0))
        ctx.strokePath()
    case .dizzy:
        ctx.setLineWidth(0.6)
        ctx.move(to: CGPoint(x: eyePos.x - 0.9, y: eyePos.y - 0.9))
        ctx.addLine(to: CGPoint(x: eyePos.x + 0.9, y: eyePos.y + 0.9))
        ctx.move(to: CGPoint(x: eyePos.x - 0.9, y: eyePos.y + 0.9))
        ctx.addLine(to: CGPoint(x: eyePos.x + 0.9, y: eyePos.y - 0.9))
        ctx.strokePath()
    }
    ctx.restoreGState()
    if !pal.isMono {
        ctx.setFillColor(eyeColor)
        circle(ctx, nosePos, 0.8); ctx.fillPath()
        if pose.eye == .open || pose.eye == .wide {
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
            circle(ctx, CGPoint(x: eyePos.x - 0.3, y: eyePos.y - 0.35), 0.32); ctx.fillPath()
        }
    }

    for extra in pose.extras {
        drawExtra(ctx, extra, pal)
    }
    return ctx.makeImage()!
}

// MARK: - アニメーション定義

struct Animation {
    var name: String
    var frames: [Pose]
}

let hangPose = Pose(angle: hangingAngle(theta: 0))

// 床で丸まる寝姿（中心はキャンバス下寄り）
func sleepPose(breath: CGFloat) -> Pose {
    let angle = curledAngle(start: 1.9, turns: 0.82)
    var p = Pose(angle: angle)
    p.snout = snoutResting(angle, centerX: 31, floorY: 35.5)
    p.scale = 1 + 0.05 * breath
    p.eye = .closed
    p.rope = .free(sway: 0)
    p.frontNear = Paw(tilt: 1.4, reach: 1.6)
    p.frontFar = Paw(tilt: 1.2, reach: 1.2)
    p.hindNear = Paw(tilt: 0.6, reach: 1.6)
    p.hindFar = Paw(tilt: 0.4, reach: 1.2)
    return p
}

// 仰向けに寝転がる（石遊び・ずっこけ）。お腹が上を向く
func onBackAngle(kick: CGFloat) -> (CGFloat) -> CGFloat {
    { s in
        let u = s / bodyLength
        return .pi / 2 - 0.25 + 0.5 * u * u + kick * pow(u, 3)
    }
}

func onBackPose(kick: CGFloat) -> Pose {
    let angle = onBackAngle(kick: kick)
    var p = Pose(angle: angle)
    p.snout = snoutResting(angle, centerX: 32, floorY: 35.5)
    p.rope = .free(sway: 0)
    p.frontNear = Paw(tilt: 0.2, reach: 3.0)
    p.frontFar = Paw(tilt: -0.2, reach: 2.6)
    p.hindNear = Paw(tilt: -0.2, reach: 2.8)
    p.hindFar = Paw(tilt: -0.5, reach: 2.4)
    return p
}

func play() -> Animation {
    Animation(name: "play", frames: (0 ..< 24).map { i in
        Pose(rig: yawRig(phi: 2 * .pi * CGFloat(i) / 24))
    })
}

func build() -> Animation {
    Animation(name: "build", frames: (0 ..< 12).map { i in
        let phi = 2 * CGFloat.pi * CGFloat(i) / 12
        var p = Pose(rig: yawRig(phi: phi, cone: 0.85, lag: 1.6, ropeSwing: 0.42))
        p.eye = .wide
        p.extras = [.motion(phi)]
        return p
    })
}

func sleep() -> Animation {
    Animation(name: "sleep", frames: (0 ..< 12).map { i in
        let t = CGFloat(i) / 12
        var p = sleepPose(breath: sin(2 * .pi * t))
        // Z が2つ、ずれて立ち上る
        for k in 0 ..< 2 {
            let u = (t + CGFloat(k) * 0.5).truncatingRemainder(dividingBy: 1)
            let size = 2.0 + 1.6 * u
            p.extras.append(.z(CGPoint(x: 38 + 6 * u, y: 22 - 10 * u), size))
        }
        p.rope = .free(sway: 1.0 * sin(2 * .pi * t))
        return p
    })
}

func wake() -> Animation {
    let n = 12
    return Animation(name: "wake", frames: (0 ..< n).map { i in
        let sleepy = sleepPose(breath: 0)
        if i < 3 {
            var p = sleepy
            p.eye = .wide
            p.scale = 1.0 + (i == 1 ? 0.08 : 0)
            p.extras = [.exclaim(CGPoint(x: 42, y: 13 - CGFloat(i)))]
            return p
        }
        if i < 7 {
            // 跳ね起きてロープへ
            let t = ease(CGFloat(i - 2) / 4)
            var p = Pose(angle: blend(sleepy.angle, hangingAngle(theta: 0.35), t))
            p.snout = lerp(sleepy.snout, pivot, t)
            p.eye = .wide
            p.rope = .free(sway: 0)
            p.frontNear = Paw(tilt: 1.8 * t, reach: 3.8)
            return p
        }
        // ロープをくわえて揺れが収まる
        let d = CGFloat(i - 7) / CGFloat(n - 8)
        var p = Pose(angle: swayAngle(theta: 0.35 * cos(.pi * d * 1.5) * (1 - d), tail: -0.3 * (1 - d)))
        p.eye = i < 9 ? .wide : .open
        return p
    })
}

func celebrate() -> Animation {
    let n = 16
    return Animation(name: "celebrate", frames: (0 ..< n).map { i in
        if i < 3 {
            // ためる：体を縮める
            let t = CGFloat(i) / 2
            var p = Pose(angle: swayAngle(theta: 0, tail: 0.6 * t))
            p.scale = 1 + 0.06 * t
            p.eye = .closed
            return p
        }
        if i < 12 {
            // ロープを離してジャンプ、両手を上げる
            let t = CGFloat(i - 3) / 8
            let h = 4 * t * (1 - t)  // 0→1→0
            var p = Pose(angle: swayAngle(theta: 0.15 * sin(t * 2 * .pi), tail: 0.5 * sin(t * 4 * .pi)))
            p.snout = CGPoint(x: pivot.x + 10 * sin(.pi * t), y: pivot.y + 3 - 2.5 * h)
            p.rope = .free(sway: 1.5 * sin(t * 3 * .pi))
            p.eye = .closed
            p.frontNear = Paw(tilt: 2.4, reach: 4.6)
            p.frontFar = Paw(tilt: 2.0, reach: 4.2)
            p.hindNear = Paw(tilt: -0.6, reach: 3.6)
            p.hindFar = Paw(tilt: -0.9, reach: 3.4)
            let r = 2 + 10 * t
            for k in 0 ..< 4 {
                let a = CGFloat(k) * .pi / 2 + .pi / 4 + t
                let size = 2.2 * (1 - abs(t - 0.5))
                p.extras.append(.spark(CGPoint(x: p.snout.x + cos(a) * r * 1.4, y: p.snout.y + 9 + sin(a) * r * 0.45), size))
            }
            return p
        }
        // ロープに戻る
        let d = CGFloat(i - 12) / 3
        var p = Pose(angle: swayAngle(theta: 0.25 * (1 - d) * cos(.pi * d * 2), tail: 0.3 * (1 - d)))
        p.eye = .open
        if i == 12 { p.extras = [.spark(CGPoint(x: 42, y: 12), 2.2), .spark(CGPoint(x: 22, y: 15), 1.6)] }
        return p
    })
}

func fail() -> Animation {
    let n = 18
    let back = onBackPose(kick: 0)
    return Animation(name: "fail", frames: (0 ..< n).map { i in
        if i < 3 {
            var p = Pose(angle: swayAngle(theta: [0.25, -0.3, 0.35][i], tail: [-0.4, 0.4, -0.5][i]))
            p.eye = .wide
            p.extras = [.sweat(CGPoint(x: 38, y: 12))]
            return p
        }
        if i < 7 {
            // ロープから滑り落ちる：回転しながら床へ
            let t = ease(CGFloat(i - 3) / 3)
            let fallAngle = blend(hangingAngle(theta: 0.6), back.angle, t)
            var p = Pose(angle: fallAngle)
            p.snout = lerp(CGPoint(x: pivot.x, y: pivot.y + 2), back.snout, t)
            p.rope = .free(sway: 2.0 * (1 - t))
            p.eye = .wide
            p.frontNear = Paw(tilt: 2.4, reach: 4.0)
            p.hindNear = Paw(tilt: -1.0, reach: 3.6)
            return p
        }
        if i < 15 {
            // 仰向けでのびる。目が回る、星がくるくる
            var p = back
            p.eye = .dizzy
            p.rope = .free(sway: 0.8 * sin(CGFloat(i)))
            if i == 7 { p.scale = 0.92 }
            let t = CGFloat(i - 7) / 8
            let headPt = point(spine(p), at: 3.0).p
            for k in 0 ..< 2 {
                let a = 2 * .pi * (t * 1.5 + CGFloat(k) * 0.5)
                p.extras.append(.spark(CGPoint(x: headPt.x + cos(a) * 5.5, y: headPt.y - 5 + sin(a) * 1.8), 1.6))
            }
            return p
        }
        // 起き上がってロープへ戻る
        let t = ease(CGFloat(i - 14) / 3)
        var p = Pose(angle: blend(back.angle, swayAngle(theta: -0.2, tail: 0.2), t))
        p.snout = lerp(back.snout, pivot, t)
        p.rope = i == n - 1 ? .held : .free(sway: 0)
        p.eye = .open
        p.extras = [.sweat(CGPoint(x: 38, y: 12))]
        return p
    })
}

func faceWash() -> Animation {
    Animation(name: "face-wash", frames: (0 ..< 16).map { i in
        let t = CGFloat(i) / 16
        let rub = sin(t * 4 * .pi)
        var p = Pose(angle: swayAngle(theta: 0.06 * sin(t * 2 * .pi), tail: 0.25 * sin(t * 2 * .pi)))
        p.frontNear = Paw(tilt: 1.95 + 0.3 * rub, reach: 4.0 + 1.0 * rub)
        p.frontFar = Paw(tilt: 1.95 - 0.3 * rub, reach: 4.0 - 1.0 * rub)
        p.angle = swayAngle(theta: 0.1 * rub, tail: 0.3 * sin(t * 2 * .pi))
        p.eye = (i >= 2 && i <= 13) ? .closed : .open
        return p
    })
}

func lookAround() -> Animation {
    Animation(name: "look-around", frames: (0 ..< 14).map { i in
        let t = CGFloat(i) / 14
        let look = sin(t * 2 * .pi)
        var p = Pose(angle: swayAngle(theta: 0.28 * look, tail: -0.4 * look))
        p.eyeShift = 0.8 * look
        p.eye = (i == 7) ? .closed : .open
        return p
    })
}

func work() -> Animation {
    // 仰向けで小石をお手玉する（カワウソの石遊び）
    Animation(name: "work", frames: (0 ..< 12).map { i in
        let t = CGFloat(i) / 12
        var p = onBackPose(kick: 0.25 * sin(t * 2 * .pi))
        let pts = spine(p)
        let chest = point(pts, at: 6.6)
        let handY = chest.p.y - 5.5
        for k in 0 ..< 2 {
            let u = (t + CGFloat(k) * 0.5).truncatingRemainder(dividingBy: 1)
            // 高い弧で左→右へ投げ、低く右→左へ戻す（カスケード）
            let x = chest.p.x - 4 + 8 * (u < 0.5 ? u * 2 : 2 - u * 2)
            let y = u < 0.5 ? handY - 9 * sin(.pi * u * 2) : handY + 1 - 1.5 * sin(.pi * (u * 2 - 1))
            p.extras.append(.pebble(CGPoint(x: x, y: y)))
        }
        p.frontNear = Paw(tilt: 0.15 * sin(t * 4 * .pi), reach: 3.4)
        p.frontFar = Paw(tilt: -0.3 - 0.15 * sin(t * 4 * .pi), reach: 3.0)
        p.rope = .free(sway: 0.6 * sin(t * 2 * .pi))
        return p
    })
}

func wave() -> Animation {
    Animation(name: "wave", frames: (0 ..< 14).map { i in
        let t = CGFloat(i) / 14
        let w = sin(t * 6 * .pi)
        var p = Pose(angle: swayAngle(theta: 0.08 * sin(t * 2 * .pi), tail: 0.4 * w))
        p.frontNear = Paw(tilt: 2.25 + 0.45 * w, reach: 4.8)
        if i == 4 || i == 9 { p.extras = [.spark(CGPoint(x: 44, y: 9), 1.6)] }
        return p
    })
}

func drowsy() -> Animation {
    let n = 16
    return Animation(name: "drowsy", frames: (0 ..< n).map { i in
        let t = CGFloat(i) / CGFloat(n)
        // ゆっくり傾いてこっくり、最後にハッと起きる
        let nod = i < 13 ? 0.3 * sin(t * 1.3 * .pi) : 0
        var p = Pose(angle: swayAngle(theta: nod, tail: -0.2 * nod))
        p.scale = 1 + 0.03 * sin(t * 2 * .pi)
        switch i {
        case 0 ..< 3: p.eye = .open
        case 3 ..< 6: p.eye = .half
        case 6 ..< 13: p.eye = .closed
        default: p.eye = .wide
        }
        if (6 ..< 13).contains(i) {
            p.extras = [.dots(min(3, (i - 5) / 2 + 1))]
        }
        if i == 13 { p.extras = [.exclaim(CGPoint(x: 40, y: 8))] }
        return p
    })
}

let animations = [play(), sleep(), wake(), build(), celebrate(), fail(), faceWash(), lookAround(), work(), wave(), drowsy()]

// MARK: - 書き出し

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func upscaled(_ image: CGImage, by k: Int, background: CGColor?) -> CGImage {
    let w = image.width * k, h = image.height * k
    let ctx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    if let bg = background {
        ctx.setFillColor(bg); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
    ctx.interpolationQuality = .none
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

var args = Array(CommandLine.arguments.dropFirst())
// --icon <png>: アプリアイコン用の大きなシルエット（ロープにぶら下がって回る姿）だけを書き出して終了
if let i = args.firstIndex(of: "--icon"), i + 1 < args.count {
    let image = render(Pose(rig: yawRig(phi: 0.25)), mono, scale: 24)
    // 不透明な部分の外接矩形で切り抜く（ロープは上端まで残る）
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let probe = CGContext(
        data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    probe.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    var minX = image.width, maxX = 0, minY = image.height, maxY = 0
    for y in 0 ..< image.height {
        for x in 0 ..< image.width where pixels[(y * image.width + x) * 4 + 3] > 8 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
    // ロープを上に延ばし、アイコンの上端から垂れ下がって見えるようにする
    let topRow = (minX ... maxX).filter { pixels[(minY * image.width + $0) * 4 + 3] > 8 }
    let ropeX = CGFloat(topRow.reduce(0, +)) / CGFloat(topRow.count) - CGFloat(minX)
    let ropeWidth = CGFloat(topRow.count)
    let extension_ = 150
    let icon = CGContext(
        data: nil, width: cropped.width, height: cropped.height + extension_, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    icon.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
    icon.setFillColor(black)
    icon.fill(CGRect(x: ropeX - ropeWidth / 2, y: CGFloat(cropped.height) - 2, width: ropeWidth, height: CGFloat(extension_) + 2))
    let output = icon.makeImage()!
    writePNG(output, to: URL(fileURLWithPath: args[i + 1]))
    print("icon \(output.width)x\(output.height)")
    exit(0)
}
var assetsDir: URL?
if let i = args.firstIndex(of: "--assets"), i + 1 < args.count {
    assetsDir = URL(fileURLWithPath: args[i + 1])
    args.removeSubrange(i ... i + 1)
}
let outDir = URL(fileURLWithPath: args.first ?? "frames")
let fm = FileManager.default
let light = CGColor(gray: 0.93, alpha: 1), dark = CGColor(gray: 0.16, alpha: 1)
try? fm.createDirectory(at: outDir.appending(path: "preview"), withIntermediateDirectories: true)

let assetJSON = #"{"info":{"author":"xcode","version":1}}"#
if let assetsDir {
    let otterDir = assetsDir.appending(path: "Otter")
    try? fm.removeItem(at: otterDir)
    try fm.createDirectory(at: otterDir, withIntermediateDirectories: true)
    try assetJSON.write(to: otterDir.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
}

var sheetRows: [[CGImage]] = []
for anim in animations {
    var monoFrames: [CGImage] = [], colorFrames: [CGImage] = []
    for sub in ["mono", "color"] {
        try? fm.createDirectory(at: outDir.appending(path: "\(anim.name)/\(sub)"), withIntermediateDirectories: true)
    }
    for (i, pose) in anim.frames.enumerated() {
        let m = render(pose, mono), c = render(pose, color)
        let name = String(format: "frame-%02d.png", i)
        writePNG(m, to: outDir.appending(path: "\(anim.name)/mono/\(name)"))
        writePNG(c, to: outDir.appending(path: "\(anim.name)/color/\(name)"))
        monoFrames.append(m); colorFrames.append(c)
        if let assetsDir {
            let resource = anim.name == "play" ? "otter-frame-\(i)" : "otter-\(anim.name)-frame-\(i)"
            let set = assetsDir.appending(path: "Otter/\(resource).imageset")
            try fm.createDirectory(at: set, withIntermediateDirectories: true)
            writePNG(m, to: set.appending(path: "\(resource).png"))
            let json = #"{"images":[{"filename":"\#(resource).png","idiom":"mac"}],"info":{"author":"xcode","version":1}}"#
            try json.write(to: set.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
        }
    }
    sheetRows.append(monoFrames)
    sheetRows.append(colorFrames)

    let gifURL = outDir.appending(path: "preview/\(anim.name).gif")
    let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, colorFrames.count, nil)!
    CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for img in colorFrames {
        CGImageDestinationAddImage(
            gif, upscaled(img, by: 4, background: dark),
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: anim.name == "play" ? 0.06 : 0.09]] as CFDictionary
        )
    }
    CGImageDestinationFinalize(gif)
}

// 全アニメーションのコンタクトシート（各アニメーション mono/color の2行、3倍）
let zoom = 3, maxCols = sheetRows.map(\.count).max()!
let cellW = canvasW * zoom, cellH = canvasH * zoom
let sheet = CGContext(
    data: nil, width: cellW * maxCols, height: cellH * sheetRows.count, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
sheet.setFillColor(CGColor(gray: 0.6, alpha: 1))
sheet.fill(CGRect(x: 0, y: 0, width: cellW * maxCols, height: cellH * sheetRows.count))
for (r, row) in sheetRows.enumerated() {
    let y = cellH * (sheetRows.count - 1 - r)
    for (c, img) in row.enumerated() {
        sheet.draw(upscaled(img, by: zoom, background: r % 2 == 0 ? light : dark), in: CGRect(x: c * cellW, y: y, width: cellW, height: cellH))
    }
}
writePNG(sheet.makeImage()!, to: outDir.appending(path: "preview/sheet.png"))

print("Rendered \(animations.map { "\($0.name)×\($0.frames.count)" }.joined(separator: ", "))")

// アニメーションごとの拡大シート（color、4倍、6列）
for (k, anim) in animations.enumerated() {
    let frames = sheetRows[k * 2 + 1]
    let z = 4, cols = 6, rows = (frames.count + cols - 1) / cols
    let cw = canvasW * z, ch = canvasH * z
    let ctx = CGContext(
        data: nil, width: cw * cols, height: ch * rows, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(CGColor(gray: 0.6, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: cw * cols, height: ch * rows))
    for (i, img) in frames.enumerated() {
        let x = (i % cols) * cw, y = ch * (rows - 1 - i / cols)
        ctx.draw(upscaled(img, by: z, background: dark), in: CGRect(x: x + 1, y: y + 1, width: cw - 2, height: ch - 2))
    }
    writePNG(ctx.makeImage()!, to: outDir.appending(path: "preview/\(anim.name).png"))
}
