// Metal port of RhineDroid app/src/main/materials/archive.mat
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
//
// Translation notes (GLSL -> MSL):
//  - GLSL mod() floors; MSL fmod() truncates, so `gmod` is used everywhere.
//  - GLSL mat2(a,b,c,d) is column-major; rotations are written out explicitly.
//  - pow(x, 2.0) / pow(x, 6.0) on possibly negative bases are written as products
//    (MSL pow() returns NaN for negative bases; the intent upstream is a Gaussian).
//  - Everything in materialVertex that depends only on the instance (offsets, opening wave, tilt,
//    focus gain, guidance ribbon) runs once per instance in `archiveInstances` instead of once per
//    vertex. The math is unchanged; only where it is evaluated moved.
import Foundation

enum ArchiveShaders {
    static let poolCount = ShelfLayout.count
    static let selected = ShelfLayout.selected

    static func source() -> String {
        prelude + curves() + archive + post
    }

    /// Same monotone Hermite segments that build-vulkan-assets.mjs splices into the Filament material.
    static func curves() -> String {
        func n(_ v: Double) -> String { String(format: "%.9f", v) }
        return [("GROW", DecryptionCurve.grow), ("REVEAL", .reveal), ("RETRACT", .retract)].map { name, curve in
            let k = curve.knots, m = curve.slopes
            var s = "static inline float curve\(name)(float time) { if (time <= \(n(k[0].0))) return \(n(k[0].1));"
            for i in 0..<(k.count - 1) {
                let span = k[i + 1].0 - k[i].0
                s += " if (time < \(n(k[i + 1].0))) { float t = (time - \(n(k[i].0))) / \(n(span));"
                s += " return (2.0*t*t*t - 3.0*t*t + 1.0) * \(n(k[i].1)) + (t*t*t - 2.0*t*t + t) * \(n(span * m[i]))"
                s += " + (-2.0*t*t*t + 3.0*t*t) * \(n(k[i + 1].1)) + (t*t*t - t*t) * \(n(span * m[i + 1])); }"
            }
            return s + " return \(n(k[k.count - 1].1)); }\n"
        }.joined()
    }

    static let prelude = """
    #include <metal_stdlib>
    using namespace metal;

    constant uint POOL = \(poolCount);
    constant uint SELECTED = \(selected);

    struct Params {
        float4x4 viewProjection;
        float4 camera;    // world position
        float4 travel;    // travel start, travel seconds, clock, opening (-1 = browsing)
        float4 grids;     // openingGrid.xy, poolGrid.xy
        float4 guidance;  // strength, width, offset, fill
        float4 a;         // inspection, idle, placement, rotation
        float4 b;         // kind, night, optics, focus
        float4 c;         // focusCenter.xy, guideCenter.xy
        float4 d;         // selectedReady
        uint4 playA;      // pool slots showing the playing song, bits 0-127
        uint4 playB;      // bits 128-255
    };
    // hires: x = hi-res array slice (−1 = thumbnail only), y = time the slice became resident.
    struct Pose { float4 cells[POOL]; float4 origins[POOL]; float4 velocities[POOL]; float4 accelerations[POOL]; float4 hires[POOL]; };
    struct Instance {
        float4 offset;    // world offset xyz, extent
        float4 rot;       // tilt cos/sin (yz), turn cos/sin (xz)
        float4 cover;     // atlas tile xy, selection band, focus gain
        float4 shade;     // selected, cell.w, surfaceNormal.w, cover mip bias
        float4 extra;     // playing glow, hi-res slice, hi-res resident time
    };
    struct Vertex { packed_float3 position; packed_float3 normal; packed_float2 uv; };
    struct Varyings {
        float4 position [[position]];
        float4 coverUv;
        float4 surfaceNormal;
        float4 shade;
        float4 casePosition;
        float3 world;
        float3 flags;     // playing glow, hi-res slice (−1 = none), hi-res resident time
    };

    static inline float gmod(float x, float y) { return x - y * floor(x / y); }

    """

