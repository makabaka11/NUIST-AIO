package com.retrsoft.nuistaio.navigation.sukisu.theme

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf

val LocalLiquidDark = staticCompositionLocalOf { false }

@Composable
fun isInDarkTheme(): Boolean = LocalLiquidDark.current
