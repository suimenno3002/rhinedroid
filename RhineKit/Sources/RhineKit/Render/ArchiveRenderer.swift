// Metal replacement for the Filament pipeline in RhineDroid VulkanArchiveRenderer.kt
// (MIT, Copyright (c) 2026 LBEILC, Copyright (c) 2026 RonaldDeng).
import CoreGraphics
import Foundation
import Metal
import simd

/// Draws the shelf: a per-instance compute pass, opaque cover inserts, the two premultiplied acrylic
/// shells, quarter-resolution depth of field, then FXAA/upscale/DoF composite into the target.
/// Main-thread object.
public final class ArchiveRenderer {
    public let device: MTLDevice
    public let scene = ArchiveScene()
    /// Fraction of the target resolution rendered (upstream "scene-quality"); capped at 8.3 MP like upstream.
    public var renderScale: Double = 1 { didSet { scene.invalidate() } }
    public var fxaa = true
    public var debugKinds = [2, 0, 1]
    /// Upstream uses 128² tiles / 512² selection for phone screens; the 2388×1668 iPad panel shows shelf
    /// cards near 200 px and the inspected cover near 800 px, so both are doubled (atlas 64 MB + mips).
    /// Hi-res covers live in a 1024² array (one slice per resident card, ~128 MB with mips).
    public static let atlasTile = 256, atlasSize = 4096, hiresSize = 1024

    private let queue: MTLCommandQueue
    private let instancePipeline: MTLComputePipelineState
    private let opaquePipeline: MTLRenderPipelineState
    private let glassPipeline: MTLRenderPipelineState
    private let dofPipeline: MTLRenderPipelineState
    private let presentPipeline: MTLRenderPipelineState
    private let depthWrite: MTLDepthStencilState
    private let depthRead: MTLDepthStencilState
    private let meshes: [(buffer: MTLBuffer, count: Int)]
    private let atlas: MTLTexture
    private let hires: MTLTexture
    private let trilinear: MTLSamplerState
    private let pointSampler: MTLSamplerState
    private let linearSampler: MTLSamplerState
    private let poseBuffers: [MTLBuffer]
    private let instanceBuffers: [MTLBuffer]
    private let inflight = DispatchSemaphore(value: 3)
    private var frame = 0
    private var color: MTLTexture?
    private var depth: MTLTexture?
    private var blurred: MTLTexture?
    private var pendingTiles: [(slot: Int, pixels: MTLBuffer)] = []
    private var pendingHires: [(slot: Int, pixels: MTLBuffer)] = []
    private static let colorFormat = MTLPixelFormat.rgba16Float
    private static let depthFormat = MTLPixelFormat.depth32Float
    private static let instanceStride = 80

