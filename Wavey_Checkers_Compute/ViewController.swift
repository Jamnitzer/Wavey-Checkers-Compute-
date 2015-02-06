//------------------------------------------------------------------------------------------
//  ViewController.m
//  Metal Example
//
//  Created by Stefan Johnson on 4/06/2014.
//  Copyright (c) 2014 Stefan Johnson. All rights reserved.
//
//------------------------------------------------------------------------------------------
// ScrimpyCat/Metal-Examples
//------------------------------------------------------------------------------------------
// converted to Swift by Jim Wrenholt.
//------------------------------------------------------------------------------------------
import UIKit
import Metal

let RESOURCE_COUNT = 3

//------------------------------------------------------------------------------------------
struct V2f
{
    let x:Float
    let y:Float
}
//------------------------------------------------------------------------------------------
struct VertexData
{
    let position:V2f
    let texCoord:V2f
}
//------------------------------------------------------------------------------------------
struct BufferDataB
{
    var rect:VertexData
    var rectB:VertexData
    var rectC:VertexData
    var rectD:VertexData
    let rectScale:V2f
    let time:Float
    let timeB:Float
    let timeC:Float
}
//------------------------------------------------------------------------------------------
class ViewController: UIViewController
{
    var commandQueue:MTLCommandQueue! = nil
    var renderLayer:CAMetalLayer! = nil
    var renderPass:MTLRenderPassDescriptor? = nil
    var displayLink:CADisplayLink! = nil       // calls render..

    var colourPipeline:MTLRenderPipelineState! = nil
    var checkerPipeline:MTLComputePipelineState! = nil

    var data:MTLBuffer! = nil
    var checkerTexture:MTLTexture! = nil

    var previousTime:CFTimeInterval = 0
    var time:Float = 0.0
    var resourceSemaphore:dispatch_semaphore_t = 0
    var resourceIndex:UInt = 0

    var defaultLibrary:MTLLibrary? = nil
    var drawable:CAMetalDrawable? = nil

