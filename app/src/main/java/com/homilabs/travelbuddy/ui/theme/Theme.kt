package com.homilabs.travelbuddy.ui.theme

import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val TbGreen = Color(0xFF12704A)
val TbGreenLight = Color(0xFF6FD6A3)
val TbAmber = Color(0xFFF2A516)

private val Light = lightColorScheme(
    primary = TbGreen,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFCDEFDC),
    onPrimaryContainer = Color(0xFF002113),
    secondary = Color(0xFF4E6356),
    secondaryContainer = Color(0xFFD1E8D8),
    tertiary = Color(0xFF8A5A00),
    tertiaryContainer = TbAmber.copy(alpha = 0.25f),
    background = Color(0xFFF7FBF7),
    surface = Color(0xFFF7FBF7),
    surfaceVariant = Color(0xFFDCE5DD),
    error = Color(0xFFB3261E),
)

private val Dark = darkColorScheme(
    primary = TbGreenLight,
    onPrimary = Color(0xFF003822),
    primaryContainer = Color(0xFF005234),
    onPrimaryContainer = Color(0xFFCDEFDC),
    secondary = Color(0xFFB5CCBC),
    secondaryContainer = Color(0xFF374B3F),
    tertiary = Color(0xFFFFBA3D),
    tertiaryContainer = Color(0xFF5A3D00),
    background = Color(0xFF101512),
    surface = Color(0xFF101512),
    surfaceVariant = Color(0xFF404943),
)

@Composable
fun TravelBuddyTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) Dark else Light,
        content = content,
    )
}
