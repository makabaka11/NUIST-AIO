package com.retrsoft.nuistaio.navigation

import android.view.View
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.unit.Density
import top.yukonga.miuix.kmp.blur.Backdrop
import top.yukonga.miuix.kmp.blur.BackdropEffectScope

/** Supplies Flutter's background image to the unmodified miuix effect pipeline.
 * Native canvas recording stays on GPU, excludes this bar and Flutter's foreground
 * overlays, and uses the same inverse-transform math as miuix's LayerBackdrop.
 */
internal class FlutterBackdrop : Backdrop {
    override val isCoordinatesDependent = true
    override var offsetResidualX = 0f
    override var offsetResidualY = 0f
    var source: View? = null
    val frame = mutableIntStateOf(0)
    private val inverse = InverseLayerScope()
    private val sourceLocation = IntArray(2)

    override fun DrawScope.drawBackdrop(
        density: Density,
        coordinates: LayoutCoordinates?,
        layerBlock: (GraphicsLayerScope.() -> Unit)?,
        downscaleFactor: Int,
    ) {
        frame.intValue // Read in the draw phase: invalidates effects when Flutter submits a frame.
        val source = source ?: return
        val coordinates = coordinates?.takeIf { it.isAttached } ?: return
        source.getLocationInWindow(sourceLocation)
        val offset = coordinates.positionInWindow() - Offset(sourceLocation[0].toFloat(), sourceLocation[1].toFloat())
        val consumerSize = (density as? BackdropEffectScope)?.size ?: size
        withTransform({
            if (layerBlock != null) {
                inverse.reset()
                with(inverse) { inverseTransform(density, consumerSize, layerBlock) }
            }
            if (downscaleFactor > 1) {
                val factor = 1f / downscaleFactor
                val scaled = offset * factor
                val roundedX = kotlin.math.round(scaled.x * 0.5f) * 2f
                val roundedY = kotlin.math.round(scaled.y * 0.5f) * 2f
                offsetResidualX = (scaled.x - roundedX) * downscaleFactor
                offsetResidualY = (scaled.y - roundedY) * downscaleFactor
                translate(-roundedX, -roundedY)
                scale(factor, factor, Offset.Zero)
            } else {
                offsetResidualX = 0f
                offsetResidualY = 0f
                translate(-offset.x, -offset.y)
            }
        }) {
            source.draw(drawContext.canvas.nativeCanvas)
        }
    }
}