    //--------------------------------------------------------------------
    override func viewDidLoad()
    {
        super.viewDidLoad()

        let device = MTLCreateSystemDefaultDevice()
        commandQueue = device.newCommandQueue()
        defaultLibrary = device.newDefaultLibrary()

        //-----------------------------------------------------------
        // vertex attribute for position
        //-----------------------------------------------------------
        let PositionDescriptor = MTLVertexAttributeDescriptor()
            PositionDescriptor.format = MTLVertexFormat.Float2
            PositionDescriptor.offset = 0      // offsetof(VertexData, position)
            PositionDescriptor.bufferIndex = 0

        //-----------------------------------------------------------
        // vertex attribute for texCoord
        //-----------------------------------------------------------
        let TexCoordDescriptor = MTLVertexAttributeDescriptor()
        TexCoordDescriptor.format = MTLVertexFormat.Float2
        TexCoordDescriptor.offset = sizeof(V2f)  // offsetof(VertexData, texCoord)
        TexCoordDescriptor.bufferIndex = 0
        //
        //-----------------------------------------------------------
        // Layout descriptor for Vertex Data.
        //-----------------------------------------------------------
        let LayoutDescriptor = MTLVertexBufferLayoutDescriptor()
        LayoutDescriptor.stride = sizeof(VertexData)
        LayoutDescriptor.stepFunction = MTLVertexStepFunction.PerVertex
        LayoutDescriptor.stepRate = 1
        //

        //-----------------------------------------------------------
        // vertex descriptor for Rect.
        //-----------------------------------------------------------
        let RectDescriptor = MTLVertexDescriptor()
        RectDescriptor.attributes[0] = PositionDescriptor
        RectDescriptor.attributes[1] = TexCoordDescriptor
        RectDescriptor.layouts[0] = LayoutDescriptor

        //-----------------------------------------------------------
        // Colour Pipeline shader.
        //-----------------------------------------------------------
        let vertexProgram = defaultLibrary!.newFunctionWithName("ColourVertex")
        let fragmentProgram = defaultLibrary!.newFunctionWithName("ColourFragment")

        let ColourPipelineDescriptor = MTLRenderPipelineDescriptor()
            ColourPipelineDescriptor.label = "ColourPipeline"
            ColourPipelineDescriptor.colorAttachments[0].pixelFormat =
                    MTLPixelFormat.BGRA8Unorm

            ColourPipelineDescriptor.vertexFunction = vertexProgram
            ColourPipelineDescriptor.fragmentFunction = fragmentProgram
            ColourPipelineDescriptor.vertexDescriptor = RectDescriptor

        self.colourPipeline = device!.newRenderPipelineStateWithDescriptor(
            ColourPipelineDescriptor, error: nil)

        if (colourPipeline == nil)
        {
            println("colourPipeline")
        }
        //-----------------------------------------------------------
        // compute pipeline state.
        //-----------------------------------------------------------
        let computeFunction = defaultLibrary!.newFunctionWithName("CheckerKernel")
        self.checkerPipeline = device!.newComputePipelineStateWithFunction(
              computeFunction!, error:nil)

        if (checkerPipeline == nil)
        {
            println("checkerPipeline")
        }
        //-----------------------------------------------------------
        // fill in BufferData.
        //-----------------------------------------------------------
        let Size:CGSize = self.view.bounds.size
        let Scale:Float = 63.8

        //-----------------------------------------------------------
        var src_data = BufferDataB(
            rect: VertexData( position: V2f(x:Float(-1.0), y:Float(-1.0)),
                    texCoord: V2f(x:Float( 0.0), y:Float( 0.0))),
            rectB:VertexData( position: V2f(x:Float(+1.0), y:Float(-1.0)),
                    texCoord: V2f(x:Float(+1.0), y:Float( 0.0))),
            rectC:VertexData( position: V2f(x:Float(-1.0), y:Float(+1.0)),
                    texCoord: V2f(x:Float( 0.0), y:Float(+1.0))),
            rectD:VertexData( position: V2f(x:Float(+1.0), y:Float(+1.0)),
                    texCoord: V2f(x:Float(+1.0), y:Float(+1.0))),
            rectScale: V2f(x: Scale / Float(Size.width),
                           y: Scale / Float(Size.height)),
            time: Float(0.0),
            timeB: Float(0.0),
            timeC: Float(0.0)
        )
        //-----------------------------------------------------------
        // new buffer with BufferData.
        //-----------------------------------------------------------
        self.data = device.newBufferWithLength(sizeof(BufferDataB),
                    options:MTLResourceOptions.OptionCPUCacheModeDefault)

        println("sizeof(VertexData) = \(sizeof(VertexData))")
        println("sizeof(BufferDataB) = \(sizeof(BufferDataB))")

        let bufferPointer = data?.contents()
        memcpy(bufferPointer!, &src_data, UInt(sizeof(BufferDataB)))

        //-----------------------------------------------------------
        // new texture checkerTexture.
        //-----------------------------------------------------------
        let ContentScale:CGFloat = UIScreen.mainScreen().scale
        let texWidth = Int(Size.width * ContentScale)
        let texHeight = Int(Size.height * ContentScale)
        let texDescriptor = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
            MTLPixelFormat.BGRA8Unorm,
            width:texWidth,
            height:texHeight,
            mipmapped:false)

        self.checkerTexture = device.newTextureWithDescriptor(texDescriptor)

        //-----------------------------------------------------------
        // generate the checker texture.
        //-----------------------------------------------------------
        generateCheckerTexture()

        //-----------------------------------------------------------
        // render layer.
        //-----------------------------------------------------------
        self.renderLayer = CAMetalLayer()
            renderLayer.device = device
            renderLayer.pixelFormat = .BGRA8Unorm
            renderLayer.framebufferOnly = true
            renderLayer.frame = view.layer.frame

        var drawableSize = view.bounds.size
            drawableSize.width = drawableSize.width * CGFloat(view.contentScaleFactor)
            drawableSize.height = drawableSize.height * CGFloat(view.contentScaleFactor)
        renderLayer.drawableSize = drawableSize

        self.view.layer.addSublayer(self.renderLayer)
        self.view.opaque = true
        self.view.contentScaleFactor = ContentScale

        self.resourceSemaphore = dispatch_semaphore_create(RESOURCE_COUNT)

        previousTime = CACurrentMediaTime()

