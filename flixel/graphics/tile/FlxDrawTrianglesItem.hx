package flixel.graphics.tile;

import flixel.FlxCamera;
import flixel.graphics.frames.FlxFrame;
import flixel.graphics.tile.FlxDrawBaseItem.FlxDrawItemType;
import flixel.math.FlxMatrix;
import flixel.math.FlxPoint;
import flixel.math.FlxRect;
import flixel.system.FlxAssets.FlxShader;
import flixel.util.FlxColor;
import openfl.display.Graphics;
import openfl.display.ShaderParameter;
import openfl.display.TriangleCulling;
import openfl.geom.ColorTransform;

typedef DrawData<T> = #if (flash || openfl >= "4.0.0") openfl.Vector<T> #else Array<T> #end;

/**
 * @author Zaphod
 */
class FlxDrawTrianglesItem extends FlxDrawBaseItem<FlxDrawTrianglesItem>
{
	static var point:FlxPoint = FlxPoint.get();
	static var rect:FlxRect = FlxRect.get();

	#if !flash
	public var shader:FlxShader;
	var alphas:Array<Float>;
	var colorMultipliers:Array<Float>;
	var colorOffsets:Array<Float>;
	var gpuMeta0:Array<Float>;
	var gpuMeta1:Array<Float>;
	#end

	public var vertices:DrawData<Float> = new DrawData<Float>();
	public var indices:DrawData<Int> = new DrawData<Int>();
	public var uvtData:DrawData<Float> = new DrawData<Float>();
	public var colors:DrawData<Int> = new DrawData<Int>();

	public var verticesPosition:Int = 0;
	public var indicesPosition:Int = 0;
	public var colorsPosition:Int = 0;

	var bounds:FlxRect = FlxRect.get();
	var borrowedGeometry:Bool = false;

	public function new()
	{
		super();
		type = FlxDrawItemType.TRIANGLES;
		#if !flash
		alphas = [];
		#end
	}

	override public function render(camera:FlxCamera):Void
	{
		if (!FlxG.renderTile)
			return;

		if (numTriangles <= 0)
			return;

		#if !flash
		var shader = shader != null ? shader : graphics.shader;
		if (shader == null)
			return;

		// Macro-generated FlxShader subclasses expose these fields directly.
		// FlxRuntimeShader keeps them in ShaderData instead, so the inherited
		// generated field may be null even though the GLSL attribute exists.
		// Resolve both representations to make runtime vertex shaders safe for
		// drawTriangles batches.
		var bitmapInput:Dynamic = shader.bitmap;
		if (bitmapInput == null) bitmapInput = Reflect.field(shader.data, "bitmap");
		if (bitmapInput == null) return;
		bitmapInput.input = graphics.bitmap;
		bitmapInput.filter = (camera.antialiasing || antialiasing)
			? openfl.display3D.Context3DTextureFilter.LINEAR
			: openfl.display3D.Context3DTextureFilter.NEAREST;
		bitmapInput.wrap = openfl.display3D.Context3DWrapMode.REPEAT; // preserve drawTriangles tiling behaviour

		var alphaParam:Dynamic = shader.alpha;
		if (alphaParam == null) alphaParam = Reflect.field(shader.data, "alpha");
		if (alphaParam != null) alphaParam.value = alphas;

		if (colored || hasColorOffsets)
		{
			var multiplierParam:Dynamic = shader.colorMultiplier;
			if (multiplierParam == null) multiplierParam = Reflect.field(shader.data, "colorMultiplier");
			if (multiplierParam != null) multiplierParam.value = colorMultipliers;
			var offsetParam:Dynamic = shader.colorOffset;
			if (offsetParam == null) offsetParam = Reflect.field(shader.data, "colorOffset");
			if (offsetParam != null) offsetParam.value = colorOffsets;
		}

		var gpuMeta0Param:Dynamic = Reflect.field(shader.data, "gpuMeta0");
		var gpuMeta1Param:Dynamic = Reflect.field(shader.data, "gpuMeta1");
		if (gpuMeta0Param != null && gpuMeta0 != null) gpuMeta0Param.value = gpuMeta0;
		if (gpuMeta1Param != null && gpuMeta1 != null) gpuMeta1Param.value = gpuMeta1;

		var transformParam:Dynamic = shader.hasTransform;
		if (transformParam == null) transformParam = Reflect.field(shader.data, "hasTransform");
		if (transformParam != null) setParameterValue(transformParam, true);
		var colorTransformParam:Dynamic = shader.hasColorTransform;
		if (colorTransformParam == null) colorTransformParam = Reflect.field(shader.data, "hasColorTransform");
		if (colorTransformParam != null) setParameterValue(colorTransformParam, colored || hasColorOffsets);

		#if (openfl > "8.7.0")
		camera.canvas.graphics.overrideBlendMode(blend);
		#end

		camera.canvas.graphics.beginShaderFill(shader);
		#else
		camera.canvas.graphics.beginBitmapFill(graphics.bitmap, null, true, (camera.antialiasing || antialiasing));
		#end

		camera.canvas.graphics.drawTriangles(vertices, indices, uvtData, TriangleCulling.NONE);
		camera.canvas.graphics.endFill();

		#if FLX_DEBUG
		if (FlxG.debugger.drawDebug)
		{
			var gfx:Graphics = camera.debugLayer.graphics;
			gfx.lineStyle(1, FlxColor.BLUE, 0.5);
			gfx.drawTriangles(vertices, indices, uvtData);
		}
		#end

		super.render(camera);
	}

