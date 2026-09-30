package com.homilabs.travelbuddy.ui.auth

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Block
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.homilabs.travelbuddy.R
import com.homilabs.travelbuddy.data.RegisterForm
import com.homilabs.travelbuddy.data.Repo
import com.homilabs.travelbuddy.model.UserProfile
import com.homilabs.travelbuddy.ui.Centered
import com.homilabs.travelbuddy.ui.ErrorNote
import com.homilabs.travelbuddy.ui.LabeledValue
import com.homilabs.travelbuddy.ui.toast
import com.homilabs.travelbuddy.util.Prefs
import kotlinx.coroutines.launch

private enum class AuthPage { LOGIN, REGISTER, CONSENT, FORGOT }

@Composable
fun AuthFlow(notice: String?) {
    var page by rememberSaveable { mutableStateOf(AuthPage.LOGIN) }
    // Kept across Register → Consent so the form isn't lost.
    var form by remember { mutableStateOf<RegisterForm?>(null) }

    BackHandler(enabled = page != AuthPage.LOGIN) {
        page = if (page == AuthPage.CONSENT) AuthPage.REGISTER else AuthPage.LOGIN
    }
    when (page) {
        AuthPage.LOGIN -> LoginScreen(
            notice = notice,
            onRegister = { page = AuthPage.REGISTER },
            onForgot = { page = AuthPage.FORGOT },
        )
        AuthPage.REGISTER -> RegisterScreen(
            initial = form,
            onBack = { page = AuthPage.LOGIN },
            onNext = { form = it; page = AuthPage.CONSENT },
        )
        AuthPage.CONSENT -> ConsentScreen(
            form = form!!,
            onBack = { page = AuthPage.REGISTER },
        )
        AuthPage.FORGOT -> ForgotScreen(onBack = { page = AuthPage.LOGIN })
    }
}

@Composable
private fun AuthColumn(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxSize().systemBarsPadding().imePadding().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) { content() }
}

@Composable
private fun Logo() {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        Image(painterResource(R.drawable.logo_mark), null, Modifier.size(96.dp))
        Text("TravelBuddy", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.primary)
        Text("Township ⇄ Plant carpool for the FFL community", style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center)
    }
}

