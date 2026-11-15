package com.retrsoft.nuistaio.navigation.sukisu.util

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import top.yukonga.miuix.kmp.blur.Backdrop
import top.yukonga.miuix.kmp.blur.BlendColorEntry
import top.yukonga.miuix.kmp.blur.BlurColors
import top.yukonga.miuix.kmp.blur.ProgressiveBlur
import top.yukonga.miuix.kmp.blur.progressiveTextureBlur
import top.yukonga.miuix.kmp.blur.isRuntimeShaderSupported

// SukiSU's progressive-bar helper, with app-wallpaper composition supplied by
// FlutterBackdrop rather than the SukiSU-only wallpaper CompositionLocals.
@Composable
fun rememberProgressiveBarBlurModifier(
    backdrop: Backdrop?,
    gradient: ProgressiveBlur,
    tint: Color,
    tintAlpha: Float,
    blurRadius: Float = 25f,
    shape: Shape = RectangleShape,
): Modifier {
    if (!isRuntimeShaderSupported() || backdrop == null) return Modifier
    return remember(backdrop, gradient, tint, tintAlpha, blurRadius, shape) {
        Modifier.progressiveTextureBlur(
            backdrop = backdrop,
            shape = shape,
            blurRadius = blurRadius,
            gradient = gradient,
            colors = BlurColors(blendColors = listOf(BlendColorEntry(color = tint.copy(alpha = tintAlpha)))),
        )
    }
}
