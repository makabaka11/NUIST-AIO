package com.retrsoft.nuistaio.navigation

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Build
import android.view.*
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.abs
import kotlin.math.roundToInt

/** Native backdrop + lens + draggable capsule, following SukiSU's FloatingBottomBar.
 * Only the Flutter background surface is sampled: never this view or Flutter overlays
 * (dialogs/routes). RenderNodes keep the sampling and blur entirely on the GPU.
 */
internal class LegacyLiquidNavView(
    context: Context, messenger: BinaryMessenger, id: Int, configuration: Map<*, *>
) : FrameLayout(context), PlatformView {
    private val channel = MethodChannel(messenger, "nuistaio/liquid_nav/$id")
    private val density = resources.displayMetrics.density
    private fun dp(value: Float) = value * density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val clip = Path()
    private val row = LinearLayout(context)
    private val labels = listOf("首页", "学习", "功能", "我的")
    private val tabs = labels.mapIndexed { index, label ->
        TextView(context).apply {
            text = label
            gravity = Gravity.CENTER
            includeFontPadding = false
            compoundDrawablePadding = dp(2f).toInt()
            isFocusable = true
            isClickable = true
            setOnClickListener { select(index) }
            accessibilityDelegate = object : AccessibilityDelegate() {
                override fun onInitializeAccessibilityNodeInfo(host: View, info: AccessibilityNodeInfo) {
                    super.onInitializeAccessibilityNodeInfo(host, info)
                    info.className = "android.widget.RadioButton"
                    info.isCheckable = true
                    info.isChecked = index == selected
                    info.isSelected = index == selected
                }
            }
        }
    }
    private var selected = 0
    private var position = 0f
    private var primary = Color.BLUE
    private var foreground = Color.BLACK
    private var surface = Color.WHITE
    private var dark = false
    private var reduceMotion = false
    private var disposed = false
    private var dragging = false
    private var downX = 0f
    private var pressedAmount = 0f
    private var animator: ValueAnimator? = null
    private var pressAnimator: ValueAnimator? = null
    private val backdrop = if (Build.VERSION.SDK_INT >= 31) GlassBackdrop() else null
    private val indicatorBackdrop = if (Build.VERSION.SDK_INT >= 31) GlassBackdrop(2f, 14f) else null
    private var flutter: FlutterView? = null
    private var observer: ViewTreeObserver? = null
    private val preDraw = ViewTreeObserver.OnPreDrawListener {
        // FlutterImageView becomes dirty only when Flutter submits content. No
        // timer or self-perpetuating redraw loop while the page is at rest.
        if (isShown && flutter?.currentImageSurface?.isDirty == true) invalidate()
        true
    }

    init {
        setWillNotDraw(false)
        clipChildren = false
        row.orientation = LinearLayout.HORIZONTAL
        row.setPadding(dp(4f).toInt(), dp(4f).toInt(), dp(4f).toInt(), dp(4f).toInt())
        tabs.forEach { row.addView(it, LinearLayout.LayoutParams(0, -1, 1f)) }
        addView(row, LayoutParams(-1, -1))
        configure(configuration)
        channel.setMethodCallHandler { call, result ->
            if (call.method == "configure" && !disposed) {
                configure(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                result.success(null)
            } else result.notImplemented()
        }
    }

    private fun configure(values: Map<*, *>) {
        primary = (values["primary"] as? Number)?.toInt() ?: primary
        foreground = (values["onSurface"] as? Number)?.toInt() ?: foreground
        surface = (values["surface"] as? Number)?.toInt() ?: surface
        dark = values["dark"] as? Boolean ?: dark
        reduceMotion = values["reduceMotion"] as? Boolean ?: false
        if (reduceMotion) {
            animator?.cancel()
            pressAnimator?.cancel()
            position = selected.toFloat()
            pressedAmount = 0f
        }
        layoutDirection = if (values["rtl"] == true) LAYOUT_DIRECTION_RTL else LAYOUT_DIRECTION_LTR
        val scale = (values["textScale"] as? Number)?.toFloat()?.coerceIn(1f, 1.3f) ?: 1f
        val next = (values["selectedIndex"] as? Number)?.toInt()?.coerceIn(0, 3) ?: selected
        if (next != selected) {
            selected = next
            animatePosition(next.toFloat())
        }
        tabs.forEachIndexed { index, tab ->
            tab.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX, dp(11f) * scale)
            tab.setTextColor(if (index == selected) primary else foreground)
            tab.isSelected = index == selected
            val icon = TabIcon(index, if (index == selected) primary else foreground)
            icon.setBounds(0, 0, dp(23f).toInt(), dp(23f).toInt())
            tab.setCompoundDrawables(null, icon, null, null)
            tab.background = StateListDrawable().apply {
                addState(intArrayOf(android.R.attr.state_focused), GradientDrawable().apply {
                    cornerRadius = dp(26f)
                    setColor(withAlpha(primary, 40))
                    setStroke(dp(2f).toInt().coerceAtLeast(1), primary)
                })
            }
        }
        invalidate()
    }

    private fun select(index: Int) {
        if (index != selected) {
            selected = index
            configure(mapOf("selectedIndex" to index, "reduceMotion" to reduceMotion,
                "rtl" to (layoutDirection == LAYOUT_DIRECTION_RTL),
                "textScale" to (tabs.first().textSize / dp(11f))))
            channel.invokeMethod("select", index)
        }
        animatePosition(index.toFloat())
    }

    private fun animatePosition(target: Float) {
        animator?.cancel()
        if (reduceMotion || !isAttachedToWindow) {
            position = target
            invalidate()
            return
        }
        animator = ValueAnimator.ofFloat(position, target).apply {
            duration = 360
            interpolator = OvershootInterpolator(0.65f)
            addUpdateListener { position = it.animatedValue as Float; invalidate() }
            start()
        }
    }

    private fun press(target: Float) {
        pressAnimator?.cancel()
        if (reduceMotion) { pressedAmount = 0f; invalidate(); return }
        pressAnimator = ValueAnimator.ofFloat(pressedAmount, target).apply {
            duration = 160
            addUpdateListener { pressedAmount = it.animatedValue as Float; invalidate() }
            start()
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        var ancestor = parent
        while (ancestor != null && ancestor !is FlutterView) ancestor = ancestor.parent
        flutter = ancestor as? FlutterView
        observer = viewTreeObserver
        observer?.addOnPreDrawListener(preDraw)
    }

    override fun onDetachedFromWindow() {
        if (observer?.isAlive == true) observer?.removeOnPreDrawListener(preDraw)
        observer = null
        flutter = null
        animator?.cancel()
        pressAnimator?.cancel()
        backdrop?.release()
        indicatorBackdrop?.release()
        super.onDetachedFromWindow()
    }

    override fun getView(): View = this
    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        if (observer?.isAlive == true) observer?.removeOnPreDrawListener(preDraw)
        animator?.cancel()
        pressAnimator?.cancel()
        backdrop?.release()
        indicatorBackdrop?.release()
        flutter = null
    }

    override fun onInterceptTouchEvent(event: MotionEvent) = true

    private fun indexAt(x: Float): Float {
        val fraction = ((x - dp(4f)) / (width - dp(8f))).coerceIn(0f, 1f)
        val logical = if (layoutDirection == LAYOUT_DIRECTION_RTL) 1f - fraction else fraction
        return (logical * 4f - 0.5f).coerceIn(0f, 3f)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.x; dragging = false
                animator?.cancel()
                parent.requestDisallowInterceptTouchEvent(true)
                press(1f)
            }
            MotionEvent.ACTION_MOVE -> {
                if (abs(event.x - downX) > ViewConfiguration.get(context).scaledTouchSlop) dragging = true
                if (dragging) { position = indexAt(event.x); invalidate() }
            }
            MotionEvent.ACTION_UP -> {
                press(0f)
                parent.requestDisallowInterceptTouchEvent(false)
                if (event.y in -dp(16f)..height + dp(16f)) {
                    val index = indexAt(event.x).roundToInt()
                    tabs[index].performClick()
                } else animatePosition(selected.toFloat())
                dragging = false
            }
            MotionEvent.ACTION_CANCEL -> {
                press(0f); dragging = false
                parent.requestDisallowInterceptTouchEvent(false)
                animatePosition(selected.toFloat())
            }
        }
        return true
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val bounds = RectF(0f, 0f, width.toFloat(), height.toFloat())
        val radius = height / 2f
        clip.reset(); clip.addRoundRect(bounds, radius, radius, Path.Direction.CW)
        canvas.save(); canvas.clipPath(clip)
        val source = flutter?.currentImageSurface
        var sampled = false
        var sourceX = 0f
        var sourceY = 0f
        if (Build.VERSION.SDK_INT >= 31 && canvas.isHardwareAccelerated && source != null) {
            val sourceLocation = IntArray(2); val location = IntArray(2)
            source.getLocationInWindow(sourceLocation); getLocationInWindow(location)
            sourceX = (location[0] - sourceLocation[0]).toFloat()
            sourceY = (location[1] - sourceLocation[1]).toFloat()
            sampled = backdrop?.draw(canvas, source,
                sourceX, sourceY, width, height, density) == true
        }
        paint.shader = null
        paint.style = Paint.Style.FILL
        paint.color = withAlpha(surface, if (sampled) { if (dark) 145 else 100 } else 245)
        canvas.drawRoundRect(bounds, radius, radius, paint)
        val tabWidth = (width - dp(8f)) / 4f
        val visualPosition = if (layoutDirection == LAYOUT_DIRECTION_RTL) 3f - position else position
        val cx = dp(4f) + (visualPosition + 0.5f) * tabWidth
        val extra = dp(3f) * pressedAmount
        val pill = RectF(cx - tabWidth / 2 + dp(1f) - extra, dp(4f) - extra / 2,
            cx + tabWidth / 2 - dp(1f) + extra, height - dp(4f) + extra / 2)
        if (Build.VERSION.SDK_INT >= 31 && sampled && source != null) {
            canvas.save()
            clip.reset(); clip.addRoundRect(pill, radius, radius, Path.Direction.CW)
            canvas.clipPath(clip)
            canvas.translate(pill.left, pill.top)
            indicatorBackdrop?.draw(canvas, source, sourceX + pill.left, sourceY + pill.top,
                pill.width().toInt(), pill.height().toInt(), density)
            canvas.restore()
            paint.color = withAlpha(surface, if (dark) 155 else 110)
            canvas.drawRoundRect(pill, radius, radius, paint)
        }
        paint.color = withAlpha(primary, if (dark) 54 else 25)
        canvas.drawRoundRect(pill, radius, radius, paint)
        paint.shader = LinearGradient(0f, 0f, width.toFloat(), height.toFloat(),
            intArrayOf(withAlpha(Color.WHITE, if (dark) 100 else 220),
                withAlpha(Color.WHITE, 15), withAlpha(Color.WHITE, 90)),
            floatArrayOf(0f, 0.55f, 1f), Shader.TileMode.CLAMP)
        paint.style = Paint.Style.STROKE; paint.strokeWidth = dp(1f)
        val inset = RectF(bounds).apply { inset(dp(0.6f), dp(0.6f)) }
        canvas.drawRoundRect(inset, radius, radius, paint)
        canvas.drawRoundRect(pill, radius, radius, paint)
        paint.shader = null; paint.style = Paint.Style.FILL
        canvas.restore()
    }

    private fun withAlpha(color: Int, alpha: Int) = (color and 0x00ffffff) or (alpha shl 24)
}

