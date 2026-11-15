package com.retrsoft.nuistaio.navigation

import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import android.view.View
import android.view.Gravity
import android.view.ViewTreeObserver
import android.widget.FrameLayout
import androidx.annotation.RequiresApi
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material.icons.outlined.AutoStories
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Widgets
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import com.retrsoft.nuistaio.navigation.sukisu.component.FloatingBottomBar
import com.retrsoft.nuistaio.navigation.sukisu.component.FloatingBottomBarItem
import com.retrsoft.nuistaio.navigation.sukisu.theme.LocalLiquidDark
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import top.yukonga.miuix.kmp.theme.LocalContentColor
import top.yukonga.miuix.kmp.theme.MiuixTheme

class LiquidNavFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val configuration = args as? Map<*, *> ?: emptyMap<Any, Any>()
        if (Build.VERSION.SDK_INT >= 33) return ComposeLiquidNavView(context, messenger, viewId, configuration)
        val legacy = LegacyLiquidNavView(context, messenger, viewId, configuration)
        val density = context.resources.displayMetrics.density
        val container = FrameLayout(context).apply {
            addView(legacy.getView(), FrameLayout.LayoutParams(-1, (64 * density).toInt(), Gravity.CENTER).apply {
                leftMargin = (16 * density).toInt()
                rightMargin = leftMargin
            })
        }
        return object : PlatformView {
            override fun getView(): View = container
            override fun dispose() = legacy.dispose()
        }
    }
}

private data class NavConfiguration(
    val selectedIndex: Int = 0,
    val primary: Int = android.graphics.Color.BLUE,
    val onSurface: Int = android.graphics.Color.BLACK,
    val surface: Int = android.graphics.Color.WHITE,
    val dark: Boolean = false,
    val rtl: Boolean = false,
    val textScale: Float = 1f,
    val progressiveBlur: Boolean = false,
) {
    fun update(values: Map<*, *>) = copy(
        selectedIndex = (values["selectedIndex"] as? Number)?.toInt()?.coerceIn(0, 3) ?: selectedIndex,
        primary = (values["primary"] as? Number)?.toInt() ?: primary,
        onSurface = (values["onSurface"] as? Number)?.toInt() ?: onSurface,
        surface = (values["surface"] as? Number)?.toInt() ?: surface,
        dark = values["dark"] as? Boolean ?: dark,
        rtl = values["rtl"] as? Boolean ?: rtl,
        textScale = (values["textScale"] as? Number)?.toFloat()?.coerceIn(1f, 1.3f) ?: textScale,
        progressiveBlur = values["progressiveBlur"] as? Boolean ?: progressiveBlur,
    )
}

@RequiresApi(33)
private class ComposeLiquidNavView(
    context: Context, messenger: BinaryMessenger, id: Int, configuration: Map<*, *>
) : FrameLayout(context), PlatformView {
    private val channel = MethodChannel(messenger, "nuistaio/liquid_nav/$id")
    private var config by mutableStateOf(NavConfiguration().update(configuration))
    private val backdrop = FlutterBackdrop()
    private val compose = ComposeView(context)
    private var flutter: FlutterView? = null
    private var observer: ViewTreeObserver? = null
    private var disposed = false
    private val preDraw = ViewTreeObserver.OnPreDrawListener {
        val source = flutter?.currentImageSurface
        if (source !== backdrop.source || source?.isDirty == true) {
            backdrop.source = source
            backdrop.frame.intValue++
        }
        true
    }

    init {
        clipChildren = false
        clipToPadding = false
        var activityContext: Context = context
        while (activityContext is ContextWrapper && activityContext !is FragmentActivity) {
            activityContext = activityContext.baseContext
        }
        val activity = activityContext as FragmentActivity
        compose.setViewTreeLifecycleOwner(activity)
        compose.setViewTreeSavedStateRegistryOwner(activity)
        addView(compose, LayoutParams(-1, -1))
        compose.setContent {
            val config = config
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalLiquidDark provides config.dark,
                LocalLayoutDirection provides if (config.rtl) LayoutDirection.Rtl else LayoutDirection.Ltr,
                LocalDensity provides Density(density.density, config.textScale),
            ) {
                MiuixTheme {
                    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        FloatingBottomBar(
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                            selectedIndex = config.selectedIndex,
                            onSelected = { index ->
                                if (!disposed && index in 0..3) {
                                    this@ComposeLiquidNavView.config = this@ComposeLiquidNavView.config.copy(selectedIndex = index)
                                    channel.invokeMethod("select", index)
                                }
                            },
                            backdrop = backdrop,
                            tabsCount = 4,
                            isBlurEnabled = true,
                            progressiveBlur = config.progressiveBlur,
                            accentColor = Color(config.primary),
                            tabContentColor = Color(config.onSurface),
                            surfaceContainer = Color(config.surface),
                        ) { activateTab ->
                            val labels = listOf("首页", "学习", "功能", "我的")
                            val filled = listOf(Icons.Filled.Home, Icons.Filled.AutoStories, Icons.Filled.Widgets, Icons.Filled.Person)
                            val outlined = listOf(Icons.Outlined.Home, Icons.Outlined.AutoStories, Icons.Outlined.Widgets, Icons.Outlined.Person)
                            labels.forEachIndexed { index, label ->
                                val selected = config.selectedIndex == index
                                FloatingBottomBarItem(
                                    selected = selected,
                                    onClick = { activateTab(index) },
                                    modifier = Modifier.defaultMinSize(minWidth = 56.dp),
                                ) {
                                    Image(
                                        imageVector = if (selected) filled[index] else outlined[index],
                                        contentDescription = null,
                                        modifier = Modifier.size(24.dp),
                                        colorFilter = ColorFilter.tint(LocalContentColor.current),
                                    )
                                    BasicText(
                                        text = label,
                                        style = TextStyle(color = LocalContentColor.current, fontSize = 11.sp, lineHeight = 14.sp),
                                        maxLines = 1,
                                        softWrap = false,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        channel.setMethodCallHandler { call, result ->
            if (call.method == "configure" && !disposed) {
                config = config.update(call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                result.success(null)
            } else result.notImplemented()
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
        detachBackdrop()
        super.onDetachedFromWindow()
    }

    private fun detachBackdrop() {
        if (observer?.isAlive == true) observer?.removeOnPreDrawListener(preDraw)
        observer = null
        flutter = null
        backdrop.source = null
    }

    override fun getView(): View = this

    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        detachBackdrop()
        compose.disposeComposition()
    }
}