    static let archive = """
    static inline float ease5(float value) { float t = saturate(value); return t*t*t*(10.0+t*(-15.0+6.0*t)); }
    static inline float bell(float x, float width) { float q = x / width; return exp(-0.5*q*q); }
    static inline float focusWeight(float lanes, float rows) { return 1.0-smoothstep(1.15,4.5,sqrt(lanes*lanes+rows*rows/9.0)); }
    static inline float introRowOffset(float time) {
        return time<24.15 ? -9.0+27.0*ease5((time-22.2)/1.95) : 18.0*(1.0-ease5((time-24.15)/1.6));
    }
    static inline float introEntryZ(float time) { float entry=saturate((time-21.92)/0.75); return -23.0*(1.0-entry)*(1.0-entry); }
    static inline float selectionBand(float index, float rows, float center) {
        float row=gmod(index,rows)-floor(rows/2.0);
        return 1.0-smoothstep(1.0,2.0,abs(row-center));
    }
    static inline float shoulder(float row, float time) {
        float age=time-25.05-abs(row)*0.065;
        float envelope=max(-0.42,2.15-0.17*(sqrt(row*row+1.0)-1.0));
        float ring=age>0.0?sin(age*5.1)*exp(-age*1.3):0.0;
        float rebound=mix(0.06,0.18,ease5((time-26.2)/0.36));
        return envelope*(ease5(age/0.62)+rebound*ring*ease5(age/0.16));
    }
    static inline float strength(float lane) { return 0.25+0.75*bell(lane,0.55); }
    static inline float packet(float distance) { return 2.5*bell(distance,3.8)-0.58*bell(distance-6.0,3.5); }
    static inline float openingField(float row, float lane, float time) {
        float t=time-22.0, phase=row+(lane-2.0)*0.65;
        float wave=ease5(t/0.32)*(packet(phase-3.0-t*19.0)*(1.0-ease5((t-2.15)/0.65))
            +packet(phase-32.0+(t-2.3)*24.0)*ease5((t-2.17)/0.32)*(1.0-ease5((t-3.5)/0.85)));
        float handoff=ease5((time-24.95)/0.45), selection=ease5((time-25.4)/0.95);
        return 0.62*wave*(1.0-handoff)+shoulder(row-12.0,time+0.3*handoff*(1.0-selection))*mix(1.0,strength(lane-2.0),selection);
    }

    // Per-instance half of materialVertex: one thread per drawn instance per frame.
    kernel void archiveInstances(uint iid [[thread_position_in_grid]],
                                 constant Params &P [[buffer(1)]],
                                 constant Pose &pose [[buffer(2)]],
                                 device Instance *instances [[buffer(3)]],
                                 constant uint &count [[buffer(4)]]) {
        if (iid >= count) return;
        float clock = P.travel.z, openingTime = P.travel.w;
        float2 openingGrid = P.grids.xy, poolGrid = P.grids.zw;
        bool opening = openingTime >= 0.0;
        float instance = float(iid);
        float row = opening ? gmod(instance,openingGrid.y)-floor(openingGrid.y/2.0) : 0.0;
        float lane = opening ? floor(instance/openingGrid.y)-floor(openingGrid.x/2.0) : 0.0;
        uint slot = opening ? uint(gmod(lane+floor(poolGrid.x/2.0)+poolGrid.x,poolGrid.x)*poolGrid.y
            +gmod(row+floor(poolGrid.y/2.0)+poolGrid.y,poolGrid.y)) : iid % POOL;
        float4 cell = pose.cells[slot];
        float seconds = max(0.001, P.travel.y);
        float t = saturate((clock - P.travel.x) / seconds);
        float t2 = t*t, t3 = t2*t, t4 = t3*t, t5 = t4*t;
        float eased = 10.0*t3 - 15.0*t4 + 6.0*t5;
        float3 offset = mix(pose.origins[slot].xyz, cell.xyz, eased)
            + pose.velocities[slot].xyz * seconds * (t - 6.0*t3 + 8.0*t4 - 3.0*t5)
            + 0.5 * pose.accelerations[slot].xyz * seconds * seconds * (t2 - 3.0*t3 + 3.0*t4 - t5);
        if (!opening) { row=cell.z/0.62; lane=cell.x/5.2; }
        bool selected = opening ? (row==0.0 && lane==0.0) : slot == SELECTED;
        float extent=1.0;
        if (opening) {
            float time=openingTime, blend=ease5((time-25.3)/1.42);
            float lift=0.4*ease5((time-25.58)/0.82)+2.95*ease5((time-27.55)/1.3);
            offset.x=lane*5.2; offset.z=row*0.62+introEntryZ(time);
            extent=(abs(row)>floor(poolGrid.y/2.0) || abs(lane)>floor(poolGrid.x/2.0) || cell.w==0.0) ? 1.0-blend : 1.0;
            if (cell.w==0.0) cell.w=-1.0;
            offset.y=-4.6+mix(openingField(row+12.0,lane+2.0,time),shoulder(row,26.56)*strength(lane),blend)
                +(selected?mix(lift,0.9,blend):0.0);
        }
        float worldRow=pose.origins[slot].w, worldLane=pose.velocities[slot].w;
        float idle = P.a.y;
        if (idle>0.0001) offset.y += idle*(0.075*sin(clock*6.2831853/8.0+worldRow*0.3-worldLane*0.45)
            +0.027*sin(clock*6.2831853/13.0-worldRow*0.17+worldLane*0.3));
        float focusGain = P.b.w>0.5 && !opening ? (selected ? 1.0 : focusWeight(
            (offset.x-P.c.x)/5.2,(offset.z-P.c.y)/0.62)) : 1.0;
        float slope=pose.accelerations[slot].w*(1.0-P.a.z);
        if (opening) {
            float time=openingTime, blend=ease5((time-25.3)/1.42);
            float openingSlope=openingField(row+12.5,lane+2.0,time)-openingField(row+11.5,lane+2.0,time);
            slope=mix(openingSlope*0.024,slope,blend);
        }
        float tile = abs(cell.w) - 1.0;
        float lightRow = opening ? introRowOffset(openingTime) : 0.0;
        // Selection-band highlight kept only for the opening film; while browsing, only the playing
        // case is lit (playing glow below).
        float band = opening ? selectionBand(instance, openingGrid.y, lightRow) * ease5((openingTime-21.92)/0.18) : 0.0;
        float lightZ = opening ? lightRow*0.62 : P.c.w;
        float rz = ((opening ? row*0.62 : offset.z) - lightZ - P.guidance.z*0.62) / max(0.1, P.guidance.y*0.31);
        float rx = (offset.x - P.c.z) / 27.0, rx2 = rx*rx;
        float ribbon = exp(-0.693147*rz*rz) * exp(-rx2*rx2*rx2);
        float normalW = mix(1.0, 0.65+0.25*P.guidance.w+0.10*clamp(ribbon*P.guidance.x,0.0,2.0), saturate(P.guidance.x));
        float angle = selected ? P.a.w : 0.0;

        Instance I;
        I.offset = float4(offset, extent);
        I.rot = float4(cos(slope), sin(slope), cos(angle), sin(angle));
        I.cover = float4(gmod(tile,16.0), floor(tile/16.0), band, focusGain);
        I.shade = float4(selected ? 1.0 : 0.0, cell.w, normalW, 1.25*(1.0-focusGain));
        uint word = slot >> 5;
        uint bits = word < 4u ? P.playA[word] : P.playB[word - 4u];
        float playing = (!opening && ((bits >> (slot & 31u)) & 1u) != 0u) ? 1.0 : 0.0;
        float4 hi = pose.hires[slot];
        // The upstream spine/top highlight now marks the playing case instead of the selection band.
        if (!opening) I.cover.z = playing;
        I.extra = float4(playing, opening ? -1.0 : hi.x, hi.y, 0.0);
        instances[iid] = I;
    }

    // Per-vertex half of materialVertex.
    vertex Varyings archiveVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                  const device Vertex *vertices [[buffer(0)]],
                                  constant Params &P [[buffer(1)]],
                                  const device Instance *instances [[buffer(3)]]) {
        Vertex v = vertices[vid];
        Instance I = instances[iid];
        float3 p = float3(v.position);
        float4 casePosition = float4(p, I.shade.w);
        p = (p-float3(0.0,1.85,0.0))*I.offset.w+float3(0.0,1.85,0.0);
        float3 normal = float3(v.normal);
        // tilt = mat2(cos,sin,-sin,cos) applied to .yz
        float cs = I.rot.x, sn = I.rot.y;
        p.yz = float2(cs*p.y - sn*p.z, sn*p.y + cs*p.z);
        normal.yz = float2(cs*normal.y - sn*normal.z, sn*normal.y + cs*normal.z);
        // turn = mat2(cos,-sin,sin,cos) applied to .xz (identity unless selected)
        float c = I.rot.z, s = I.rot.w;
        p.xz = float2(c*p.x + s*p.z, -s*p.x + c*p.z);
        normal.xz = float2(c*normal.x + s*normal.z, -s*normal.x + c*normal.z);
        p += I.offset.xyz;
        if (I.shade.y == 0.0) p = float3(0.0, -1000.0, 0.0);

        Varyings out;
        out.world = p;
        out.position = P.viewProjection * float4(p, 1.0);
        float2 uv = float2(v.uv);
        out.coverUv = float4((I.cover.xy + clamp(uv,0.03125,0.96875)) / 16.0, I.cover.z, I.cover.w);
        out.surfaceNormal = float4(normal, I.shade.z);
        out.shade = float4(I.shade.x, I.shade.y, uv.x, uv.y);
        out.casePosition = casePosition;
        out.flags = I.extra.xyz;
        return out;
    }

    static inline float clearWindow(float x, float y) {
        return (1.0-smoothstep(1.50,1.55,abs(x-0.17)))*(1.0-smoothstep(1.50,1.55,abs(y-1.85)));
    }
    static inline float topRibbon(float x, float y) {
        return exp(-max(0.0,3.525-y)*24.0)*(0.22+0.78*exp(-max(0.0,x-(\(ArchiveMesh.spineEdge)))*1.7));
    }
    // Not upstream: matching light along the bottom edge, used to define the lifted case.
    static inline float bottomRibbon(float y) { return exp(-max(0.0,y-0.175)*24.0); }
    static inline float acrylicOpacity(float window, float spine, float rim, float lid) {
        // Spine (Ivory_Edges) opacity raised from upstream's 0.22 so the ivory edge reads as solid.
        // Shell outside the spine made clearer than upstream (0.32 → 0.20) so the ivory edge stands out.
        return mix(0.20-0.05*lid,0.012+0.008*lid,window)+0.56*spine+0.20*rim;
    }

    fragment float4 archiveFragment(Varyings in [[stage_in]],
                                    constant Params &P [[buffer(1)]],
                                    texture2d<float> covers [[texture(0)]],
                                    texture2d_array<float> hires [[texture(1)]],
                                    sampler trilinear [[sampler(0)]]) {
        float kind = P.b.x, night = P.b.y, optics = P.b.z, focus = P.b.w;
        float opening = P.travel.w;
        float3 n = normalize(in.surfaceNormal.xyz);
        // normalize(float3(-0.5, 0.8, 0.4))
        float light = 0.56 + 0.44 * abs(dot(n, float3(-0.48795004, 0.78072006, 0.39036003)));
        float3 paper = float3(0.62, 0.63, 0.59);
        bool ready = in.flags.y >= 0.0;
        uint slice = uint(max(in.flags.y, 0.0));
        if (kind > 1.5) {
            if (in.shade.y > 0.0) paper = covers.sample(trilinear, in.coverUv.xy, bias(in.casePosition.w)).rgb;
            // Cards in the hi-res window draw their 1024² cover (same focus bias), cross-fading in once
            // when it becomes resident, so nothing swaps resolution while large on screen.
            if (ready) {
                float fade = saturate((P.travel.z - in.flags.z) / 0.35);
                paper = mix(paper, hires.sample(trilinear, in.shade.zw, slice, bias(in.casePosition.w)).rgb, fade);
            }
        }
        if (in.shade.x > 0.5 && kind > 1.5 && ready && P.a.x >= 0.0) {
            float inspectionTime = 34.12 + max(0.0, P.travel.z - P.a.x) * 1.5;
            float clarity = curveREVEAL(inspectionTime);
            if (clarity < 0.999) {
                float2 uv = in.shade.zw;
                paper = hires.sample(trilinear, uv, slice, level(3.0*(1.0-clarity))).rgb;
                float2 position = float2(0.17,1.85) + (uv-0.5)*3.06;
                float2 from = float2(-1.6,0.5), to = float2(1.98,3.24), axis = to-from;
                float along = dot(position-from,axis)/dot(axis,axis);
                float perpendicular = abs((position.x-from.x)*axis.y-(position.y-from.y)*axis.x)/length(axis);
                float grow = curveGROW(inspectionTime), remaining = curveRETRACT(inspectionTime);
                float line = (1.0-smoothstep(0.008,0.025,perpendicular))*step(1.0-remaining,along)*step(along,grow);
                paper = mix(paper, float3(0.95,0.65,0.31), line);
            }
        }
        paper *= in.surfaceNormal.w;
        float3 frame = mix(float3(0.80,0.79,0.73), float3(0.075,0.105,0.14), night);
        float3 color = kind > 1.5 ? paper : frame * light;
        float alpha = 1.0;
        if (kind < 1.5) {
            float3 viewDir = normalize(P.camera.xyz - in.world);
            float facing = saturate(1.0-abs(dot(n, viewDir)));
            float rim = facing*facing*facing;
            float spine = kind < 0.5 ? in.shade.z : 0.0;
            float lid = step(0.5, kind);
            float2 local = in.casePosition.xy;
            float window = clearWindow(local.x, local.y);
            float top = topRibbon(local.x, local.y);
            float lip = 1.0-smoothstep(0.012,0.036,abs(max(abs(local.x-0.17),abs(local.y-1.85))-1.53));
            float highlight = (spine*(0.55+0.45*rim)+top*0.9)*in.coverUv.z*clamp(P.guidance.x,0.0,2.0)*(0.3+0.7*in.coverUv.w);
            float3 reflection = mix(float3(0.92,0.96,1.0), float3(0.48,0.66,0.82), night);
            float3 scatter = mix(float3(1.0,0.75,0.40), float3(0.62,0.79,1.0), night);
            color = frame*light*mix(0.86,1.0,lid)*(1.0-0.12*lip) + reflection*(rim*0.22+top*0.08);
            color += scatter*highlight;
            if (focus > 0.5 && opening < 0.0)
                color += reflection*0.12*in.coverUv.w*(rim+0.6*top);
            if (optics > 0.0) {
                float q = (local.x+local.y*0.55-0.4)/0.70;
                float sweep = exp(-q*q);
                color += reflection*optics*(0.35*rim+top*(0.22+in.coverUv.z*clamp(P.guidance.x,0.0,2.0))+0.10*sweep);
            }
            // Not upstream: a faint --accent edge light on the case of the playing song.
            float edge = 1.0-smoothstep(0.012,0.07,abs(max(abs(local.x-0.17),abs(local.y-1.85))-1.53));
            float glow = in.flags.x * (0.5*rim + 0.4*top + 0.5*edge + 0.35*spine);
            color += mix(float3(0.462,0.138,0.034), float3(0.693,0.423,0.205), night) * glow * 1.2;
            // Not upstream: the lifted case gets a denser shell, a lit bottom edge and a stronger lip so its
            // lower half reads against the shelf behind it. Fades in with the placement.
            float lifted = in.shade.x * P.a.z;
            float bottom = bottomRibbon(local.y);
            color = mix(color, color*0.82, lifted*0.35*(1.0-window));
            color += reflection*lifted*(0.30*bottom + 0.16*top + 0.12*lip + 0.10*rim);
            alpha = clamp(acrylicOpacity(window,spine,rim,lid)+0.06*lip+0.08*top+0.16*highlight+0.10*glow
                          + lifted*(0.05*(1.0-window) + 0.30*bottom + 0.12*lip), 0.0, 0.96);
        }
        return float4(color*alpha, alpha);
    }

    """