	override public function reset():Void
	{
		super.reset();
		if (borrowedGeometry)
		{
			vertices = new DrawData<Float>();
			indices = new DrawData<Int>();
			uvtData = new DrawData<Float>();
			#if !flash
			alphas = [];
			#end
			borrowedGeometry = false;
		}
		else
		{
			vertices.splice(0, vertices.length);
			indices.splice(0, indices.length);
			uvtData.splice(0, uvtData.length);
		}
		colors.splice(0, colors.length);

		verticesPosition = 0;
		indicesPosition = 0;
		colorsPosition = 0;
		#if !flash
		alphas.splice(0, alphas.length);
		if (colorMultipliers != null)
			colorMultipliers.splice(0, colorMultipliers.length);
		if (colorOffsets != null)
			colorOffsets.splice(0, colorOffsets.length);
		if (gpuMeta0 != null)
			gpuMeta0.splice(0, gpuMeta0.length);
		if (gpuMeta1 != null)
			gpuMeta1.splice(0, gpuMeta1.length);
		#end
	}

	/**
	 * Uses immutable caller-owned triangle storage for one render pass.
	 * Intended for GPU-generated geometry that already owns a persistent mesh.
	 */
	public function borrowTriangles(vertices:DrawData<Float>, indices:DrawData<Int>, uvtData:DrawData<Float>, alphaData:Array<Float>,
		?position:FlxPoint, ?cameraBounds:FlxRect):Bool
	{
		if (borrowedGeometry || this.vertices.length != 0 || this.indices.length != 0)
			return false;
		this.vertices = vertices;
		this.indices = indices;
		this.uvtData = uvtData;
		#if !flash
		alphas = alphaData;
		#end
		verticesPosition = vertices.length;
		indicesPosition = indices.length;
		borrowedGeometry = true;
		if (position != null) position.putWeak();
		if (cameraBounds != null) cameraBounds.putWeak();
		return true;
	}

	override public function dispose():Void
	{
		super.dispose();

		vertices = null;
		indices = null;
		uvtData = null;
		colors = null;
		bounds = null;
		#if !flash
		alphas = null;
		colorMultipliers = null;
		colorOffsets = null;
		gpuMeta0 = null;
		gpuMeta1 = null;
		#end
	}