        displayLink = CADisplayLink(target: self, selector: Selector("render"))
        displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSDefaultRunLoopMode)
    }
    //--------------------------------------------------------------------
    override func didReceiveMemoryWarning()
    {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    //--------------------------------------------------------------------
    override func prefersStatusBarHidden() -> Bool
    {
        return true
    }
    //--------------------------------------------------------------------
    func generateCheckerTexture()
    {
        //-----------------------------------------------------------
        // called only once to fill in a texture.
        //-----------------------------------------------------------
        let commandBuffer = commandQueue.commandBuffer()
        commandBuffer.label = "CreateCheckerTextureCommandBuffer"

        let WorkGroupSize = MTLSizeMake(16, 16, 1)
        let WorkGroupCount = MTLSizeMake(
                    checkerTexture.width / 16 / 4,
                    checkerTexture.height / 16, 1)

        let computeEncoder = commandBuffer.computeCommandEncoder()
        computeEncoder.pushDebugGroup("Create checker texture")

        // SET PIPELINE STATE
        computeEncoder.setComputePipelineState(checkerPipeline)

       // SET BUFFERDATA
        let scaleOffset = 4 * sizeof(VertexData)
        computeEncoder.setBuffer(data, offset: scaleOffset, atIndex: 0) //offsetof(BufferData, rectScale)

        // SET TEXTURE
        computeEncoder.setTexture(checkerTexture, atIndex: 0)

        // THREADGROUPS
        computeEncoder.dispatchThreadgroups(WorkGroupCount,
            threadsPerThreadgroup: WorkGroupSize)

        computeEncoder.popDebugGroup()
        computeEncoder.endEncoding()

        commandBuffer.commit()
    }
    //--------------------------------------------------------------------
    //--------------------------------------------------------------------
    func render()
    {
        dispatch_semaphore_wait(resourceSemaphore, DISPATCH_TIME_FOREVER)

        self.resourceIndex = UInt(resourceIndex + 1) % UInt(RESOURCE_COUNT)

        let Current:CFTimeInterval = CACurrentMediaTime()
        let DeltaTime:CFTimeInterval = Current - previousTime
        previousTime = Current

        time += Float(0.2) * Float(DeltaTime)

        let timeOffset = sizeof(VertexData) * 4 + sizeof(V2f)
            + sizeof(Float) * Int(resourceIndex)

        let bufferPointer = data?.contents()
        memcpy(bufferPointer! + timeOffset, &time, UInt(sizeof(Float)))

        let commandBuffer = commandQueue.commandBuffer()
            commandBuffer.label = "RenderFrameCommandBuffer"

        let renderPassDesc:MTLRenderPassDescriptor = currentFramebuffer()
        let RenderCommand = commandBuffer.renderCommandEncoderWithDescriptor(
                renderPassDesc )

        RenderCommand!.pushDebugGroup("Apply wave")

        let aViewport = MTLViewport(originX: 0.0, originY: 0.0,
            width: Double(renderLayer.drawableSize.width),
            height: Double(renderLayer.drawableSize.height),
            znear: 0.0, zfar: 1.0)

        RenderCommand!.setViewport(aViewport)

        RenderCommand!.setRenderPipelineState(colourPipeline!)
        RenderCommand!.setVertexBuffer( data!,
                                        offset:0,      //offsetof(BufferData, rect)
                                        atIndex:0 )

        RenderCommand!.setFragmentTexture(checkerTexture!, atIndex:0)
        RenderCommand!.setFragmentBuffer(data!,
                                        offset:timeOffset,   // offsetof(BufferData, time[resourceIndex])
                                        atIndex:0 )

        //--------------------------------------------------------------------
        RenderCommand!.drawPrimitives( MTLPrimitiveType.TriangleStrip,
                                        vertexStart:0,
                                        vertexCount:4 )

        RenderCommand!.popDebugGroup()
        RenderCommand!.endEncoding()

        commandBuffer.presentDrawable(currentDrawable()!)

        //----------------------------------------------------------------
        commandBuffer.addCompletedHandler{
            [weak self] commandBuffer in
            if let strongSelf = self
            {
                dispatch_semaphore_signal(strongSelf.resourceSemaphore)
            }
            return  }
        //----------------------------------------------------------------
        commandBuffer.commit()

        renderPass = nil
        drawable = nil
    }
    //--------------------------------------------------------------------
    func currentFramebuffer() -> MTLRenderPassDescriptor
    {
        if (renderPass == nil)
        {
            let Drawable = self.currentDrawable()
            if (Drawable != nil)
            {
                self.renderPass = MTLRenderPassDescriptor()
                renderPass!.colorAttachments[0].texture = Drawable!.texture
                renderPass!.colorAttachments[0].loadAction = MTLLoadAction.DontCare
                renderPass!.colorAttachments[0].storeAction = MTLStoreAction.Store
            }
        }
        return renderPass!
    }
    //--------------------------------------------------------------------
    func currentDrawable() -> CAMetalDrawable?
    {
        while (self.drawable == nil)
        {
            self.drawable = renderLayer.nextDrawable()
        }
        return self.drawable
    }
    //--------------------------------------------------------------------
    deinit
    {
        displayLink.invalidate()
    }
    //--------------------------------------------------------------------
}
//--------------------------------------------------------------------------------
