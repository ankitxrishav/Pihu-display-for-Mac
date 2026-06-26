package com.pihu.display

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowManager
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.io.InputStream
import java.net.ServerSocket
import java.net.Socket
import java.net.InetSocketAddress
import kotlin.concurrent.thread
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.content.Context
import org.json.JSONObject
import java.util.UUID

class MainActivity : Activity(), SurfaceHolder.Callback {

    private val TAG = "PihuDisplay"
    private val PORT = 27183

    private var surfaceView: SurfaceView? = null
    private var lastVideoWidth = 0
    private var lastVideoHeight = 0
    private var decoder: MediaCodec? = null
    private var isDecoderConfigured = false
    private var surface: Surface? = null

    @Volatile
    private var isRunning = false
    private var rxThread: Thread? = null
    private var decoderThread: Thread? = null

    private var overlayView: LinearLayout? = null
    private var statusText: TextView? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        
        val container = FrameLayout(this)
        container.setBackgroundColor(Color.parseColor("#121214"))
        container.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            if (lastVideoWidth > 0 && lastVideoHeight > 0) {
                adjustSurfaceViewAspectRatio(lastVideoWidth, lastVideoHeight)
            }
        }

        surfaceView = SurfaceView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER
            )
        }
        surfaceView?.holder?.addCallback(this)
        container.addView(surfaceView)

        val welcomeLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#E0121214"))
            val paddingPx = (40 * resources.displayMetrics.density).toInt()
            setPadding(paddingPx, paddingPx, paddingPx, paddingPx)
        }

        val catIcon = ImageView(this).apply {
            val drawableId = resources.getIdentifier("ic_cat_launcher", "mipmap", packageName)
            if (drawableId != 0) {
                setImageResource(drawableId)
            }
            val size = (128 * resources.displayMetrics.density).toInt()
            layoutParams = LinearLayout.LayoutParams(size, size).apply {
                bottomMargin = (24 * resources.displayMetrics.density).toInt()
            }
        }
        welcomeLayout.addView(catIcon)

        val titleText = TextView(this).apply {
            text = "Pihu Display"
            textSize = 28f
            setTextColor(Color.parseColor("#FFFFFF"))
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = (8 * resources.displayMetrics.density).toInt()
            }
        }
        welcomeLayout.addView(titleText)

        statusText = TextView(this).apply {
            text = "Waiting for host connection..."
            textSize = 16f
            setTextColor(Color.parseColor("#A0A0A2"))
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = (32 * resources.displayMetrics.density).toInt()
            }
        }
        welcomeLayout.addView(statusText)

        val guideBox = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#1E1E22"))
            val pX = (24 * resources.displayMetrics.density).toInt()
            val pY = (16 * resources.displayMetrics.density).toInt()
            setPadding(pX, pY, pX, pY)
            layoutParams = LinearLayout.LayoutParams(
                (360 * resources.displayMetrics.density).toInt(),
                LinearLayout.LayoutParams.WRAP_CONTENT
            )
        }

        val guideTitle = TextView(this).apply {
            text = "Connection Guide"
            textSize = 14f
            setTextColor(Color.parseColor("#808082"))
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = (12 * resources.displayMetrics.density).toInt()
            }
        }
        guideBox.addView(guideTitle)

        val guideSteps = TextView(this).apply {
            text = "1. Connect device to Mac via USB\n" +
                   "2. Enable USB Debugging in Developer Options\n" +
                   "3. Run ./run.sh on your Mac"
            textSize = 14f
            setTextColor(Color.parseColor("#D0D0D2"))
            setLineSpacing(8f, 1.1f)
        }
        guideBox.addView(guideSteps)
        welcomeLayout.addView(guideBox)

        container.addView(welcomeLayout)
        setContentView(container)

        overlayView = welcomeLayout
    }

    override fun onResume() {
        super.onResume()
        hideSystemUI()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            hideSystemUI()
        }
    }

    private fun hideSystemUI() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            window.setDecorFitsSystemWindows(false)
            val controller = window.insetsController
            if (controller != null) {
                controller.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY)
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    private fun adjustSurfaceViewAspectRatio(videoWidth: Int, videoHeight: Int) {
        lastVideoWidth = videoWidth
        lastVideoHeight = videoHeight
        
        runOnUiThread {
            val view = surfaceView ?: return@runOnUiThread
            val container = view.parent as? View ?: return@runOnUiThread
            val containerWidth = container.width
            val containerHeight = container.height
            if (containerWidth <= 0 || containerHeight <= 0 || videoWidth <= 0 || videoHeight <= 0) return@runOnUiThread

            val videoAspect = videoWidth.toFloat() / videoHeight.toFloat()
            val containerAspect = containerWidth.toFloat() / containerHeight.toFloat()

            val targetWidth: Int
            val targetHeight: Int

            if (videoAspect > containerAspect) {
                // Video is wider than screen aspect ratio: letterbox
                targetWidth = containerWidth
                targetHeight = (containerWidth / videoAspect).toInt()
            } else {
                // Video is taller than screen aspect ratio: pillarbox
                targetHeight = containerHeight
                targetWidth = (containerHeight * videoAspect).toInt()
            }

            val lp = view.layoutParams as FrameLayout.LayoutParams
            lp.width = targetWidth
            lp.height = targetHeight
            lp.gravity = Gravity.CENTER
            view.layoutParams = lp
            Log.d(TAG, "Adjusted SurfaceView size to ${targetWidth}x${targetHeight} for video ${videoWidth}x${videoHeight}")
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        Log.d(TAG, "Surface created")
        surface = holder.surface
        startStreaming()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        Log.d(TAG, "Surface changed: ${width}x${height}")
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        Log.d(TAG, "Surface destroyed")
        stopStreaming()
        surface = null
    }

    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var multicastLock: WifiManager.MulticastLock? = null

    private fun registerNsdService() {
        try {
            // 1. Acquire Multicast Lock
            val wifiManager = getSystemService(Context.WIFI_SERVICE) as WifiManager
            multicastLock = wifiManager.createMulticastLock("PihuMulticastLock").apply {
                setReferenceCounted(true)
                acquire()
            }
            Log.d(TAG, "Multicast lock acquired")
            
            // 2. Register NSD Service
            nsdManager = (getSystemService(Context.NSD_SERVICE) as NsdManager).apply {
                val serviceInfo = NsdServiceInfo().apply {
                    serviceName = "PihuDisplay-${android.os.Build.MODEL.replace(" ", "_")}"
                    serviceType = "_pihu._tcp."
                    port = PORT
                }
                
                registrationListener = object : NsdManager.RegistrationListener {
                    override fun onServiceRegistered(registeredInfo: NsdServiceInfo) {
                        Log.d(TAG, "NSD Service registered: ${registeredInfo.serviceName}")
                    }
                    
                    override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                        Log.e(TAG, "NSD Registration failed: $errorCode")
                    }
                    
                    override fun onServiceUnregistered(registeredInfo: NsdServiceInfo) {
                        Log.d(TAG, "NSD Service unregistered")
                    }
                    
                    override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                        Log.e(TAG, "NSD Unregistration failed: $errorCode")
                    }
                }
                
                registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register NSD service", e)
        }
    }
    
    private fun unregisterNsdService() {
        try {
            registrationListener?.let {
                nsdManager?.unregisterService(it)
            }
            registrationListener = null
            nsdManager = null
            
            multicastLock?.let {
                if (it.isHeld) {
                    it.release()
                }
            }
            multicastLock = null
            Log.d(TAG, "NSD service unregistered and multicast lock released")
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering NSD service", e)
        }
    }

    private fun startStreaming() {
        if (isRunning) return
        isRunning = true
        registerNsdService()

        rxThread = thread(name = "PihuRxThread", priority = Thread.MAX_PRIORITY) {
            runRxLoop()
        }
    }

    private fun stopStreaming() {
        isRunning = false
        unregisterNsdService()
        rxThread?.interrupt()
        rxThread = null
        
        decoderThread?.interrupt()
        decoderThread = null

        releaseDecoder()
    }

    private fun initDecoder(surface: Surface) {
        try {
            Log.d(TAG, "Initializing MediaCodec decoder")
            val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            
            // We configure with 1920x1080 default, but the decoder will adapt
            // when it receives the SPS/PPS NAL units.
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1080)
            
            // Set low-latency properties if supported by the hardware
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, android.media.MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
            }
            
            try {
                codec.configure(format, surface, null, 0)
            } catch (e: Exception) {
                Log.w(TAG, "MediaCodec low-latency configuration failed, retrying with standard parameters", e)
                val safeFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1080)
                codec.configure(safeFormat, surface, null, 0)
            }
            codec.start()
            
            decoder = codec
            isDecoderConfigured = true
            Log.d(TAG, "MediaCodec decoder started successfully")

            // Start decoder output pulling thread
            val myCodec = codec
            decoderThread = thread(name = "PihuDecoderThread", priority = Thread.MAX_PRIORITY) {
                val bufferInfo = MediaCodec.BufferInfo()
                while (isRunning && decoder == myCodec) {
                    try {
                        val outputBufferIndex = myCodec.dequeueOutputBuffer(bufferInfo, 10000) // 10ms timeout
                        if (outputBufferIndex >= 0) {
                            myCodec.releaseOutputBuffer(outputBufferIndex, true)
                        } else if (outputBufferIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            val newFormat = myCodec.outputFormat
                            val hasCrop = newFormat.containsKey("crop-left") && newFormat.containsKey("crop-right") &&
                                          newFormat.containsKey("crop-top") && newFormat.containsKey("crop-bottom")
                            val videoWidth = if (hasCrop) {
                                newFormat.getInteger("crop-right") - newFormat.getInteger("crop-left") + 1
                            } else {
                                newFormat.getInteger(MediaFormat.KEY_WIDTH)
                            }
                            val videoHeight = if (hasCrop) {
                                newFormat.getInteger("crop-bottom") - newFormat.getInteger("crop-top") + 1
                            } else {
                                newFormat.getInteger(MediaFormat.KEY_HEIGHT)
                            }
                            Log.d(TAG, "Decoder output format changed: ${videoWidth}x${videoHeight}")
                            adjustSurfaceViewAspectRatio(videoWidth, videoHeight)
                        }
                    } catch (e: InterruptedException) {
                        break
                    } catch (e: Exception) {
                        if (decoder != myCodec) {
                            break
                        }
                        Log.e(TAG, "Error in decoder output thread", e)
                        try { Thread.sleep(50) } catch (ex: InterruptedException) { break }
                    }
                }
                Log.d(TAG, "Decoder thread exiting for codec $myCodec")
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize decoder", e)
            runOnUiThread {
                Toast.makeText(this, "Failed to init hardware decoder: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun releaseDecoder() {
        Log.d(TAG, "Releasing MediaCodec decoder")
        isDecoderConfigured = false
        val codec = decoder
        decoder = null
        codec?.let {
            try {
                it.stop()
                it.release()
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing decoder", e)
            }
        }
    }

    private fun readExactly(inputStream: InputStream, buffer: ByteArray, length: Int): Boolean {
        var totalRead = 0
        while (totalRead < length) {
            val read = inputStream.read(buffer, totalRead, length - totalRead)
            if (read == -1) return false
            totalRead += read
        }
        return true
    }

    private fun sendLengthPrefixedData(outputStream: java.io.OutputStream, data: ByteArray): Boolean {
        return try {
            val lengthBuffer = java.nio.ByteBuffer.allocate(4).putInt(data.size)
            outputStream.write(lengthBuffer.array())
            outputStream.write(data)
            outputStream.flush()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Error writing length-prefixed data", e)
            false
        }
    }
    
    private fun readLengthPrefixedData(inputStream: InputStream): ByteArray? {
        val lengthBuffer = ByteArray(4)
        if (!readExactly(inputStream, lengthBuffer, 4)) return null
        val length = ((lengthBuffer[0].toInt() and 0xFF) shl 24) or
                     ((lengthBuffer[1].toInt() and 0xFF) shl 16) or
                     ((lengthBuffer[2].toInt() and 0xFF) shl 8) or
                     (lengthBuffer[3].toInt() and 0xFF)
        if (length <= 0 || length > 10 * 1024 * 1024) return null
        val dataBuffer = ByteArray(length)
        if (!readExactly(inputStream, dataBuffer, length)) return null
        return dataBuffer
    }

    private fun runRxLoop() {
        val lengthBuffer = ByteArray(4)
        var payloadBuffer = ByteArray(1024 * 1024) // 1MB reusable buffer
        var serverSocket: ServerSocket? = null

        while (isRunning) {
            val s = surface
            if (s == null) {
                try { Thread.sleep(100) } catch (e: InterruptedException) {}
                continue
            }

            // Ensure decoder is initialized
            if (decoder == null) {
                initDecoder(s)
            }

            // Ensure ServerSocket is active and bound
            if (serverSocket == null || serverSocket.isClosed) {
                try {
                    Log.d(TAG, "Starting ServerSocket on port $PORT...")
                    runOnUiThread {
                        statusText?.text = "Waiting for host connection..."
                        overlayView?.visibility = View.VISIBLE
                    }
                    val sSock = ServerSocket()
                    sSock.reuseAddress = true
                    sSock.bind(InetSocketAddress(PORT))
                    serverSocket = sSock
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start ServerSocket: ${e.message}")
                    try { Thread.sleep(1000) } catch (ex: InterruptedException) {}
                    continue
                }
            }

            var socket: Socket? = null
            var inputStream: InputStream? = null
            try {
                Log.d(TAG, "Waiting for incoming connection...")
                val sock = serverSocket.accept()
                socket = sock
                socket.tcpNoDelay = true
                socket.receiveBufferSize = 1024 * 1024
                
                // Get physical screen size
                val displayMetrics = resources.displayMetrics
                val screenWidth = displayMetrics.widthPixels
                val screenHeight = displayMetrics.heightPixels
                Log.d(TAG, "Host connected successfully! Screen size: ${screenWidth}x${screenHeight}")

                inputStream = socket.getInputStream()
                val outputStream = socket.getOutputStream()

                // JSON Handshake and Pairing
                val handshakeBytes = readLengthPrefixedData(inputStream)
                if (handshakeBytes == null) {
                    throw Exception("Failed to read handshake bytes from client")
                }
                
                val handshakeJson = JSONObject(String(handshakeBytes, Charsets.UTF_8))
                val clientId = handshakeJson.optString("client_id")
                val clientToken = handshakeJson.optString("token")
                
                val isLoopback = sock.inetAddress.isLoopbackAddress
                var isPaired = false
                var generatedToken = ""
                
                if (isLoopback) {
                    Log.d(TAG, "Connection from loopback. Implicitly trusted.")
                    isPaired = true
                } else {
                    val prefs = getSharedPreferences("pihu_paired_devices", Context.MODE_PRIVATE)
                    val storedToken = prefs.getString(clientId, null)
                    if (storedToken != null && storedToken == clientToken) {
                        Log.d(TAG, "Client token verified successfully.")
                        isPaired = true
                    }
                }
                
                if (!isPaired) {
                    val randomPin = (100000 + (Math.random() * 900000).toInt()).toString()
                    Log.d(TAG, "Pairing required. Generated PIN: $randomPin")
                    
                    runOnUiThread {
                        statusText?.text = "Pairing Code: $randomPin\nEnter this code on your Mac."
                        overlayView?.visibility = View.VISIBLE
                    }
                    
                    val pairingRequiredResp = JSONObject().apply {
                        put("status", "pairing_required")
                    }
                    if (!sendLengthPrefixedData(outputStream, pairingRequiredResp.toString().toByteArray(Charsets.UTF_8))) {
                        throw Exception("Failed to send pairing required response")
                    }
                    
                    val pinBytes = readLengthPrefixedData(inputStream)
                    if (pinBytes == null) {
                        throw Exception("Failed to read PIN request")
                    }
                    val pinJson = JSONObject(String(pinBytes, Charsets.UTF_8))
                    val enteredPin = pinJson.optString("pin")
                    
                    if (enteredPin == randomPin) {
                        generatedToken = UUID.randomUUID().toString()
                        val prefs = getSharedPreferences("pihu_paired_devices", Context.MODE_PRIVATE)
                        prefs.edit().putString(clientId, generatedToken).apply()
                        Log.d(TAG, "Pairing successful! Generated token saved.")
                        isPaired = true
                    } else {
                        Log.w(TAG, "Incorrect PIN entered: $enteredPin (Expected: $randomPin)")
                        val failureResp = JSONObject().apply {
                            put("status", "pairing_failed")
                            put("reason", "Incorrect PIN")
                        }
                        sendLengthPrefixedData(outputStream, failureResp.toString().toByteArray(Charsets.UTF_8))
                        throw Exception("Incorrect PIN entered")
                    }
                }
                
                if (isPaired) {
                    val successResp = JSONObject().apply {
                        put("status", "success")
                        put("device_name", android.os.Build.MODEL)
                        put("token", if (generatedToken.isNotEmpty()) generatedToken else clientToken)
                        put("width", screenWidth)
                        put("height", screenHeight)
                    }
                    if (!sendLengthPrefixedData(outputStream, successResp.toString().toByteArray(Charsets.UTF_8))) {
                        throw Exception("Failed to send success response")
                    }
                    
                    runOnUiThread {
                        Toast.makeText(this@MainActivity, "Connected to host display!", Toast.LENGTH_SHORT).show()
                        overlayView?.visibility = View.GONE
                    }
                } else {
                    throw Exception("Client not paired")
                }

                var frameCount = 0
                while (isRunning) {
                    val stream = inputStream ?: break
                    // 1. Read 4-byte length prefix
                    if (!readExactly(stream, lengthBuffer, 4)) {
                        Log.d(TAG, "Socket stream reached EOF while reading length")
                        break
                    }

                    val length = ((lengthBuffer[0].toInt() and 0xFF) shl 24) or
                                 ((lengthBuffer[1].toInt() and 0xFF) shl 16) or
                                 ((lengthBuffer[2].toInt() and 0xFF) shl 8) or
                                 (lengthBuffer[3].toInt() and 0xFF)

                    if (length <= 0 || length > 10 * 1024 * 1024) {
                        Log.e(TAG, "Invalid packet length: $length")
                        break
                    }

                    // Resize payload buffer if necessary
                    if (length > payloadBuffer.size) {
                        payloadBuffer = ByteArray(length)
                    }

                    // 2. Read exactly `length` bytes of payload
                    if (!readExactly(stream, payloadBuffer, length)) {
                        Log.d(TAG, "Socket stream reached EOF while reading payload of size $length")
                        break
                    }

                    // 3. Feed directly to decoder
                    val currentDecoder = decoder
                    if (currentDecoder != null && isDecoderConfigured) {
                        try {
                            var inputBufferIndex = -1
                            val startTime = System.currentTimeMillis()
                            while (isRunning && isDecoderConfigured && System.currentTimeMillis() - startTime < 500) {
                                inputBufferIndex = currentDecoder.dequeueInputBuffer(10000) // 10ms timeout
                                if (inputBufferIndex >= 0) {
                                    break
                                }
                            }

                            if (inputBufferIndex >= 0) {
                                val inputBuffer = currentDecoder.getInputBuffer(inputBufferIndex)
                                if (inputBuffer != null) {
                                    inputBuffer.clear()
                                    inputBuffer.put(payloadBuffer, 0, length)
                                    val pts = System.nanoTime() / 1000
                                    currentDecoder.queueInputBuffer(inputBufferIndex, 0, length, pts, 0)
                                    
                                    frameCount++
                                    if (frameCount % 60 == 0) {
                                        Log.d(TAG, "Decoded 60 frames (total: $frameCount)")
                                    }
                                }
                            } else {
                                Log.w(TAG, "Dropped packet of size $length due to decoder busy")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Error feeding packet to decoder", e)
                        }
                    }
                }
            } catch (e: Exception) {
                if (isRunning) {
                    Log.e(TAG, "Socket error: ${e.message}")
                }
            } finally {
                try { inputStream?.close() } catch (e: Exception) {}
                try { socket?.close() } catch (e: Exception) {}
                socket = null
                inputStream = null
                
                releaseDecoder()
                
                runOnUiThread {
                    if (isRunning) {
                        statusText?.text = "Disconnected. Waiting for reconnection..."
                        overlayView?.visibility = View.VISIBLE
                        Toast.makeText(this@MainActivity, "Disconnected. Retrying...", Toast.LENGTH_SHORT).show()
                    }
                }
                try { Thread.sleep(1000) } catch (e: InterruptedException) { break }
            }
        }

        // Final cleanup when thread is stopping
        try { serverSocket?.close() } catch (e: Exception) {}
    }
}