	public function addTriangles(vertices:DrawData<Float>, indices:DrawData<Int>, uvtData:DrawData<Float>, ?colors:DrawData<Int>, ?position:FlxPoint,
			?cameraBounds:FlxRect #if !flash , ?transform:ColorTransform, ?gpuMetadata:Array<Float> #end):Void
	{
		if (position == null)
			position = point.set();

		if (cameraBounds == null)
			cameraBounds = rect.set(0, 0, FlxG.width, FlxG.height);

		var verticesLength:Int = vertices.length;
		var prevVerticesLength:Int = this.vertices.length;
		var numberOfVertices:Int = Std.int(verticesLength / 2);
		var prevIndicesLength:Int = this.indices.length;
		var prevUVTDataLength:Int = this.uvtData.length;
		var prevColorsLength:Int = this.colors.length;
		var prevNumberOfVertices:Int = this.numVertices;

		var tempX:Float, tempY:Float;
		var i:Int = 0;
		var currentVertexPosition:Int = prevVerticesLength;

		while (i < verticesLength)
		{
			tempX = position.x + vertices[i];
			tempY = position.y + vertices[i + 1];

			this.vertices[currentVertexPosition++] = tempX;
			this.vertices[currentVertexPosition++] = tempY;

			if (i == 0)
			{
				bounds.set(tempX, tempY, 0, 0);
			}
			else
			{
				inflateBounds(bounds, tempX, tempY);
			}

			i += 2;
		}

		if (!cameraBounds.overlaps(bounds))
		{
			this.vertices.splice(this.vertices.length - verticesLength, verticesLength);
		}
		else
		{
			var uvtDataLength:Int = uvtData.length;
			for (i in 0...uvtDataLength)
			{
				this.uvtData[prevUVTDataLength + i] = uvtData[i];
			}

			var indicesLength:Int = indices.length;
			for (i in 0...indicesLength)
			{
				this.indices[prevIndicesLength + i] = indices[i] + prevNumberOfVertices;
			}

			if (colored)
			{
				for (i in 0...numberOfVertices)
				{
					this.colors[prevColorsLength + i] = colors[i];
				}

				colorsPosition += numberOfVertices;
			}

			verticesPosition += verticesLength;
			indicesPosition += indicesLength;
		}

		position.putWeak();
		cameraBounds.putWeak();

		#if !flash
		// Only append attributes for triangles accepted by this call. Using the
		// batch-wide numTriangles here repeated every previous arrow on every add,
		// causing quadratic CPU work and oversized attribute buffers.
		final addedTriangles = Std.int((this.indices.length - prevIndicesLength) / 3);
		if (gpuMetadata != null && gpuMetadata.length >= 8 && addedTriangles > 0)
		{
			if (gpuMeta0 == null) gpuMeta0 = [];
			if (gpuMeta1 == null) gpuMeta1 = [];
			for (_ in 0...(addedTriangles * 3))
			{
				gpuMeta0.push(gpuMetadata[0]);
				gpuMeta0.push(gpuMetadata[1]);
				gpuMeta0.push(gpuMetadata[2]);
				gpuMeta0.push(gpuMetadata[3]);
				gpuMeta1.push(gpuMetadata[4]);
				gpuMeta1.push(gpuMetadata[5]);
				gpuMeta1.push(gpuMetadata[6]);
				gpuMeta1.push(gpuMetadata[7]);
			}
		}
		for (_ in 0...addedTriangles)
		{
			alphas.push(transform != null ? transform.alphaMultiplier : 1.0);
			alphas.push(transform != null ? transform.alphaMultiplier : 1.0);
			alphas.push(transform != null ? transform.alphaMultiplier : 1.0);
		}

		if (colored || hasColorOffsets)
		{
			if (colorMultipliers == null)
				colorMultipliers = [];

			if (colorOffsets == null)
				colorOffsets = [];

			for (_ in 0...(addedTriangles * 3))
			{
				if(transform != null)
				{
					colorMultipliers.push(transform.redMultiplier);
					colorMultipliers.push(transform.greenMultiplier);
					colorMultipliers.push(transform.blueMultiplier);

					colorOffsets.push(transform.redOffset);
					colorOffsets.push(transform.greenOffset);
					colorOffsets.push(transform.blueOffset);
					colorOffsets.push(transform.alphaOffset);
				}
				else
				{
					colorMultipliers.push(1);
					colorMultipliers.push(1);
					colorMultipliers.push(1);
	
					colorOffsets.push(0);
					colorOffsets.push(0);
					colorOffsets.push(0);
					colorOffsets.push(0);
				}

				colorMultipliers.push(1);
			}
		}
		#end
	}

	inline function setParameterValue(parameter:ShaderParameter<Bool>, value:Bool):Void
	{
		if (parameter.value == null)
			parameter.value = [];
		parameter.value[0] = value;
	}

	public static inline function inflateBounds(bounds:FlxRect, x:Float, y:Float):FlxRect
	{
		if (x < bounds.x)
		{
			bounds.width += bounds.x - x;
			bounds.x = x;
		}

		if (y < bounds.y)
		{
			bounds.height += bounds.y - y;
			bounds.y = y;
		}

		if (x > bounds.x + bounds.width)
		{
			bounds.width = x - bounds.x;
		}

		if (y > bounds.y + bounds.height)
		{
			bounds.height = y - bounds.y;
		}

		return bounds;
	}

	override public function addQuad(frame:FlxFrame, matrix:FlxMatrix, ?transform:ColorTransform):Void
	{
		var prevVerticesPos:Int = verticesPosition;
		var prevIndicesPos:Int = indicesPosition;
		var prevColorsPos:Int = colorsPosition;
		var prevNumberOfVertices:Int = numVertices;

		var point = FlxPoint.get();
		point.transform(matrix);

		vertices[prevVerticesPos] = point.x;
		vertices[prevVerticesPos + 1] = point.y;

		uvtData[prevVerticesPos] = frame.uv.x;
		uvtData[prevVerticesPos + 1] = frame.uv.y;

		point.set(frame.frame.width, 0);
		point.transform(matrix);

		vertices[prevVerticesPos + 2] = point.x;
		vertices[prevVerticesPos + 3] = point.y;

		uvtData[prevVerticesPos + 2] = frame.uv.width;
		uvtData[prevVerticesPos + 3] = frame.uv.y;

		point.set(frame.frame.width, frame.frame.height);
		point.transform(matrix);

		vertices[prevVerticesPos + 4] = point.x;
		vertices[prevVerticesPos + 5] = point.y;

		uvtData[prevVerticesPos + 4] = frame.uv.width;
		uvtData[prevVerticesPos + 5] = frame.uv.height;

		point.set(0, frame.frame.height);
		point.transform(matrix);

		vertices[prevVerticesPos + 6] = point.x;
		vertices[prevVerticesPos + 7] = point.y;

		point.put();

		uvtData[prevVerticesPos + 6] = frame.uv.x;
		uvtData[prevVerticesPos + 7] = frame.uv.height;

		indices[prevIndicesPos] = prevNumberOfVertices;
		indices[prevIndicesPos + 1] = prevNumberOfVertices + 1;
		indices[prevIndicesPos + 2] = prevNumberOfVertices + 2;
		indices[prevIndicesPos + 3] = prevNumberOfVertices + 2;
		indices[prevIndicesPos + 4] = prevNumberOfVertices + 3;
		indices[prevIndicesPos + 5] = prevNumberOfVertices;

		if (colored)
		{
			var red = 1.0;
			var green = 1.0;
			var blue = 1.0;
			var alpha = 1.0;

			if (transform != null)
			{
				red = transform.redMultiplier;
				green = transform.greenMultiplier;
				blue = transform.blueMultiplier;

				#if !neko
				alpha = transform.alphaMultiplier;
				#end
			}

			var color = FlxColor.fromRGBFloat(red, green, blue, alpha);

			colors[prevColorsPos] = color;
			colors[prevColorsPos + 1] = color;
			colors[prevColorsPos + 2] = color;
			colors[prevColorsPos + 3] = color;

			colorsPosition += 4;
		}

		verticesPosition += 8;
		indicesPosition += 6;
	}

	override function get_numVertices():Int
	{
		return Std.int(vertices.length / 2);
	}

	override function get_numTriangles():Int
	{
		return Std.int(indices.length / 3);
	}
}