/** Hardware-only recording avoids readback, screenshots, and full-screen bitmaps. */
@RequiresApi(31)
private class GlassBackdrop(private val blurRadius: Float = 4f, private val lensDepth: Float = 24f) {
    private val node = RenderNode("nuistaio-glass-backdrop")
    private var effectSize = ""
    private val lens = if (Build.VERSION.SDK_INT >= 33) LensEffect() else null

    fun draw(canvas: Canvas, source: View, x: Float, y: Float,
             width: Int, height: Int, density: Float): Boolean {
        if (width <= 0 || height <= 0 || source.width <= 0) return false
        // Extra pixels allow blur and refraction to sample outside the capsule.
        val padding = (28f * density).toInt()
        val w = width + padding * 2; val h = height + padding * 2
        node.setPosition(-padding, -padding, width + padding, height + padding)
        val recording = node.beginRecording(w, h)
        recording.translate(padding - x, padding - y)
        source.draw(recording)
        node.endRecording()
        val key = "$width:$height:$density"
        if (effectSize != key) {
            val blur = RenderEffect.createBlurEffect(blurRadius * density, blurRadius * density, Shader.TileMode.CLAMP)
            node.setRenderEffect(if (Build.VERSION.SDK_INT >= 33) {
                lens?.create(width, height, padding, density * lensDepth, blur) ?: blur
            } else blur)
            effectSize = key
        }
        canvas.drawRenderNode(node)
        return true
    }