    /// Post-processing standing in for Filament's View: depth of field at quarter resolution like
    /// Filament's default (nativeResolution = false, cocScale 12, max CoC 1 / 2 px), then FXAA, the
    /// fixed dynamic-resolution upscale and the DoF composite in one output pass.
    static let post = """
    struct Screen { float4 position [[position]]; float2 uv; };

    vertex Screen fullscreen(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        Screen o;
        o.position = float4(p*2.0-1.0, 0.0, 1.0);
        o.uv = float2(p.x, 1.0-p.y);
        return o;
    }

    // lens: K (Filament cocScale * Ks * Kc), focus distance, near, far
    // limits: -maxForegroundCOC, maxBackgroundCOC, full-resolution texel.xy
    struct DofParams { float4 lens; float4 limits; };

    static inline float cocAt(depth2d<float> depth, sampler s, float2 uv, constant DofParams &D) {
        float d = depth.sample(s, uv);
        float n = D.lens.z, f = D.lens.w;
        float z = n * f / (f - d * (f - n));
        return clamp(D.lens.x * (1.0 - D.lens.y / z), D.limits.x, D.limits.y);
    }

    // Half-resolution gather; alpha carries the centre CoC (full-resolution pixels) for the composite.
    // A tap contributes when its own blur reaches this pixel; background taps may not bleed over a
    // sharper pixel in front of them.
    fragment float4 depthOfField(Screen in [[stage_in]],
                                 texture2d<float> color [[texture(0)]],
                                 depth2d<float> depth [[texture(1)]],
                                 constant DofParams &D [[buffer(0)]],
                                 sampler point [[sampler(0)]], sampler linear [[sampler(1)]]) {
        float center = cocAt(depth, point, in.uv, D);
        float3 sum = color.sample(linear, in.uv).rgb;
        float total = 1.0;
        float reach = max(-D.limits.x, D.limits.y);
        for (int i = 0; i < 8; i++) {
            float r = reach * sqrt((float(i)+0.5)/8.0);
            float a = float(i) * 2.39996323;
            float2 uv = in.uv + float2(cos(a), sin(a)) * r * D.limits.zw;
            float tap = cocAt(depth, point, uv, D);
            float w = saturate(abs(tap) - r + 0.5);
            if (tap > center) w = min(w, saturate(abs(center) - r + 0.5));
            sum += color.sample(linear, uv).rgb * w;
            total += w;
        }
        return float4(sum / total, center);
    }

    static inline float luma(float3 c) { return sqrt(dot(c, float3(0.299, 0.587, 0.114))); }

    // FXAA (console variant) at output resolution against the render-resolution source, which also
    // performs the bilinear upscale.
    static inline float3 fxaa(texture2d<float> source, sampler linear, float2 uv, float2 texel) {
        float3 m = source.sample(linear, uv).rgb;
        float lNW = luma(source.sample(linear, uv + float2(-0.5,-0.5)*texel).rgb);
        float lNE = luma(source.sample(linear, uv + float2( 0.5,-0.5)*texel).rgb);
        float lSW = luma(source.sample(linear, uv + float2(-0.5, 0.5)*texel).rgb);
        float lSE = luma(source.sample(linear, uv + float2( 0.5, 0.5)*texel).rgb);
        float lM = luma(m);
        float lMin = min(lM, min(min(lNW,lNE), min(lSW,lSE)));
        float lMax = max(lM, max(max(lNW,lNE), max(lSW,lSE)));
        if (lMax - lMin < max(0.0312, lMax*0.125)) return m;
        float2 dir = float2(-((lNW+lNE)-(lSW+lSE)), (lNW+lSW)-(lNE+lSE));
        float reduce = max((lNW+lNE+lSW+lSE)*0.03125, 1.0/128.0);
        float scale = 1.0/(min(abs(dir.x),abs(dir.y))+reduce);
        dir = clamp(dir*scale, -8.0, 8.0) * texel;
        float3 a = 0.5*(source.sample(linear, uv + dir*(1.0/3.0-0.5)).rgb + source.sample(linear, uv + dir*(2.0/3.0-0.5)).rgb);
        float3 b = a*0.5 + 0.25*(source.sample(linear, uv - dir*0.5).rgb + source.sample(linear, uv + dir*0.5).rgb);
        float lB = luma(b);
        return (lB < lMin || lB > lMax) ? a : b;
    }

    // F: source texel.xy, fxaa on, dof on
    fragment float4 present(Screen in [[stage_in]],
                            texture2d<float> source [[texture(0)]],
                            texture2d<float> blurred [[texture(1)]],
                            constant float4 &F [[buffer(0)]],
                            sampler linear [[sampler(0)]]) {
        float3 color = F.z > 0.5 ? fxaa(source, linear, in.uv, F.xy) : source.sample(linear, in.uv).rgb;
        if (F.w > 0.5) {
            float4 b = blurred.sample(linear, in.uv);
            color = mix(color, b.rgb, saturate(abs(b.a)));
        }
        return float4(color, 1.0);
    }
    """
}