    public init(device: MTLDevice, glb: Data, targetFormat: MTLPixelFormat) throws {
        self.device = device
        queue = device.makeCommandQueue()!
        let library = try device.makeLibrary(source: ArchiveShaders.source(), options: {
            let o = MTLCompileOptions(); o.mathMode = .fast; return o
        }())

        func pipeline(_ vertex: String, _ fragment: String, format: MTLPixelFormat, blended: Bool, depth: Bool) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: vertex)
            d.fragmentFunction = library.makeFunction(name: fragment)
            d.colorAttachments[0].pixelFormat = format
            if depth { d.depthAttachmentPixelFormat = Self.depthFormat }
            if blended {
                // Filament "transparent" blending: premultiplied over.
                let c = d.colorAttachments[0]!
                c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: d)
        }
        instancePipeline = try device.makeComputePipelineState(function: library.makeFunction(name: "archiveInstances")!)
        opaquePipeline = try pipeline("archiveVertex", "archiveFragment", format: Self.colorFormat, blended: false, depth: true)
        glassPipeline = try pipeline("archiveVertex", "archiveFragment", format: Self.colorFormat, blended: true, depth: true)
        dofPipeline = try pipeline("fullscreen", "depthOfField", format: Self.colorFormat, blended: false, depth: false)
        presentPipeline = try pipeline("fullscreen", "present", format: targetFormat, blended: false, depth: false)

        let write = MTLDepthStencilDescriptor(); write.depthCompareFunction = .less; write.isDepthWriteEnabled = true
        let read = MTLDepthStencilDescriptor(); read.depthCompareFunction = .less; read.isDepthWriteEnabled = false
        depthWrite = device.makeDepthStencilState(descriptor: write)!
        depthRead = device.makeDepthStencilState(descriptor: read)!

        let mesh = try ArchiveMesh(glb: glb)
        meshes = mesh.kinds.map { values in
            (values.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)! }, values.count / 8)
        }

        func texture(_ size: Int, levels: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: size, height: size, mipmapped: true)
            d.mipmapLevelCount = levels
            d.storageMode = .private
            d.usage = [.shaderRead, .renderTarget]
            return device.makeTexture(descriptor: d)!
        }
        atlas = texture(Self.atlasSize, levels: 5)
        let array = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: Self.hiresSize, height: Self.hiresSize, mipmapped: true)
        array.textureType = .type2DArray
        array.arrayLength = ArchiveScene.hiresCapacity
        array.storageMode = .private
        array.usage = [.shaderRead]
        hires = device.makeTexture(descriptor: array)!

        func sampler(_ min: MTLSamplerMinMagFilter, mip: MTLSamplerMipFilter) -> MTLSamplerState {
            let d = MTLSamplerDescriptor()
            d.minFilter = min; d.magFilter = min; d.mipFilter = mip
            d.sAddressMode = .clampToEdge; d.tAddressMode = .clampToEdge
            return device.makeSamplerState(descriptor: d)!
        }
        trilinear = sampler(.linear, mip: .linear)
        pointSampler = sampler(.nearest, mip: .notMipmapped)
        linearSampler = sampler(.linear, mip: .notMipmapped)
        let poseLength = ShelfLayout.count * 16 * ArchiveScene.poseArrays
        poseBuffers = (0..<3).map { _ in device.makeBuffer(length: poseLength, options: [.storageModeShared, .cpuCacheModeWriteCombined])! }
        instanceBuffers = (0..<3).map { _ in device.makeBuffer(length: ShelfLayout.introCount * Self.instanceStride, options: .storageModePrivate)! }

        // Fill the atlas with the paper insert colour so unloaded mips never sample garbage. Hi-res
        // slices are only sampled once uploaded, so they need no fill.
        let blank = Self.paper(size: Self.atlasTile)
        if let command = queue.makeCommandBuffer(), let blit = command.makeBlitCommandEncoder() {
            let tile = device.makeBuffer(bytes: blank, length: blank.count)!
            for slot in 0..<256 { Self.copy(tile, size: Self.atlasTile, into: atlas, slot: slot, blit: blit) }
            blit.generateMipmaps(for: atlas)
            blit.endEncoding(); command.commit()
        }
    }

    // MARK: Covers

    /// RGBA8 sRGB pixels of a 128² tile (see `CoverArt.pixels`).
    public func uploadTile(slot: Int, pixels: Data) {
        pendingTiles.append((slot, pixels.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)! }))
    }

    /// RGBA8 sRGB pixels of a 1024² hi-res cover for array slice `slot`.
    public func uploadHires(slot: Int, pixels: Data) {
        pendingHires.append((slot, pixels.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count)! }))
    }

    static func copy(_ buffer: MTLBuffer, size: Int, into texture: MTLTexture, slot: Int, blit: MTLBlitCommandEncoder) {
        let tiles = texture.width / size
        blit.copy(from: buffer, sourceOffset: 0, sourceBytesPerRow: size * 4, sourceBytesPerImage: size * size * 4,
                  sourceSize: MTLSize(width: size, height: size, depth: 1), to: texture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: slot % tiles * size, y: slot / tiles * size, z: 0))
    }

    static func paper(size: Int) -> [UInt8] {
        // #C2C3BB, the insert colour upstream paints behind every cover.
        [UInt8](unsafeUninitializedCapacity: size * size * 4) { buffer, count in
            for i in 0..<(size * size) { buffer[i * 4] = 194; buffer[i * 4 + 1] = 195; buffer[i * 4 + 2] = 187; buffer[i * 4 + 3] = 255 }
            count = size * size * 4
        }
    }

    // MARK: Frame

    public func renderSize(for target: (width: Int, height: Int)) -> (width: Int, height: Int) {
        let cap = sqrt(8_294_400.0 / Double(target.width * target.height))
        let ratio = min(max(min(renderScale, cap), 0.1), 2)
        return (max(1, Int((Double(target.width) * ratio).rounded())), max(1, Int((Double(target.height) * ratio).rounded())))
    }

    private func ensureTargets(_ size: (width: Int, height: Int)) {
        guard color?.width != size.width || color?.height != size.height else { return }
        func make(_ format: MTLPixelFormat, _ w: Int, _ h: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            return device.makeTexture(descriptor: d)!
        }
        color = make(Self.colorFormat, size.width, size.height)
        depth = make(Self.depthFormat, size.width, size.height)
        // Filament nativeResolution = false: DoF runs at half width and height.
        blurred = make(Self.colorFormat, max(1, size.width / 2), max(1, size.height / 2))
    }

    /// Encodes one frame into `target` and commits. `present` lets the caller schedule a drawable.
    @discardableResult
    public func draw(to target: MTLTexture, present: ((MTLCommandBuffer) -> Void)? = nil) -> MTLCommandBuffer {
        inflight.wait()
        let command = queue.makeCommandBuffer()!
        let semaphore = inflight
        command.addCompletedHandler { _ in semaphore.signal() }
        scene.resize(width: target.width, height: target.height)
        let size = renderSize(for: (target.width, target.height))
        ensureTargets(size)

        if !pendingTiles.isEmpty || !pendingHires.isEmpty, let blit = command.makeBlitCommandEncoder() {
            for tile in pendingTiles { Self.copy(tile.pixels, size: Self.atlasTile, into: atlas, slot: tile.slot, blit: blit) }
            if !pendingTiles.isEmpty { blit.generateMipmaps(for: atlas) }
            let size = Self.hiresSize
            for cover in pendingHires {
                blit.copy(from: cover.pixels, sourceOffset: 0, sourceBytesPerRow: size * 4, sourceBytesPerImage: size * size * 4,
                          sourceSize: MTLSize(width: size, height: size, depth: 1), to: hires, destinationSlice: cover.slot,
                          destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            }
            if !pendingHires.isEmpty { blit.generateMipmaps(for: hires) }
            blit.endEncoding()
            pendingTiles.removeAll(); pendingHires.removeAll()
        }

        let pose = poseBuffers[frame % 3]
        let instances = instanceBuffers[frame % 3]
        frame += 1
        scene.writePose(to: pose.contents())
        var base = scene.uniforms(kind: 0)
        let visible = scene.visible
        var count = UInt32(scene.instanceCount)

        if visible, let compute = command.makeComputeCommandEncoder() {
            compute.setComputePipelineState(instancePipeline)
            compute.setBytes(&base, length: MemoryLayout<ArchiveUniforms>.stride, index: 1)
            compute.setBuffer(pose, offset: 0, index: 2)
            compute.setBuffer(instances, offset: 0, index: 3)
            compute.setBytes(&count, length: 4, index: 4)
            let width = instancePipeline.threadExecutionWidth
            compute.dispatchThreadgroups(MTLSize(width: (Int(count) + width - 1) / width, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
            compute.endEncoding()
        }

        let paper = ArchivePalette.linear(scene.themeValue) as SIMD3<Float>
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: Double(paper.x), green: Double(paper.y), blue: Double(paper.z), alpha: 1)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1
        let dof = scene.depthOfField && visible
        pass.depthAttachment.storeAction = dof ? .store : .dontCare

        let encoder = command.makeRenderCommandEncoder(descriptor: pass)!
        if visible {
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(instances, offset: 0, index: 3)
            encoder.setFragmentTexture(atlas, index: 0)
            encoder.setFragmentTexture(hires, index: 1)
            encoder.setFragmentSamplerState(trilinear, index: 0)
            // Opaque inserts first (they write depth), then the shell and the frosted lid.
            for kind in debugKinds {
                encoder.setRenderPipelineState(kind == 2 ? opaquePipeline : glassPipeline)
                encoder.setDepthStencilState(kind == 2 ? depthWrite : depthRead)
                var uniforms = base
                uniforms.b.x = Float(kind)
                encoder.setVertexBuffer(meshes[kind].buffer, offset: 0, index: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<ArchiveUniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ArchiveUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: meshes[kind].count, instanceCount: Int(count))
            }
        }
        encoder.endEncoding()

        if dof {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = blurred
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            let e = command.makeRenderCommandEncoder(descriptor: pass)!
            e.setRenderPipelineState(dofPipeline)
            var params = dofParams(height: size.height, width: size.width)
            e.setFragmentTexture(color, index: 0)
            e.setFragmentTexture(depth, index: 1)
            e.setFragmentBytes(&params, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
            e.setFragmentSamplerState(pointSampler, index: 0)
            e.setFragmentSamplerState(linearSampler, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
        }

        let out = MTLRenderPassDescriptor()
        out.colorAttachments[0].texture = target
        out.colorAttachments[0].loadAction = .dontCare
        out.colorAttachments[0].storeAction = .store
        let p = command.makeRenderCommandEncoder(descriptor: out)!
        p.setRenderPipelineState(presentPipeline)
        var flags = SIMD4<Float>(1 / Float(size.width), 1 / Float(size.height), fxaa ? 1 : 0, dof ? 1 : 0)
        p.setFragmentTexture(color, index: 0)
        p.setFragmentTexture(blurred, index: 1)
        p.setFragmentBytes(&flags, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        p.setFragmentSamplerState(linearSampler, index: 0)
        p.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        p.endEncoding()

        present?(command)
        command.commit()
        scene.presented()
        return command
    }

    /// Filament's thin-lens CoC: K = cocScale · (H / sensor) · A·f / (d − f), f from the vertical FOV,
    /// A = f / N with the default aperture f/16; clamped to 1 px foreground / 2 px background.
    private func dofParams(height: Int, width: Int) -> (SIMD4<Float>, SIMD4<Float>) {
        let sensor = 0.024, aperture = 16.0, cocScale = 12.0
        let focal = sensor * Double(scene.projection.columns.1.y) * 0.5
        let d = max(scene.focusDistance, ArchiveScene.near)
        let k = scene.dofScale * cocScale * (Double(height) / sensor) * (focal / aperture * focal) / max(d - focal, 1e-4)
        return (SIMD4(Float(k), Float(d), Float(ArchiveScene.near), Float(ArchiveScene.far)),
                SIMD4(-1, 2, 1 / Float(width), 1 / Float(height)))
    }
}