    fun release() { node.discardDisplayList() }
}

/** Capsule distance-field lens inspired by SukiSU / AndroidLiquidGlass. */
@RequiresApi(33)
private class LensEffect {
    private val shader = RuntimeShader("""
        uniform shader content;
        uniform float2 size;
        uniform float padding;
        uniform float depth;
        half4 main(float2 p) {
            float2 q = p - padding - size * 0.5;
            float r = size.y * 0.5;
            float2 v = float2(q.x - clamp(q.x, -size.x * 0.5 + r, size.x * 0.5 - r), q.y);
            float distance = length(v);
            float edge = clamp((distance - r + depth) / depth, 0.0, 1.0);
            float bend = (1.0 - sqrt(max(0.0, 1.0 - edge * edge))) * depth;
            float2 normal = v / max(distance, 0.001);
            return content.eval(p - normal * bend);
        }
    """.trimIndent())

    fun create(width: Int, height: Int, padding: Int, depth: Float, blur: RenderEffect): RenderEffect {
        shader.setFloatUniform("size", width.toFloat(), height.toFloat())
        shader.setFloatUniform("padding", padding.toFloat())
        shader.setFloatUniform("depth", depth)
        return RenderEffect.createChainEffect(RenderEffect.createRuntimeShaderEffect(shader, "content"), blur)
    }
}