@Composable
private fun PasswordField(value: String, onChange: (String) -> Unit, label: String = "Password") {
    var show by remember { mutableStateOf(false) }
    OutlinedTextField(
        value = value, onValueChange = onChange, label = { Text(label) }, singleLine = true,
        visualTransformation = if (show) VisualTransformation.None else PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        trailingIcon = {
            IconButton(onClick = { show = !show }) {
                Icon(if (show) Icons.Default.VisibilityOff else Icons.Default.Visibility, if (show) "Hide" else "Show")
            }
        },
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun LoginScreen(notice: String?, onRegister: () -> Unit, onForgot: () -> Unit) {
    val scope = rememberCoroutineScope()
    var email by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AuthColumn {
        Spacer(Modifier.height(24.dp))
        Logo()
        Spacer(Modifier.height(8.dp))
        if (!notice.isNullOrBlank()) {
            Card { Text(notice, Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium) }
        }
        OutlinedTextField(
            value = email, onValueChange = { email = it.trim() }, label = { Text("Email") }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth(),
        )
        PasswordField(password, { password = it })
        ErrorNote(error)
        Button(
            onClick = {
                error = null; busy = true
                scope.launch {
                    try {
                        Repo.login(email, password)
                    } catch (e: Exception) {
                        error = Repo.friendly(e)
                    } finally {
                        busy = false
                    }
                }
            },
            enabled = !busy && email.contains('@') && password.isNotEmpty(),
            modifier = Modifier.fillMaxWidth().height(48.dp),
        ) { if (busy) CircularProgressIndicator(Modifier.size(22.dp)) else Text("Log in") }
        TextButton(onClick = onForgot, modifier = Modifier.align(Alignment.End)) { Text("Forgot password?") }
        OutlinedButton(onClick = onRegister, modifier = Modifier.fillMaxWidth()) { Text("New here? Register") }
    }
}

@Composable
private fun RegisterScreen(initial: RegisterForm?, onBack: () -> Unit, onNext: (RegisterForm) -> Unit) {
    var name by rememberSaveable { mutableStateOf(initial?.name ?: "") }
    var email by rememberSaveable { mutableStateOf(initial?.email ?: "") }
    var password by remember { mutableStateOf(initial?.password ?: "") }
    var password2 by remember { mutableStateOf(initial?.password ?: "") }
    var employeeId by rememberSaveable { mutableStateOf(initial?.employeeId ?: "") }
    var department by rememberSaveable { mutableStateOf(initial?.department ?: "") }
    var phone by rememberSaveable { mutableStateOf(initial?.phone ?: "") }
    var township by rememberSaveable { mutableStateOf(initial?.townshipLocation ?: "") }
    var error by remember { mutableStateOf<String?>(null) }

    fun validate(): String? {
        val digits = phone.filter { it.isDigit() }
        return when {
            name.trim().length < 3 -> "Please enter your full name."
            !Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(email.trim()) -> "Please enter a valid email address."
            password.length < 8 -> "Password must be at least 8 characters."
            password != password2 -> "The two passwords don't match."
            employeeId.isBlank() -> "Please enter your employee ID."
            department.isBlank() -> "Please enter your department."
            digits.length !in 10..13 || !Regex("^[+0-9 -]+$").matches(phone.trim()) ->
                "Please enter a valid mobile number, e.g. 03001234567."
            township.isBlank() -> "Please enter your township location (e.g. house/block)."
            else -> null
        }
    }

    AuthColumn {
        Text("Register", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("An admin will approve your account. Your phone number is visible to approved members so rides can be arranged.",
            style = MaterialTheme.typography.bodyMedium)
        @Composable
        fun field(v: String, set: (String) -> Unit, label: String, kb: KeyboardType = KeyboardType.Text) =
            OutlinedTextField(
                value = v, onValueChange = set, label = { Text(label) }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = kb), modifier = Modifier.fillMaxWidth(),
            )
        field(name, { name = it.take(60) }, "Full name")
        field(email, { email = it.trim().take(100) }, "Email (personal is fine)", KeyboardType.Email)
        PasswordField(password, { password = it.take(64) }, "Password (min 8 characters)")
        PasswordField(password2, { password2 = it.take(64) }, "Repeat password")
        field(employeeId, { employeeId = it.take(20) }, "Employee ID")
        field(department, { department = it.take(60) }, "Department")
        field(phone, { phone = it.take(16) }, "Mobile number", KeyboardType.Phone)
        field(township, { township = it.take(80) }, "Township location (house / block)")
        ErrorNote(error)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onBack, modifier = Modifier.weight(1f)) { Text("Back") }
            Button(
                onClick = {
                    error = validate()
                    if (error == null) onNext(
                        RegisterForm(name, email, password, employeeId, department, phone, township)
                    )
                },
                modifier = Modifier.weight(1f),
            ) { Text("Next") }
        }
    }
}

@Composable
private fun ConsentScreen(form: RegisterForm, onBack: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var agreed by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    AuthColumn {
        Text("Before you join", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Card {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("1. TravelBuddy is a free, volunteer carpool between colleagues. No money is involved; each ride is a private arrangement.")
                Text("2. Your name, phone, employee ID and department are visible to approved members so rides can be arranged.")
                Text("3. During a started ride, the driver's live location is shared only with that ride's passengers. Ride history is deleted after 30 days.")
            }
        }
        Row(
            Modifier.fillMaxWidth().toggleable(value = agreed, role = Role.Checkbox, onValueChange = { agreed = it }),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Checkbox(checked = agreed, onCheckedChange = null)
            Text("I understand and agree", Modifier.padding(start = 8.dp))
        }
        ErrorNote(error)
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                enabled = agreed && !busy,
                onClick = {
                    busy = true; error = null
                    scope.launch {
                        try {
                            Prefs(ctx).consentAccepted = true
                            Repo.register(form)
                            ctx.toast("Registered. Waiting for admin approval.")
                        } catch (e: Exception) {
                            error = Repo.friendly(e)
                        } finally {
                            busy = false
                        }
                    }
                },
                modifier = Modifier.fillMaxWidth(),
            ) { if (busy) CircularProgressIndicator(Modifier.size(22.dp)) else Text("Agree & register") }
            OutlinedButton(onClick = onBack, enabled = !busy, modifier = Modifier.fillMaxWidth()) { Text("Back") }
        }
    }
}

@Composable
private fun ForgotScreen(onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var email by rememberSaveable { mutableStateOf("") }
    var sent by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AuthColumn {
        Text("Reset password", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("We'll email you a link to choose a new password. Check your spam folder too.")
        OutlinedTextField(
            value = email, onValueChange = { email = it.trim() }, label = { Text("Email") }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth(),
        )
        ErrorNote(error)
        if (sent) Text("If an account exists for $email, a reset email is on its way.", color = MaterialTheme.colorScheme.primary)
        Button(
            enabled = !busy && email.contains('@'),
            onClick = {
                busy = true; error = null
                scope.launch {
                    try {
                        Repo.sendPasswordReset(email); sent = true
                    } catch (e: Exception) {
                        // Don't reveal whether the account exists.
                        val msg = Repo.friendly(e)
                        if ("No account" in msg) sent = true else error = msg
                    } finally {
                        busy = false
                    }
                }
            },
            modifier = Modifier.fillMaxWidth(),
        ) { Text("Send reset email") }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) { Text("Back to login") }
    }
}

// ---------------------------------------------------------------- account states

@Composable
fun PendingScreen(profile: UserProfile) {
    Column(
        Modifier.fillMaxSize().systemBarsPadding().verticalScroll(rememberScrollState()).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Spacer(Modifier.height(32.dp))
        Icon(Icons.Default.HourglassTop, null, Modifier.size(64.dp), tint = MaterialTheme.colorScheme.primary)
        Text("Waiting for approval", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text(
            "An admin will check your details. This screen updates by itself as soon as you're approved — you can close the app meanwhile.",
            textAlign = TextAlign.Center,
        )
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                LabeledValue("Name", profile.name)
                LabeledValue("Email", profile.email)
                LabeledValue("Employee ID", profile.employeeId)
                LabeledValue("Department", profile.department)
                LabeledValue("Phone", profile.phone)
                LabeledValue("Township", profile.townshipLocation)
            }
        }
        OutlinedButton(onClick = { Repo.logout() }) { Text("Log out") }
    }
}

@Composable
fun BlockedScreen(profile: UserProfile) {
    Centered {
        Icon(Icons.Default.Block, null, Modifier.size(64.dp), tint = MaterialTheme.colorScheme.error)
        Spacer(Modifier.height(12.dp))
        Text("Account blocked", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        val reason = profile.audit.lastOrNull { it.action == "BLOCKED" }?.reason
        Text(
            "Your TravelBuddy account has been blocked by an admin." +
                (if (!reason.isNullOrBlank()) "\n\nReason: $reason" else "") +
                "\n\nPlease contact the TravelBuddy admin if you think this is a mistake.",
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(16.dp))
        OutlinedButton(onClick = { Repo.logout() }) { Text("Log out") }
    }
}

@Composable
fun MissingProfileScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    Centered {
        Text("Account setup not finished", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(8.dp))
        Text(
            "We couldn't find your TravelBuddy profile. This happens if registration was interrupted. " +
                "Please log out and register again, or contact the admin.",
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(16.dp))
        if (Repo.lastRegisterForm != null) Button(onClick = {
            scope.launch {
                try { Repo.finishRegistration() } catch (e: Exception) { ctx.toast(Repo.friendly(e)) }
            }
        }) { Text("Try again") }
        OutlinedButton(onClick = { Repo.logout() }) { Text("Log out") }
    }
}