private class TabIcon(private val index: Int, color: Int) : Drawable() {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color; style = Paint.Style.STROKE; strokeWidth = 1.8f
        strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    override fun draw(canvas: Canvas) {
        canvas.save(); canvas.translate(bounds.left.toFloat(), bounds.top.toFloat())
        canvas.scale(bounds.width() / 24f, bounds.height() / 24f)
        val path = Path()
        when (index) {
            0 -> {
                path.moveTo(3f, 10f); path.lineTo(12f, 3f); path.lineTo(21f, 10f)
                path.moveTo(5f, 9f); path.lineTo(5f, 21f); path.lineTo(10f, 21f)
                path.lineTo(10f, 14f); path.lineTo(14f, 14f); path.lineTo(14f, 21f)
                path.lineTo(19f, 21f); path.lineTo(19f, 9f)
            }
            1 -> {
                path.moveTo(12f, 5f); path.cubicTo(9f, 3f, 5f, 3f, 2f, 4f)
                path.lineTo(2f, 19f); path.cubicTo(6f, 18f, 9f, 18f, 12f, 20f)
                path.cubicTo(15f, 18f, 18f, 18f, 22f, 19f); path.lineTo(22f, 4f)
                path.cubicTo(18f, 3f, 15f, 3f, 12f, 5f); path.lineTo(12f, 20f)
            }
            2 -> {
                path.addRoundRect(3f, 3f, 10f, 10f, 1f, 1f, Path.Direction.CW)
                path.addRoundRect(14f, 3f, 21f, 10f, 1f, 1f, Path.Direction.CW)
                path.addRoundRect(3f, 14f, 10f, 21f, 1f, 1f, Path.Direction.CW)
                path.addRoundRect(14f, 14f, 21f, 21f, 1f, 1f, Path.Direction.CW)
            }
            3 -> {
                path.addCircle(12f, 7f, 4f, Path.Direction.CW)
                path.moveTo(4f, 21f); path.cubicTo(4f, 11f, 20f, 11f, 20f, 21f)
            }
        }
        canvas.drawPath(path, paint); canvas.restore()
    }
    override fun setAlpha(alpha: Int) { paint.alpha = alpha }
    override fun setColorFilter(colorFilter: ColorFilter?) { paint.colorFilter = colorFilter }
    @Suppress("DEPRECATION")
    override fun getOpacity() = PixelFormat.TRANSLUCENT
}
